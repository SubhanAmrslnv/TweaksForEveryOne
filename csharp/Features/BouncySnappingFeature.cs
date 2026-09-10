using System;
using System.Collections.Generic;
using System.Windows.Forms;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Bouncy Snapping Feature (macOS Elastic Perimeter Parity).
///
/// Windows snapping against screen perimeters rebound elastically by 4px before
/// settling flush to the edge via AppleSpringEngine.
/// </summary>
public class BouncySnappingFeature : IDisposable
{
    private IntPtr _hook;
    private NativeMethods.WinEventDelegate? _winEventDelegate;
    private DispatcherTimer? _animTimer;

    private class ActiveBounce
    {
        public IntPtr Hwnd;
        public int TargetX, TargetY, Width, Height;
        public double OffsetX, OffsetY;
        public double VelX, VelY;
    }

    private readonly List<ActiveBounce> _bounces = new();

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle() => SetEnabled(!IsEnabled);

    private void Start()
    {
        if (_hook != IntPtr.Zero) return;

        _winEventDelegate = OnMoveSizeEnd;
        _hook = NativeMethods.SetWinEventHook(
            NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
            NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
            IntPtr.Zero,
            _winEventDelegate,
            0,
            0,
            NativeMethods.WINEVENT_OUTOFCONTEXT);

        _animTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _animTimer.Tick += OnAnimTick;
    }

    private void OnMoveSizeEnd(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect)) return;

        int wx = rect.Left;
        int wy = rect.Top;
        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;

        var screen = Screen.FromRectangle(new System.Drawing.Rectangle(wx, wy, ww, wh));
        var work = screen.WorkingArea;

        double bounceX = 0;
        double bounceY = 0;

        // Check proximity to screen edges (within 6px)
        if (Math.Abs(wx - work.Left) <= 6) bounceX = 4.0;
        else if (Math.Abs(rect.Right - work.Right) <= 6) bounceX = -4.0;

        if (Math.Abs(wy - work.Top) <= 6) bounceY = 4.0;
        else if (Math.Abs(rect.Bottom - work.Bottom) <= 6) bounceY = -4.0;

        if (bounceX != 0 || bounceY != 0)
        {
            lock (_bounces)
            {
                _bounces.Add(new ActiveBounce
                {
                    Hwnd = hwnd,
                    TargetX = wx,
                    TargetY = wy,
                    Width = ww,
                    Height = wh,
                    OffsetX = bounceX,
                    OffsetY = bounceY,
                    VelX = bounceX * 15.0,
                    VelY = bounceY * 15.0
                });

                if (_animTimer != null && !_animTimer.IsEnabled)
                {
                    _animTimer.Start();
                }
            }
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        lock (_bounces)
        {
            for (int i = _bounces.Count - 1; i >= 0; i--)
            {
                var b = _bounces[i];
                if (!NativeMethods.IsWindow(b.Hwnd))
                {
                    _bounces.RemoveAt(i);
                    continue;
                }

                AppleSpringEngine.Step(ref b.OffsetX, ref b.VelX, 0.0, 0.015, AppleSpringEngine.SpringConfig.Bouncy);
                AppleSpringEngine.Step(ref b.OffsetY, ref b.VelY, 0.0, 0.015, AppleSpringEngine.SpringConfig.Bouncy);

                int curX = b.TargetX + (int)Math.Round(b.OffsetX);
                int curY = b.TargetY + (int)Math.Round(b.OffsetY);

                NativeMethods.SetWindowPos(b.Hwnd, IntPtr.Zero, curX, curY, 0, 0,
                    NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

                if (Math.Abs(b.OffsetX) < 0.2 && Math.Abs(b.OffsetY) < 0.2)
                {
                    NativeMethods.SetWindowPos(b.Hwnd, IntPtr.Zero, b.TargetX, b.TargetY, 0, 0,
                        NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    _bounces.RemoveAt(i);
                }
            }

            if (_bounces.Count == 0)
            {
                _animTimer?.Stop();
            }
        }
    }

    private void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }

        _animTimer?.Stop();
        _animTimer = null;

        lock (_bounces)
        {
            _bounces.Clear();
        }

        _winEventDelegate = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
