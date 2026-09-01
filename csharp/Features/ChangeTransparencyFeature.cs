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
    private const int StepAlpha = 25;

    private readonly NativeMethods.LowLevelMouseProc _proc;
    private IntPtr _hookId = IntPtr.Zero;

    public bool IsEnabled { get; private set; }

    public ChangeTransparencyFeature()
    {
        _proc = HookCallback;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            using Process curProcess = Process.GetCurrentProcess();
            using ProcessModule? curModule = curProcess.MainModule;
            if (curModule != null)
            {
                _hookId = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _proc,
                    NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
            }
        }
        else
        {
            if (_hookId != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0 && wParam == (IntPtr)NativeMethods.WM_MOUSEWHEEL)
            {
                bool isShift = (NativeMethods.GetAsyncKeyState(0x10) & 0x8000) != 0; // VK_SHIFT
                bool isAlt = (NativeMethods.GetAsyncKeyState(0x12) & 0x8000) != 0;   // VK_MENU

                if (isShift && isAlt)
                {
                    NativeMethods.MSLLHOOKSTRUCT hookStruct =
                        Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);
                    int delta = (short)(hookStruct.mouseData >> 16);

                    ChangeTransparency(delta);

                    // Swallow the scroll so the window underneath does not also scroll.
                    return (IntPtr)1;
                }
            }
        }
        catch
        {
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
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

        int current = AlphaCompositor.GetBase(hwnd);
        int next = current + (delta > 0 ? StepAlpha : -StepAlpha);

        if (next > 255) next = 255;
        if (next < AlphaCompositor.MinAlpha) next = AlphaCompositor.MinAlpha;

        AlphaCompositor.SetBase(hwnd, (byte)next);
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
