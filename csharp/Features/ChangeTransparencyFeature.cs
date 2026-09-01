using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class ChangeTransparencyFeature : IDisposable
{
    private NativeMethods.LowLevelMouseProc _proc;
    private IntPtr _hookID = IntPtr.Zero;

    // We don't have an On/Off toggle for this feature, it's always running 
    // waiting for Shift+Alt+Wheel.
    public ChangeTransparencyFeature()
    {
        _proc = HookCallback;
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            _hookID = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _proc,
                NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)NativeMethods.WM_MOUSEWHEEL)
        {
            bool isShift = (NativeMethods.GetAsyncKeyState(0x10) & 0x8000) != 0; // VK_SHIFT
            bool isAlt = (NativeMethods.GetAsyncKeyState(0x12) & 0x8000) != 0;   // VK_MENU (Alt)

            if (isShift && isAlt)
            {
                NativeMethods.MSLLHOOKSTRUCT hookStruct = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);
                int delta = (short)(hookStruct.mouseData >> 16);
                
                // Positive delta = Wheel Up (more opaque)
                // Negative delta = Wheel Down (more transparent)
                ChangeTransparency(delta);

                // Return 1 to swallow the scroll so the window doesn't scroll
                return (IntPtr)1;
            }
        }
        return NativeMethods.CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    private void ChangeTransparency(int delta)
    {
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
        hwnd = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);

        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        // Ignore Desktop and Taskbar
        System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") return;

        uint style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        
        byte currentAlpha = 255;
        if ((style & NativeMethods.WS_EX_LAYERED) != 0)
        {
            // We should theoretically read the existing alpha, but Windows GetLayeredWindowAttributes 
            // is notoriously finicky if the window is layered but hasn't had alpha set yet.
            // Let's assume a default logic or keep an internal map.
            // For simplicity, we just jump down/up from a baseline.
        }

        // To make it rock solid, we will track it ourselves or increment/decrement
        // In AHK, WheelDown drops it by ~10% (25.5 alpha).
        // I will implement a quick internal tracking or rely on a property.
        
        // Actually, we can use GetLayeredWindowAttributes!
        byte alpha = 255;
        if ((style & NativeMethods.WS_EX_LAYERED) != 0)
        {
            NativeMethods.GetLayeredWindowAttributes(hwnd, out uint crKey, out alpha, out uint dwFlags);
        }

        int newAlpha = alpha + (delta > 0 ? 25 : -25);
        if (newAlpha > 255) newAlpha = 255;
        if (newAlpha < 25) newAlpha = 25; // Don't let it become completely invisible

        if ((style & NativeMethods.WS_EX_LAYERED) == 0 && newAlpha < 255)
        {
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, style | NativeMethods.WS_EX_LAYERED);
        }

        NativeMethods.SetLayeredWindowAttributes(hwnd, 0, (byte)newAlpha, NativeMethods.LWA_ALPHA);
    }

    public void Dispose()
    {
        if (_hookID != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }
    }
}
