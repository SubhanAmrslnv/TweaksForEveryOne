using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

namespace WindowTweaks.Core;

/// <summary>
/// The thread that owns this process's low-level input hooks, and nothing else.
///
/// THIS IS THE MOST LOAD-BEARING FILE IN THE APP FOR PERCEIVED SYSTEM PERFORMANCE, so read this
/// before moving a hook off it.
///
/// Windows delivers a WH_MOUSE_LL or WH_KEYBOARD_LL callback to the thread that installed the hook,
/// and it holds the input event that caused it until that thread returns. The hooks used to be
/// installed from the WPF UI thread, which meant every mouse move and every keystroke in the whole
/// operating system had to wait behind whatever WPF happened to be doing on it: a ripple animation,
/// the taskbar clock's 500 ms tick, the settings window measuring itself, a magnifier repaint. That
/// is the "everything lags" report, and it is also the "Windows' own snap only works the second
/// time" report - past LowLevelHooksTimeout (300 ms by default) Windows stops waiting for a hook,
/// silently REMOVES it, and the gesture it was holding is delivered late or not at all.
///
/// So: one dedicated thread, above-normal priority, running nothing but SetWindowsHookEx and a
/// GetMessage pump. A hook callback here competes with nothing. It is a private message pump rather
/// than a plain loop because a low-level hook only receives callbacks on a thread that pumps
/// messages - without the pump the hooks install successfully and then never fire.
///
/// RULES FOR CODE THAT RUNS ON THIS THREAD:
///   - Return in microseconds. No disk, no cross-process SendMessage without a short timeout, no
///     COM, no allocation-heavy work, and never a lock that UI code also takes.
///   - Never touch WPF. Marshal to the dispatcher with BeginInvoke - and check AppLifetime.IsExiting
///     before you do, or a held key will queue work onto a dispatcher that is shutting down.
/// </summary>
internal static class HookThread
{
    private static readonly object Gate = new();
    private static readonly Queue<Action> Work = new();

    private static Thread? _thread;
    private static uint _threadId;

    /// <summary>Signalled once the pump is running, so Invoke cannot post to a thread with no pump.</summary>
    private static readonly ManualResetEventSlim Started = new(false);

    private static bool _stopping;

    /// <summary>True when called from the hook thread itself.</summary>
    public static bool IsCurrent => Volatile.Read(ref _threadId) == NativeMethods.GetCurrentThreadId();

    public static void EnsureStarted()
    {
        lock (Gate)
        {
            if (_thread != null) return;

            _stopping = false;
            Started.Reset();

            _thread = new Thread(Pump)
            {
                IsBackground = true,
                Name = "WindowTweaks.Hooks",

                // Above normal, not highest: this thread gates OS-wide input delivery, so it must
                // not sit behind the UI thread's rendering - but it must not starve it either.
                Priority = ThreadPriority.AboveNormal
            };

            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();
        }

        // A two second cap rather than an unbounded wait: if the thread cannot start, the caller
        // gets a feature that does not work, not a hung application.
        Started.Wait(2000);
    }

    /// <summary>
    /// Runs <paramref name="work"/> on the hook thread and waits for it. Used for installing and
    /// removing hooks, which MUST happen on the thread that will receive the callbacks.
    /// </summary>
    public static void Invoke(Action work)
    {
        if (work == null) return;

        if (IsCurrent)
        {
            work();
            return;
        }

        EnsureStarted();

        using ManualResetEventSlim done = new(false);
        Exception? failure = null;

        Post(() =>
        {
            try
            {
                work();
            }
            catch (Exception ex)
            {
                failure = ex;
            }
            finally
            {
                try { done.Set(); } catch { }
            }
        });

        // Bounded, for the same reason as above: a wedged hook thread must not become a wedged app.
        done.Wait(2000);

        if (failure != null) Debug.WriteLine("Hook thread work failed: " + failure.Message);
    }

    private static void Post(Action work)
    {
        uint id;

        lock (Gate)
        {
            Work.Enqueue(work);
            id = _threadId;
        }

        if (id != 0) NativeMethods.PostThreadMessage(id, NativeMethods.WM_HOOKTHREAD_RUN, IntPtr.Zero, IntPtr.Zero);
    }

    private static void Pump()
    {
        Volatile.Write(ref _threadId, NativeMethods.GetCurrentThreadId());

        // Force a message queue to exist before anyone can post to it. PostThreadMessage fails
        // against a thread that has never called a message function.
        NativeMethods.PostThreadMessage(_threadId, NativeMethods.WM_HOOKTHREAD_RUN, IntPtr.Zero, IntPtr.Zero);

        Started.Set();

        while (true)
        {
            int result = NativeMethods.GetMessage(out NativeMethods.MSG msg, IntPtr.Zero, 0, 0);

            // 0 is WM_QUIT, -1 is an error. Either way this thread is finished.
            if (result <= 0) break;

            if (msg.message == NativeMethods.WM_HOOKTHREAD_QUIT) break;

            if (msg.message == NativeMethods.WM_HOOKTHREAD_RUN) Drain();

            lock (Gate)
            {
                if (_stopping && Work.Count == 0) break;
            }
        }

        Drain();

        lock (Gate)
        {
            Volatile.Write(ref _threadId, 0);
            _thread = null;
        }
    }

    private static void Drain()
    {
        while (true)
        {
            Action? next;

            lock (Gate)
            {
                if (Work.Count == 0) return;
                next = Work.Dequeue();
            }

            try
            {
                next();
            }
            catch (Exception ex)
            {
                // An exception escaping here would end the pump, and with it every hook in the
                // process, for the rest of the session and with no visible cause.
                Debug.WriteLine("Hook thread work threw: " + ex.Message);
            }
        }
    }

    /// <summary>
    /// Stops the pump. Exit only, and only after every hook has been removed - the pump is what
    /// delivers hook callbacks, so a hook left installed with no pump stalls input system-wide.
    /// </summary>
    public static void Stop()
    {
        uint id;

        lock (Gate)
        {
            if (_thread == null) return;
            _stopping = true;
            id = _threadId;
        }

        if (id != 0) NativeMethods.PostThreadMessage(id, NativeMethods.WM_HOOKTHREAD_QUIT, IntPtr.Zero, IntPtr.Zero);

        Thread? t;
        lock (Gate) t = _thread;

        // Do not block exit on it. The thread is a background thread, so the runtime will not wait
        // for it either way; this is only a courtesy so the hooks are gone before the process is.
        try { t?.Join(500); } catch { }
    }
}
