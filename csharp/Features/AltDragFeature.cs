using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class AltDragFeature : IDisposable
{
    private bool _enabled = true;
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;

    private const int HTCAPTION = 2;
    private const int WM_NCLBUTTONDOWN = 0x00A1;
    private const int VK_MENU = 0x12;

    private const int WM_LBUTTONDOWN = 0x0201;

    [StructLayout(LayoutKind.Sequential)]
    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public NativeMethods.POINT ptMinPosition;
        public NativeMethods.POINT ptMaxPosition;
        public NativeMethods.RECT rcNormalPosition;
    }

    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    private const int SW_SHOWMAXIMIZED = 3;

    public AltDragFeature()
    {
        _procDelegate = new NativeMethods.LowLevelMouseProc(HookCallback);
    }

    public void Toggle()
    {
        _enabled = !_enabled;

        if (_enabled)
        {
            if (_hook == IntPtr.Zero)
            {
                using (var curProcess = Process.GetCurrentProcess())
                using (var curModule = curProcess.MainModule)
                {
                    _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _procDelegate, NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
                }
            }
        }
        else
        {
            if (_hook != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hook);
                _hook = IntPtr.Zero;
            }
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();

            if (msg == WM_LBUTTONDOWN)
            {
                // Check if Alt is held
                short altState = GetAsyncKeyState(VK_MENU);
                if ((altState & 0x8000) != 0)
                {
                    var hookStruct = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

                    // Get window under cursor
                    NativeMethods.POINT pt = new NativeMethods.POINT { X = hookStruct.pt.X, Y = hookStruct.pt.Y };
                    IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
                    if (hwnd != IntPtr.Zero)
                    {
                        IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
                        if (root != IntPtr.Zero)
                        {
                            // Skip maximized windows
                            WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
                            placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                            if (GetWindowPlacement(root, ref placement))
                            {
                                if (placement.showCmd == SW_SHOWMAXIMIZED)
                                {
                                    // Don't drag maximized windows
                                    return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
                                }
                            }

                            // Activate the window
                            NativeMethods.SetForegroundWindow(root);

                            // Trigger native drag
                            NativeMethods.PostMessage(root, (uint)WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);

                            // Swallow the original click so we don't click on buttons inside the window
                            return new IntPtr(1);
                        }
                    }
                }
            }
        }

        return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
