using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class StealthPanicTrigger : IDisposable
{
    private bool _enabled = true;
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;
    private Action _onTripleEsc;
    
    private int _escCount = 0;
    private Stopwatch _timer = new Stopwatch();
    private const int TIMEOUT_MS = 600;

    public StealthPanicTrigger(Action onTripleEsc)
    {
        _onTripleEsc = onTripleEsc;
        _procDelegate = new NativeMethods.LowLevelMouseProc(HookCallback);
        
        using (var curProcess = Process.GetCurrentProcess())
        using (var curModule = curProcess.MainModule)
        {
            _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, _procDelegate, NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && _enabled)
        {
            int msg = wParam.ToInt32();
            if (msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN)
            {
                int vkCode = Marshal.ReadInt32(lParam);
                if (vkCode == NativeMethods.VK_ESCAPE)
                {
                    if (_escCount == 0 || _timer.ElapsedMilliseconds > TIMEOUT_MS)
                    {
                        _escCount = 1;
                        _timer.Restart();
                    }
                    else
                    {
                        _escCount++;
                        if (_escCount >= 3)
                        {
                            _escCount = 0;
                            _timer.Stop();
                            
                            // Trigger the panic action asynchronously so we don't block the hook chain
                            System.Threading.Tasks.Task.Run(() => _onTripleEsc?.Invoke());
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
