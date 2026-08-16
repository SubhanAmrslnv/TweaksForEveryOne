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

    std::shared_ptr<RenderQueue> m_renderQueue;
    std::vector<AnimationTask> m_animations;
    std::map<uint64_t, std::string> m_slotOwner;      // (window, channel) -> key
    std::map<std::string, Ownership> m_keyOwnership;  // key -> (window, channel)
    mutable std::mutex m_mutex;
    std::atomic<bool> m_running;
    std::thread m_thread;
};

} // namespace TweakCore
