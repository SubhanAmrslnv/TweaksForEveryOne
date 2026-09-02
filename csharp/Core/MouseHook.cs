using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WindowTweaks.Core;

/// <summary>Which mouse events a subscriber wants to be shown. See MouseHook.Subscribe.</summary>
[Flags]
internal enum MouseEvents
{
    None = 0,

    /// <summary>WM_MOUSEMOVE. Fires 100+ times a second while the hand is moving.</summary>
    Move = 1,

    /// <summary>Button down and up, all three buttons.</summary>
    Buttons = 2,

    /// <summary>The wheel, vertical and horizontal.</summary>
    Wheel = 4,

    All = Move | Buttons | Wheel
}

/// <summary>
/// THE ONE low-level mouse hook in this process, shared and installed only on demand - the same
/// arrangement, and for the same reasons, as <see cref="KeyboardHook"/>. Five features used to
/// install their own, and with several WH_MOUSE_LL hooks in one process the first one to swallow an
/// event hides it from the others, so which features worked depended on the order the user had
/// happened to switch them on in.
///
/// Three things here are load-bearing:
///
/// 1. THE HOOK LIVES ON <see cref="HookThread"/>, not on the UI thread. Windows holds the input
///    event that caused a callback until the installing thread returns, so a hook on the UI thread
///    makes every mouse movement in the operating system wait behind WPF. Read HookThread's header.
///
/// 2. SUBSCRIBERS DECLARE WHAT THEY WANT. A feature that only cares about the middle button used to
///    be called for every mouse move, and one that only cares about moves used to be called for
///    every click - so the cost of the slowest handler was paid on every event of every kind. The
///    interest mask is checked before dispatch.
///
/// 3. THIS PROCESS RECOGNISES ITS OWN SYNTHETIC INPUT. Everything the app injects is tagged with
///    NativeMethods.SyntheticTag in dwExtraInfo and arrives with <see cref="MouseEvent.IsOurs"/>
///    set. Grab and pan needs that to replay a click it swallowed without immediately eating the
///    replay; it used to count events instead ("ignore the next two"), which lost sync the moment
///    any other event arrived in between - and that is why middle-click stopped opening and closing
///    browser tabs.
///
/// A HANDLER RUNS ON THE HOOK THREAD AND MUST RETURN IN MICROSECONDS. No disk, no COM, no
/// cross-process SendMessage without a very short timeout, and no WPF - marshal to the dispatcher,
/// after checking AppLifetime.IsExiting.
/// </summary>
internal static class MouseHook
{
    public readonly struct MouseEvent
    {
        public MouseEvent(int message, int x, int y, uint mouseData, bool isInjected, bool isOurs)
        {
            Message = message;
            X = x;
            Y = y;
            MouseData = mouseData;
            IsInjected = isInjected;
            IsOurs = isOurs;
        }

        public int Message { get; }

        /// <summary>Physical desktop pixels. NOT WPF units - see Core/OverlayPlacement.cs.</summary>
        public int X { get; }
        public int Y { get; }

        public uint MouseData { get; }

        /// <summary>True for any event from SendInput or mouse_event, whoever injected it.</summary>
        public bool IsInjected { get; }

        /// <summary>True when THIS process injected it. Strictly stronger than IsInjected.</summary>
        public bool IsOurs { get; }

        /// <summary>The signed wheel notch count, for a wheel message. Positive is away from the user.</summary>
        public int WheelDelta => (short)(MouseData >> 16);
    }

    /// <summary>Return true to SUPPRESS the event, so it never reaches the window underneath.</summary>
    public delegate bool Handler(MouseEvent e);

    private const int LLMHF_INJECTED = 0x01;

    private readonly struct Subscription
    {
        public Subscription(string owner, MouseEvents interest, Handler handler)
        {
            Owner = owner;
            Interest = interest;
            Handler = handler;
        }

        public string Owner { get; }
        public MouseEvents Interest { get; }
        public Handler Handler { get; }
    }

    private static readonly object Gate = new();
    private static readonly List<Subscription> Subscribers = new();

    /// <summary>
    /// A snapshot of Subscribers, rebuilt only when the list changes. The callback used to call
    /// ToArray() on every event, which allocated on the hook path 100+ times a second.
    /// </summary>
    private static volatile Subscription[] _snapshot = Array.Empty<Subscription>();

    /// <summary>The OR of every subscriber's interest, so an unwanted category is rejected at once.</summary>
    private static volatile MouseEvents _wanted = MouseEvents.None;

    private static IntPtr _hook = IntPtr.Zero;

    // Must be a field: if the delegate is only passed to SetWindowsHookEx the GC is free to collect
    // it, and the callback becomes a dangling pointer - a crash that shows up at random.
    private static NativeMethods.LowLevelMouseProc? _proc;

    public static void Subscribe(string owner, Handler handler)
    {
        Subscribe(owner, MouseEvents.All, handler);
    }

    public static void Subscribe(string owner, MouseEvents interest, Handler handler)
    {
        lock (Gate)
        {
            RemoveOwner(owner);
            Subscribers.Add(new Subscription(owner, interest, handler));
            Rebuild();
        }

        // Outside the lock: installing runs on the hook thread and waits for it, and that thread
        // must never be able to block on a lock the UI thread holds.
        EnsureInstalled();
    }

    public static void Unsubscribe(string owner)
    {
        bool empty;

        lock (Gate)
        {
            RemoveOwner(owner);
            Rebuild();
            empty = Subscribers.Count == 0;
        }

        // No subscribers means no reason to hold a global mouse hook. Release it.
        if (empty) Uninstall();
    }

    /// <summary>Caller must hold Gate.</summary>
    private static void RemoveOwner(string owner)
    {
        for (int i = Subscribers.Count - 1; i >= 0; i--)
        {
            if (Subscribers[i].Owner == owner) Subscribers.RemoveAt(i);
        }
    }

    /// <summary>Caller must hold Gate.</summary>
    private static void Rebuild()
    {
        _snapshot = Subscribers.ToArray();

        MouseEvents wanted = MouseEvents.None;
        foreach (Subscription s in _snapshot) wanted |= s.Interest;
        _wanted = wanted;
    }

    private static void EnsureInstalled()
    {
        // Checked here as well as inside the Invoke: every feature that subscribes calls this, and
        // without the early return each one paid a full round trip to the hook thread only to find
        // the hook already installed. The check is repeated inside because only the hook thread may
        // act on the answer.
        if (_hook != IntPtr.Zero) return;

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
                    NativeMethods.WH_MOUSE_LL, _proc,
                    NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
            }
            catch
            {
                _hook = IntPtr.Zero;
            }
        });
    }

    private static void Uninstall()
    {
        HookThread.Invoke(() =>
        {
            if (_hook == IntPtr.Zero) return;

            try { NativeMethods.UnhookWindowsHookEx(_hook); } catch { }
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
            _snapshot = Array.Empty<Subscription>();
            _wanted = MouseEvents.None;
        }

        Uninstall();
    }

    private static MouseEvents Categorise(int message)
    {
        return message switch
        {
            NativeMethods.WM_MOUSEMOVE => MouseEvents.Move,
            NativeMethods.WM_MOUSEWHEEL => MouseEvents.Wheel,
            NativeMethods.WM_MOUSEHWHEEL => MouseEvents.Wheel,
            NativeMethods.WM_LBUTTONDOWN => MouseEvents.Buttons,
            NativeMethods.WM_LBUTTONUP => MouseEvents.Buttons,
            NativeMethods.WM_RBUTTONDOWN => MouseEvents.Buttons,
            NativeMethods.WM_RBUTTONUP => MouseEvents.Buttons,
            NativeMethods.WM_MBUTTONDOWN => MouseEvents.Buttons,
            NativeMethods.WM_MBUTTONUP => MouseEvents.Buttons,
            _ => MouseEvents.None
        };
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        IntPtr hook = _hook;

        if (nCode < 0) return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

        // Teardown is reached by refusing to queue more work, not by draining the queue. A hand
        // resting on the mouse used to keep feeding the dispatcher that OnExit was shutting down.
        if (AppLifetime.IsExiting) return NativeMethods.CallNextHookEx(hook, nCode, wParam, lParam);

        bool suppress = false;

        try
        {
            int msg = wParam.ToInt32();
            MouseEvents category = Categorise(msg);

            // The cheap gate first: no read of the hook struct, no dispatch, nothing.
            if (category != MouseEvents.None && (_wanted & category) != 0)
            {
                NativeMethods.MSLLHOOKSTRUCT data = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

                bool injected = (data.flags & LLMHF_INJECTED) != 0;
                bool ours = injected && data.dwExtraInfo == NativeMethods.SyntheticTag;

                MouseEvent e = new(msg, data.pt.X, data.pt.Y, (uint)data.mouseData, injected, ours);

                Subscription[] snapshot = _snapshot;

                // Every interested subscriber sees every event, even after one has asked to
                // suppress, so their gesture state stays correct. Suppression is the OR.
                foreach (Subscription sub in snapshot)
                {
                    if ((sub.Interest & category) == 0) continue;

                    try
                    {
                        if (sub.Handler(e)) suppress = true;
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
