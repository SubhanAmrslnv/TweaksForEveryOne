using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class NextMonitorFeature
{
    private const uint SWP_NOZORDER = 0x0004;

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        // Un-maximize if maximized
        NativeMethods.ShowWindow(hwnd, NativeMethods.SW_RESTORE);

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT winRect)) return;

        NativeMethods.RECT frameRect = winRect;
        if (NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT dRect, Marshal.SizeOf(typeof(NativeMethods.RECT))) == 0)
        {
            frameRect = dRect;
        }

        // Get all monitors
        List<NativeMethods.MONITORINFO> monitors = new List<NativeMethods.MONITORINFO>();
        List<IntPtr> monitorHandles = new List<IntPtr>();

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref NativeMethods.RECT lprcMonitor, IntPtr dwData) =>
        {
            NativeMethods.MONITORINFO mi = new NativeMethods.MONITORINFO();
            mi.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
            if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
            {
                monitors.Add(mi);
                monitorHandles.Add(hMonitor);
            }
            return true;
        }, IntPtr.Zero);

        if (monitors.Count < 2) return; // Need at least 2 monitors

        IntPtr currentHMonitor = NativeMethods.MonitorFromWindow(hwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        int curIdx = monitorHandles.IndexOf(currentHMonitor);
        if (curIdx == -1) curIdx = 0;

        int nxtIdx = (curIdx + 1) % monitors.Count;

        NativeMethods.MONITORINFO src = monitors[curIdx];
        NativeMethods.MONITORINFO dst = monitors[nxtIdx];

        int sw = src.rcWork.Right - src.rcWork.Left;
        int sh = src.rcWork.Bottom - src.rcWork.Top;
        int dw = dst.rcWork.Right - dst.rcWork.Left;
        int dh = dst.rcWork.Bottom - dst.rcWork.Top;

        if (sw <= 0 || sh <= 0) return;

        int fw = frameRect.Right - frameRect.Left;
        int fh = frameRect.Bottom - frameRect.Top;

        // Scale visual frame
        int tw = (int)Math.Round((double)fw * dw / sw);
        int th = (int)Math.Round((double)fh * dh / sh);

        int tx = dst.rcWork.Left + (int)Math.Round((double)(frameRect.Left - src.rcWork.Left) * dw / sw);
        int ty = dst.rcWork.Top + (int)Math.Round((double)(frameRect.Top - src.rcWork.Top) * dh / sh);

        // Clamp
        if (tw > dw) tw = dw;
        if (th > dh) th = dh;
        if (tx + tw > dst.rcWork.Right) tx = dst.rcWork.Right - tw;
        if (ty + th > dst.rcWork.Bottom) ty = dst.rcWork.Bottom - th;
        if (tx < dst.rcWork.Left) tx = dst.rcWork.Left;
        if (ty < dst.rcWork.Top) ty = dst.rcWork.Top;

        // Compute Win32 offset for invisible DWM borders
        int borderW = (winRect.Right - winRect.Left) - fw;
        int borderH = (winRect.Bottom - winRect.Top) - fh;
        int offsetX = winRect.Left - frameRect.Left;
        int offsetY = winRect.Top - frameRect.Top;

        int finalX = tx + offsetX;
        int finalY = ty + offsetY;
        int finalW = tw + borderW;
        int finalH = th + borderH;

        LayoutHistoryManager.SaveLayout(hwnd, winRect);
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, finalX, finalY, finalW, finalH, SWP_NOZORDER);
    }
}
