using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class TileWindowFeature
{
    private const uint SWP_NOZORDER = 0x0004;

    public void TileWindow(int cell)
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

        int wl = monitorInfo.rcWork.Left;
        int wt = monitorInfo.rcWork.Top;
        int wr = monitorInfo.rcWork.Right;
        int wb = monitorInfo.rcWork.Bottom;

        int aw = wr - wl;
        int ah = wb - wt;
        int hw = aw / 2;
        int hh = ah / 2;
        
        // The far half takes the remainder, so an odd work-area width leaves no one-pixel seam
        int rw = aw - hw;
        int rh = ah - hh;

        int tx = wl, ty = wt, tw = hw, th = hh;

        switch (cell)
        {
            case 7: tx = wl;      ty = wt;      tw = hw; th = hh; break;
            case 8: tx = wl;      ty = wt;      tw = aw; th = hh; break;
            case 9: tx = wl + hw; ty = wt;      tw = rw; th = hh; break;
            case 4: tx = wl;      ty = wt;      tw = hw; th = ah; break;
            case 5: tx = wl + rw / 2; ty = wt + rh / 2; tw = hw; th = hh; break;
            case 6: tx = wl + hw; ty = wt;      tw = rw; th = ah; break;
            case 1: tx = wl;      ty = wt + hh; tw = hw; th = rh; break;
            case 2: tx = wl;      ty = wt + hh; tw = aw; th = rh; break;
            case 3: tx = wl + hw; ty = wt + hh; tw = rw; th = rh; break;
            default: return;
        }

        // Compute Win32 offset for invisible DWM borders
        int borderW = (winRect.Right - winRect.Left) - (frameRect.Right - frameRect.Left);
        int borderH = (winRect.Bottom - winRect.Top) - (frameRect.Bottom - frameRect.Top);
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
