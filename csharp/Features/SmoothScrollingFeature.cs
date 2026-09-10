using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Smooth Scrolling Feature (macOS Trackpad Continuous Inertial Scroll Parity).
///
/// Intercepts coarse mechanical wheel notches (+/- 120) and subdivides them into
/// continuous, high-refresh-rate micro-velocity pulses for buttery smooth document navigation.
/// </summary>
public class SmoothScrollingFeature : IDisposable
{
    private const string HookOwner = "SmoothScrollingFeature";
    private DispatcherTimer? _subdivisionTimer;
    private double _remainingDelta;

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

        _subdivisionTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(12)
        };
        _subdivisionTimer.Tick += OnSubdivisionTick;
    }

    private bool OnWheel(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        // Add to smooth accumulator
        _remainingDelta += e.WheelDelta;

        OsdWindow.Post(() =>
        {
            if (_subdivisionTimer != null && !_subdivisionTimer.IsEnabled)
            {
                _subdivisionTimer.Start();
            }
        });

        return true; // Suppress coarse notched event
    }

    private void OnSubdivisionTick(object? sender, EventArgs e)
    {
        if (Math.Abs(_remainingDelta) < 1.0)
        {
            _remainingDelta = 0;
            _subdivisionTimer?.Stop();
            return;
        }

        // Emit ~24 units per tick (subdividing a 120 notch over 5 ticks / 60ms)
        double step = Math.Sign(_remainingDelta) * Math.Min(Math.Abs(_remainingDelta), 24.0);
        _remainingDelta -= step;

        SyntheticInput.Wheel((int)Math.Round(step));
    }

    private void Stop()
    {
        MouseHook.Unsubscribe(HookOwner);
        _subdivisionTimer?.Stop();
        _subdivisionTimer = null;
        _remainingDelta = 0;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
