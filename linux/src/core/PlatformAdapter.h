#pragma once

#include <cstdint>
#include <string>

namespace TweakCore {

struct WindowState {
    uint32_t windowId;
    int x, y, width, height;
    float alpha;
    bool isVisible;
    bool isMinimized;
    bool isMaximized;
    bool alwaysOnTop;
    bool alwaysOnBottom;
};

// Abstract interface for Platform Adapters (X11, Wayland/DBus)
class PlatformAdapter {
public:
    virtual ~PlatformAdapter() = default;

    // Initialization and event loop integration
    virtual void init() = 0;
    virtual void pollEvents() = 0;

    // Window Management
    virtual void setWindowGeometry(uint32_t windowId, int x, int y, int width, int height) = 0;
    virtual void setWindowAlpha(uint32_t windowId, float alpha) = 0;
    virtual void setWindowState(uint32_t windowId, bool alwaysOnTop, bool alwaysOnBottom, bool shaded) = 0;
    
    // Batching support (e.g., DeferWindowPos equivalent)
    virtual void beginBatch() = 0;
    virtual void commitBatch() = 0;

    // Global queries
    virtual WindowState getWindowState(uint32_t windowId) = 0;
    virtual uint32_t getActiveWindow() = 0;
};

} // namespace TweakCore
