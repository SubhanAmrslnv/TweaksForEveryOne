#include "AnimationScheduler.h"
#include <algorithm>
#include <exception>
#include <string>
#include <utility>
#include <vector>

namespace TweakCore {

// The frame period is 16 ms here and 15 ms on Windows, and that divergence is
// deliberate. The Windows value is a measured compensation for the ~15.6 ms
// timer tick, documented with benchmarks in src/AnimationScheduler.ahk. Whether
// Linux needs the same trick is untested; do not harmonise the two without
// measuring on a real session.
static constexpr float kFrameMs = 16.0f;

// How long the produce phase may take before the frame is counted as late. The
// render phase is not included: it is one flush and its cost belongs to the
// backend, not to the animations.
static constexpr float kProduceBudgetMs = 12.0f;

// A key that throws every frame would otherwise put 60+ lines a second into the
// log, and a genuinely broken animation is exactly the case where the log has to
// stay readable.
static constexpr int  kThrowLogIntervalMs = 1000;
static constexpr size_t kThrowLogMaxKeys  = 64;

AnimationScheduler::AnimationScheduler(std::shared_ptr<RenderQueue> renderQueue)
    : m_renderQueue(std::move(renderQueue)), m_running(false) {}

AnimationScheduler::~AnimationScheduler() {
    stop();
}

void AnimationScheduler::start() {
    if (m_running) return;
    m_running = true;
    m_thread = std::thread(&AnimationScheduler::loop, this);
}

void AnimationScheduler::stop() {
    m_running = false;
    if (m_thread.joinable()) {
        m_thread.join();
    }
}

uint64_t AnimationScheduler::slotOf(uint32_t windowId, AnimChannel channel) {
    return (static_cast<uint64_t>(windowId) << 8) | static_cast<uint64_t>(channel);
}

void AnimationScheduler::forgetOwnershipLocked(const std::string& key) {
    auto it = m_keyOwnership.find(key);
    if (it == m_keyOwnership.end()) {
        return;
    }
    const uint64_t slot = slotOf(it->second.windowId, it->second.channel);
    m_keyOwnership.erase(it);
    // Only release the slot if it still points at this key: a claim that
    // replaced us has already rewritten it, and stealing it back here would
    // leave the new owner running unowned.
    auto slotIt = m_slotOwner.find(slot);
    if (slotIt != m_slotOwner.end() && slotIt->second == key) {
        m_slotOwner.erase(slotIt);
    }
}

void AnimationScheduler::cancelLocked(const std::string& key) {
    m_animations.erase(
        std::remove_if(m_animations.begin(), m_animations.end(), [&](const AnimationTask& t) {
            return t.key == key;
        }),
        m_animations.end()
    );
    forgetOwnershipLocked(key);
}

void AnimationScheduler::registerAnimation(const std::string& key, AnimationCallback callback) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_animations.erase(
        std::remove_if(m_animations.begin(), m_animations.end(), [&](const AnimationTask& t) {
            return t.key == key;
        }),
        m_animations.end()
    );
    m_animations.push_back({key, std::move(callback)});
}

void AnimationScheduler::cancelAnimation(const std::string& key) {
    std::lock_guard<std::mutex> lock(m_mutex);
    cancelLocked(key);
}

void AnimationScheduler::claim(uint32_t windowId, AnimChannel channel, const std::string& key,
                               AnimationCallback callback) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const uint64_t slot = slotOf(windowId, channel);

    auto slotIt = m_slotOwner.find(slot);
    if (slotIt != m_slotOwner.end() && slotIt->second != key) {
        cancelLocked(slotIt->second);
    }
    forgetOwnershipLocked(key);  // this key may have owned another slot

    m_slotOwner[slot] = key;
    m_keyOwnership[key] = Ownership{windowId, channel};

    m_animations.erase(
        std::remove_if(m_animations.begin(), m_animations.end(), [&](const AnimationTask& t) {
            return t.key == key;
        }),
        m_animations.end()
    );
    m_animations.push_back({key, std::move(callback)});
}

void AnimationScheduler::release(uint32_t windowId, AnimChannel channel) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_slotOwner.find(slotOf(windowId, channel));
    if (it != m_slotOwner.end()) {
        cancelLocked(it->second);
    }
}

void AnimationScheduler::releaseAll(uint32_t windowId) {
    release(windowId, AnimChannel::Geometry);
    release(windowId, AnimChannel::Alpha);
    release(windowId, AnimChannel::Region);
}

std::string AnimationScheduler::owner(uint32_t windowId, AnimChannel channel) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_slotOwner.find(slotOf(windowId, channel));
    return (it == m_slotOwner.end()) ? std::string() : it->second;
}

void AnimationScheduler::setLogSink(std::function<void(const std::string&)> sink) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_logSink = std::move(sink);
}

AnimationScheduler::FrameStats AnimationScheduler::stats() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_stats;
}

std::string AnimationScheduler::throwLineLocked(const std::string& key, const char* what,
                                                std::chrono::steady_clock::time_point now) {
    auto it = m_lastThrow.find(key);
    if (it != m_lastThrow.end()) {
        const auto since =
            std::chrono::duration_cast<std::chrono::milliseconds>(now - it->second).count();
        if (since < kThrowLogIntervalMs) {
            return {};
        }
    }
    if (m_lastThrow.size() > kThrowLogMaxKeys) {
        m_lastThrow.clear();   // bound it; worst case is one repeated line
    }
    m_lastThrow[key] = now;

    return "animation '" + key + "' threw and was retired: " +
           std::string(what ? what : "unknown exception");
}

void AnimationScheduler::loop() {
    auto lastTime = std::chrono::steady_clock::now();
    const auto targetDt = std::chrono::milliseconds(static_cast<int>(kFrameMs));

    while (m_running) {
        auto now = std::chrono::steady_clock::now();
        float dt = std::chrono::duration<float, std::milli>(now - lastTime).count();
        // Clamped, as on Windows. After a long stall an unclamped dt teleports
        // every rate-based animation to its end in a single frame.
        if (dt <= 0.0f) {
            dt = kFrameMs;
        } else if (dt > kFrameMs * 3.0f) {
            dt = kFrameMs * 3.0f;
        }
        lastTime = now;

        std::vector<AnimationTask> currentAnimations;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            currentAnimations = m_animations;  // snapshot: callbacks may register or cancel
        }

        const auto produceStart = std::chrono::steady_clock::now();

        std::vector<std::string> toRemove;
        std::vector<std::pair<std::string, std::string>> threw;
        for (auto& task : currentAnimations) {
            // Swallowing the exception is right - one bad callback must not kill
            // the frame loop and take every other animation with it. Letting it
            // escape was NOT right: this runs on a std::thread with no handler
            // above it, so a single throw called std::terminate and killed the
            // whole daemon. Windows retires the animation and logs; so does this.
            //
            // Collected here and reported after the loop, not inline: deciding
            // whether a key is still inside its throttle window needs m_mutex,
            // and callbacks must never run while it is held.
            bool keepAlive = false;
            try {
                keepAlive = task.callback(dt);
            } catch (const std::exception& e) {
                threw.emplace_back(task.key, e.what() ? e.what() : "std::exception");
            } catch (...) {
                threw.emplace_back(task.key, "non-std exception");
            }
            if (!keepAlive) {
                toRemove.push_back(task.key);
            }
        }

        const auto produceEnd = std::chrono::steady_clock::now();

        std::vector<std::string> toLog;
        std::function<void(const std::string&)> sink;
        if (!toRemove.empty() || !threw.empty()) {
            std::lock_guard<std::mutex> lock(m_mutex);
            for (const auto& key : toRemove) {
                // An animation that ends of its own accord releases its channel,
                // so a feature does not have to remember to.
                cancelLocked(key);
            }
            for (const auto& entry : threw) {
                std::string line = throwLineLocked(entry.first, entry.second.c_str(), produceEnd);
                if (!line.empty()) {
                    toLog.push_back(std::move(line));
                }
            }
            sink = m_logSink;
        }
        // Emitted with NO lock held - see throwLineLocked.
        if (sink) {
            for (const auto& line : toLog) {
                sink(line);
            }
        }

        // Flush UNCONDITIONALLY, exactly once per frame.
        //
        // This used to be guarded by "did any animation ask to stay alive?",
        // which silently dropped the terminal state of every animation: a
        // callback that writes its final geometry and returns false set the flag
        // to false, so nothing flushed and the window never reached the position
        // it was animating toward. That is the exact failure mode RenderCore.ahk
        // documents as having killed snapping, the transparency wheel and
        // un-ghosting on the Windows side, and it is why the invariant in
        // linux/CLAUDE.md says "flush exactly once per frame" with no condition.
        const auto renderStart = std::chrono::steady_clock::now();
        // Guarded for the same reason the callbacks are. This reaches into a
        // PlatformAdapter, which reaches the X server or the session bus, and an
        // exception from there would unwind out of the loop and terminate the
        // process just as surely as a bad animation did. Losing one frame is
        // survivable; losing the daemon is not.
        try {
            m_renderQueue->flush();
        } catch (...) {
        }
        const auto renderEnd = std::chrono::steady_clock::now();

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_stats.produceMs =
                std::chrono::duration<float, std::milli>(produceEnd - produceStart).count();
            m_stats.renderMs =
                std::chrono::duration<float, std::milli>(renderEnd - renderStart).count();
            ++m_stats.frames;
            if (m_stats.produceMs > kProduceBudgetMs) {
                ++m_stats.overBudget;
            }
        }

        bool idle;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            idle = m_animations.empty();
        }

        // Nothing to drive: wait a whole frame rather than spinning. Windows
        // kills its timer outright here; this thread has to stay alive to be
        // joinable, so it parks instead.
        auto frameTime = std::chrono::steady_clock::now() - now;
        if (idle) {
            std::this_thread::sleep_for(targetDt);
        } else if (frameTime < targetDt) {
            std::this_thread::sleep_for(targetDt - frameTime);
        }
    }
}

} // namespace TweakCore
