#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "Geometry.h"

namespace TweakCore {

struct WindowState {
    uint32_t windowId = 0;
    int x = 0, y = 0, width = 0, height = 0;
    float alpha = 1.0f;
    bool isVisible = false;
    bool isMinimized = false;
    bool isMaximized = false;
    bool alwaysOnTop = false;
    bool alwaysOnBottom = false;
};

// What a backend can actually do.
//
// A backend declares this rather than failing silently, because on Wayland a
// great many of these are not merely unimplemented but forbidden: a normal
// client cannot move another window, set its opacity, read the global pointer or
// warp it. WAYLAND-LIMITATIONS.md commits this project to documenting such a
// feature as unsupported rather than reaching for LD_PRELOAD, /dev/input as
// root, or the accessibility APIs. A capability enum is how that commitment
// becomes something the code can honour instead of only the docs.
enum class Capability {
    SetGeometry,
    SetAlpha,
    SetRegion,      // roll-up / shade clipping
    SetZOrder,
    ListWindows,    // obstacle collection for snapping
    ReadPointer,    // hot corners, proximity ghost
    WarpPointer,    // infinite cursor wrap
    GrabHotkeys,
    WindowEvents,   // created / destroyed / focus / move-resize
    Monitors
};

// Abstract interface for platform adapters (X11 today; a D-Bus-backed Wayland
// adapter next).
//
// EVERY MUTATOR RETURNS bool. That is not defensiveness - RenderQueue records a
// value in its last-applied cache only when the call actually landed. Recording
// unconditionally poisons the cache: the next identical write is then diffed
// away as redundant, and the feature silently never works on that window again.
// Windows hit exactly this on elevated windows, where WinSetTransparent fails,
// and it disabled parallax, breathing and the ghost for that window for the rest
// of the session with nothing logged. The Linux equivalents are a window that
// dies between queue and flush, and a compositor that refuses the request.
class PlatformAdapter {
public:
    virtual ~PlatformAdapter() = default;

    virtual bool supports(Capability c) const = 0;

    // Lifecycle
    virtual bool init() = 0;
    virtual void pollEvents() = 0;
    virtual void shutdown() = 0;

    // Window mutation - the only caller is RenderQueue.
    virtual bool setWindowGeometry(uint32_t windowId, int x, int y, int width, int height) = 0;
    virtual bool setWindowAlpha(uint32_t windowId, float alpha) = 0;
    // Remove the opacity property outright. See AlphaCommand in Geometry.h for
    // why this is a distinct operation and not setWindowAlpha(1.0f).
    virtual bool clearWindowAlpha(uint32_t windowId) = 0;
    virtual bool setWindowRegion(uint32_t windowId, const RegionSpec& region) = 0;
    virtual bool setWindowZOrder(uint32_t windowId, const ZOrderSpec& z) = 0;
    virtual bool setWindowState(uint32_t windowId, bool alwaysOnTop, bool alwaysOnBottom,
                                bool shaded) = 0;

    // Batching (the DeferWindowPos equivalent).
    virtual void beginBatch() = 0;
    virtual void commitBatch() = 0;

    // Queries
    virtual bool isWindowAlive(uint32_t windowId) const = 0;
    virtual WindowState getWindowState(uint32_t windowId) const = 0;
    virtual uint32_t getActiveWindow() const = 0;
    // Every top-level window, front to back. This is what finally gives
    // SnapGeometry::computeSnap its obstacle vector - the single largest missing
    // input in the audit, and the reason snapping is unreachable today.
    virtual std::vector<uint32_t> listWindows() const = 0;
    // Stable per-application identity for position memory. X11: WM_CLASS.
    // Wayland: the extension reports desktop-app-id, since WM_CLASS is not
    // universal there.
    virtual std::string windowAppId(uint32_t windowId) const = 0;

    // Monitors. Full rects and work areas are separate: a panel that auto-hides
    // changes the work area with no monitor-change event, so a cached work area
    // is stale exactly when it matters. Cache the monitor rects; read the work
    // area live.
    virtual std::vector<Rect> monitors() const = 0;
    virtual Rect workArea(int monitorIndex) const = 0;

    // Pointer
    virtual Point pointerPosition() const = 0;
    virtual bool  warpPointer(int x, int y) = 0;
};

} // namespace TweakCore
