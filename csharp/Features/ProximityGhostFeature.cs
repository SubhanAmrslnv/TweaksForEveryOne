using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class ProximityGhostFeature : IDisposable
{
    private class GhostInfo
    {
        public uint OriginalExStyle;
        public int LastAlpha = -1;
    }

    private readonly Dictionary<IntPtr, GhostInfo> _ghostWindows = new();
    private bool _isMonitoring = false;
    private CancellationTokenSource? _cancellationTokenSource;

    private const int MaxDist = 400;
    private const int MinAlpha = 51; // 80% transparent
    private const int MaxAlpha = 255;
    private const int ClickDist = 50;

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        if (_ghostWindows.ContainsKey(hwnd))
        {
            UnGhostWindow(hwnd);
            return;
        }

        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);

        // If it's already click-through, don't mess with it (we wouldn't know how to restore it)
        if ((exStyle & NativeMethods.WS_EX_TRANSPARENT) == NativeMethods.WS_EX_TRANSPARENT)
            return;

        // Force Layered
        if ((exStyle & NativeMethods.WS_EX_LAYERED) == 0)
        {
            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | NativeMethods.WS_EX_LAYERED);
        }

        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_TRANSPARENT);
        
        NativeMethods.SetWindowPos(hwnd, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0, 
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);

        _ghostWindows[hwnd] = new GhostInfo { OriginalExStyle = exStyle };

        if (!_isMonitoring)
        {
            StartMonitoring();
        }
    }

    private void UnGhostWindow(IntPtr hwnd)
    {
        if (!_ghostWindows.TryGetValue(hwnd, out GhostInfo? info))
            return;

        _ghostWindows.Remove(hwnd);

        if (!NativeMethods.IsWindow(hwnd))
            return;

        NativeMethods.SetLayeredWindowAttributes(hwnd, 0, 255, NativeMethods.LWA_ALPHA);

        uint currentExStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        
        if ((info.OriginalExStyle & NativeMethods.WS_EX_TRANSPARENT) == 0)
            currentExStyle &= ~NativeMethods.WS_EX_TRANSPARENT;
            
        if ((info.OriginalExStyle & NativeMethods.WS_EX_LAYERED) == 0)
            currentExStyle &= ~NativeMethods.WS_EX_LAYERED;

        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, currentExStyle);

        NativeMethods.SetWindowPos(hwnd, NativeMethods.HWND_NOTOPMOST, 0, 0, 0, 0, 
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
    }

    private void StartMonitoring()
    {
        _isMonitoring = true;
        _cancellationTokenSource = new CancellationTokenSource();
        Task.Run(() => MonitorLoop(_cancellationTokenSource.Token));
    }

    private async Task MonitorLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            if (_ghostWindows.Count == 0)
            {
                _isMonitoring = false;
                break;
            }

            NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
            
            List<IntPtr> dead = new();

            // Using array copy to avoid modifying collection while iterating
            IntPtr[] keys = new IntPtr[_ghostWindows.Count];
            _ghostWindows.Keys.CopyTo(keys, 0);

            foreach (var hwnd in keys)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    dead.Add(hwnd);
                    continue;
                }

                if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
                    continue;
                
                int dist = GetDistToRect(pt.X, pt.Y, rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
                
                int targetAlpha = MaxAlpha;
                if (dist == 0)
                    targetAlpha = MaxAlpha;
                else if (dist >= MaxDist)
                    targetAlpha = MinAlpha;
                else
                {
                    double ratio = 1.0 - ((double)dist / MaxDist);
                    targetAlpha = MinAlpha + (int)(ratio * (MaxAlpha - MinAlpha));
                }

                GhostInfo info = _ghostWindows[hwnd];
                if (info.LastAlpha != targetAlpha)
                {
                    NativeMethods.SetLayeredWindowAttributes(hwnd, 0, (byte)targetAlpha, NativeMethods.LWA_ALPHA);
                    info.LastAlpha = targetAlpha;
                }

                uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
                bool isClickThrough = (exStyle & NativeMethods.WS_EX_TRANSPARENT) != 0;

                if (dist < ClickDist)
                {
                    if (isClickThrough)
                        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle & ~NativeMethods.WS_EX_TRANSPARENT);
                }
                else if (dist > ClickDist + 12)
                {
                    if (!isClickThrough)
                        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | NativeMethods.WS_EX_TRANSPARENT);
                }
            }

            foreach (var h in dead)
            {
                _ghostWindows.Remove(h);
            }

            await Task.Delay(25, token);
        }
    }

    private int GetDistToRect(int px, int py, int rx, int ry, int rw, int rh)
    {
        int dx = 0;
        int dy = 0;

        if (px < rx) dx = rx - px;
        else if (px > rx + rw) dx = px - (rx + rw);

        if (py < ry) dy = ry - py;
        else if (py > ry + rh) dy = py - (ry + rh);

        return (int)Math.Sqrt(dx * dx + dy * dy);
    }

    public void Dispose()
    {
        _cancellationTokenSource?.Cancel();
        foreach (var hwnd in new List<IntPtr>(_ghostWindows.Keys))
        {
            UnGhostWindow(hwnd);
        }
    }
}
