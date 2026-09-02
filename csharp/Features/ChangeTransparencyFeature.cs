using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Shift+Alt+Wheel sets the opacity of the window under the cursor.
///
/// The step is applied to the COMPOSITOR'S BASE, not to whatever the window currently shows. The
/// previous version read the value back with GetLayeredWindowAttributes, which returns whatever
/// breathing or ghosting last wrote - so scrolling on a dimmed window jumped to that effect's value
/// and then fought it for control. The base is the user's own choice and nothing else touches it.
///
/// This is the only feature allowed to call AlphaCompositor.SetBase.
/// </summary>
public class ChangeTransparencyFeature : IDisposable
{
    public bool IsEnabled { get; private set; }

    public ChangeTransparencyFeature()
    {
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        // The wheel only, which is what this gesture is.
        if (enabled) MouseHook.Subscribe("ChangeTransparencyFeature", MouseEvents.Wheel, HookCallback);
        else MouseHook.Unsubscribe("ChangeTransparencyFeature");
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool HookCallback(MouseHook.MouseEvent e)
    {
        if (e.Message == NativeMethods.WM_MOUSEWHEEL)
        {
            // Grab and pan scrolls by injecting wheel events. Panning with Shift and Alt held down
            // would otherwise dissolve the window being panned.
            if (e.IsOurs) return false;

            bool isShift = (NativeMethods.GetAsyncKeyState(0x10) & 0x8000) != 0; // VK_SHIFT
            bool isAlt = (NativeMethods.GetAsyncKeyState(0x12) & 0x8000) != 0;   // VK_MENU

            if (isShift && isAlt)
            {
                ChangeTransparency(e.WheelDelta);
                // Swallow the scroll so the window underneath does not also scroll.
                return true;
            }
        }
        return false;
    }

    private static void ChangeTransparency(int delta)
    {
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        IntPtr hwnd = NativeMethods.GetAncestor(NativeMethods.WindowFromPoint(pt), NativeMethods.GA_ROOT);

        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        StringBuilder sb = new(256);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls is "Shell_TrayWnd" or "Progman" or "WorkerW" or "Shell_SecondaryTrayWnd") return;

        int step = TuningRegistry.Int(TuningRegistry.TransparencyStep);

        int current = AlphaCompositor.GetBase(hwnd);
        int next = current + (delta > 0 ? step : -step);

        if (next > 255) next = 255;
        if (next < AlphaCompositor.MinAlpha) next = AlphaCompositor.MinAlpha;

        AlphaCompositor.SetBase(hwnd, (byte)next);
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
