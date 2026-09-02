using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Auto-hides the taskbar, but only while it is actually in the way.
///
/// WHY THE SECOND MONITOR'S TASKBAR KEPT DISAPPEARING. Windows' auto-hide is a SINGLE SETTING FOR
/// EVERY TASKBAR - SHAppBarMessage(ABM_SETSTATE) takes one taskbar handle but the state it sets is
/// system-wide. The first version decided from the primary monitor alone: maximise something on the
/// primary and the secondary monitor's bar vanished too, with nothing on that monitor to explain it,
/// and it stayed hidden while that window stayed maximised. That is the reported fault, and it is
/// not fixable by passing a different handle - the API has no per-monitor form.
///
/// So the decision now covers every taskbar there is. On the default "all" scope the bars hide only
/// when every one of them is genuinely covered, which is the only rule under which a global switch
/// cannot surprise the user on a monitor they were not looking at.
///
/// WHY THE POLL IS NOW CHEAP. It used to enumerate every monitor and then every top-level window in
/// the system, five times a second, calling GetClassName and GetWindowPlacement on each - which is
/// part of the "everything lags" report all on its own. The question it was answering is far simpler
/// than the code that answered it: IS THE TASKBAR COVERED? WindowFromPoint just above each bar
/// answers exactly that, in about three microseconds, and it is self-correcting - while the bar is
/// hidden the point is over whatever covered it, and when that window closes the point comes back as
/// the desktop.
/// </summary>
public class SmartTaskbarFeature : IDisposable
{
    private const int ABM_SETSTATE = 0x0000000A;
    private const int ABS_AUTOHIDE = 0x0000001;
    private const int ABS_ALWAYSONTOP = 0x0000002;

    /// <summary>
    /// Two and a half times a second. Fast enough that hiding does not feel late, slow enough to be
    /// invisible in a profile - and each tick is a handful of microseconds now.
    /// </summary>
    private const int PollMs = 400;

    private DispatcherTimer? _timer;

    /// <summary>-1 until the first decision, so the first tick always applies its result.</summary>
    private int _appliedState = -1;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            _appliedState = -1;

            // A DispatcherTimer rather than a polling Task: this is a TIMER, not an animation, and
            // it must not keep a frame loop alive. See the timing notes in CLAUDE.md.
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(PollMs) };
            _timer.Tick += OnTick;
            _timer.Start();
        }
        else
        {
            if (_timer != null)
            {
                _timer.Stop();
                _timer.Tick -= OnTick;
                _timer = null;
            }

            // Always leave the bars visible. A user who switches this off and finds their taskbar
            // still hiding has no way to work out which program did it.
            Apply(false);
            _appliedState = -1;
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void OnTick(object? sender, EventArgs e)
    {
        // The flag test lives inside the tick as well as at the call site: a feature that changed a
        // system-wide setting has to be able to put it back even while being switched off.
        //
        // The teardown is written out rather than delegated to SetEnabled(false), which would return
        // immediately here - IsEnabled is already false - and leave this timer running for the rest
        // of the session.
        if (!IsEnabled)
        {
            if (_timer != null)
            {
                _timer.Stop();
                _timer.Tick -= OnTick;
                _timer = null;
            }

            Apply(false);
            _appliedState = -1;
            return;
        }

        try
        {
            bool hide = ShouldHide();

            int wanted = hide ? 1 : 0;
            if (wanted == _appliedState) return;

            Apply(hide);
            _appliedState = wanted;
        }
        catch
        {
            // An exception escaping a timer callback kills the timer, and the feature would be dead
            // for the rest of the session with no visible cause.
        }
    }

    private static bool ShouldHide()
    {
        List<IntPtr> bars = FindTaskbars();
        if (bars.Count == 0) return false;

        bool primaryScope = string.Equals(
            TuningRegistry.Choice(TuningRegistry.TaskbarHideScope), "primary",
            StringComparison.OrdinalIgnoreCase);

        bool anyCovered = false;

        foreach (IntPtr bar in bars)
        {
            bool covered = IsCovered(bar);

            if (primaryScope)
            {
                // FindTaskbars puts the primary bar first, so the first answer is the only one that
                // matters in this scope.
                return covered;
            }

            if (!covered) return false;
            anyCovered = true;
        }

        return anyCovered;
    }

    /// <summary>
    /// The primary taskbar first, then every secondary one. Secondary bars all share the class
    /// Shell_SecondaryTrayWnd, so they are found by enumerating rather than by FindWindow.
    /// </summary>
    private static List<IntPtr> FindTaskbars()
    {
        List<IntPtr> bars = new(2);

        IntPtr primary = NativeMethods.FindWindow("Shell_TrayWnd", null);
        if (primary != IntPtr.Zero) bars.Add(primary);

        try
        {
            NativeMethods.EnumWindows((hwnd, _) =>
            {
                StringBuilder sb = new(48);
                NativeMethods.GetClassName(hwnd, sb, sb.Capacity);

                if (sb.ToString() == "Shell_SecondaryTrayWnd") bars.Add(hwnd);
                return true;
            }, IntPtr.Zero);
        }
        catch
        {
            // A failed enumeration leaves just the primary bar, which is the old behaviour and
            // still better than doing nothing.
        }

        return bars;
    }

    /// <summary>
    /// True when something that is not the shell sits over this taskbar.
    ///
    /// The probe point is the centre of the bar, two pixels above its top edge - which is inside the
    /// window that covers it, not inside the bar. Probing the bar itself would only ever find the
    /// bar.
    /// </summary>
    private static bool IsCovered(IntPtr bar)
    {
        if (!NativeMethods.GetWindowRect(bar, out NativeMethods.RECT r)) return false;

        int height = r.Bottom - r.Top;
        if (height <= 0) return false;

        // A hidden auto-hide bar sits almost entirely off screen, so its own rect cannot be used to
        // find "just above it". The monitor's bottom edge can.
        NativeMethods.POINT centre = new() { X = (r.Left + r.Right) / 2, Y = r.Top + height / 2 };
        IntPtr monitor = NativeMethods.MonitorFromPoint(centre, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (monitor == IntPtr.Zero) return false;

        NativeMethods.MONITORINFO info = new();
        info.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
        if (!NativeMethods.GetMonitorInfo(monitor, ref info)) return false;

        NativeMethods.POINT probe = new()
        {
            X = (info.rcMonitor.Left + info.rcMonitor.Right) / 2,
            Y = info.rcMonitor.Bottom - height - 2
        };

        IntPtr hwnd = NativeMethods.WindowFromPoint(probe);
        if (hwnd == IntPtr.Zero) return false;

        IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
        if (root == IntPtr.Zero) return false;

        StringBuilder sb = new(64);
        NativeMethods.GetClassName(root, sb, sb.Capacity);
        string cls = sb.ToString();

        // The desktop and the shell's own surfaces are not "covering" anything, and neither are this
        // app's own overlays - the taskbar clock sits ON the bar by design, and letting it count as
        // coverage would hide the bar the clock is drawn on.
        if (IsShellSurface(cls)) return false;

        NativeMethods.GetWindowThreadProcessId(root, out uint pid);
        if (pid == (uint)Environment.ProcessId) return false;

        return true;
    }

    private static bool IsShellSurface(string cls)
    {
        return cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd"
            or "Windows.UI.Core.CoreWindow" or "TopLevelWindowForOverflowXamlIsland"
            or "Shell_InputSwitchTopLevelWindow" or "NotifyIconOverflowWindow";
    }

    /// <summary>
    /// Sets the system-wide auto-hide state. The handle is the primary taskbar because the API wants
    /// one, but the effect covers every bar - which is the whole reason ShouldHide considers them
    /// all.
    /// </summary>
    private static void Apply(bool hide)
    {
        try
        {
            IntPtr bar = NativeMethods.FindWindow("Shell_TrayWnd", null);
            if (bar == IntPtr.Zero) return;

            APPBARDATA data = new()
            {
                cbSize = Marshal.SizeOf(typeof(APPBARDATA)),
                hWnd = bar,
                lParam = new IntPtr(hide ? ABS_AUTOHIDE : ABS_ALWAYSONTOP)
            };

            SHAppBarMessage(ABM_SETSTATE, ref data);
        }
        catch
        {
        }
    }

    [DllImport("shell32.dll")]
    private static extern int SHAppBarMessage(int dwMessage, ref APPBARDATA pData);

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uCallbackMessage;
        public int uEdge;
        public NativeMethods.RECT rc;
        public IntPtr lParam;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
