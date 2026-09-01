using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class ResetTransparencyFeature
{
    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        // Skip Desktop / Taskbar
        System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") return;

        uint style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        
        if ((style & NativeMethods.WS_EX_LAYERED) != 0)
        {
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, style & ~NativeMethods.WS_EX_LAYERED);
        }
    }
}
