using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Window Unrolling Feature.
///
/// New windows unfurl vertically from top to bottom like a silk blind within 180ms
/// using AppleSpringEngine.
/// </summary>
public class WindowUnrollingFeature : IDisposable
{
    private IntPtr _hook;
    private NativeMethods.WinEventDelegate? _winEventDelegate;
    private DispatcherTimer? _animTimer;

    private class ActiveUnroll
    {
        public IntPtr Hwnd;
        public int X, Y, Width, TargetHeight;
        public double CurrentHeight = 10.0;
        public double VelH = 1200.0;
    }

    private readonly List<ActiveUnroll> _unrolls = new();

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

        _winEventDelegate = OnWinEvent;
        _hook = NativeMethods.SetWinEventHook(
            NativeMethods.EVENT_OBJECT_SHOW,
            NativeMethods.EVENT_OBJECT_SHOW,
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

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || hwnd == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == (uint)Environment.ProcessId) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect)) return;

        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;
        if (ww <= 100 || wh <= 100) return;

        lock (_unrolls)
        {
            _unrolls.Add(new ActiveUnroll
            {
                Hwnd = hwnd,
                X = rect.Left,
                Y = rect.Top,
                Width = ww,
                TargetHeight = wh,
                CurrentHeight = 20.0,
                VelH = 1500.0
            });

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, rect.Left, rect.Top, ww, 20,
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            if (_animTimer != null && !_animTimer.IsEnabled)
            {
                _animTimer.Start();
            }
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        lock (_unrolls)
        {
            for (int i = _unrolls.Count - 1; i >= 0; i--)
            {
                var u = _unrolls[i];
                if (!NativeMethods.IsWindow(u.Hwnd))
                {
                    _unrolls.RemoveAt(i);
                    continue;
                }

                AppleSpringEngine.Step(ref u.CurrentHeight, ref u.VelH, u.TargetHeight, 0.015, AppleSpringEngine.SpringConfig.Gentle);

                int curH = Math.Max(20, (int)Math.Round(u.CurrentHeight));
                NativeMethods.SetWindowPos(u.Hwnd, IntPtr.Zero, u.X, u.Y, u.Width, curH,
                    NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

                if (Math.Abs(u.CurrentHeight - u.TargetHeight) < 2.0 && Math.Abs(u.VelH) < 5.0)
                {
                    NativeMethods.SetWindowPos(u.Hwnd, IntPtr.Zero, u.X, u.Y, u.Width, u.TargetHeight,
                        NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    _unrolls.RemoveAt(i);
                }
            }

            if (_unrolls.Count == 0)
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

        lock (_unrolls)
        {
            _unrolls.Clear();
        }

        _winEventDelegate = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
