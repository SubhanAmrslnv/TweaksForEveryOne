#pragma once

#include <cmath>
#include <algorithm>

namespace TweakCore {

/// Analytical Damped Harmonic Motion Engine (Apple CASpringAnimation parity).
///
/// Implements second-order differential equation:
///     m * d^2x/dt^2 + c * dx/dt + k * (x - x_target) = 0
///
/// Where:
///     m = 1.0 (normalized unit mass)
///     k = oscillator stiffness [180.0, 320.0 N/m]
///     zeta = damping ratio [0.82, 0.94]
///     c = 2 * sqrt(m * k) * zeta
struct SpringConfig {
    float stiffness;
    float dampingRatio;
    float mass = 1.0f;

    static constexpr SpringConfig Default() { return {240.0f, 0.88f, 1.0f}; }
    static constexpr SpringConfig Snappy()  { return {320.0f, 0.85f, 1.0f}; }
    static constexpr SpringConfig Gentle()  { return {180.0f, 0.92f, 1.0f}; }
    static constexpr SpringConfig Bouncy()  { return {220.0f, 0.76f, 1.0f}; }
};

class SpringPhysics {
public:
    /// Evaluates a single 1D spring step using closed-form analytical integration.
    static void step(float& currentPos, float& currentVel, float targetPos, float dt,
                     const SpringConfig& config = SpringConfig::Default()) {
        if (dt > 0.033f) dt = 0.033f;
        if (dt <= 0.0f) return;

        const float d = currentPos - targetPos;
        const float v = currentVel;

        const float m = config.mass > 0.0f ? config.mass : 1.0f;
        const float k = config.stiffness;
        const float zeta = config.dampingRatio;

        const float omega0 = std::sqrt(k / m);

        if (zeta < 1.0f) {
            const float omegaD = omega0 * std::sqrt(1.0f - (zeta * zeta));
            const float decay = std::exp(-zeta * omega0 * dt);

            const float cosVal = std::cos(omegaD * dt);
            const float sinVal = std::sin(omegaD * dt);

            const float b = (v + (zeta * omega0 * d)) / omegaD;

            currentPos = targetPos + decay * (d * cosVal + b * sinVal);
            currentVel = decay * (v * (cosVal - (zeta * omega0 / omegaD) * sinVal) -
                                  d * ((omega0 * omega0 / omegaD) * sinVal));
        } else {
            const float decay = std::exp(-omega0 * dt);
            const float b = v + (omega0 * d);

            currentPos = targetPos + decay * (d + b * dt);
            currentVel = decay * (v - omega0 * (v + omega0 * d) * dt);
        }

        if (std::abs(currentPos - targetPos) < 0.005f && std::abs(currentVel) < 0.02f) {
            currentPos = targetPos;
            currentVel = 0.0f;
        }
    }

    /// Evaluates a 2D spring step. Returns true if both dimensions settled.
    static bool step2D(float& x, float& y, float& vx, float& vy,
                       float targetX, float targetY, float dt,
                       const SpringConfig& config = SpringConfig::Default()) {
        step(x, vx, targetX, dt, config);
        step(y, vy, targetY, dt, config);
        return (x == targetX && vx == 0.0f && y == targetY && vy == 0.0f);
    }
};

} // namespace TweakCore
