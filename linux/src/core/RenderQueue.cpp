#include "RenderQueue.h"

#include <algorithm>
#include <optional>
#include <vector>

namespace TweakCore {

RenderQueue::RenderQueue(std::shared_ptr<PlatformAdapter> adapter)
    : m_adapter(std::move(adapter)) {}

// ----- geometry ---------------------------------------------------------------

void RenderQueue::setGeometry(uint32_t windowId, int x, int y, int w, int h,
                              RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    auto& state = m_queue[windowId];

    if (!state.hasGeometry || priority >= state.geometryPriority) {
        state.x = x;
        state.y = y;
        state.width = w;
        state.height = h;
        state.hasGeometry = true;
        state.geometryPriority = priority;
    }
}

// ----- region -----------------------------------------------------------------

void RenderQueue::setRegion(uint32_t windowId, RegionSpec region, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    auto& state = m_queue[windowId];
    if (!state.hasRegion || priority >= state.regionPriority) {
        state.region = std::move(region);
        state.hasRegion = true;
        state.regionPriority = priority;
    }
}

void RenderQueue::clearRegion(uint32_t windowId, RenderPriority priority) {
    setRegion(windowId, RegionSpec{}, priority);   // default-constructed == cleared
}

// ----- z-order ----------------------------------------------------------------

void RenderQueue::setZOrder(uint32_t windowId, ZOrderSpec z, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    auto& state = m_queue[windowId];
    if (!state.hasZOrder || priority >= state.zOrderPriority) {
        state.zOrder = z;
        state.hasZOrder = true;
        state.zOrderPriority = priority;
    }
}

// ----- alpha ------------------------------------------------------------------

void RenderQueue::queueAlphaLocked(uint32_t windowId, AlphaCommand cmd, RenderPriority priority,
                                   bool composed) {
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

    if (!cmd.off) {
        cmd.value = std::clamp(cmd.value, 0.0f, 1.0f);
    }
    state.alpha = cmd;
    if (!had || priority > state.alphaPriority) {
        state.alphaPriority = priority;
    }
    state.hasAlpha = true;
}

void RenderQueue::setAlpha(uint32_t windowId, float alpha, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    queueAlphaLocked(windowId, AlphaCommand{false, alpha}, priority, false);
}

void RenderQueue::setAlphaOff(uint32_t windowId, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    queueAlphaLocked(windowId, AlphaCommand{true, 1.0f}, priority, false);
}

void RenderQueue::recomposeAlphaLocked(uint32_t windowId, RenderPriority priority) {
    auto it = m_alphaState.find(windowId);
    if (it == m_alphaState.end()) {
        return;
    }

    // The neutral case emits "off", NOT 1.0.
    //
    // This used to queue composed(), which for a neutral record is 1.0 - fully
    // opaque but still layered. That is not the same thing, and the difference
    // is visible: on X11 it leaves _NET_WM_WINDOW_OPACITY set to 0xFFFFFFFF
    // rather than deleting the property, which keeps the window on the
    // compositor slow path and, on some compositors, keeps it from ever being
    // treated as fully opaque again. Windows has emitted 256 ("Off", strip
    // WS_EX_LAYERED) here from the start.
    //
    // The test is STRUCTURAL - base 1.0 and zero layers - never numeric. A
    // record whose layers happen to multiply out to 1.0 stays layered on
    // purpose; see AlphaCommand in Geometry.h for what depends on that.
    AlphaCommand cmd;
    if (it->second.isNeutral()) {
        cmd.off = true;
    } else {
        // Recomputed from source every time rather than accumulated, so repeated
        // float products cannot drift.
        cmd.value = std::clamp(it->second.composed(), 0.0f, 1.0f);
    }
    queueAlphaLocked(windowId, cmd, priority, true);
}

void RenderQueue::setBaseAlpha(uint32_t windowId, float alpha, RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
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
    recomposeAlphaLocked(windowId, priority);   // emit BEFORE pruning

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
    if (m_shutdown.load()) {
        return;
    }
    const float f = std::clamp(factor, 0.0f, 1.0f);

    auto& rec = m_alphaState[windowId];
    auto layer = rec.layers.find(name);
    if (layer != rec.layers.end() && layer->second == f) {
        return;  // a settled fade re-asserts the same factor every frame
    }
    rec.layers[name] = f;

    // A layer present at 1.0 is NOT the same as no layer: its presence keeps the
    // record non-neutral, which is what stops a proximity ghost from being
    // handed back to unlayered state every time the cursor rests on it.
    recomposeAlphaLocked(windowId, priority);
}

void RenderQueue::clearAlphaLayer(uint32_t windowId, const std::string& name,
                                  RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
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
    if (m_shutdown.load()) {
        return;
    }
    if (m_alphaState.erase(windowId) == 0) {
        return;
    }
    // The record is gone, so recomposeAlphaLocked would return early. Queue the
    // structurally-neutral command directly.
    queueAlphaLocked(windowId, AlphaCommand{true, 1.0f}, priority, true);
}

void RenderQueue::resetAllAlphaState(RenderPriority priority) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown.load()) {
        return;
    }
    std::vector<uint32_t> ids;
    ids.reserve(m_alphaState.size());
    for (const auto& entry : m_alphaState) {
        ids.push_back(entry.first);
    }
    m_alphaState.clear();
    for (uint32_t id : ids) {
        queueAlphaLocked(id, AlphaCommand{true, 1.0f}, priority, true);
    }
}

float RenderQueue::currentAlpha(uint32_t windowId, float defaultValue) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto pending = m_queue.find(windowId);
    if (pending != m_queue.end() && pending->second.hasAlpha) {
        return pending->second.alpha.off ? 1.0f : pending->second.alpha.value;
    }
    auto applied = m_lastAlpha.find(windowId);
    if (applied != m_lastAlpha.end()) {
        return applied->second.off ? 1.0f : applied->second.value;
    }
    return defaultValue;
}

// ----- bookkeeping ------------------------------------------------------------

void RenderQueue::removeWindow(uint32_t windowId) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.erase(windowId);
    m_alphaState.erase(windowId);
    m_lastAlpha.erase(windowId);
    m_lastRegion.erase(windowId);
}

void RenderQueue::sweepDead() {
    if (!m_adapter) {
        return;
    }

    // Collect the candidate ids first, then ask the adapter with no lock held,
    // then erase under the lock. Three passes rather than one because the
    // adapter call must not happen inside the mutex - the same rule applyOnce()
    // follows, for the same reason.
    std::vector<uint32_t> ids;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        for (const auto& e : m_lastAlpha) {
            ids.push_back(e.first);
        }
        for (const auto& e : m_lastRegion) {
            ids.push_back(e.first);
        }
        for (const auto& e : m_alphaState) {
            ids.push_back(e.first);
        }
    }
    std::sort(ids.begin(), ids.end());
    ids.erase(std::unique(ids.begin(), ids.end()), ids.end());

    std::vector<uint32_t> dead;
    for (uint32_t id : ids) {
        if (!m_adapter->isWindowAlive(id)) {
            dead.push_back(id);
        }
    }
    if (dead.empty()) {
        return;
    }
    std::lock_guard<std::mutex> lock(m_mutex);
    for (uint32_t id : dead) {
        m_queue.erase(id);
        m_alphaState.erase(id);
        m_lastAlpha.erase(id);
        m_lastRegion.erase(id);
    }
}

void RenderQueue::shutdown() {
    m_shutdown.store(true);
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.clear();
    m_alphaState.clear();
    m_lastAlpha.clear();
    m_lastRegion.clear();
}

RenderQueue::FlushStats RenderQueue::stats() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_stats;
}

// ----- apply ------------------------------------------------------------------

bool RenderQueue::applyOnce() {
    // Swap the pending map out for an empty one BEFORE reading it, then release
    // the lock before touching the adapter.
    //
    // Two problems solved at once. First, a producer that interrupts this pass
    // writes into the fresh map and is picked up next pass, instead of being
    // lost or corrupting the walk. Second - and this is the change from the
    // original - the adapter is no longer called with m_mutex held: a backend
    // that blocks on the X server or the session bus used to stall every
    // producer in the process behind it, including the frame loop.
    std::map<uint32_t, QueuedState> pending;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_queue.empty()) {
            return false;
        }
        pending.swap(m_queue);
    }

    // main.cpp does not construct a PlatformAdapter yet, so this is reachable
    // with a null adapter. Dropping the queue is the honest behaviour: there is
    // nothing to apply it to, and holding it would leak.
    if (!m_adapter) {
        return true;
    }

    m_adapter->beginBatch();

    for (const auto& [winId, state] : pending) {
        if (state.hasGeometry) {
            const bool ok =
                m_adapter->setWindowGeometry(winId, state.x, state.y, state.width, state.height);
            std::lock_guard<std::mutex> lock(m_mutex);
            ++m_stats.adapterCalls;
            if (!ok) {
                ++m_stats.failed;
            }
        }

        if (state.hasAlpha) {
            std::optional<AlphaCommand> last;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                auto it = m_lastAlpha.find(winId);
                if (it != m_lastAlpha.end()) {
                    last = it->second;
                }
            }
            if (last && *last == state.alpha) {
                std::lock_guard<std::mutex> lock(m_mutex);
                ++m_stats.suppressed;
            } else {
                const bool ok = state.alpha.off
                                    ? m_adapter->clearWindowAlpha(winId)
                                    : m_adapter->setWindowAlpha(winId, state.alpha.value);
                std::lock_guard<std::mutex> lock(m_mutex);
                ++m_stats.adapterCalls;
                // Record ONLY when the call actually landed.
                //
                // Recording unconditionally poisons the cache: every later
                // identical write is then diffed away as redundant, and the
                // feature silently never works on that window again. Windows hit
                // this on elevated windows, where WinSetTransparent fails, and it
                // disabled parallax, breathing and the ghost for that window for
                // the rest of the session with nothing logged anywhere.
                if (ok) {
                    m_lastAlpha[winId] = state.alpha;
                } else {
                    ++m_stats.failed;
                }
            }
        }

        if (state.hasRegion) {
            std::optional<RegionSpec> last;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                auto it = m_lastRegion.find(winId);
                if (it != m_lastRegion.end()) {
                    last = it->second;
                }
            }
            if (last && *last == state.region) {
                std::lock_guard<std::mutex> lock(m_mutex);
                ++m_stats.suppressed;
            } else {
                const bool ok = m_adapter->setWindowRegion(winId, state.region);
                std::lock_guard<std::mutex> lock(m_mutex);
                ++m_stats.adapterCalls;
                if (ok) {
                    m_lastRegion[winId] = state.region;
                } else {
                    ++m_stats.failed;
                }
            }
        }

        if (state.hasZOrder) {
            const bool ok = m_adapter->setWindowZOrder(winId, state.zOrder);
            std::lock_guard<std::mutex> lock(m_mutex);
            ++m_stats.adapterCalls;
            if (!ok) {
                ++m_stats.failed;
            }
        }
    }

    m_adapter->commitBatch();
    return true;
}

void RenderQueue::flush() {
    if (m_shutdown.load()) {
        return;
    }

    bool expected = false;
    if (!m_flushBusy.compare_exchange_strong(expected, true)) {
        // Someone is already flushing. Ask them to run one more pass and return.
        // Blocking here would deadlock a one-shot producer that commits from
        // inside the frame loop against the loop it is running on.
        m_flushAgain.store(true);
        std::lock_guard<std::mutex> lock(m_mutex);
        ++m_stats.reentries;
        return;
    }

    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < kMaxPasses; ++i) {   // bounded: never spin on a pathological producer
        m_flushAgain.store(false);
        applyOnce();
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            ++m_stats.passes;
        }
        if (!m_flushAgain.load()) {
            break;
        }
    }
    const auto elapsed =
        std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - start).count();

    bool sweep = false;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        ++m_stats.flushes;
        m_stats.lastFlushMs = elapsed;
        m_stats.maxFlushMs = std::max(m_stats.maxFlushMs, elapsed);
        if (++m_sinceSweep >= kSweepInterval) {
            m_sinceSweep = 0;
            sweep = true;
        }
    }
    if (sweep) {
        sweepDead();
    }

    m_flushBusy.store(false);
}

void RenderQueue::commit() {
    flush();
}

} // namespace TweakCore
