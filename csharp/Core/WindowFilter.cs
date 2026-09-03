using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace WindowTweaks.Core;

/// <summary>
/// Whether a foreign window may be touched at all, and what kind of window it is.
///
/// This exists because the same predicate was written six times, differently, as a private method
/// inside whichever feature needed it - so BreathingFeature excluded four shell classes while
/// SmartTaskbarFeature excluded eight, and nothing kept the lists in step. The tests here are the
/// union of what those features already did, plus the two that CLAUDE.md records as necessary and
/// nobody had implemented: DWMWA_CLOAKED and an own-process check.
///
/// ORDERED CHEAPEST FIRST, and that ordering is the design. Style and state getters cost ~0.3 us, a
/// class name ~1 us, a DWM attribute ~2 us and naming a process far more, so the gate is arranged so
/// that the common answer - an ordinary window, or an obvious shell surface - is reached without
/// paying for the expensive tests at all.
///
/// AlphaCompositor's header carries the rule this file serves: "Never make a foreign window layered
/// speculatively ... can break exclusive full-screen presentation. Decide eligibility BEFORE touching
/// it." The compositor trusts its caller to have decided. This is where a caller decides.
/// </summary>
internal static class WindowFilter
{
    /// <summary>
    /// One buffer per thread, reused. A fresh StringBuilder per window is a couple of hundred
    /// allocations per sweep for nothing (SmartTaskbarFeature hoists one out of its enumeration for
    /// exactly this reason); [ThreadStatic] rather than a plain static because a background-thread
    /// caller must not share it.
    /// </summary>
    [ThreadStatic]
    private static StringBuilder? _scratch;

    /// <summary>
    /// Shell surfaces, the taskbar and the desktop: windows that belong to Explorer's own UI and are
    /// never an application window a user thinks of as "a window".
    ///
    /// ApplicationFrameWindow is DELIBERATELY ABSENT. That is the host window of every packaged UWP
    /// app - Calculator, Photos, Settings - and it is exactly the kind of window an ambient effect
    /// should act on. Only the hosted Windows.UI.Core.CoreWindow is excluded, and for a real UWP app
    /// that one is cloaked anyway.
    /// </summary>
    private static readonly HashSet<string> ShellClasses = new(StringComparer.Ordinal)
    {
        // The taskbars and the desktop.
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "Progman",
        "WorkerW",

        // Start, Search, the tray overflow flyout, the input-method switcher.
        "Windows.UI.Core.CoreWindow",
        "TopLevelWindowForOverflowXamlIsland",
        "Shell_InputSwitchTopLevelWindow",
        "NotifyIconOverflowWindow",

        // Alt+Tab and Task View. Dimming the window switcher while the user is holding Alt+Tab is
        // the most visible form of this bug, and it was reachable before.
        "XamlExplorerHostIslandWindow",
        "MultitaskingViewFrame"
    };

    /// <summary>
    /// Chromium and Gecko top-level window classes. Every Chromium-based browser shares
    /// Chrome_WidgetWin_1, as does every Electron app - which is why a class match alone is never
    /// treated as proof of anything except "this could be a browser window".
    /// </summary>
    private static readonly HashSet<string> BrowserClasses = new(StringComparer.Ordinal)
    {
        "Chrome_WidgetWin_1",
        "Chrome_WidgetWin_0",
        "MozillaWindowClass"
    };

    /// <summary>
    /// Browser image names, for a build that renamed its window class - portable builds, forks and
    /// repackaged browsers. A set built once, rather than a chain of == against a ToLowerInvariant()
    /// allocated per call.
    /// </summary>
    private static readonly HashSet<string> BrowserExes = new(StringComparer.Ordinal)
    {
        "chrome", "msedge", "firefox", "brave", "opera", "opera_gx",
        "vivaldi", "chromium", "thorium", "librewolf", "waterfox", "yandex"
    };

    /// <summary>
    /// Titles a Picture-in-Picture window may carry, matched UNANCHORED and case-insensitively.
    ///
    /// Plain strings and not a Regex: the previous version compiled a pattern per call, and anchored
    /// it as ^(...)$ - which made it near-useless, because Chrome titles its PiP window with the PAGE
    /// title and never with the words "Picture in Picture". Firefox does title its window literally
    /// "Picture-in-Picture", which is the case this actually catches.
    /// </summary>
    private static readonly string[] PipTitles =
    {
        "Picture-in-Picture",
        "Picture in Picture",
        "PiP",
        "Картинка в картинке",
        "Resim içinde resim",
        "Şəkil içində şəkil"
    };

    /// <summary>
    /// True for an ordinary, visible, on-screen, foreign top-level application window - the only kind
    /// an ambient effect may touch at all.
    /// </summary>
    public static bool IsOrdinaryAppWindow(IntPtr hwnd) => IsOrdinaryAppWindow(hwnd, out _);

    /// <summary>
    /// The same test, handing back the class name it had to fetch anyway so the caller does not pay
    /// for it twice. <paramref name="cls"/> is always assigned, "" when it could not be read.
    /// </summary>
    public static bool IsOrdinaryAppWindow(IntPtr hwnd, out string cls)
    {
        cls = string.Empty;

        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;
        if (!NativeMethods.IsWindowVisible(hwnd)) return false;

        // A minimized window: dimming it achieves nothing and shows one dim frame on restore.
        if (NativeMethods.IsIconic(hwnd)) return false;

        // Our own windows. This app's OSD readouts, ripple overlays, magnifier lens and taskbar clock
        // are all real top-level windows, and an effect that dimmed them would be dimming itself.
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == 0 || pid == (uint)Environment.ProcessId) return false;

        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        if ((exStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0) return false;

        cls = ClassOf(hwnd);
        if (cls.Length == 0) return false;          // caught mid-creation
        if (ShellClasses.Contains(cls)) return false;

        // Last, because it is the only DWM call in the gate: a cloaked window is on another virtual
        // desktop or is a suspended UWP app. IsWindowVisible returns TRUE for both.
        if (IsCloaked(hwnd)) return false;

        return true;
    }

    /// <summary>The window's class name, or "" if it could not be read.</summary>
    public static string ClassOf(IntPtr hwnd)
    {
        StringBuilder sb = _scratch ??= new StringBuilder(256);
        sb.Clear();
        sb.EnsureCapacity(256);

        int written = NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        return written > 0 ? sb.ToString() : string.Empty;
    }

    /// <summary>The window's title, or "" if it could not be read.</summary>
    public static string TitleOf(IntPtr hwnd)
    {
        StringBuilder sb = _scratch ??= new StringBuilder(256);
        sb.Clear();
        sb.EnsureCapacity(256);

        int written = NativeMethods.GetWindowText(hwnd, sb, sb.Capacity);
        return written > 0 ? sb.ToString() : string.Empty;
    }

    public static bool IsShellClass(string cls) => ShellClasses.Contains(cls);

    public static bool IsBrowserClass(string cls) => BrowserClasses.Contains(cls);

    /// <summary>
    /// True when DWM reports the window cloaked: another virtual desktop, or a suspended UWP app.
    /// A failed query answers false - an unreadable attribute is not evidence of cloaking, and the
    /// rest of the gate has already established this is an ordinary window.
    /// </summary>
    public static bool IsCloaked(IntPtr hwnd)
    {
        int cloaked = 0;
        int hr = NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_CLOAKED, out cloaked, sizeof(int));
        return hr == 0 && cloaked != 0;
    }

    /// <summary>
    /// True when the window has an owner - a dialog, a palette, a popup.
    ///
    /// Exposed on its own and NEVER folded into IsOrdinaryAppWindow. It is the right test for
    /// position memory, where every Chrome popup shares a class with the main window and would
    /// otherwise overwrite its remembered rectangle. It is the wrong test for an ambient effect:
    /// dialogs and tool palettes are owned windows that should still fade.
    /// </summary>
    public static bool IsOwned(IntPtr hwnd) => NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero;

    /// <summary>
    /// True when the window has a sizing border.
    ///
    /// Exposed on its own for the same reason as <see cref="IsOwned"/>: installers, login boxes,
    /// mini players and a great many WS_POPUP application windows are not resizable, and all of them
    /// are windows a user expects an ambient effect to act on.
    /// </summary>
    public static bool IsResizable(IntPtr hwnd)
        => (NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_STYLE) & NativeMethods.WS_THICKFRAME) != 0;

    /// <summary>
    /// True when the window looks like a browser's Picture-in-Picture player.
    ///
    /// The style pair is the gate and nothing past it runs unless it passes: a PiP window is always
    /// topmost and never maximizable, and testing that costs two ~0.3 us getters. Only then does this
    /// look at the class, then at the image name, then at the title - in increasing order of cost.
    ///
    /// Accepted false positive: any topmost, non-maximizable Chromium window is treated as PiP, which
    /// takes in Chrome's own bubbles and some Electron overlays. The cost of being wrong that way is
    /// that a small transient window does not fade, which is the answer wanted anyway; the cost of the
    /// opposite error is a dimmed video, which is the bug being fixed.
    /// </summary>
    public static bool IsPictureInPicture(IntPtr hwnd)
    {
        uint style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_STYLE);
        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);

        if ((exStyle & NativeMethods.WS_EX_TOPMOST) == 0) return false;
        if ((style & NativeMethods.WS_MAXIMIZEBOX) != 0) return false;

        if (IsBrowserClass(ClassOf(hwnd))) return true;

        string exe = ProcessNameCache.ForWindow(hwnd);
        if (exe.Length != 0 && BrowserExes.Contains(exe)) return true;

        string title = TitleOf(hwnd);
        if (title.Length == 0) return false;

        foreach (string name in PipTitles)
        {
            if (title.Contains(name, StringComparison.OrdinalIgnoreCase)) return true;
        }

        return false;
    }

    /// <summary>
    /// True when the window covers its monitor's full rectangle - a fullscreen video, a borderless
    /// game, a presentation.
    ///
    /// rcMonitor, NOT rcWork. A merely MAXIMIZED window matches rcWork, because the taskbar band is
    /// excluded from it - so maximized windows are not caught here and keep breathing, which is what
    /// they should do. Only a window covering the monitor including the taskbar band is fullscreen.
    ///
    /// Inequalities, not equality. GetWindowRect includes the invisible DWM border, so the rectangle
    /// it reports is a few pixels LARGER than the visible frame; an == comparison would miss every
    /// fullscreen window on Windows 11.
    ///
    /// A window whose geometry cannot be read answers TRUE. Everywhere else in this app an unreadable
    /// window means "skip the optimisation", but here it has to mean "do not touch it": the specific
    /// failure being avoided is SetLayeredWindowAttributes breaking exclusive full-screen
    /// presentation, and a window we cannot measure is exactly the one not to gamble on.
    ///
    /// Never call this per-window-per-tick. A window rect plus two monitor queries is ~6-9 us, which
    /// across every top-level window several times a second buys nothing.
    /// </summary>
    public static bool IsFullScreenOnItsMonitor(IntPtr hwnd)
    {
        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r)) return true;

        IntPtr monitor = NativeMethods.MonitorFromWindow(hwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (monitor == IntPtr.Zero) return true;

        NativeMethods.MONITORINFO mi = new() { cbSize = (uint)Marshal.SizeOf<NativeMethods.MONITORINFO>() };
        if (!NativeMethods.GetMonitorInfo(monitor, ref mi)) return true;

        return r.Left <= mi.rcMonitor.Left
            && r.Top <= mi.rcMonitor.Top
            && r.Right >= mi.rcMonitor.Right
            && r.Bottom >= mi.rcMonitor.Bottom;
    }
}
