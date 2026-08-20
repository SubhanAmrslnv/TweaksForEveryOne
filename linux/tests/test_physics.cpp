#include "TestHarness.h"

#include "core/Physics.h"
#include "core/VelocitySampler.h"

using namespace TweakCore;

int main() {
    // ---- quinticEaseOut ------------------------------------------------------
    // This one is a REGRESSION TEST, not a sanity check. The expression
    // `1.0f - (--t)*t*t*t*t` reads as correct and evaluates to 2.0 at t=0, and
    // both CLAUDE.md files carry a struck-through note begging nobody to
    // "correct" the sign back after reading it without evaluating it. A test is
    // the only thing that actually stops that.
    CASE("quinticEaseOut endpoints");
    CHECK_NEAR(Physics::quinticEaseOut(0.0f), 0.0f, 1e-6);
    CHECK_NEAR(Physics::quinticEaseOut(1.0f), 1.0f, 1e-6);
    CHECK(Physics::quinticEaseOut(0.0f) < 1.5f);   // the 2.0 bug, named explicitly

    CASE("quinticEaseOut is monotonic and decelerating");
    {
        float prev = Physics::quinticEaseOut(0.0f);
        float prevStep = 1.0f;
        for (int i = 1; i <= 100; ++i) {
            const float t = static_cast<float>(i) / 100.0f;
            const float v = Physics::quinticEaseOut(t);
            CHECK(v >= prev - 1e-6f);
            const float step = v - prev;
            CHECK(step <= prevStep + 1e-6f);   // ease-OUT: never speeds up
            prevStep = step;
            prev = v;
        }
    }

    // ---- settleBump ----------------------------------------------------------
    CASE("settleBump is zero at both ends and peaks at 1.0");
    CHECK_NEAR(Physics::settleBump(0.0f), 0.0f, 1e-6);
    CHECK_NEAR(Physics::settleBump(1.0f), 0.0f, 1e-6);
    // The 9.4815 normaliser is what makes the peak equal the pixels the caller
    // asked for. Without it the whole excursion is a tenth of the request and
    // invisible, which is a bug that looks exactly like "the feature is off".
    CHECK_NEAR(Physics::settleBump(0.25f), 1.0f, 1e-3);

    // ---- glideDurationMs -----------------------------------------------------
    CASE("glideDurationMs floors and clamps");
    CHECK_NEAR(Physics::glideDurationMs(0.0f, 650.0f), 140.0f, 1e-3);
    CHECK(Physics::glideDurationMs(100000.0f, 650.0f) <= 650.0f);
    CHECK(Physics::glideDurationMs(500.0f, 650.0f) > Physics::glideDurationMs(100.0f, 650.0f));

    // ---- predictThrow --------------------------------------------------------
    CASE("predictThrow uses the shared 0.18 gain and clamps");
    {
        int x = 0, y = 0;
        Physics::predictThrow(100, 100, 1000.0f, 0.0f, 1.0f, 500.0f, x, y);
        CHECK_NEAR(x, 100 + 180, 1.0);   // 1000 px/s * 1.0 gain * 0.18
        CHECK_NEAR(y, 100, 1.0);

        Physics::predictThrow(0, 0, 100000.0f, -100000.0f, 1.0f, 500.0f, x, y);
        CHECK(x <= 500);
        CHECK(y >= -500);
    }

    // ---- parallaxAlpha -------------------------------------------------------
    CASE("parallaxAlpha names both ends of the ramp");
    {
        ParallaxRamp ramp;   // 40 px/s, 600 px/s, 0.24

        // Below the start: not engaged at all. `fade == 0` is what callers test,
        // instead of the magic `alpha < 250` that threw away the first five units
        // of every fade and left the layer installed on the way out.
        const auto still = Physics::parallaxAlpha(0.0f, ramp);
        CHECK_NEAR(still.alpha, 1.0f, 1e-6);
        CHECK_NEAR(still.fade, 0.0f, 1e-6);

        const auto atStart = Physics::parallaxAlpha(40.0f, ramp);
        CHECK_NEAR(atStart.fade, 0.0f, 1e-6);

        const auto atFull = Physics::parallaxAlpha(600.0f, ramp);
        CHECK_NEAR(atFull.alpha, 0.24f, 1e-4);
        CHECK_NEAR(atFull.fade, 1.0f, 1e-6);

        const auto beyond = Physics::parallaxAlpha(5000.0f, ramp);
        CHECK_NEAR(beyond.alpha, 0.24f, 1e-4);   // clamped, not extrapolated

        // The point of the rewrite: an ORDINARY drag must produce a visible
        // fade. The old gain returned 225/255 = 0.88 at 400 px/s, which is
        // indistinguishable from switched off.
        const auto ordinary = Physics::parallaxAlpha(400.0f, ramp);
        CHECK(ordinary.alpha < 0.55f);
        CHECK(ordinary.fade > 0.0f);
    }

    CASE("parallaxAlpha survives degenerate ends");
    {
        ParallaxRamp bad;
        bad.fromPxPerSec = 500.0f;
        bad.fullPxPerSec = 100.0f;   // inverted: would divide by a negative
        const auto r = Physics::parallaxAlpha(300.0f, bad);
        CHECK(r.alpha >= 0.0f && r.alpha <= 1.0f);
        CHECK(r.fade >= 0.0f && r.fade <= 1.0f);
    }

    // ---- VelocitySampler -----------------------------------------------------
    // The highest-value test in the suite. The same hand motion must report the
    // same px/s whether it arrives in one heavy frame or ten light ones. When
    // this was wrong on Windows, every downstream constant - the throw gain, the
    // tilt and monitor-throw thresholds, the parallax ramp, the magnetic-group
    // break - was silently calibrated to one frame duration, and the same flick
    // threw a window three times as far under load.
    CASE("velocity is frame-rate independent");
    {
        VelocitySampler fine;
        fine.begin(0, 0);
        for (int i = 1; i <= 10; ++i) {
            fine.sample(i * 10, 0, 10.0f);   // 10 px per 10 ms, ten times
        }

        VelocitySampler coarse;
        coarse.begin(0, 0);
        coarse.sample(100, 0, 100.0f);       // 100 px in one 100 ms step

        // Both describe 1000 px/s. The EMA has different settling in each case,
        // so this is a tolerance on the reported speed, not an identity - but the
        // pre-fix code reported values an order of magnitude apart.
        CHECK(fine.speed() > 600.0f);
        CHECK(coarse.speed() > 600.0f);
        CHECK(std::fabs(fine.speed() - coarse.speed()) < 400.0f);
    }

    CASE("velocity converges on the true px/s");
    {
        VelocitySampler s;
        s.begin(0, 0);
        int x = 0;
        for (int i = 0; i < 60; ++i) {   // ~1 s of steady 1000 px/s
            x += 16;
            s.sample(x, 0, 16.0f);
        }
        CHECK_NEAR(s.speed(), 1000.0, 60.0);
        CHECK(s.velY() == 0.0f);
    }

    CASE("emaFactor is a time constant");
    {
        // One time constant of elapsed time must cover ~63% of the gap,
        // regardless of how the time is chopped up.
        CHECK_NEAR(VelocitySampler::emaFactor(30.0f, 30.0f), 0.6321, 1e-3);
        CHECK_NEAR(VelocitySampler::emaFactor(0.0f, 30.0f), 0.0, 1e-6);
        CHECK_NEAR(VelocitySampler::emaFactor(1e9f, 30.0f), 1.0, 1e-6);
    }

    CASE("smoothAlpha approaches its target and never overshoots");
    {
        VelocitySampler s;
        s.begin(0, 0);
        float a = 1.0f;
        for (int i = 0; i < 200; ++i) {
            a = s.smoothAlpha(0.24f, 16.0f);
            CHECK(a >= 0.24f - 1e-4f);
            CHECK(a <= 1.0f + 1e-4f);
        }
        CHECK_NEAR(a, 0.24, 1e-3);
    }

    return TweakTest::summarise("physics");
}
