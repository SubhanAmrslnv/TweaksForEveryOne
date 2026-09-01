using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class SmartCapsFeature : IDisposable
{
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;
    
    private const int VK_CAPITAL = 0x14;
    private const int VK_ESCAPE = 0x1B;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;
    private const int KEYEVENTF_KEYUP = 0x0002;

    private Stopwatch _timer = new Stopwatch();
    private bool _capsDown = false;
    private bool _toggled = false;
    
    public SmartCapsFeature()
    {
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

            if (vkCode == VK_CAPITAL)
            {
                // KBDLLHOOKSTRUCT has flags at offset 8. We must check if it's injected 
                // by our own SendInput to prevent an infinite hook loop.
                int flags = Marshal.ReadInt32(lParam, 8);
                bool isInjected = (flags & 0x10) != 0; // LLKHF_INJECTED

                if (!isInjected)
                {
                    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    {
                        if (!_capsDown)
                        {
                            _capsDown = true;
                            _toggled = false;
                            _timer.Restart();
                            
                            // Task to toggle caps lock if held for 400ms
                            Task.Run(() =>
                            {
                                Thread.Sleep(400);
                                if (_capsDown && !_toggled)
                                {
                                    _toggled = true;
                                    SimulateKeyPress(VK_CAPITAL);
                                }
                            });
                        }
                        // Swallow the original hardware press
                        return new IntPtr(1);
                    }
                    else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
                    {
                        if (_capsDown)
                        {
                            _capsDown = false;
                            _timer.Stop();
                            
                            if (!_toggled && _timer.ElapsedMilliseconds < 400)
                            {
                                // Short press -> Send Escape
                                SimulateKeyPress(VK_ESCAPE);
                            }
                        }
                        // Swallow the original hardware release
                        return new IntPtr(1);
                    }
                }
            }
        }

        return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private void SimulateKeyPress(ushort vk)
    {
        NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[2];
        
        inputs[0].type = NativeMethods.INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = vk;
        inputs[0].u.ki.dwFlags = 0; // keydown

        inputs[1].type = NativeMethods.INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = vk;
        inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;

        NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
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
