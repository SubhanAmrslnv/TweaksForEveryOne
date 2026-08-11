#include "RenderQueue.h"

namespace TweakCore {

RenderQueue::RenderQueue(std::shared_ptr<PlatformAdapter> adapter)
    : m_adapter(adapter) {}

void RenderQueue::setGeometry(uint32_t windowId, int x, int y, int w, int h, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto& state = m_queue[windowId];
    
    // Only overwrite if incoming priority is >= current stored priority
    if (!state.hasGeometry || priority >= state.priority) {
        state.x = x;
        state.y = y;
        state.width = w;
        state.height = h;
        state.hasGeometry = true;
        state.priority = priority;
    }
}

void RenderQueue::setAlpha(uint32_t windowId, float alpha, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto& state = m_queue[windowId];
    
    if (!state.hasAlpha || priority >= state.priority) {
        state.alpha = alpha;
        state.hasAlpha = true;
        // Elevate overall priority if needed
        if (priority > state.priority) {
            state.priority = priority;
        }
    }
}

void RenderQueue::flush() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_queue.empty()) return;

    m_adapter->beginBatch();

    for (const auto& [winId, state] : m_queue) {
        if (state.hasGeometry) {
            m_adapter->setWindowGeometry(winId, state.x, state.y, state.width, state.height);
        }
        if (state.hasAlpha) {
            m_adapter->setWindowAlpha(winId, state.alpha);
        }
    }

    m_adapter->commitBatch();
    m_queue.clear();
}

} // namespace TweakCore
