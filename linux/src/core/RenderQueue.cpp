#include "RenderQueue.h"

#include <algorithm>
#include <vector>

namespace TweakCore {

RenderQueue::RenderQueue(std::shared_ptr<PlatformAdapter> adapter)
    : m_adapter(std::move(adapter)) {}

void RenderQueue::setGeometry(uint32_t windowId, int x, int y, int w, int h, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto& state = m_queue[windowId];

    // Geometry and opacity carry SEPARATE priorities.
    //
    // They used to share one field, and only setAlpha guarded it: setGeometry
    // assigned state.priority unconditionally, so an Ambient geometry write
    // after a User alpha write downgraded the stored priority and let a later
    // Ambient alpha write win over the User one. Windows keeps four independent
    // maps (RS_Alpha, RS_Pos, RS_Region, RS_ZOrder) precisely so one attribute
    // cannot arbitrate for another.
    if (!state.hasGeometry || priority >= state.geometryPriority) {
        state.x = x;
        state.y = y;
        state.width = w;
        state.height = h;
        state.hasGeometry = true;
        state.geometryPriority = priority;
    }
}

void RenderQueue::queueAlphaLocked(uint32_t windowId, float alpha, RenderPriority priority, bool composed) {
    auto& state = m_queue[windowId];

    // A composed value is the COMPLETE truth for this window, so it overwrites
    // whatever is pending and keeps the strongest priority the entry has been
    // given. Two composed writes in one flush always agree - both derive from
    // the same AlphaState - and dropping the later one because it happened to
    // carry a lower priority is what would strand a cleared layer: the clearing
    // owner returns early on the next frame because the layer is already gone,
    // so nothing would ever re-queue it.
    const bool had = state.hasAlpha;
    if (!composed && had && priority < state.alphaPriority) {
        return;
    }

    state.alpha = std::clamp(alpha, 0.0f, 1.0f);
    if (!had || priority > state.alphaPriority) {
        state.alphaPriority = priority;
    }
    state.hasAlpha = true;
}

void RenderQueue::setAlpha(uint32_t windowId, float alpha, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    queueAlphaLocked(windowId, alpha, priority, false);
}

void RenderQueue::recomposeAlphaLocked(uint32_t windowId, RenderPriority priority) {
    auto it = m_alphaState.find(windowId);
    if (it == m_alphaState.end()) {
        return;
    }
    // Recomputed from source every time rather than accumulated, so repeated
    // float products cannot drift.
    queueAlphaLocked(windowId, it->second.composed(), priority, true);
}

void RenderQueue::setBaseAlpha(uint32_t windowId, float alpha, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const float v = std::clamp(alpha, 0.0f, 1.0f);
    auto it = m_alphaState.find(windowId);
    if (it == m_alphaState.end()) {
        if (v >= 1.0f) {
            return;  // neutral, and no record to make neutral
        }
        m_alphaState[windowId].base = v;
    } else {
        if (it->second.base == v) {
            return;
        }
        it->second.base = v;
    }
    recomposeAlphaLocked(windowId, priority);

    it = m_alphaState.find(windowId);
    if (it != m_alphaState.end() && it->second.isNeutral()) {
        m_alphaState.erase(it);
    }
}

float RenderQueue::baseAlpha(uint32_t windowId) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_alphaState.find(windowId);
    return (it == m_alphaState.end()) ? 1.0f : it->second.base;
}

void RenderQueue::setAlphaLayer(uint32_t windowId, const std::string& name, float factor,
                                RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const float f = std::clamp(factor, 0.0f, 1.0f);

    auto& rec = m_alphaState[windowId];
    auto layer = rec.layers.find(name);
    if (layer != rec.layers.end() && layer->second == f) {
        return;  // a settled fade re-asserts the same factor every frame
    }
    rec.layers[name] = f;

    // A layer present at 1.0 is NOT the same as no layer: its presence keeps the
    // record non-neutral, which is what stops a proximity ghost from being
    // handed back to full opaque state every time the cursor rests on it.
    recomposeAlphaLocked(windowId, priority);
}

void RenderQueue::clearAlphaLayer(uint32_t windowId, const std::string& name, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_alphaState.find(windowId);
    if (it == m_alphaState.end()) {
        return;
    }
    if (it->second.layers.erase(name) == 0) {
        return;  // already clear: safe to call every frame
    }
    recomposeAlphaLocked(windowId, priority);  // emit BEFORE pruning

    it = m_alphaState.find(windowId);
    if (it != m_alphaState.end() && it->second.isNeutral()) {
        m_alphaState.erase(it);
    }
}

void RenderQueue::resetAlphaState(uint32_t windowId, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_alphaState.erase(windowId) == 0) {
        return;
    }
    // The record is gone, so recomposeAlphaLocked would return early. Queue the
    // fully-opaque value directly.
    queueAlphaLocked(windowId, 1.0f, priority, true);
}

void RenderQueue::resetAllAlphaState(RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<uint32_t> ids;
    ids.reserve(m_alphaState.size());
    for (const auto& entry : m_alphaState) {
        ids.push_back(entry.first);
    }
    m_alphaState.clear();
    for (uint32_t id : ids) {
        queueAlphaLocked(id, 1.0f, priority, true);
    }
}

void RenderQueue::removeWindow(uint32_t windowId) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.erase(windowId);
    m_alphaState.erase(windowId);
}

void RenderQueue::flush() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_queue.empty()) {
        return;
    }
    // main.cpp does not construct a PlatformAdapter yet, so this is reachable
    // with a null adapter. Dropping the queue is the honest behaviour: there is
    // nothing to apply it to, and holding it would leak.
    if (!m_adapter) {
        m_queue.clear();
        return;
    }

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
