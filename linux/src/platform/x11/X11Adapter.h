#pragma once

#include "core/PlatformAdapter.h"

namespace TweakPlatform {

// Native XCB backend. The only PlatformAdapter implementation today, and the one
// target that needs no compositor cooperation - which is why Linux Mint /
// Cinnamon is the environment to prove every feature against first.
//
// STATUS: not implemented. Every mutator returns false and every query returns
// an empty or default value, HONESTLY - supports() reports nothing as available,
// so a feature that consults it degrades instead of appearing to work. The
// previous version of this file returned a hardcoded 800x600 window rect from
// getWindowState(), which is worse than failing: it looks like a working query.
//
// The intended implementation, method by method, is recorded against each
// override so the XCB research does not have to be redone:
//
//   listWindows      _NET_CLIENT_LIST_STACKING (falls back to _NET_CLIENT_LIST)
//   getWindowState   xcb_get_geometry + _NET_WM_STATE + _NET_FRAME_EXTENTS
//   windowAppId      WM_CLASS via xcb_icccm_get_wm_class
//   setWindowGeometry xcb_configure_window, X/Y/WIDTH/HEIGHT
//   setWindowAlpha   _NET_WM_WINDOW_OPACITY, a CARDINAL of alpha * 0xFFFFFFFF
//   clearWindowAlpha xcb_delete_property on the same atom - NOT a write of
//                    0xFFFFFFFF; see AlphaCommand in core/Geometry.h
//   setWindowRegion  xcb_shape_rectangles on ShapeBounding; cleared == ShapeMask
//                    with an empty pixmap
//   setWindowZOrder  _NET_WM_STATE_ABOVE / _NET_WM_STATE_BELOW via a client
//                    message, or xcb_configure_window with STACK_MODE
//   isWindowAlive    xcb_get_window_attributes, checked for BadWindow
//   monitors         xcb_randr_get_monitors
//   workArea         _NET_WORKAREA, refined per monitor from each panel's
//                    _NET_WM_STRUT_PARTIAL - _NET_WORKAREA is one rect for the
//                    whole desktop, so it is not enough on multi-monitor
//   pointerPosition  xcb_query_pointer
//   warpPointer      xcb_warp_pointer (or XTest, if the WM ignores warps)
//   pollEvents       xcb_poll_for_event - NOT xcb_wait_for_event, which blocks
//   hotkeys          xcb_grab_key. EVERY global hotkey is Shift+Alt+<key>; the
//                    Ctrl+Alt tier a comment here used to name was removed from
//                    the Windows side in 3dadac4 and does not exist
class X11Adapter : public TweakCore::PlatformAdapter {
public:
    X11Adapter();
    ~X11Adapter() override;

    bool supports(TweakCore::Capability c) const override;

    bool init() override;
    void pollEvents() override;
    void shutdown() override;

    bool setWindowGeometry(uint32_t windowId, int x, int y, int width, int height) override;
    bool setWindowAlpha(uint32_t windowId, float alpha) override;
    bool clearWindowAlpha(uint32_t windowId) override;
    bool setWindowRegion(uint32_t windowId, const TweakCore::RegionSpec& region) override;
    bool setWindowZOrder(uint32_t windowId, const TweakCore::ZOrderSpec& z) override;
    bool setWindowState(uint32_t windowId, bool alwaysOnTop, bool alwaysOnBottom,
                        bool shaded) override;

    void beginBatch() override;
    void commitBatch() override;

    bool isWindowAlive(uint32_t windowId) const override;
    TweakCore::WindowState getWindowState(uint32_t windowId) const override;
    uint32_t getActiveWindow() const override;
    std::vector<uint32_t> listWindows() const override;
    std::string windowAppId(uint32_t windowId) const override;

    std::vector<TweakCore::Rect> monitors() const override;
    TweakCore::Rect workArea(int monitorIndex) const override;

    TweakCore::Point pointerPosition() const override;
    bool warpPointer(int x, int y) override;

private:
    // Deliberately void*, so this header does not drag <xcb/xcb.h> into every
    // translation unit that merely wants to construct the backend. It is null
    // until init() succeeds, and every method above checks it.
    void* m_connection = nullptr;
};

} // namespace TweakPlatform
