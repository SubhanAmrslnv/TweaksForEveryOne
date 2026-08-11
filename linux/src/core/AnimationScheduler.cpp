#include "AnimationScheduler.h"
#include <algorithm>

namespace TweakCore {

AnimationScheduler::AnimationScheduler(std::shared_ptr<RenderQueue> renderQueue)
    : m_renderQueue(renderQueue), m_running(false) {}

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

void AnimationScheduler::registerAnimation(const std::string& key, AnimationCallback callback) {
    std::lock_guard<std::mutex> lock(m_mutex);
    // Remove if exists
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
    m_animations.erase(
        std::remove_if(m_animations.begin(), m_animations.end(), [&](const AnimationTask& t) {
            return t.key == key;
        }),
        m_animations.end()
    );
}

void AnimationScheduler::loop() {
    auto lastTime = std::chrono::steady_clock::now();
    const auto targetDt = std::chrono::milliseconds(16); // ~60fps

    while (m_running) {
        auto now = std::chrono::steady_clock::now();
        float dt = std::chrono::duration<float>(now - lastTime).count();
        lastTime = now;

        bool hasActive = false;
        std::vector<AnimationTask> currentAnimations;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            currentAnimations = m_animations;
        }

        std::vector<std::string> toRemove;
        for (auto& task : currentAnimations) {
            bool keepAlive = task.callback(dt);
            if (!keepAlive) {
                toRemove.push_back(task.key);
            } else {
                hasActive = true;
            }
        }

        if (!toRemove.empty()) {
            std::lock_guard<std::mutex> lock(m_mutex);
            for (const auto& key : toRemove) {
                m_animations.erase(
                    std::remove_if(m_animations.begin(), m_animations.end(), [&](const AnimationTask& t) {
                        return t.key == key;
                    }),
                    m_animations.end()
                );
            }
        }

        // Flush render queue if we produced any updates
        if (hasActive) {
            m_renderQueue->flush();
        }

        // Sleep to maintain target frame rate
        auto frameTime = std::chrono::steady_clock::now() - now;
        if (frameTime < targetDt) {
            std::this_thread::sleep_for(targetDt - frameTime);
        }
    }
}

} // namespace TweakCore
