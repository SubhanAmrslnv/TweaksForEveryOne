using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class BreathingFeature : IDisposable
{
    private bool _isEnabled = false;
    private DispatcherTimer _timer;
    private Dictionary<IntPtr, DateTime> _lastActive = new();
    private const int IDLE_MS = 5000;
    private const byte DIM_ALPHA = 120;
    
    public bool IsEnabled => _isEnabled;

    public BreathingFeature()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _timer.Tick += Timer_Tick;
    }

    public void Toggle()
    {
        _isEnabled = !_isEnabled;
        if (_isEnabled)
        {
            _lastActive.Clear();
            _timer.Start();
            Debug.WriteLine("Breathing Windows: Enabled");
        }
        else
        {
            _timer.Stop();
            RestoreAllWindows();
            _lastActive.Clear();
            Debug.WriteLine("Breathing Windows: Disabled");
        }
    }

    private void Timer_Tick(object? sender, EventArgs e)
    {
        IntPtr fgHwnd = NativeMethods.GetForegroundWindow();
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        IntPtr mouseHwnd = NativeMethods.WindowFromPoint(pt);

        // Get the root window from a point (WindowFromPoint often returns a child control)
        mouseHwnd = NativeMethods.GetAncestor(mouseHwnd, NativeMethods.GA_ROOT);

        DateTime now = DateTime.Now;
        List<IntPtr> activeThisTick = new List<IntPtr>();

        NativeMethods.EnumWindows((IntPtr hwnd, IntPtr lParam) =>
        {
            if (!NativeMethods.IsWindowVisible(hwnd)) return true;
            
            // Basic filtering
            StringBuilder sb = new StringBuilder(256);
            NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
            string cls = sb.ToString();
            if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") return true;

            activeThisTick.Add(hwnd);

            if (hwnd == fgHwnd || hwnd == mouseHwnd)
            {
                _lastActive[hwnd] = now;
                SetWindowAlpha(hwnd, 255);
            }
            else
            {
                if (!_lastActive.ContainsKey(hwnd))
                {
                    _lastActive[hwnd] = now;
                }
                
                if ((now - _lastActive[hwnd]).TotalMilliseconds > IDLE_MS)
                {
                    SetWindowAlpha(hwnd, DIM_ALPHA);
                }
            }

            return true;
        }, IntPtr.Zero);

        // Cleanup closed windows from tracking
        List<IntPtr> toRemove = new List<IntPtr>();
        foreach (var key in _lastActive.Keys)
        {
            if (!activeThisTick.Contains(key))
            {
                toRemove.Add(key);
            }
        }
        foreach (var key in toRemove)
        {
            _lastActive.Remove(key);
        }
    }

    private void SetWindowAlpha(IntPtr hwnd, byte alpha)
    {
        if (!NativeMethods.IsWindow(hwnd)) return;

        uint style = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        
        if (alpha == 255)
        {
            // Just set alpha to 255, removing the WS_EX_LAYERED flag can cause black flickering
            // in some WPF/WinForms apps if they natively rely on it.
            if ((style & NativeMethods.WS_EX_LAYERED) != 0)
                NativeMethods.SetLayeredWindowAttributes(hwnd, 0, 255, NativeMethods.LWA_ALPHA);
            return;
        }

        if ((style & NativeMethods.WS_EX_LAYERED) == 0)
        {
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, style | NativeMethods.WS_EX_LAYERED);
        }

        NativeMethods.SetLayeredWindowAttributes(hwnd, 0, alpha, NativeMethods.LWA_ALPHA);
    }

    private void RestoreAllWindows()
    {
        foreach (var hwnd in _lastActive.Keys)
        {
            SetWindowAlpha(hwnd, 255);
        }
    }

    public void Dispose()
    {
        _timer.Stop();
        RestoreAllWindows();
    }
}
