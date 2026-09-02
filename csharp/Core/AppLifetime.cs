using System;
using System.Threading;

namespace WindowTweaks.Core;

/// <summary>
/// One flag that says "this process is on its way out", plus the watchdog that guarantees it
/// actually gets there.
///
/// WHY THIS EXISTS. Exit used to freeze or not happen at all, and there were three separate causes:
///
///   1. Shutdown could be requested twice - the tray menu, Shift+Alt+F6 and a WM_CLOSE from the
///      installer all call it - and WPF throws on the second call, from inside a message handler,
///      which left the first shutdown half finished.
///
///   2. The hooks kept dispatching while teardown ran. Every feature that answers a hook marshals
///      its work onto the dispatcher, so a hand resting on the mouse or a held key kept queueing
///      work onto the very dispatcher that was trying to shut down. Exit is not reached by draining
///      that queue; it is reached by refusing to add to it. <see cref="IsExiting"/> is tested at the
///      top of both shared hooks and in every dispatcher callback that a hook can start.
///
///   3. Teardown itself can block indefinitely on things this app does not control - a COM call
///      into an audio endpoint that is being removed, SetParent on a window whose owner has already
///      gone, a WPF window whose Close is waiting on a render. There is no correct timeout for any
///      of them individually, so there is one for all of them together: <see cref="StartWatchdog"/>
///      terminates the process if OnExit has not completed in time.
///
/// The watchdog is a last resort and is deliberately generous. Everything OnExit does that MATTERS
/// to the user - flushing settings, giving each feature the chance to undo what it did to other
/// applications' windows - happens well inside the window.
/// </summary>
internal static class AppLifetime
{
    private static int _exiting;

    /// <summary>
    /// Set once by App to its own shutdown path, so code that cannot reach App can still ask for a
    /// clean exit. The taskbar clock needs this: it owns the app's only permanently visible window,
    /// so anything posting WM_CLOSE to the process finds the CLOCK before the app's message window,
    /// and it has to forward that request rather than just closing itself and leaving the process
    /// running with no window and no way to stop it.
    /// </summary>
    public static Action? ShutdownRequested { get; set; }

    /// <summary>Asks the app to exit, if it is listening. Safe before startup and after exit.</summary>
    public static void RequestShutdown()
    {
        try
        {
            ShutdownRequested?.Invoke();
        }
        catch
        {
        }
    }

    /// <summary>
    /// True from the first moment shutdown is requested. Hooks and hook-started dispatcher work
    /// must check this and do nothing.
    /// </summary>
    public static bool IsExiting => Volatile.Read(ref _exiting) != 0;

    /// <summary>
    /// Marks the process as exiting. Returns true for the FIRST caller only, so the caller can use
    /// it to make shutdown idempotent.
    /// </summary>
    public static bool BeginExit()
    {
        return Interlocked.Exchange(ref _exiting, 1) == 0;
    }

    /// <summary>
    /// Arms a hard exit. Call at the top of OnExit; the timer is cancelled by nothing, because a
    /// normal exit reaches Environment.Exit before it fires.
    /// </summary>
    public static void StartWatchdog(int milliseconds = 5000)
    {
        Thread t = new(() =>
        {
            Thread.Sleep(milliseconds);

            // Still here means some part of teardown is wedged. The alternative to this line is the
            // process the user reported: no window, no tray icon, still running.
            try
            {
                Environment.Exit(0);
            }
            catch
            {
            }
        })
        {
            IsBackground = true,
            Name = "WindowTweaks.ExitWatchdog"
        };

        t.Start();
    }
}
