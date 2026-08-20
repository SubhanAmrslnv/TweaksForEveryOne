#include "VelocitySampler.h"

#include <algorithm>
#include <cmath>

namespace TweakCore {

void VelocitySampler::begin(int x, int y) {
    m_prevX = x;
    m_prevY = y;
    m_lastDx = 0;
    m_lastDy = 0;
    m_velX = 0.0f;
    m_velY = 0.0f;
    m_alpha = 1.0f;
    m_started = true;
}

float VelocitySampler::emaFactor(float dt, float tauMs) {
    if (dt <= 0.0f) {
        return 0.0f;
    }
    if (tauMs <= 0.0f) {
        return 1.0f;   // no smoothing requested: jump straight to the target
    }
    return 1.0f - std::exp(-dt / tauMs);
}

float VelocitySampler::sample(int x, int y, float dt, float nominalFrameMs) {
    if (!m_started) {
        begin(x, y);
        return 0.0f;
    }
    if (dt <= 0.0f) {
        dt = nominalFrameMs;
    }

    m_lastDx = x - m_prevX;
    m_lastDy = y - m_prevY;

    // px per frame -> px per second, THEN smooth. Doing it the other way round
    // is the frame-rate dependence this class exists to remove.
    const float instX = (static_cast<float>(m_lastDx) / dt) * 1000.0f;
    const float instY = (static_cast<float>(m_lastDy) / dt) * 1000.0f;

    const float k = emaFactor(dt, kVelocityTauMs);
    m_velX += (instX - m_velX) * k;
    m_velY += (instY - m_velY) * k;

    m_prevX = x;
    m_prevY = y;

    return speed();
}

float VelocitySampler::speed() const {
    return std::sqrt(m_velX * m_velX + m_velY * m_velY);
}

float VelocitySampler::smoothAlpha(float target, float dt, float nominalFrameMs) {
    if (dt <= 0.0f) {
        dt = nominalFrameMs;
    }
    target = std::clamp(target, 0.0f, 1.0f);
    m_alpha += (target - m_alpha) * emaFactor(dt, kAlphaTauMs);
    return m_alpha;
}

} // namespace TweakCore
