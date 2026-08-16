#pragma once

#include "PlatformAdapter.h"
#include <map>
#include <memory>
#include <mutex>
#include <string>

namespace TweakCore {

// Mirrors src/RenderCore.ahk on the Windows side. Nothing outside this layer
// mutates window state; features queue desired state and one flush per frame
// applies it.
//
// Priority arbitration is PER FLUSH. Values mirror RS_PRI_* 10/20/30/40.
enum class RenderPriority {
    Ambient = 0,
    Animation = 1,
    Drag = 2,
    User = 3
};

struct QueuedState {
    bool hasGeometry = false;
    RenderPriority geometryPriority = RenderPriority::Ambient;
    int x = 0, y = 0, width = 0, height = 0;

    bool hasAlpha = false;
    RenderPriority alphaPriority = RenderPriority::Ambient;
    float alpha = 1.0f;
};

// Composed opacity for one window: a base the user chose, times any number of
// named modifier layers.
//
// Windows carries the identical model in RS_AlphaState. It exists because every
// producer used to write an ABSOLUTE opacity, so any feature that finished by
// clearing transparency silently destroyed the opacity another feature - or the
// user - had asked for. Clearing one layer here cannot touch the base or any
// other layer.
//
// ONE OWNER PER LAYER NAME. The compiler cannot enforce it; the names in use on
// both platforms are "drag", "ghost", "breathe", "depth", "open" and "gravity".
struct AlphaState {
    float base = 1.0f;
    std::map<std::string, float> layers;

    bool isNeutral() const {
        return base >= 1.0f && layers.empty();
    }

    float composed() const {
        float v = base;
        for (const auto& entry : layers) {
            v *= entry.second;
        }
        return v;
    }
};

class RenderQueue {
public:
    explicit RenderQueue(std::shared_ptr<PlatformAdapter> adapter);

    void setGeometry(uint32_t windowId, int x, int y, int w, int h, RenderPriority priority);

    // Absolute opacity. For surfaces WE own, where one owner is guaranteed by
    // construction. Use the layer API below for windows belonging to other
    // clients.
    void setAlpha(uint32_t windowId, float alpha, RenderPriority priority);

    // Composed opacity, for foreign windows.
    void setBaseAlpha(uint32_t windowId, float alpha, RenderPriority priority = RenderPriority::User);
    float baseAlpha(uint32_t windowId) const;
    void setAlphaLayer(uint32_t windowId, const std::string& name, float factor,
                       RenderPriority priority = RenderPriority::Animation);
    void clearAlphaLayer(uint32_t windowId, const std::string& name,
                         RenderPriority priority = RenderPriority::Animation);
    void resetAlphaState(uint32_t windowId, RenderPriority priority = RenderPriority::User);
    void resetAllAlphaState(RenderPriority priority = RenderPriority::User);

    // Forget everything about a window. Must be called when a window is
    // destroyed: without it a recycled id inherits a dead window's opacity.
    // This is the second of the two invariants CLAUDE.md listed as "not yet
    // expressible here".
    void removeWindow(uint32_t windowId);

    // Called by the AnimationScheduler once per frame.
    void flush();

private:
    // Derive the composed value and queue it. Only place a final opacity is
    // computed. Caller must hold m_mutex.
    void recomposeAlphaLocked(uint32_t windowId, RenderPriority priority);
    void queueAlphaLocked(uint32_t windowId, float alpha, RenderPriority priority, bool composed);

    std::shared_ptr<PlatformAdapter> m_adapter;
    std::map<uint32_t, QueuedState> m_queue;      // cleared every flush
    std::map<uint32_t, AlphaState> m_alphaState;  // persistent; pruned when neutral
    mutable std::mutex m_mutex;
};

} // namespace TweakCore
