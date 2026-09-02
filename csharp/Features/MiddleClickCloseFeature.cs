using System;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Middle-click a window's title bar to close it, the way a browser tab closes.
///
/// TWO THINGS ARE DELIBERATE AND SHOULD NOT BE "SIMPLIFIED":
///
/// 1. BROWSERS ARE SKIPPED BY DEFAULT. A browser's tab strip IS its title bar - Chrome, Edge and
///    Firefox all answer HTCAPTION for the empty space beside the tabs - so treating them like any
///    other window means a middle click near the tabs closes the entire browser instead of a tab.
///    That was the reported "middle click breaks opening and closing tabs". It is a setting rather
///    than a hard rule, because someone who never middle-clicks near a tab strip may want it.
///
/// 2. THE EXPENSIVE TEST IS BEHIND A CHEAP ONE. Deciding whether a point is on a title bar means
///    asking the target window, with SendMessage - a CROSS-PROCESS call, on the input path, inside a
///    low-level hook. Windows removes a hook that takes longer than LowLevelHooksTimeout (300 ms by
///    default), and it removes it silently: the feature stops working and so does every other hook
///    in the process. So the probe only runs when the click is inside the top band of the window's
///    own rectangle, which is free to check, and it runs with a 40 ms timeout and SMTO_ABORTIFHUNG
///    so a hung window cannot take the hook down with it.
/// </summary>
public class MiddleClickCloseFeature : IDisposable
{
    private const string HookOwner = nameof(MiddleClickCloseFeature);

    /// <summary>
    /// Cheap pre-filter: how far down from the top of a window a title bar can possibly be. Generous
    /// - a scaled display with a tall custom caption needs the room - but still rejects the whole
    /// client area, which is where almost every middle click actually lands.
    /// </summary>
    private const int CaptionBandPx = 120;

    /// <summary>
    /// Short enough that four of these back to back stay inside the hook budget. The old value was
    /// 120 ms, which on its own is a third of that budget.
    /// </summary>
    private const uint ProbeTimeoutMs = 40;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        // Buttons only. This handler does a cross-process probe, and calling it for every mouse
        // move would be the single most expensive thing in the process.
        if (enabled) MouseHook.Subscribe(HookOwner, MouseEvents.Buttons, OnMouse);
        else MouseHook.Unsubscribe(HookOwner);
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        if (e.Message != NativeMethods.WM_MBUTTONDOWN) return false;

        // THE ONE PLACE TWO FEATURES ARBITRATE OVER THE SAME BUTTON, and it needs to be explicit
        // because the alternative is a double action.
        //
        // Grab and pan owns the middle button when it is on: it swallows the physical press, decides
        // whether the gesture was a pan or a click, and replays a tagged click if it was a click. So
        // if this feature also acted on the PHYSICAL press, a middle click on a title bar would close
        // that window immediately AND then replay a click onto whatever ended up under the cursor -
        // closing a second window. Waiting for the replay makes the two features compose: hold to
        // pan, click to close.
        //
        // With grab and pan off there is no replay to wait for, so the physical press is the click.
        if (!e.IsOurs && FeatureRegistry.IsEnabled(FeatureKeys.GrabPan)) return false;

        NativeMethods.POINT pt = new() { X = e.X, Y = e.Y };

        return TryClose(pt);
    }

    private static bool TryClose(NativeMethods.POINT pt)
    {
        try
        {
            IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
            if (hwnd == IntPtr.Zero) return false;

            hwnd = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
            if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;

            // Never our own windows: the settings window, and every overlay this app puts on screen.
            NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == (uint)Environment.ProcessId) return false;

            StringBuilder sb = new(64);
            NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
            string cls = sb.ToString();

            // The shell is never a candidate. Closing Progman or a tray window does nothing good.
            if (IsShellSurface(cls)) return false;

            if (IsBrowser(cls) && SkipBrowsers()) return false;

            // The free pre-filter, before the cross-process call. See the class comment.
            if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r)) return false;
            if (pt.Y > r.Top + CaptionBandPx) return false;

            // A maximised window's caption still reports HTCAPTION, so no special case is needed,
            // but a MINIMISED window's rect is off screen and cannot contain the point anyway.
            IntPtr lParam = MakeLParam(pt.X, pt.Y);

            IntPtr sent = NativeMethods.SendMessageTimeout(
                hwnd, NativeMethods.WM_NCHITTEST, IntPtr.Zero, lParam,
                NativeMethods.SMTO_ABORTIFHUNG, ProbeTimeoutMs, out IntPtr result);

            // Zero means the window did not answer in time, which for a "Not Responding" window is
            // the normal case. Leaving it alone is right: it cannot be asked to close either.
            if (sent == IntPtr.Zero) return false;
            if (result.ToInt64() != NativeMethods.HTCAPTION) return false;

            NativeMethods.PostMessage(hwnd, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);

            // Swallow the click only now that it has definitely been acted on. Returning true on a
            // click that did nothing would make middle-click dead everywhere.
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool SkipBrowsers()
    {
        return string.Equals(
            TuningRegistry.Choice(TuningRegistry.MiddleClickSkipBrowsers), "skip",
            StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Window classes whose caption area is really a tab strip. Chrome_WidgetWin_1 covers Chrome,
    /// Edge, Brave, Opera and every Electron application, which is a lot of what is on a desktop.
    /// </summary>
    private static bool IsBrowser(string cls)
    {
        return cls is "Chrome_WidgetWin_1" or "Chrome_WidgetWin_0" or "MozillaWindowClass";
    }

    private static bool IsShellSurface(string cls)
    {
        return cls is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd" or "Progman" or "WorkerW"
            or "Windows.UI.Core.CoreWindow" or "TopLevelWindowForOverflowXamlIsland";
    }

    private static IntPtr MakeLParam(int x, int y)
    {
        return (IntPtr)((y << 16) | (x & 0xFFFF));
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
