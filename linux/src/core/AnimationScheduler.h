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

namespace TweakCore {

using AnimationCallback = std::function<bool(float dt)>;

struct AnimationTask {
    std::string key;
    AnimationCallback callback;
};

class AnimationScheduler {
public:
    AnimationScheduler(std::shared_ptr<RenderQueue> renderQueue);
    ~AnimationScheduler();

    void start();
    void stop();

    // Register a callback. Overwrites existing animation with the same key.
    // Callback should return 'true' to stay alive, 'false' when finished.
    void registerAnimation(const std::string& key, AnimationCallback callback);
    void cancelAnimation(const std::string& key);

private:
    void loop();

    std::shared_ptr<RenderQueue> m_renderQueue;
    std::vector<AnimationTask> m_animations;
    std::mutex m_mutex;
    std::atomic<bool> m_running;
    std::thread m_thread;
};

} // namespace TweakCore
