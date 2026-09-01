using System;
using System.Diagnostics;

namespace WindowTweaks.Core;

/// <summary>
/// Smoothed drag velocity in PIXELS PER SECOND.
///
/// Two things here are deliberate and both were learned by getting them wrong:
///
/// 1. The unit is px/s, not px/frame. A per-frame displacement means every consumer is silently
///    calibrated to one frame duration, and under load the same hand motion reports up to 3x the
///    velocity.
/// 2. The smoothing constant is a TIME constant - k = 1 - exp(-dt/tau) - not a fixed per-sample
///    ratio, so the amount of smoothing does not change when sample spacing does.
///
/// MagneticSnappingFeature carries its own copy of this maths inline. It is left alone on
/// purpose: it is the one deep feature in the tree and re-plumbing it for shared code would risk
/// the only physics that currently works.
/// </summary>
internal sealed class VelocitySampler
{
    private const double TauMs = 30.0;

    private long _lastTicks;
    private int _lastX;
    private int _lastY;
    private bool _primed;

    public double VelocityX { get; private set; }
    public double VelocityY { get; private set; }

    public double Speed => Math.Sqrt(VelocityX * VelocityX + VelocityY * VelocityY);

    public void Reset(int x, int y)
    {
        _lastX = x;
        _lastY = y;
        _lastTicks = Stopwatch.GetTimestamp();
        VelocityX = 0;
        VelocityY = 0;
        _primed = true;
    }

    public void Sample(int x, int y)
    {
        if (!_primed)
        {
            Reset(x, y);
            return;
        }

        long now = Stopwatch.GetTimestamp();
        double dtMs = (now - _lastTicks) / (double)Stopwatch.Frequency * 1000.0;
        if (dtMs <= 0.0) return;

        double vx = (x - _lastX) / dtMs * 1000.0;
        double vy = (y - _lastY) / dtMs * 1000.0;

        double k = 1.0 - Math.Exp(-dtMs / TauMs);
        VelocityX += (vx - VelocityX) * k;
        VelocityY += (vy - VelocityY) * k;

        _lastX = x;
        _lastY = y;
        _lastTicks = now;
    }
}
