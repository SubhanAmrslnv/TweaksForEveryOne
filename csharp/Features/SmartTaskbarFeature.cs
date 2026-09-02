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
/// the desktop. The taskbar handles themselves are cached, because they only change when the display
/// layout does or when Explorer restarts.
///
/// THE PROBE HAS THREE ANSWERS, NOT TWO. Hovering the bottom edge reveals a hidden bar, and the probe
/// then finds the BAR - which establishes nothing about what is behind it. Reading that as "not
/// covered" switched auto-hide off for one tick and back on at the next, so the bar flickered for as
/// long as the pointer rested there. See <see cref="Coverage.Unknown"/>.
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

    /// <summary>How long the discovered taskbar handles are trusted. See Taskbars().</summary>
    private const int TaskbarCacheMs = 5000;

    /// <summary>Below this a taskbar rectangle is a hidden sliver, not a bar. See Probe().</summary>
    private const int MinRealBarHeightPx = 16;

    private DispatcherTimer? _timer;

    /// <summary>-1 until the first decision, so the first tick always applies its result.</summary>
    private int _appliedState = -1;

    private readonly List<IntPtr> _taskbars = new(2);
    private long _taskbarsFoundAt;

    /// <summary>The height the bar has when it is actually shown. Seeded with the Windows 11 default.</summary>
    private int _lastBarHeight = 48;

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
            bool? hide = ShouldHide();

            // Nothing could be established this tick - the pointer is resting on a revealed bar.
            // Keep the current state rather than guessing, or the bar flickers.
            if (hide == null) return;

            int wanted = hide.Value ? 1 : 0;
            if (wanted == _appliedState) return;

            Apply(hide.Value);
            _appliedState = wanted;
        }
        catch
        {
            // An exception escaping a timer callback kills the timer, and the feature would be dead
            // for the rest of the session with no visible cause.
        }
    }

    /// <summary>What one probe of one taskbar could establish.</summary>
    private enum Coverage
    {
        /// <summary>A normal window sits over the bar.</summary>
        Covered,

        /// <summary>The desktop, or the shell, or one of this app's own overlays.</summary>
        Clear,

        /// <summary>
        /// The probe found the taskbar itself, which answers nothing. This is not a rare corner: it
        /// is what happens every time the user hovers the bottom edge to reveal a hidden bar. Treating
        /// it as "clear" made the feature switch auto-hide OFF on that tick and back ON at the next
        /// one, so the bar visibly flickered for as long as the pointer rested there.
        /// </summary>
        Unknown
    }

    /// <summary>Null when nothing could be established this tick, so the caller keeps its decision.</summary>
    private bool? ShouldHide()
    {
        IReadOnlyList<IntPtr> bars = Taskbars();
        if (bars.Count == 0) return false;

        bool primaryOnly = TuningRegistry.Is(TuningRegistry.TaskbarHideScope, "primary");

        bool sawAnswer = false;
        bool allCovered = true;

        foreach (IntPtr bar in bars)
        {
            Coverage coverage = Probe(bar);

            // Taskbars() puts the primary bar first, so in this scope the first real answer is the
            // only one that matters.
            if (primaryOnly) return coverage == Coverage.Unknown ? null : coverage == Coverage.Covered;

            if (coverage == Coverage.Unknown) continue;

            sawAnswer = true;
            if (coverage != Coverage.Covered) allCovered = false;
        }

        if (!sawAnswer) return null;
        return allCovered;
    }

    /// <summary>
    /// The primary taskbar first, then every secondary one. Secondary bars all share the class
    /// Shell_SecondaryTrayWnd, so they are found by enumerating rather than by FindWindow.
    ///
    /// THE RESULT IS CACHED, because the answer only changes when the display layout does. This used
    /// to enumerate every top-level window in the system on every tick - two and a half times a
    /// second, allocating a StringBuilder per window - to rediscover two handles that had not moved.
    /// A time-based refresh rather than a WM_DISPLAYCHANGE hook: this feature owns no window to
    /// receive that message on, and re-enumerating every few seconds also recovers from an Explorer
    /// restart, which invalidates the handles without changing the display layout at all.
    /// </summary>
    private IReadOnlyList<IntPtr> Taskbars()
    {
        long now = Environment.TickCount64;

        bool stale = _taskbars.Count == 0 || now - _taskbarsFoundAt > TaskbarCacheMs;

        if (!stale)
        {
            // Cheap validity check: an Explorer restart replaces every bar, and a stale handle would
            // silently report "clear" for the rest of the cache window.
            foreach (IntPtr bar in _taskbars)
            {
                if (NativeMethods.IsWindow(bar)) continue;
                stale = true;
                break;
            }
        }

        if (!stale) return _taskbars;

        _taskbars.Clear();
        _taskbarsFoundAt = now;

        IntPtr primary = NativeMethods.FindWindow("Shell_TrayWnd", null);
        if (primary != IntPtr.Zero) _taskbars.Add(primary);

        try
        {
            StringBuilder sb = new(48);

            NativeMethods.EnumWindows((hwnd, _) =>
            {
                // One StringBuilder for the whole enumeration. A fresh one per window is a couple of
                // hundred allocations per sweep for nothing.
                sb.Clear();
                NativeMethods.GetClassName(hwnd, sb, sb.Capacity);

                if (sb.ToString() == "Shell_SecondaryTrayWnd") _taskbars.Add(hwnd);
                return true;
            }, IntPtr.Zero);
        }
        catch
        {
            // A failed enumeration leaves just the primary bar, which is the old behaviour and
            // still better than doing nothing.
        }

        return _taskbars;
    }

    /// <summary>
    /// Asks what sits over one taskbar, by looking just above where that bar would be if it were
    /// visible. Probing the bar's own rectangle would only ever find the bar.
    /// </summary>
    private Coverage Probe(IntPtr bar)
    {
        if (!NativeMethods.GetWindowRect(bar, out NativeMethods.RECT r)) return Coverage.Unknown;

        NativeMethods.POINT centre = new() { X = (r.Left + r.Right) / 2, Y = (r.Top + r.Bottom) / 2 };
        IntPtr monitor = NativeMethods.MonitorFromPoint(centre, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (monitor == IntPtr.Zero) return Coverage.Unknown;

        NativeMethods.MONITORINFO info = new();
        info.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
        if (!NativeMethods.GetMonitorInfo(monitor, ref info)) return Coverage.Unknown;

        // The bar's CURRENT height is not usable: a hidden auto-hide bar is a two-pixel sliver, so a
        // probe derived from it lands inside the band the bar occupies when it comes back. The last
        // height seen while the bar was a real bar is remembered instead.
        int height = r.Bottom - r.Top;
        if (height >= MinRealBarHeightPx) _lastBarHeight = height;

        NativeMethods.POINT probe = new()
        {
            X = (info.rcMonitor.Left + info.rcMonitor.Right) / 2,
            Y = info.rcMonitor.Bottom - _lastBarHeight - 2
        };

        IntPtr hwnd = NativeMethods.WindowFromPoint(probe);
        if (hwnd == IntPtr.Zero) return Coverage.Clear;

        IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
        if (root == IntPtr.Zero) return Coverage.Clear;

        StringBuilder sb = new(64);
        NativeMethods.GetClassName(root, sb, sb.Capacity);
        string cls = sb.ToString();

        // A revealed taskbar answers nothing at all - see Coverage.Unknown.
        if (cls is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return Coverage.Unknown;

        // The desktop and the shell's other surfaces are not covering anything, and neither are this
        // app's own overlays - the taskbar clock sits ON the bar by design, and letting it count as
        // coverage would hide the bar the clock is drawn on.
        if (IsShellSurface(cls)) return Coverage.Clear;

        NativeMethods.GetWindowThreadProcessId(root, out uint pid);
        if (pid == (uint)Environment.ProcessId) return Coverage.Clear;

        return Coverage.Covered;
    }

    /// <summary>
    /// Shell surfaces that are not "covering" the taskbar: the desktop, and the shell's own small
    /// windows. The taskbar classes themselves are deliberately absent - Probe tests for those first
    /// and answers Unknown, because finding the bar establishes nothing about what is behind it.
    /// </summary>
    private static bool IsShellSurface(string cls)
    {
        return cls is "Progman" or "WorkerW"
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
