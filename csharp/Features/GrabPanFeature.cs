using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class GrabPanFeature : IDisposable
{
    private bool _enabled = false;
    private IntPtr _hook = IntPtr.Zero;
    private NativeMethods.LowLevelMouseProc _procDelegate;
    
    private bool _isTracking = false;
    private bool _dragged = false;
    private int _startX = 0;
    private int _startY = 0;
    private int _ignoreClicks = 0;

    public GrabPanFeature()
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
                using (var curProcess = System.Diagnostics.Process.GetCurrentProcess())
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
            _isTracking = false;
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();
            var hookStruct = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

            if (msg == NativeMethods.WM_MBUTTONDOWN)
            {
                if (_ignoreClicks > 0)
                {
                    _ignoreClicks--;
                    return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
                }

                _isTracking = true;
                _dragged = false;
                _startX = hookStruct.pt.X;
                _startY = hookStruct.pt.Y;
                return (IntPtr)1; // Swallow
            }
            else if (msg == NativeMethods.WM_MOUSEMOVE && _isTracking)
            {
                int curX = hookStruct.pt.X;
                int curY = hookStruct.pt.Y;
                
                int dx = curX - _startX;
                int dy = curY - _startY;

                if (!_dragged && (Math.Abs(dx) > 3 || Math.Abs(dy) > 3))
                {
                    _dragged = true;
                }

                if (_dragged)
                {
                    int step = 25;
                    
                    if (Math.Abs(dy) >= step)
                    {
                        int count = Math.Abs(dy) / step;
                        int wheelData = (dy < 0) ? (-120 * count) : (120 * count);
                        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_WHEEL, 0, 0, (uint)wheelData, IntPtr.Zero);
                        
                        _startY = _startY + (dy < 0 ? -count * step : count * step);
                    }

                    if (Math.Abs(dx) >= step)
                    {
                        int count = Math.Abs(dx) / step;
                        int wheelData = (dx < 0) ? (120 * count) : (-120 * count);
                        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_HWHEEL, 0, 0, (uint)wheelData, IntPtr.Zero);
                        
                        _startX = _startX + (dx < 0 ? -count * step : count * step);
                    }
                }
                // Do NOT swallow MouseMove, so the cursor actually moves on screen
            }
            else if (msg == NativeMethods.WM_MBUTTONUP)
            {
                if (_ignoreClicks > 0)
                {
                    _ignoreClicks--;
                    return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
                }

                if (_isTracking)
                {
                    _isTracking = false;
                    
                    if (!_dragged)
                    {
                        // Simulate regular click
                        _ignoreClicks = 2; // Ignore our synthetic down and up
                        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, IntPtr.Zero);
                        NativeMethods.mouse_event(NativeMethods.MOUSEEVENTF_MIDDLEUP, 0, 0, 0, IntPtr.Zero);
                    }
                    
                    return (IntPtr)1; // Swallow the physical up
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
