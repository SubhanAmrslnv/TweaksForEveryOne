using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class AlwaysOnBottomFeature : IDisposable
{
    private Dictionary<IntPtr, WindowRect> _bottomWindows = new();

    public struct WindowRect
    {
        public int X, Y, W, H;
    }

    private IntPtr GetDesktopHwnd()
    {
        IntPtr desktopHwnd = NativeMethods.FindWindow("Progman", null);
        
        NativeMethods.EnumWindows((IntPtr w, IntPtr lParam) =>
        {
            StringBuilder sb = new StringBuilder(256);
            NativeMethods.GetClassName(w, sb, sb.Capacity);
            if (sb.ToString() == "WorkerW")
            {
                IntPtr defView = NativeMethods.FindWindowEx(w, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (defView != IntPtr.Zero)
                {
                    desktopHwnd = w;
                    return false; // Stop enumeration
                }
            }
            return true;
        }, IntPtr.Zero);

        return desktopHwnd;
    }

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        StringBuilder sbCls = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbCls, sbCls.Capacity);
        string cls = sbCls.ToString();

        if (string.IsNullOrEmpty(cls) || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || cls == "Progman" || cls == "WorkerW")
            return;

        if (_bottomWindows.ContainsKey(hwnd))
        {
            RestoreFromBottom(hwnd);
            return;
        }

        IntPtr desktop = GetDesktopHwnd();
        if (desktop == IntPtr.Zero) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
            return;

        int w = rect.Right - rect.Left;
        int h = rect.Bottom - rect.Top;

        if (NativeMethods.SetParent(hwnd, desktop) == IntPtr.Zero)
        {
            Debug.WriteLine("Cannot pin this window to the desktop");
            return;
        }

        _bottomWindows[hwnd] = new WindowRect { X = rect.Left, Y = rect.Top, W = w, H = h };

        NativeMethods.POINT pt = new NativeMethods.POINT { X = rect.Left, Y = rect.Top };
        NativeMethods.ScreenToClient(desktop, ref pt);

        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, pt.X, pt.Y, w, h, NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER);
    }

    private void RestoreFromBottom(IntPtr hwnd)
    {
        if (!_bottomWindows.TryGetValue(hwnd, out WindowRect info))
            return;

        _bottomWindows.Remove(hwnd);

        if (!NativeMethods.IsWindow(hwnd))
            return;

        int x = info.X, y = info.Y, w = info.W, h = info.H;
        if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
        {
            x = rect.Left;
            y = rect.Top;
            w = rect.Right - rect.Left;
            h = rect.Bottom - rect.Top;
        }

        NativeMethods.SetParent(hwnd, IntPtr.Zero);
        // HWND_TOP is 0 according to SetWindowPos docs (actually it's (IntPtr)0 for TOP).
        // In C# it's just IntPtr.Zero.
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, x, y, w, h, NativeMethods.SWP_NOACTIVATE);
    }

    public void Dispose()
    {
        foreach (var hwnd in new List<IntPtr>(_bottomWindows.Keys))
        {
            RestoreFromBottom(hwnd);
        }
    }
}
