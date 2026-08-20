#include "TestHarness.h"
#include "FakeAdapter.h"

#include "core/RenderQueue.h"

#include <memory>

using namespace TweakCore;
using TweakTest::FakeAdapter;

int main() {
    // ---- composed alpha ------------------------------------------------------
    CASE("composed alpha is base times every layer");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setBaseAlpha(1, 0.5f);
        q.setAlphaLayer(1, "breathe", 0.5f);
        q.flush();

        CHECK(fake->alphaCalls.size() == 1);
        CHECK(!fake->alphaCalls.back().off);
        CHECK_NEAR(fake->alphaCalls.back().value, 0.25f, 1e-4);
    }

    CASE("clearing one layer leaves the base and the other layers alone");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        // This is the defect class the whole composition model exists for. The
        // user sets 50% with the wheel, a feature dims it further, the feature
        // finishes - and before composition, the feature wrote an absolute
        // "fully opaque" and destroyed the 50% the user had asked for.
        q.setBaseAlpha(1, 0.5f);
        q.setAlphaLayer(1, "depth", 0.8f);
        q.flush();
        fake->alphaCalls.clear();

        q.clearAlphaLayer(1, "depth");
        q.flush();

        CHECK(fake->alphaCalls.size() == 1);
        CHECK(!fake->alphaCalls.back().off);
        CHECK_NEAR(fake->alphaCalls.back().value, 0.5f, 1e-4);
        CHECK_NEAR(q.baseAlpha(1), 0.5f, 1e-4);
    }

    // ---- structural neutrality ----------------------------------------------
    CASE("off is emitted only for a structurally neutral record");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setBaseAlpha(1, 0.5f);
        q.flush();
        fake->alphaCalls.clear();

        q.setBaseAlpha(1, 1.0f);   // back to neutral: base 1.0, no layers
        q.flush();

        CHECK(fake->alphaCalls.size() == 1);
        CHECK(fake->alphaCalls.back().off);   // NOT a write of 1.0
    }

    CASE("a layer at factor 1.0 keeps the record layered");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        // The proximity ghost installs its layer at 1.0 for exactly this reason.
        // A numeric neutrality test would strip and re-add the layered state 60
        // times a second while the cursor rests on a ghost, and in between the
        // window is opaque, click-through and always-on-top with no visible cue.
        q.setAlphaLayer(1, "ghost", 1.0f);
        q.flush();

        CHECK(fake->alphaCalls.size() == 1);
        CHECK(!fake->alphaCalls.back().off);
        CHECK_NEAR(fake->alphaCalls.back().value, 1.0f, 1e-4);
    }

    CASE("resetAlphaState hands back a structurally neutral window");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setBaseAlpha(1, 0.3f);
        q.setAlphaLayer(1, "drag", 0.5f);
        q.flush();
        fake->alphaCalls.clear();

        q.resetAlphaState(1);
        q.flush();
        CHECK(fake->alphaCalls.size() == 1);
        CHECK(fake->alphaCalls.back().off);
    }

    // ---- priority ------------------------------------------------------------
    CASE("priorities arbitrate within one flush");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setGeometry(1, 10, 10, 100, 100, RenderPriority::User);
        q.setGeometry(1, 20, 20, 200, 200, RenderPriority::Ambient);   // dropped
        q.flush();

        CHECK(fake->geometryCalls.size() == 1);
        CHECK(fake->geometryCalls.back().x == 10);
    }

    CASE("geometry priority cannot arbitrate for alpha");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        // The documented bug: one shared priority field meant an Ambient
        // geometry write after a User alpha write downgraded the entry, and a
        // later Ambient alpha write then beat the User one.
        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.setGeometry(1, 0, 0, 10, 10, RenderPriority::Ambient);
        q.setAlpha(1, 0.9f, RenderPriority::Ambient);   // must NOT win
        q.flush();

        CHECK(fake->alphaCalls.size() == 1);
        CHECK_NEAR(fake->alphaCalls.back().value, 0.5f, 1e-4);
    }

    // ---- caching -------------------------------------------------------------
    CASE("a repeated identical alpha is suppressed");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setBaseAlpha(1, 0.5f);
        q.flush();
        CHECK(fake->alphaCalls.size() == 1);

        // A settled fade re-asserts the same value every frame. Two guards catch
        // it - the early-out in setBaseAlpha and the last-applied cache - and
        // this pins the second one.
        q.setAlpha(1, 0.5f, RenderPriority::Ambient);
        q.flush();
        CHECK(fake->alphaCalls.size() == 1);
        CHECK(q.stats().suppressed >= 1);
    }

    CASE("a FAILED call does not poison the cache");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        // Windows recorded the value whether or not WinSetTransparent landed. On
        // an elevated window it never landed, so every later identical write was
        // then diffed away as redundant and parallax, breathing and the ghost
        // silently never worked on that window again - with nothing logged.
        fake->failFor.insert(1);
        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.flush();
        CHECK(fake->alphaCalls.empty());
        CHECK(q.stats().failed >= 1);

        fake->failFor.clear();
        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.flush();
        CHECK(fake->alphaCalls.size() == 1);   // retried, not suppressed
    }

    // ---- region --------------------------------------------------------------
    CASE("cleared is not the same as an empty rect list");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        RegionSpec rolled;
        rolled.cleared = false;
        rolled.rects.push_back(Rect{0, 0, 400, 30});
        q.setRegion(1, rolled);
        q.flush();
        CHECK(fake->regionCalls.size() == 1);
        CHECK(!fake->regionCalls.back().second.cleared);

        q.clearRegion(1);
        q.flush();
        CHECK(fake->regionCalls.size() == 2);
        CHECK(fake->regionCalls.back().second.cleared);
        CHECK(fake->regionCalls.back().second.rects.empty());
    }

    // ---- lifecycle -----------------------------------------------------------
    CASE("removeWindow forgets everything about a window");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setBaseAlpha(1, 0.5f);
        q.flush();
        q.removeWindow(1);
        CHECK_NEAR(q.baseAlpha(1), 1.0f, 1e-6);

        // A recycled id must not inherit the opacity of the dead one: the write
        // has to reach the adapter again rather than being diffed away.
        fake->alphaCalls.clear();
        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.flush();
        CHECK(fake->alphaCalls.size() == 1);
    }

    CASE("sweepDead reclaims windows nobody reported");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        fake->alive.insert(2);
        q.setBaseAlpha(1, 0.5f);   // will be reported dead
        q.setBaseAlpha(2, 0.5f);   // alive
        q.flush();

        q.sweepDead();
        CHECK_NEAR(q.baseAlpha(1), 1.0f, 1e-6);
        CHECK_NEAR(q.baseAlpha(2), 0.5f, 1e-6);
    }

    CASE("shutdown makes later writes and flushes inert");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.shutdown();
        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.flush();
        // A feature timer that outlives teardown must not be able to re-apply
        // state the teardown has just undone.
        CHECK(fake->alphaCalls.empty());
    }

    CASE("commit flushes inline when no scheduler is running");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        // The one-shot producer case. The scheduler parks when nothing is
        // animating, so a hotkey that queues and returns has nobody to flush it -
        // which is what silently killed snapping-without-glide, the transparency
        // wheel, breathing restore and un-ghosting on Windows.
        q.setGeometry(7, 1, 2, 3, 4, RenderPriority::User);
        q.commit();
        CHECK(fake->geometryCalls.size() == 1);
    }

    CASE("currentAlpha prefers a pending write over the last applied one");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setAlpha(1, 0.5f, RenderPriority::User);
        q.flush();
        CHECK_NEAR(q.currentAlpha(1), 0.5f, 1e-4);

        q.setAlpha(1, 0.2f, RenderPriority::User);
        CHECK_NEAR(q.currentAlpha(1), 0.2f, 1e-4);   // not yet flushed, still wins
        CHECK_NEAR(q.currentAlpha(999, 0.7f), 0.7f, 1e-4);
    }

    CASE("a flush is wrapped in exactly one batch");
    {
        auto fake = std::make_shared<FakeAdapter>();
        RenderQueue q(fake);

        q.setGeometry(1, 0, 0, 10, 10, RenderPriority::User);
        q.setGeometry(2, 0, 0, 10, 10, RenderPriority::User);
        q.flush();
        CHECK(fake->batchesOpened == 1);
        CHECK(fake->batchDepth == 0);
    }

    return TweakTest::summarise("renderqueue");
}
