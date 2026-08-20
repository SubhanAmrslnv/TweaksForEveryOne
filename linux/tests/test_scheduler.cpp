#include "TestHarness.h"
#include "FakeAdapter.h"

#include "core/AnimationScheduler.h"
#include "core/RenderQueue.h"

#include <atomic>
#include <chrono>
#include <memory>
#include <stdexcept>
#include <thread>

using namespace TweakCore;
using TweakTest::FakeAdapter;

namespace {

// The scheduler drives itself on its own thread, so every assertion here has to
// wait for real frames. 16 ms nominal, so 40 frames is comfortably under a
// second even on a loaded CI box.
void waitFrames(int frames) {
    std::this_thread::sleep_for(std::chrono::milliseconds(16 * frames + 40));
}

} // namespace

int main() {
    CASE("a throwing callback does not kill the process or the other animations");
    {
        // This is the test that would have caught std::terminate. The callback
        // exception used to unwind straight out of the frame loop, and since the
        // loop runs on a std::thread with no handler above it, one bad animation
        // took the whole daemon down. Windows retires the animation and logs.
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        std::atomic<int> goodTicks{0};
        std::atomic<int> logged{0};
        sched.setLogSink([&](const std::string&) { ++logged; });

        sched.registerAnimation("bad", [](float) -> bool {
            throw std::runtime_error("deliberate");
        });
        sched.registerAnimation("good", [&](float) -> bool {
            ++goodTicks;
            return true;
        });

        sched.start();
        waitFrames(10);

        // Survived, the healthy animation kept running, the bad one was retired,
        // and the failure was reported rather than swallowed in silence.
        CHECK(goodTicks.load() > 0);
        CHECK(logged.load() >= 1);
        CHECK(sched.owner(0, AnimChannel::Geometry).empty());

        sched.stop();
    }

    CASE("throw reporting is throttled per key");
    {
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        std::atomic<int> logged{0};
        sched.setLogSink([&](const std::string&) { ++logged; });

        // Re-register every frame so it throws repeatedly. Without throttling
        // this would be 60 log lines a second, and a broken animation is exactly
        // the case where the log has to stay readable.
        sched.start();
        for (int i = 0; i < 20; ++i) {
            sched.registerAnimation("noisy", [](float) -> bool {
                throw std::runtime_error("again");
            });
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
        }
        sched.stop();

        CHECK(logged.load() >= 1);
        CHECK(logged.load() <= 3);   // ~1 per second, not ~20
    }

    CASE("the terminal state of a finished animation still reaches the adapter");
    {
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        // The flush is unconditional for this reason: a callback that writes its
        // final geometry and returns false used to have that write dropped,
        // because the flush was gated on "did anything ask to stay alive?".
        sched.registerAnimation("oneshot", [&](float) -> bool {
            queue->setGeometry(42, 7, 8, 9, 10, RenderPriority::Animation);
            return false;
        });
        sched.start();
        waitFrames(6);
        sched.stop();

        CHECK(fake->geometryCalls.size() == 1);
        CHECK(fake->geometryCalls.back().x == 7);
    }

    CASE("claiming a channel cancels the previous owner");
    {
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        std::atomic<int> firstTicks{0};
        sched.claim(1, AnimChannel::Geometry, "glide", [&](float) -> bool {
            ++firstTicks;
            return true;
        });
        CHECK(sched.owner(1, AnimChannel::Geometry) == "glide");

        sched.claim(1, AnimChannel::Geometry, "bounce", [](float) -> bool { return true; });
        CHECK(sched.owner(1, AnimChannel::Geometry) == "bounce");

        sched.start();
        const int snapshot = firstTicks.load();
        waitFrames(6);
        // The displaced animation is genuinely gone, not merely unowned. Two
        // animations driving the same property of the same window is what made
        // "bouncy snapping" never put a pixel on screen.
        CHECK(firstTicks.load() == snapshot);
        sched.stop();
    }

    CASE("an animation that ends releases its channel");
    {
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        sched.claim(1, AnimChannel::Alpha, "fade", [](float) -> bool { return false; });
        sched.start();
        waitFrames(6);
        sched.stop();

        CHECK(sched.owner(1, AnimChannel::Alpha).empty());
    }

    CASE("frame stats are collected");
    {
        auto fake = std::make_shared<FakeAdapter>();
        auto queue = std::make_shared<RenderQueue>(fake);
        AnimationScheduler sched(queue);

        sched.registerAnimation("tick", [](float) -> bool { return true; });
        sched.start();
        waitFrames(10);
        const auto s = sched.stats();
        sched.stop();

        CHECK(s.frames > 0);
    }

    return TweakTest::summarise("scheduler");
}
