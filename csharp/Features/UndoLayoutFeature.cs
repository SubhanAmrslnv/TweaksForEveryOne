using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class UndoLayoutFeature
{
    private const uint SWP_NOZORDER = 0x0004;

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        if (LayoutHistoryManager.TryPopLayout(hwnd, out NativeMethods.RECT savedRect))
        {
            int w = savedRect.Right - savedRect.Left;
            int h = savedRect.Bottom - savedRect.Top;
            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, savedRect.Left, savedRect.Top, w, h, SWP_NOZORDER);
        }
    }
}
