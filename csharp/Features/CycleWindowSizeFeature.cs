using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class CycleWindowSizeFeature
{
    private class CycleState
    {
        public int Index;
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private Dictionary<IntPtr, CycleState> _cycleStates = new();
    private readonly double[] SIZE_CYCLE = { 0.50, 0.75, 0.90 };
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

        IntPtr hMonitor = NativeMethods.MonitorFromWindow(hwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (hMonitor == IntPtr.Zero) return;

        NativeMethods.MONITORINFO monitorInfo = new NativeMethods.MONITORINFO();
        monitorInfo.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
        if (!NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo)) return;

        int idx = 0;
        if (_cycleStates.TryGetValue(hwnd, out CycleState st))
        {
            // If window hasn't been moved/resized by the user manually, continue cycle
            if (Math.Abs(st.Left - frameRect.Left) <= 2 &&
                Math.Abs(st.Top - frameRect.Top) <= 2 &&
                Math.Abs(st.Right - frameRect.Right) <= 2 &&
                Math.Abs(st.Bottom - frameRect.Bottom) <= 2)
            {
                idx = (st.Index + 1) % SIZE_CYCLE.Length;
            }
        }

        double frac = SIZE_CYCLE[idx];

        int workW = monitorInfo.rcWork.Right - monitorInfo.rcWork.Left;
        int workH = monitorInfo.rcWork.Bottom - monitorInfo.rcWork.Top;

        // Target visual frame size
        int tw = (int)Math.Round(workW * frac);
        int th = (int)Math.Round(workH * frac);
        
        // Target visual frame center
        int tx = monitorInfo.rcWork.Left + (workW - tw) / 2;
        int ty = monitorInfo.rcWork.Top + (workH - th) / 2;

        // Save target visual frame to state for next cycle check
        _cycleStates[hwnd] = new CycleState
        {
            Index = idx,
            Left = tx,
            Top = ty,
            Right = tx + tw,
            Bottom = ty + th
        };

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
