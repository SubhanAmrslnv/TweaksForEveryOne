using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WindowTweaks.Core;

/// <summary>
/// THE ONE low-level keyboard hook in this process, shared by every feature that needs to see a
/// bare keypress.
///
/// Why this class exists at all, beyond not repeating the install/uninstall code four times:
///
/// A global WH_KEYBOARD_LL hook is the defining API of a keylogger, and it is what antivirus
/// heuristics weight most heavily. Four features used to install their OWN hook, so the process held
/// four simultaneous global keyboard hooks - which reads, to a behavioural scanner, as a program
/// determined to capture keystrokes no matter what. Collapsing them to one hook that is installed
/// only while a feature that needs it is switched on is an honest description of what the app does,
/// and a far weaker signal.
///
/// What this hook does NOT do, deliberately and permanently:
///   - it does not store, buffer, log or count the keys it sees; each subscriber keeps only the
///     small amount of state its own gesture needs (a tap count and a stopwatch)
///   - it does not write anything to disk
///   - it does not send anything anywhere; this process makes no network connections at all
/// Keep it that way. Adding keystroke retention here would make the heuristic correct.
///
/// See docs/ANTIVIRUS.md.
/// </summary>
internal static class KeyboardHook
{
    /// <summary>What a subscriber is told about one key event. Nothing is retained after dispatch.</summary>
    public readonly struct KeyEvent
    {
        public KeyEvent(int virtualKey, bool isKeyDown, bool isInjected)
        {
            VirtualKey = virtualKey;
            IsKeyDown = isKeyDown;
            IsInjected = isInjected;
        }

        public int VirtualKey { get; }
        public bool IsKeyDown { get; }

        /// <summary>
        /// True when the event came from SendInput rather than hardware. A feature that synthesises
        /// keys must ignore these or it will hook its own output in a loop.
        /// </summary>
        public bool IsInjected { get; }
    }

    /// <summary>Return true to SUPPRESS the key, so it never reaches the focused application.</summary>
    public delegate bool Handler(KeyEvent e);

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;

    /// <summary>KBDLLHOOKSTRUCT.flags bit meaning "this event was injected by SendInput".</summary>
    private const int LLKHF_INJECTED = 0x10;

    /// <summary>Byte offset of `flags` within KBDLLHOOKSTRUCT (vkCode, scanCode, flags, ...).</summary>
    private const int OffsetFlags = 8;

    private static readonly object Gate = new();

    // Insertion-ordered so dispatch order is deterministic.
    private static readonly List<KeyValuePair<string, Handler>> Subscribers = new();

    /// <summary>
    /// A snapshot of Subscribers, rebuilt only when the list changes. The callback used to take the
    /// lock and call ToArray() on every key event, which allocated on an input path.
    /// </summary>
    private static volatile KeyValuePair<string, Handler>[] _snapshot = Array.Empty<KeyValuePair<string, Handler>>();

    private static IntPtr _hook = IntPtr.Zero;

    // The delegate must be held in a field. If it is only passed to SetWindowsHookEx, the GC is free
    // to collect it and the callback becomes a dangling pointer - a crash that appears at random.
    private static NativeMethods.LowLevelKeyboardProc? _proc;

    public static int SubscriberCount
    {
        get
        {
            lock (Gate) return Subscribers.Count;
        }
    }

    /// <summary>True when a hook is actually installed right now.</summary>
    public static bool IsInstalled
    {
        get
        {
            lock (Gate) return _hook != IntPtr.Zero;
        }
    }

    public static void Subscribe(string owner, Handler handler)
    {
        lock (Gate)
        {
            RemoveOwner(owner);
            Subscribers.Add(new KeyValuePair<string, Handler>(owner, handler));
            _snapshot = Subscribers.ToArray();
        }

        // Outside the lock: installing runs on the hook thread and waits for it, and that thread
        // must never be able to block on a lock the UI thread is holding.
        EnsureInstalled();
    }

    public static void Unsubscribe(string owner)
    {
        bool empty;

        lock (Gate)
        {
            RemoveOwner(owner);
            _snapshot = Subscribers.ToArray();
            empty = Subscribers.Count == 0;
        }

        // No subscribers means no reason to hold a global keyboard hook. Release it.
        if (empty) Uninstall();
    }

    /// <summary>Caller must hold Gate.</summary>
    private static void RemoveOwner(string owner)
    {
        for (int i = Subscribers.Count - 1; i >= 0; i--)
        {
            if (Subscribers[i].Key == owner) Subscribers.RemoveAt(i);
        }
    }

    /// <summary>
    /// Installs the hook ON THE HOOK THREAD. A low-level hook's callbacks are delivered to the
    /// thread that installed it, and Windows holds the keystroke that caused one until that thread
    /// returns - so installing from the UI thread makes every keystroke in the operating system
    /// wait behind WPF. See Core/HookThread.cs.
    /// </summary>
    private static void EnsureInstalled()
    {
        HookThread.Invoke(() =>
        {
            if (_hook != IntPtr.Zero) return;

            try
            {
                _proc = HookCallback;

                using Process curProcess = Process.GetCurrentProcess();
                using ProcessModule? curModule = curProcess.MainModule;
                if (curModule == null) return;

                _hook = NativeMethods.SetWindowsHookEx(
                    NativeMethods.WH_KEYBOARD_LL, _proc,
                    NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
            }
            catch
            {
                _hook = IntPtr.Zero;
            }
        });
    }

    /// <summary>Removes the hook, on the same thread that installed it.</summary>
    private static void Uninstall()
    {
        HookThread.Invoke(() =>
        {
            if (_hook == IntPtr.Zero) return;

            try
            {
                NativeMethods.UnhookWindowsHookEx(_hook);
            }
            catch
            {
            }

            _hook = IntPtr.Zero;
            _proc = null;
        });
    }

    /// <summary>Release the hook regardless of subscribers. Exit only.</summary>
    public static void Shutdown()
    {
        lock (Gate)
        {
            Subscribers.Clear();
            _snapshot = Array.Empty<KeyValuePair<string, Handler>>();
        }

        Uninstall();
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        IntPtr hook = _hook;

        if (nCode < 0) return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

        // Teardown is reached by refusing to queue more work, not by draining the queue. A held key
        // used to keep feeding the very dispatcher that OnExit was trying to shut down.
        if (AppLifetime.IsExiting) return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

        bool suppress = false;

        try
        {
            int msg = wParam.ToInt32();

            bool isDown = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
            bool isUp = msg is WM_KEYUP or WM_SYSKEYUP;

            if (isDown || isUp)
            {
                int vkCode = Marshal.ReadInt32(lParam);
                bool injected = (Marshal.ReadInt32(lParam, OffsetFlags) & LLKHF_INJECTED) != 0;

                KeyEvent e = new(vkCode, isDown, injected);

                // The snapshot is read without the lock and never mutated in place: a handler may
                // subscribe or unsubscribe in response (Stealth Panic suspends features), and
                // mutating the live list under an enumerator would throw inside a hook callback.
                KeyValuePair<string, Handler>[] snapshot = _snapshot;

                // Every subscriber sees every event, even after one asks to suppress, so their tap
                // counters stay correct. Suppression is the OR of all answers.
                foreach (KeyValuePair<string, Handler> sub in snapshot)
                {
                    try
                    {
                        if (sub.Value(e)) suppress = true;
                    }
                    catch
                    {
                        // One misbehaving subscriber must not break the others, and must never
                        // escalate out of a hook callback.
                    }
                }
            }
        }
        catch
        {
            // An exception escaping here would tear down the hook and, with it, every feature that
            // depends on it - for the rest of the session, with no visible cause.
        }

        if (suppress) return new IntPtr(1);
        return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);
    }
}
