using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class CenterWindowFeature
{
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOSIZE = 0x0001;

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

        IntPtr hMonitor = NativeMethods.MonitorFromWindow(hwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (hMonitor == IntPtr.Zero) return;

        NativeMethods.MONITORINFO monitorInfo = new NativeMethods.MONITORINFO();
        monitorInfo.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
        if (!NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo)) return;

        int frameW = frameRect.Right - frameRect.Left;
        int frameH = frameRect.Bottom - frameRect.Top;

        int workW = monitorInfo.rcWork.Right - monitorInfo.rcWork.Left;
        int workH = monitorInfo.rcWork.Bottom - monitorInfo.rcWork.Top;

        // Calculate exact center in visual DWM space
        int newFrameL = monitorInfo.rcWork.Left + (workW - frameW) / 2;
        int newFrameT = monitorInfo.rcWork.Top + (workH - frameH) / 2;

        // Adjust to Win32 logical space
        int offsetX = winRect.Left - frameRect.Left;
        int offsetY = winRect.Top - frameRect.Top;

        int finalX = newFrameL + offsetX;
        int finalY = newFrameT + offsetY;

        LayoutHistoryManager.SaveLayout(hwnd, winRect);
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, finalX, finalY, 0, 0, SWP_NOZORDER | SWP_NOSIZE);
    }
}
