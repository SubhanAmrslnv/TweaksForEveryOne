#include "AnimationScheduler.h"
#include <algorithm>

namespace TweakCore {

// The frame period is 16 ms here and 15 ms on Windows, and that divergence is
// deliberate. The Windows value is a measured compensation for the ~15.6 ms
// timer tick, documented with benchmarks in src/AnimationScheduler.ahk. Whether
// Linux needs the same trick is untested; do not harmonise the two without
// measuring on a real session.
static constexpr float kFrameMs = 16.0f;

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

        std::vector<std::string> toRemove;
        for (auto& task : currentAnimations) {
            if (!task.callback(dt)) {
                toRemove.push_back(task.key);
            }
        }

        if (!toRemove.empty()) {
            std::lock_guard<std::mutex> lock(m_mutex);
            for (const auto& key : toRemove) {
                // An animation that ends of its own accord releases its channel,
                // so a feature does not have to remember to.
                cancelLocked(key);
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
        m_renderQueue->flush();

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
