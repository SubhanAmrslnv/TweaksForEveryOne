#pragma once

#include "RenderQueue.h"
#include <functional>
#include <vector>
#include <string>
#include <chrono>
#include <thread>
#include <atomic>
#include <mutex>
#include <memory>
#include <map>
#include <cstdint>

namespace TweakCore {

// dt is elapsed MILLISECONDS since the last frame, clamped. Windows passes
// (dt, now); here a callback that needs absolute time accumulates dt itself.
using AnimationCallback = std::function<bool(float dt)>;

struct AnimationTask {
    std::string key;
    AnimationCallback callback;
};

// A channel is a property class. At most one animation may own (window, channel)
// at a time, and claiming it cancels whoever held it.
//
// This is the first of the two invariants linux/CLAUDE.md listed as "not yet
// expressible here": two animations must never drive the same property of the
// same window at the same priority. On Windows the absence of it produced real
// bugs - a 400 ms wobble kept resizing a window the user had already grabbed
// again, because the five hand-written cancel lists had drifted apart and none
// of them named it.
enum class AnimChannel {
    Geometry,
    Alpha,
    Region
};

class AnimationScheduler {
public:
    explicit AnimationScheduler(std::shared_ptr<RenderQueue> renderQueue);
    ~AnimationScheduler();

    void start();
    void stop();

    // Register a callback. Overwrites an existing animation with the same key.
    // Callback returns true to stay alive, false when finished.
    void registerAnimation(const std::string& key, AnimationCallback callback);
    void cancelAnimation(const std::string& key);

    // Register and take sole ownership of this window's channel, cancelling
    // whoever held it.
    void claim(uint32_t windowId, AnimChannel channel, const std::string& key,
               AnimationCallback callback);
    // Cancel whatever owns this window's channel.
    void release(uint32_t windowId, AnimChannel channel);
    // Cancel every channel of this window.
    void releaseAll(uint32_t windowId);
    // The key currently driving this window's channel, or "" if nothing is.
    std::string owner(uint32_t windowId, AnimChannel channel) const;

    // Where a retired-by-exception animation gets reported.
    //
    // core/ may not depend on the logger, the settings or Qt GUI, so the sink is
    // injected rather than called directly. Leaving it unset keeps the old
    // behaviour of dropping the message, which is why setting it matters: on
    // Windows a bare `catch` here is exactly what made "drag parallax does
    // nothing" undiagnosable - one throw inside the velocity sampler retired the
    // whole drag pipeline for that drag, with a clean parse and an empty log.
    void setLogSink(std::function<void(const std::string&)> sink);

    // Per-frame timings, for diagnosing a loop that is missing its deadline.
    struct FrameStats {
        float    produceMs = 0.0f;   // time in callbacks, last frame
        float    renderMs  = 0.0f;   // time in RenderQueue::flush(), last frame
        uint64_t frames    = 0;
        uint64_t overBudget = 0;     // frames whose produce phase exceeded the budget
    };
    FrameStats stats() const;

private:
    void loop();
    // Caller must hold m_mutex.
    void cancelLocked(const std::string& key);
    void forgetOwnershipLocked(const std::string& key);
    static uint64_t slotOf(uint32_t windowId, AnimChannel channel);

    struct Ownership {
        uint32_t windowId;
        AnimChannel channel;
    };

    // Returns the line to log, or "" when this key is still inside its throttle
    // window. It deliberately does NOT call the sink: the sink is user code, it
    // is reached through m_mutex, and a sink that touched the scheduler - the
    // obvious thing for a diagnostics module to do - would deadlock against a
    // non-recursive mutex. The caller emits after unlocking.
    std::string throwLineLocked(const std::string& key, const char* what,
                                std::chrono::steady_clock::time_point now);

    std::shared_ptr<RenderQueue> m_renderQueue;
    std::function<void(const std::string&)> m_logSink;

    // When each key was last reported as throwing. Bounded rather than pruned:
    // keys are per-window ("glide_12345"), so an unbounded map would grow for the
    // whole session. It only ever gains an entry when a callback actually throws,
    // so in a healthy process it stays empty and the cap never fires.
    std::map<std::string, std::chrono::steady_clock::time_point> m_lastThrow;

    FrameStats m_stats;
    std::vector<AnimationTask> m_animations;
    std::map<uint64_t, std::string> m_slotOwner;      // (window, channel) -> key
    std::map<std::string, Ownership> m_keyOwnership;  // key -> (window, channel)
    mutable std::mutex m_mutex;
    std::atomic<bool> m_running;
    std::thread m_thread;
};

} // namespace TweakCore
