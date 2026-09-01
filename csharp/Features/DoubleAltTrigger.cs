using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class DoubleAltTrigger : IDisposable
{
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;
    private Action _onDoubleAlt;
    
    private int _altCount = 0;
    private bool _otherKeyPressed = false;
    private Stopwatch _timer = new Stopwatch();
    private const int TIMEOUT_MS = 400;

    private const int VK_MENU = 0x12;
    private const int VK_LMENU = 0xA4;
    private const int VK_RMENU = 0xA5;

    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;

    public DoubleAltTrigger(Action onDoubleAlt)
    {
        _onDoubleAlt = onDoubleAlt;
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

            bool isAlt = (vkCode == VK_MENU || vkCode == VK_LMENU || vkCode == VK_RMENU);

            if (msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN)
            {
                if (isAlt)
                {
                    // If it's a new sequence or time expired
                    if (_altCount == 0 || _timer.ElapsedMilliseconds > TIMEOUT_MS)
                    {
                        _altCount = 1;
                        _otherKeyPressed = false;
                        _timer.Restart();
                    }
                    else
                    {
                        // It's the second Alt within the timeout
                        if (!_otherKeyPressed)
                        {
                            _altCount = 0;
                            _timer.Stop();
                            System.Threading.Tasks.Task.Run(() => _onDoubleAlt?.Invoke());
                            
                            // Optionally swallow the second Alt? 
                            // Returning 1 would swallow it, but Alt alone doesn't do much harm.
                        }
                        else
                        {
                            // Another key was pressed, so start over
                            _altCount = 1;
                            _otherKeyPressed = false;
                            _timer.Restart();
                        }
                    }
                }
                else
                {
                    // Not Alt
                    if (_altCount > 0)
                    {
                        _otherKeyPressed = true;
                    }
                }
            }
            else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
            {
                if (isAlt)
                {
                    // Alt key up. If another key was pressed, we invalidate the sequence.
                    if (_otherKeyPressed)
                    {
                        _altCount = 0;
                        _timer.Stop();
                    }
                }
                else
                {
                    // Other key up doesn't invalidate by itself, but key down did.
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
