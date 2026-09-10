using System;

namespace WindowTweaks.Core;

/// <summary>
/// Analytical Damped Harmonic Motion Engine (CASpringAnimation parity).
///
/// Implements second-order differential equation:
///     m * d^2x/dt^2 + c * dx/dt + k * (x - x_target) = 0
///
/// Where:
///     m = 1.0 (normalized unit mass)
///     k = oscillator stiffness [180.0, 320.0 N/m]
///     zeta = damping ratio [0.82, 0.94]
///     c = 2 * sqrt(m * k) * zeta
///
/// Features:
///   - Exact analytical step integration: unconditionally stable across variable frame times dt <= 33ms.
///   - Interruptible retargeting: changing targets mid-flight preserves instantaneous velocity.
///   - Zero heap allocation in simulation loops.
/// </summary>
internal static class AppleSpringEngine
{
    public readonly record struct SpringConfig(double Stiffness, double DampingRatio, double Mass = 1.0)
    {
        /// <summary>Default balanced Apple spring (k=240, zeta=0.88): fluid, responsive, organic elastic settle.</summary>
        public static readonly SpringConfig Default = new(240.0, 0.88, 1.0);

        /// <summary>Snappy spring (k=320, zeta=0.85): fast micro-interactions, context menus, selection rings.</summary>
        public static readonly SpringConfig Snappy = new(320.0, 0.85, 1.0);

        /// <summary>Gentle spring (k=180, zeta=0.92): large spatial transitions, desktop dimmers, window glides.</summary>
        public static readonly SpringConfig Gentle = new(180.0, 0.92, 1.0);

        /// <summary>Bouncy spring (k=220, zeta=0.76): elastic rebound for perimeter snapping.</summary>
        public static readonly SpringConfig Bouncy = new(220.0, 0.76, 1.0);
    }

    /// <summary>
    /// Evaluates a single 1D spring step using exact closed-form analytical integration.
    /// </summary>
    public static void Step(
        ref double currentPos,
        ref double currentVel,
        double targetPos,
        double dt,
        SpringConfig config)
    {
        // Clamp frame delta to 33ms to avoid numerical instability on frame hitches
        if (dt > 0.033) dt = 0.033;
        if (dt <= 0.0) return;

        double d = currentPos - targetPos;
        double v = currentVel;

        double m = config.Mass > 0 ? config.Mass : 1.0;
        double k = config.Stiffness;
        double zeta = config.DampingRatio;

        double omega0 = Math.Sqrt(k / m);

        if (zeta < 1.0)
        {
            // Underdamped (standard Apple spring behavior)
            double omegaD = omega0 * Math.Sqrt(1.0 - (zeta * zeta));
            double decay = Math.Exp(-zeta * omega0 * dt);

            double cosVal = Math.Cos(omegaD * dt);
            double sinVal = Math.Sin(omegaD * dt);

            double b = (v + (zeta * omega0 * d)) / omegaD;

            currentPos = targetPos + (decay * ((d * cosVal) + (b * sinVal)));
            currentVel = decay * ((v * (cosVal - ((zeta * omega0 / omegaD) * sinVal))) - (d * ((omega0 * omega0 / omegaD) * sinVal)));
        }
        else
        {
            // Critically damped or overdamped
            double decay = Math.Exp(-omega0 * dt);
            double b = v + (omega0 * d);

            currentPos = targetPos + (decay * (d + (b * dt)));
            currentVel = decay * (v - (omega0 * (v + (omega0 * d)) * dt));
        }

        // Snap to target when below perceptible sub-pixel threshold
        if (Math.Abs(currentPos - targetPos) < 0.005 && Math.Abs(currentVel) < 0.02)
        {
            currentPos = targetPos;
            currentVel = 0.0;
        }
    }

    /// <summary>
    /// Evaluates a 2D spring step (e.g. coordinates, dimensions, offsets).
    /// </summary>
    public static bool Step2D(
        ref double x,
        ref double y,
        ref double vx,
        ref double vy,
        double targetX,
        double targetY,
        double dt,
        SpringConfig config)
    {
        Step(ref x, ref vx, targetX, dt, config);
        Step(ref y, ref vy, targetY, dt, config);

        bool settledX = x == targetX && vx == 0.0;
        bool settledY = y == targetY && vy == 0.0;
        return settledX && settledY;
    }
}
