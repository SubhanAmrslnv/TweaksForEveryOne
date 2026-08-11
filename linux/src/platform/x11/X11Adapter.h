#pragma once

#include "core/PlatformAdapter.h"

namespace TweakPlatform {

class X11Adapter : public TweakCore::PlatformAdapter {
public:
    X11Adapter();
    ~X11Adapter() override;

    void init() override;
    void pollEvents() override;

    void setWindowGeometry(uint32_t windowId, int x, int y, int width, int height) override;
    void setWindowAlpha(uint32_t windowId, float alpha) override;
    void setWindowState(uint32_t windowId, bool alwaysOnTop, bool alwaysOnBottom, bool shaded) override;
    
    void beginBatch() override;
    void commitBatch() override;

    TweakCore::WindowState getWindowState(uint32_t windowId) override;
    uint32_t getActiveWindow() override;

private:
    void setupGlobalHotkeys();
    // internal XCB connection pointer
    void* m_connection;
};

} // namespace TweakPlatform
