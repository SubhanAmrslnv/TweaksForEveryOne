#include "Physics.h"

// std::sqrt. This include was missing, which was a compile error on its own -
// neither this file nor Physics.h pulled in <cmath>.
#include <cmath>
#include <algorithm>

namespace TweakCore {

float Physics::glideDurationMs(float distancePx, float maxMs) {
    // 140 ms floor, not 200: the old floor meant a 20 px correction took as long
    // as a 150 px slide and felt like the window was wading. The floor only
    // exists to stop a two-frame animation.
    float ms = 140.0f + distancePx * 0.9f;
    if (ms < 140.0f) {
        ms = 140.0f;
    }
    if (maxMs > 0.0f && ms > maxMs) {
        ms = maxMs;
    }
    return ms;
}

void Physics::predictThrow(int startX, int startY, float velXPerSec, float velYPerSec,
                           float throwGain, float maxPx, int& outX, int& outY) {
    // 0.18 px of travel per px/s of release speed at unit gain. That constant is
    // shared with the Windows side, where it is the old per-frame gain of 12
    // expressed in the frame-rate-independent unit (12 * 0.015).
    float dx = velXPerSec * throwGain * 0.18f;
    float dy = velYPerSec * throwGain * 0.18f;

    if (maxPx > 0.0f) {
        dx = std::clamp(dx, -maxPx, maxPx);
        dy = std::clamp(dy, -maxPx, maxPx);
    }

    outX = startX + static_cast<int>(dx);
    outY = startY + static_cast<int>(dy);
}

ParallaxResult Physics::parallaxAlpha(float speedPxPerSec, const ParallaxRamp& ramp) {
    float lo = ramp.fromPxPerSec;
    float hi = ramp.fullPxPerSec;
    // Degenerate or inverted ends would divide by zero or run the ramp
    // backwards. Windows guards this the same way rather than validating at the
    // settings layer, because both values are independently typed by the user.
    if (hi <= lo) {
        hi = lo + 1.0f;
    }

    const float fade = std::clamp((speedPxPerSec - lo) / (hi - lo), 0.0f, 1.0f);
    const float minA = std::clamp(ramp.minAlpha, 0.0f, 1.0f);

    return ParallaxResult{ 1.0f - fade * (1.0f - minA), fade };
}

} // namespace TweakCore
