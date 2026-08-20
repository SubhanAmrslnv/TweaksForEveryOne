#pragma once

#include "Geometry.h"
#include "PlatformAdapter.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>

namespace TweakCore {

// Mirrors src/RenderCore.ahk on the Windows side. Nothing outside this layer
// mutates window state; features queue desired state and one flush per frame
// applies it.
//
// Priority arbitration is PER FLUSH. Values mirror RS_PRI_* 10/20/30/40 - the
// ordering is what matters, not the numbers, since only comparisons are made.
enum class RenderPriority {
    Ambient = 0,    // breathing, ghost proximity
    Animation = 1,  // glide, bounce, pulse, fade, slide-in
    Drag = 2,       // drag parallax, alt-drag, grab-pan
    User = 3        // the opacity wheel, an explicit move
};

// The outstanding work for one window. Emptied by every flush, so presence means
// "queued and not yet applied" - never read it as a description of the window.
//
// EACH ATTRIBUTE CARRIES ITS OWN PRIORITY. Geometry and alpha used to share one
// field and only setAlpha guarded it, so an Ambient geometry write after a User
// alpha write downgraded the stored priority and let a later Ambient alpha write
// beat the User one. Windows keeps four independent maps for exactly this
// reason; four priority fields in one entry buys the same isolation with one
// lookup and one erase in removeWindow().
struct QueuedState {
    bool hasGeometry = false;
    RenderPriority geometryPriority = RenderPriority::Ambient;
    int x = 0, y = 0, width = 0, height = 0;

    bool hasAlpha = false;
    RenderPriority alphaPriority = RenderPriority::Ambient;
    AlphaCommand alpha{};

    bool hasRegion = false;
    RenderPriority regionPriority = RenderPriority::Ambient;
    RegionSpec region{};

    bool hasZOrder = false;
    RenderPriority zOrderPriority = RenderPriority::Ambient;
    ZOrderSpec zOrder{};
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
// Two owners of one name reproduce the oscillation bug this replaced, inside a
// single layer, where it is harder to see.
struct AlphaState {
    float base = 1.0f;
    std::map<std::string, float> layers;

    // STRUCTURAL, not numeric, and that distinction is load-bearing - see
    // AlphaCommand in Geometry.h.
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

    void setRegion(uint32_t windowId, RegionSpec region,
                   RenderPriority priority = RenderPriority::Animation);
    void clearRegion(uint32_t windowId, RenderPriority priority = RenderPriority::Animation);

    // Never diffed against a last-applied cache: the stacking order changes
    // under us constantly - the user clicks a window, the WM raises it - so a
    // cache would be wrong more often than right. Same reason geometry is not
    // cached either.
    void setZOrder(uint32_t windowId, ZOrderSpec z,
                   RenderPriority priority = RenderPriority::Animation);

    // Absolute opacity. For surfaces WE own, where one owner is guaranteed by
    // construction. Use the layer API below for windows belonging to other
    // clients.
    void setAlpha(uint32_t windowId, float alpha, RenderPriority priority);
    void setAlphaOff(uint32_t windowId, RenderPriority priority);

    // Composed opacity, for foreign windows.
    void setBaseAlpha(uint32_t windowId, float alpha,
                      RenderPriority priority = RenderPriority::User);
    float baseAlpha(uint32_t windowId) const;
    void setAlphaLayer(uint32_t windowId, const std::string& name, float factor,
                       RenderPriority priority = RenderPriority::Animation);
    void clearAlphaLayer(uint32_t windowId, const std::string& name,
                         RenderPriority priority = RenderPriority::Animation);
    void resetAlphaState(uint32_t windowId, RenderPriority priority = RenderPriority::User);
    void resetAllAlphaState(RenderPriority priority = RenderPriority::User);

    // What opacity does this window actually have right now?
    //
    // A pending write wins over the last applied one, because that is what the
    // next flush will produce. Lets a reversed fade - an OSD revived mid-hide -
    // start from where the window is instead of jumping. "off" reports as 1.0.
    float currentAlpha(uint32_t windowId, float defaultValue = 1.0f) const;

    // Forget everything about a window. Must be called when a window is
    // destroyed: without it a recycled id inherits the opacity of a dead one.
    void removeWindow(uint32_t windowId);

    // Backstop for windows nobody told us about. Called from flush() every
    // kSweepInterval flushes, and safe to call directly.
    void sweepDead();

    // Called by the AnimationScheduler once per frame, unconditionally.
    void flush();

    // Called by a ONE-SHOT producer - a hotkey, a polling monitor, anything that
    // queues and returns. Same body as flush().
    //
    // This is not a convenience alias. The scheduler parks when nothing is
    // animating, so a queued change with nobody to flush it is simply never
    // applied. On Windows that silently killed snapping-without-glide, the
    // transparency wheel, breathing restore and un-ghosting, and left brand-new
    // windows sitting at alpha 0 - invisible, focused and clickable.
    void commit();

    // Teardown. Drops every map and makes any later flush a no-op, so a timer
    // that outlives teardown cannot re-apply state that shutdown has just undone.
    void shutdown();

    struct FlushStats {
        uint64_t flushes      = 0;
        uint64_t passes       = 0;   // apply passes, including re-entrant repeats
        uint64_t adapterCalls = 0;
        uint64_t suppressed   = 0;   // writes the last-applied cache skipped
        uint64_t failed       = 0;   // adapter calls that returned false
        uint64_t reentries    = 0;
        float    lastFlushMs  = 0.0f;
        float    maxFlushMs   = 0.0f;
    };
    FlushStats stats() const;

private:
    // One pass over the pending map. Returns true if it had anything to do.
    bool applyOnce();

    // Derive the composed value and queue it. The only place a final opacity is
    // computed. Caller must hold m_mutex.
    void recomposeAlphaLocked(uint32_t windowId, RenderPriority priority);
    void queueAlphaLocked(uint32_t windowId, AlphaCommand cmd, RenderPriority priority,
                          bool composed);

    std::shared_ptr<PlatformAdapter> m_adapter;
    std::map<uint32_t, QueuedState> m_queue;      // cleared every flush
    std::map<uint32_t, AlphaState> m_alphaState;  // persistent; pruned when neutral

    // Last value actually applied, so a redundant write can be skipped. Only the
    // two attributes this pipeline owns outright are cached: re-applying them is
    // individually expensive, and nothing else changes them behind our back.
    //
    // Geometry is deliberately NOT cached. A cache is only valid when the cache
    // owns the state, and the user dragging a title bar moves a window without
    // telling us - caching last-requested positions made a second snap to the
    // same edge a silent no-op on Windows.
    std::map<uint32_t, AlphaCommand> m_lastAlpha;
    std::map<uint32_t, RegionSpec> m_lastRegion;

    mutable std::mutex m_mutex;

    // Re-entrancy guard, NOT a lock. A nested flush asks the outer one to run
    // another pass and returns; blocking here would deadlock a producer that
    // commits from inside the frame loop against the loop it is running on.
    std::atomic<bool> m_flushBusy{false};
    std::atomic<bool> m_flushAgain{false};
    std::atomic<bool> m_shutdown{false};

    unsigned m_sinceSweep = 0;
    FlushStats m_stats;

    static constexpr unsigned kSweepInterval = 600;  // ~10 s of continuous animation
    static constexpr int kMaxPasses = 4;             // never spin on a pathological producer
};

} // namespace TweakCore
