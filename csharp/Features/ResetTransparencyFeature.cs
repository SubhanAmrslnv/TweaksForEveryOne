using System;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Shift+Alt+X returns the active window to fully opaque.
///
/// This goes through AlphaCompositor.Reset rather than stripping WS_EX_LAYERED by hand. Doing it by
/// hand left the compositor still believing the window was dimmed, so the next ambient tick simply
/// put the transparency back - and it also stripped a style the app itself might have set, which is
/// what causes black flicker in some WPF and WinForms windows.
/// </summary>
public class ResetTransparencyFeature
{
    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        StringBuilder sb = new(256);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls is "Shell_TrayWnd" or "Progman" or "WorkerW" or "Shell_SecondaryTrayWnd") return;

        // Clears the user's base AND every ambient layer, then drops the record entirely.
        AlphaCompositor.Reset(hwnd);
    }
}
