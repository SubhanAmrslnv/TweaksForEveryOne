#pragma once

namespace TweakCore {

// Both ends of the drag-parallax ramp, in the units the settings carry them in:
// speeds in px/s, opacity as a fraction. Defaults match the Windows TUNE_SPEC
// rows parallaxfrom / parallaxfull / parallaxmin (40 px/s, 600 px/s, 24%).
struct ParallaxRamp {
    float fromPxPerSec = 40.0f;
    float fullPxPerSec = 600.0f;
    float minAlpha     = 0.24f;
};

struct ParallaxResult {
    float alpha;   // 0..1, what to install as the "drag" layer's factor
    float fade;    // 0..1, how far along the ramp we are; 0 means "not engaged"
};

// Motion curves and glide maths. Mirrors Glide() in the Windows
// src/DropPlacement.ahk (it lived in src/WindowTweaks.ahk until the module split
// reduced that file to a 111-line entry point); keep the two aligned when
// changing either.
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

    // Drag parallax: how opaque a window should be while it is moving this fast.
    //
    // A RAMP BETWEEN TWO SPEEDS, not a gain per px/s, and that distinction is the
    // whole point. The Windows original was `alpha = 255 - speed * 0.06`, which
    // returned 225/255 at an ordinary 400 px/s drag - 88% opacity, which nobody
    // can see - and reached its floor only past 3200 px/s. It was doing exactly
    // what it said and was still indistinguishable from switched off. Naming both
    // ends makes "invisible at a normal drag speed" a value on the settings page
    // instead of a constant buried on a 16 ms path.
    //
    // `fade` is returned alongside the alpha because the caller needs to know
    // whether the ramp is engaged AT ALL, which it used to infer from a magic
    // `alpha < 250` - a test that threw away the first five units of every fade
    // and left the layer installed on the way out.
    static ParallaxResult parallaxAlpha(float speedPxPerSec, const ParallaxRamp& ramp);
};

} // namespace TweakCore
