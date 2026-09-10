using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Ghost Slide-In Feature (macOS / iOS Modal Presentation Parity).
///
/// Newly created windows glide up 20px from below with a smooth accompanying
/// alpha curve driven by AppleSpringEngine.
/// </summary>
public class GhostSlideInFeature : IDisposable
{
    private IntPtr _hook;
    private NativeMethods.WinEventDelegate? _winEventDelegate;
    private DispatcherTimer? _animTimer;

    private class ActiveSlide
    {
        public IntPtr Hwnd;
        public int TargetX, TargetY, Width, Height;
        public double CurrentOffsetY = 20.0;
        public double VelY = -120.0;
        public double Alpha = 0.15;
    }

    private readonly List<ActiveSlide> _slides = new();

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

        int wx = rect.Left;
        int wy = rect.Top;
        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;

        lock (_slides)
        {
            _slides.Add(new ActiveSlide
            {
                Hwnd = hwnd,
                TargetX = wx,
                TargetY = wy,
                Width = ww,
                Height = wh,
                CurrentOffsetY = 20.0,
                VelY = -140.0,
                Alpha = 0.15
            });

            AlphaCompositor.SetLayer(hwnd, "slidein", 0.15);
            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, wx, wy + 20, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            if (_animTimer != null && !_animTimer.IsEnabled)
            {
                _animTimer.Start();
            }
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        lock (_slides)
        {
            for (int i = _slides.Count - 1; i >= 0; i--)
            {
                var s = _slides[i];
                if (!NativeMethods.IsWindow(s.Hwnd))
                {
                    _slides.RemoveAt(i);
                    continue;
                }

                AppleSpringEngine.Step(ref s.CurrentOffsetY, ref s.VelY, 0.0, 0.015, AppleSpringEngine.SpringConfig.Default);
                s.Alpha = Math.Min(1.0, s.Alpha + 0.08);

                int curY = s.TargetY + (int)Math.Round(s.CurrentOffsetY);
                NativeMethods.SetWindowPos(s.Hwnd, IntPtr.Zero, s.TargetX, curY, 0, 0,
                    NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

                AlphaCompositor.SetLayer(s.Hwnd, "slidein", s.Alpha);

                if (Math.Abs(s.CurrentOffsetY) < 0.3 && Math.Abs(s.VelY) < 1.0)
                {
                    NativeMethods.SetWindowPos(s.Hwnd, IntPtr.Zero, s.TargetX, s.TargetY, 0, 0,
                        NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    AlphaCompositor.ClearLayer(s.Hwnd, "slidein");
                    _slides.RemoveAt(i);
                }
            }

            if (_slides.Count == 0)
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

        lock (_slides)
        {
            foreach (var s in _slides)
            {
                AlphaCompositor.ClearLayer(s.Hwnd, "slidein");
            }
            _slides.Clear();
        }

        _winEventDelegate = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
