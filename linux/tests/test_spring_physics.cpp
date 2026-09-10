#include "TestHarness.h"
#include "core/SpringPhysics.h"

#include <cmath>

using namespace TweakCore;

int main() {
    // ---- 1D Convergence under Default Config ----------------------------------
    CASE("spring converges and settles exactly at target");
    {
        float pos = 0.0f;
        float vel = 0.0f;
        const float target = 100.0f;

        // Step at 60Hz (~16.6ms) for 2 seconds (120 frames)
        for (int i = 0; i < 120; ++i) {
            SpringPhysics::step(pos, vel, target, 0.0166f, SpringConfig::Default());
        }

        // Settling threshold should snap exactly to target with zero velocity
        CHECK_NEAR(pos, 100.0f, 1e-5);
        CHECK_NEAR(vel, 0.0f, 1e-5);
    }

    // ---- Underdamped Overshoot ------------------------------------------------
    CASE("bouncy config exhibits transient overshoot before settling");
    {
        float pos = 0.0f;
        float vel = 0.0f;
        const float target = 100.0f;
        bool overshot = false;

        // Bouncy spring has zeta = 0.76 < 1.0, so it will overshoot target
        for (int i = 0; i < 180; ++i) {
            SpringPhysics::step(pos, vel, target, 0.0166f, SpringConfig::Bouncy());
            if (pos > target) {
                overshot = true;
            }
        }

        CHECK(overshot);
        CHECK_NEAR(pos, 100.0f, 1e-5);
        CHECK_NEAR(vel, 0.0f, 1e-5);
    }

    // ---- Overdamped / Critically Damped (zeta >= 1.0) -------------------------
    CASE("critically damped config approaches target monotonically without overshoot");
    {
        SpringConfig critical{200.0f, 1.0f, 1.0f};
        float pos = 0.0f;
        float vel = 0.0f;
        const float target = 100.0f;
        bool overshot = false;

        for (int i = 0; i < 180; ++i) {
            SpringPhysics::step(pos, vel, target, 0.0166f, critical);
            if (pos > target + 1e-4f) {
                overshot = true;
            }
        }

        CHECK(!overshot);
        CHECK_NEAR(pos, 100.0f, 1e-4);
        CHECK_NEAR(vel, 0.0f, 1e-4);
    }

    // ---- Numerical Stability & dt Clamping -----------------------------------
    CASE("large delta time is clamped to avoid explosive divergence");
    {
        float pos = 0.0f;
        float vel = 0.0f;
        const float target = 50.0f;

        // Pass a giant 1.0 second dt; engine should clamp to 33ms and not explode or NaN
        SpringPhysics::step(pos, vel, target, 1.0f, SpringConfig::Snappy());

        CHECK(!std::isnan(pos));
        CHECK(!std::isinf(pos));
        CHECK(!std::isnan(vel));
        CHECK(!std::isinf(vel));
        CHECK(pos > 0.0f);
        CHECK(pos < target * 2.0f);
    }

    // ---- Zero / Negative dt No-op --------------------------------------------
    CASE("zero or negative dt leaves state untouched");
    {
        float pos = 42.0f;
        float vel = 10.0f;
        SpringPhysics::step(pos, vel, 100.0f, 0.0f);
        CHECK_NEAR(pos, 42.0f, 1e-6);
        CHECK_NEAR(vel, 10.0f, 1e-6);

        SpringPhysics::step(pos, vel, 100.0f, -0.016f);
        CHECK_NEAR(pos, 42.0f, 1e-6);
        CHECK_NEAR(vel, 10.0f, 1e-6);
    }

    // ---- 2D Stepping and Settle Predicate ------------------------------------
    CASE("step2D returns true only when both axes settle");
    {
        float x = 0.0f, y = 0.0f;
        float vx = 0.0f, vy = 0.0f;
        const float targetX = 200.0f;
        const float targetY = 300.0f;

        bool settled = false;
        int frames = 0;
        for (int i = 0; i < 200; ++i) {
            settled = SpringPhysics::step2D(x, y, vx, vy, targetX, targetY, 0.0166f, SpringConfig::Snappy());
            ++frames;
            if (settled) break;
        }

        CHECK(settled);
        CHECK_NEAR(x, targetX, 1e-5);
        CHECK_NEAR(y, targetY, 1e-5);
        CHECK_NEAR(vx, 0.0f, 1e-5);
        CHECK_NEAR(vy, 0.0f, 1e-5);
        CHECK(frames > 10); // ensured dynamic trajectory before settling
    }

    return TweakTest::summarise("spring_physics");
}
