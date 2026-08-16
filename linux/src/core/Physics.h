#pragma once

namespace TweakCore {

// Motion curves and glide maths. Mirrors Glide() in the Windows
// src/WindowTweaks.ahk; keep the two aligned when changing either.
//
// Invariant shared with the Windows side: parameterise on ELAPSED TIME, never on
// frame count. Every function here takes a normalised t in [0, 1] computed from
// wall-clock milliseconds, so a heavy frame makes an animation skip rather than
// run in slow motion.
class Physics {
public:
    // Quintic ease-out: 0 at t=0, 1 at t=1, decelerating throughout.
    //
    // The sign here used to be wrong. `1.0f - (--t)*t*t*t*t` decrements t before
    // the four remaining reads, so it evaluates 1 - (t-1)^5, which is 2.0 at t=0
    // and falls to 1.0 - a curve that runs backwards and starts at twice the
    // target delta. The Windows original is `1 - (1 - t) ** 5`, and since
    // (t-1)^5 == -(1-t)^5 the correct C++ is a plus.
    static float quinticEaseOut(float t) {
        return 1.0f + (--t) * t * t * t * t;
    }

    // Settle bump: exactly 0 at both ends, peaking at t = 0.25.
    //
    // Multiplied by the overshoot distance and added to the eased position, this
    // is what carries a window PAST the edge it is landing against and lets it
    // spring back, instead of easing asymptotically in and then being squashed
    // by a second animation. Normalised by 1/0.10547 so the peak equals the
    // requested pixels; without that the whole excursion is a tenth of what the
    // caller asked for and invisible.
    static float settleBump(float t) {
        const float u = 1.0f - t;
        return 9.4815f * t * u * u * u;
    }

    // How long a glide of this distance should take, in milliseconds, clamped to
    // the configured maximum. Matches the Windows formula.
    static float glideDurationMs(float distancePx, float maxMs);

    // Where a window released at this velocity is heading, before snapping is
    // considered. Velocity is PIXELS PER SECOND on both platforms.
    //
    // This replaces a kinetic-friction resting-position solver
    // (d = v^2 / 2a, with a hardcoded a = 500) that corresponded to nothing on
    // the Windows side. Windows extrapolates ballistically by a tunable gain and
    // then lerps toward whatever the snap resolved to, which is a different model
    // and the one both sides now use.
    static void predictThrow(int startX, int startY, float velXPerSec, float velYPerSec,
                             float throwGain, float maxPx, int& outX, int& outY);
};

} // namespace TweakCore
