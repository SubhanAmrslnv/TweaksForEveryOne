using System;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Overscroll Bounce Feature (macOS Rubber-Band Scrolling Parity).
///
/// Simulates Apple-style rubber-band elasticity on high-velocity wheel scroll pulses,
/// giving the window viewport a subtle harmonic bounce.
/// </summary>
public class OverscrollBounceFeature : IDisposable
{
    private const string HookOwner = "OverscrollBounceFeature";
    private DispatcherTimer? _bounceTimer;
    private IntPtr _activeHwnd;
    private int _origY;
    private double _offsetY;
    private double _velY;

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
        MouseHook.Subscribe(HookOwner, MouseEvents.Wheel, OnWheel);

        _bounceTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _bounceTimer.Tick += OnBounceTick;
    }

    private bool OnWheel(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        // Apply slight elastic pulse for strong wheel movements
        if (Math.Abs(e.WheelDelta) >= 120)
        {
            OsdWindow.Post(() =>
            {
                IntPtr fg = NativeMethods.GetForegroundWindow();
                if (fg == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(fg)) return;

                if (_activeHwnd != fg)
                {
                    if (NativeMethods.GetWindowRect(fg, out NativeMethods.RECT r))
                    {
                        _activeHwnd = fg;
                        _origY = r.Top;
                    }
                }

                _velY += e.WheelDelta > 0 ? -40.0 : 40.0;
                _bounceTimer?.Start();
            });
        }

        return false;
    }

    private void OnBounceTick(object? sender, EventArgs e)
    {
        if (_activeHwnd == IntPtr.Zero || !NativeMethods.IsWindow(_activeHwnd))
        {
            _bounceTimer?.Stop();
            return;
        }

        AppleSpringEngine.Step(ref _offsetY, ref _velY, 0.0, 0.015, AppleSpringEngine.SpringConfig.Bouncy);

        if (NativeMethods.GetWindowRect(_activeHwnd, out NativeMethods.RECT r))
        {
            int curY = _origY + (int)Math.Round(_offsetY);
            NativeMethods.SetWindowPos(_activeHwnd, IntPtr.Zero, r.Left, curY, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
        }

        if (Math.Abs(_offsetY) < 0.2 && Math.Abs(_velY) < 0.5)
        {
            _offsetY = 0;
            _velY = 0;
            _bounceTimer?.Stop();
        }
    }

    private void Stop()
    {
        MouseHook.Unsubscribe(HookOwner);
        _bounceTimer?.Stop();
        _bounceTimer = null;

        if (_activeHwnd != IntPtr.Zero && NativeMethods.IsWindow(_activeHwnd))
        {
            if (NativeMethods.GetWindowRect(_activeHwnd, out NativeMethods.RECT r))
            {
                NativeMethods.SetWindowPos(_activeHwnd, IntPtr.Zero, r.Left, _origY, 0, 0,
                    NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
            }
        }
        _activeHwnd = IntPtr.Zero;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
