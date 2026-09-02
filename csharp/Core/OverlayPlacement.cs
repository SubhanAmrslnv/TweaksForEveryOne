using System;
using System.Windows;
using System.Windows.Interop;

namespace WindowTweaks.Core;

/// <summary>
/// Puts a WPF overlay window at a point that came from a mouse hook.
///
/// THE BUG THIS EXISTS TO PREVENT. A low-level mouse hook reports PHYSICAL pixels. WPF's
/// Window.Left / Top / Width / Height are device-independent units. Assigning one to the other is
/// correct only at 100% scaling, and every overlay in this app did exactly that: on a 150% display
/// the cursor locator, the clipboard OSD and the text magnifier all landed two thirds of the way
/// towards the top-left corner of the screen, which is why they were reported as "does not appear"
/// rather than "appears in the wrong place". On a 4K laptop panel at 250% they were off screen.
///
/// The fix is to stop mixing the two coordinate spaces. Size is still set in WPF units, because the
/// content inside is laid out in WPF units and should scale with the display like everything else;
/// POSITION is applied with SetWindowPos in physical pixels, where the hook's numbers already live.
///
/// The app is manifested PerMonitorV2 (see app.manifest), so the scale factor is a property of the
/// monitor the overlay is going to, not of the process - hence <see cref="ScaleAt"/> resolving the
/// monitor from the point rather than caching one number.
/// </summary>
internal static class OverlayPlacement
{
    /// <summary>
    /// The scale factor of the monitor containing a physical point: 1.0 at 96 DPI, 1.5 at 150%.
    /// Falls back to 1.0, which is the pre-existing behaviour and never worse than it.
    /// </summary>
    public static double ScaleAt(int physicalX, int physicalY)
    {
        try
        {
            NativeMethods.POINT pt = new() { X = physicalX, Y = physicalY };
            IntPtr monitor = NativeMethods.MonitorFromPoint(pt, NativeMethods.MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return 1.0;

            if (NativeMethods.GetDpiForMonitor(monitor, NativeMethods.MDT_EFFECTIVE_DPI,
                    out uint dpiX, out uint _) != 0)
            {
                return 1.0;
            }

            if (dpiX == 0) return 1.0;
            return dpiX / 96.0;
        }
        catch
        {
            // shcore.dll is present on every version this app supports, but a missing export must
            // degrade to an overlay in a slightly wrong place, not to an exception in a hook.
            return 1.0;
        }
    }

    /// <summary>
    /// Moves a window so its top-left corner is at a physical desktop pixel, clamped so the whole
    /// window stays on the monitor it landed on.
    ///
    /// The window must already have a handle - call this after Show(), or from SourceInitialized.
    /// It does nothing (rather than throwing) before then, because the alternative is a feature that
    /// crashes the first time it is used.
    /// </summary>
    public static void MoveTo(Window? window, int physicalX, int physicalY, bool clampToMonitor = true)
    {
        if (window == null) return;

        try
        {
            IntPtr hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;

            if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT current)) return;

            int width = current.Right - current.Left;
            int height = current.Bottom - current.Top;

            int x = physicalX;
            int y = physicalY;

            if (clampToMonitor)
            {
                NativeMethods.POINT pt = new() { X = physicalX, Y = physicalY };
                IntPtr monitor = NativeMethods.MonitorFromPoint(pt, NativeMethods.MONITOR_DEFAULTTONEAREST);

                if (monitor != IntPtr.Zero)
                {
                    NativeMethods.MONITORINFO info = new();
                    info.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));

                    if (NativeMethods.GetMonitorInfo(monitor, ref info))
                    {
                        // rcMonitor, not rcWork: an overlay is allowed over the taskbar, and the
                        // clock block deliberately sits on it.
                        int right = info.rcMonitor.Right - width;
                        int bottom = info.rcMonitor.Bottom - height;

                        // Math.Max guards the case of a window wider than the monitor, where the
                        // clamp bounds cross over and Math.Clamp would throw.
                        x = Math.Clamp(x, info.rcMonitor.Left, Math.Max(info.rcMonitor.Left, right));
                        y = Math.Clamp(y, info.rcMonitor.Top, Math.Max(info.rcMonitor.Top, bottom));
                    }
                }
            }

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
        }
        catch
        {
        }
    }

    /// <summary>
    /// Centres a window on a physical point - what almost every overlay here actually wants, since
    /// the point is the cursor.
    /// </summary>
    public static void CentreOn(Window? window, int physicalX, int physicalY, bool clampToMonitor = true)
    {
        if (window == null) return;

        try
        {
            IntPtr hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT current)) return;

            int width = current.Right - current.Left;
            int height = current.Bottom - current.Top;

            MoveTo(window, physicalX - width / 2, physicalY - height / 2, clampToMonitor);
        }
        catch
        {
        }
    }

    /// <summary>
    /// Applies the styles that make an overlay a true overlay: click-through at the Win32 level,
    /// never activated, never in Alt-Tab.
    ///
    /// WPF's IsHitTestVisible is NOT enough. It only stops hit-testing inside the WPF tree; Win32
    /// still returns the window from WindowFromPoint, so without WS_EX_TRANSPARENT an invisible
    /// overlay becomes a dead zone that swallows clicks meant for the application underneath.
    /// </summary>
    public static void MakeClickThrough(Window? window)
    {
        if (window == null) return;

        try
        {
            IntPtr hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;

            uint ex = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
                ex | NativeMethods.WS_EX_TRANSPARENT
                   | NativeMethods.WS_EX_NOACTIVATE
                   | NativeMethods.WS_EX_TOOLWINDOW);
        }
        catch
        {
        }
    }
}
