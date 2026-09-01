using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class DoubleCtrlTrigger : IDisposable
{
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;
    private Action _onDoubleCtrl;
    
    private int _ctrlCount = 0;
    private bool _otherKeyPressed = false;
    private Stopwatch _timer = new Stopwatch();
    private const int TIMEOUT_MS = 400;

    private const int VK_CONTROL = 0x11;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;

    public DoubleCtrlTrigger(Action onDoubleCtrl)
    {
        _onDoubleCtrl = onDoubleCtrl;
        _procDelegate = new NativeMethods.LowLevelMouseProc(HookCallback);
        
        using (var curProcess = Process.GetCurrentProcess())
        using (var curModule = curProcess.MainModule)
        {
            _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, _procDelegate, NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();
            int vkCode = Marshal.ReadInt32(lParam);

            bool isCtrl = (vkCode == VK_CONTROL || vkCode == VK_LCONTROL || vkCode == VK_RCONTROL);

            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                if (isCtrl)
                {
                    // If it's a new sequence or time expired
                    if (_ctrlCount == 0 || _timer.ElapsedMilliseconds > TIMEOUT_MS)
                    {
                        _ctrlCount = 1;
                        _otherKeyPressed = false;
                        _timer.Restart();
                    }
                    else
                    {
                        // It's the second Ctrl within the timeout
                        if (!_otherKeyPressed)
                        {
                            _ctrlCount = 0;
                            _timer.Stop();
                            System.Threading.Tasks.Task.Run(() => _onDoubleCtrl?.Invoke());
                        }
                        else
                        {
                            // Another key was pressed, so start over
                            _ctrlCount = 1;
                            _otherKeyPressed = false;
                            _timer.Restart();
                        }
                    }
                }
                else
                {
                    // Not Ctrl
                    if (_ctrlCount > 0)
                    {
                        _otherKeyPressed = true;
                    }
                }
            }
            else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
            {
                if (isCtrl)
                {
                    // Ctrl key up. If another key was pressed, we invalidate the sequence.
                    if (_otherKeyPressed)
                    {
                        _ctrlCount = 0;
                        _timer.Stop();
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
