#include "X11Adapter.h"

#include <iostream>

namespace TweakPlatform {

using TweakCore::Capability;
using TweakCore::Point;
using TweakCore::Rect;
using TweakCore::RegionSpec;
using TweakCore::WindowState;
using TweakCore::ZOrderSpec;

X11Adapter::X11Adapter() = default;

X11Adapter::~X11Adapter() {
    shutdown();
}

// Nothing is implemented, so nothing is claimed.
//
// This is the whole point of the capability query: a feature that asks first
// gets a truthful no and can say so to the user, instead of queueing state into
// a backend that silently drops it. When a method below lands, its capability
// flips here in the same commit - that pairing is the rule.
bool X11Adapter::supports(Capability) const {
    return false;
}

bool X11Adapter::init() {
    std::cerr << "X11Adapter: not implemented - no window management is available.\n";
    // m_connection = xcb_connect(nullptr, nullptr);
    return false;
}

void X11Adapter::pollEvents() {
    if (!m_connection) {
        return;
    }
    // MUST be xcb_poll_for_event, not xcb_wait_for_event.
    //
    // The original sketch here used xcb_wait_for_event in a while loop, which
    // blocks until an event arrives. On a quiet desktop that is forever, and
    // this method is called from a loop that also has to service timers - the
    // same class of mistake as a blocking WaitForResponse() on the Windows
    // side, where it froze every timer in the process.
}

void X11Adapter::shutdown() {
    if (!m_connection) {
        return;
    }
    // xcb_disconnect(static_cast<xcb_connection_t*>(m_connection));
    m_connection = nullptr;
}

bool X11Adapter::setWindowGeometry(uint32_t, int, int, int, int) {
    return false;
}

bool X11Adapter::setWindowAlpha(uint32_t, float) {
    return false;
}

bool X11Adapter::clearWindowAlpha(uint32_t) {
    return false;
}

bool X11Adapter::setWindowRegion(uint32_t, const RegionSpec&) {
    return false;
}

bool X11Adapter::setWindowZOrder(uint32_t, const ZOrderSpec&) {
    return false;
}

bool X11Adapter::setWindowState(uint32_t, bool, bool, bool) {
    return false;
}

void X11Adapter::beginBatch() {}

void X11Adapter::commitBatch() {
    // xcb_flush(static_cast<xcb_connection_t*>(m_connection));
}

bool X11Adapter::isWindowAlive(uint32_t) const {
    // False, not true. A sweep that believes every window is alive never
    // reclaims anything, and the maps it exists to bound grow for the session;
    // reporting dead is the safe direction, because the only consequence is that
    // state is forgotten a little early on a backend that cannot apply it anyway.
    return false;
}

WindowState X11Adapter::getWindowState(uint32_t windowId) const {
    // A default-constructed state, NOT the hardcoded 800x600 this used to
    // return. A plausible-looking fake rect is worse than an empty one: it feeds
    // the snapping maths real-looking numbers and produces confident nonsense.
    WindowState s;
    s.windowId = windowId;
    return s;
}

uint32_t X11Adapter::getActiveWindow() const {
    return 0;
}

std::vector<uint32_t> X11Adapter::listWindows() const {
    return {};
}

std::string X11Adapter::windowAppId(uint32_t) const {
    return {};
}

std::vector<Rect> X11Adapter::monitors() const {
    return {};
}

Rect X11Adapter::workArea(int) const {
    return {};
}

Point X11Adapter::pointerPosition() const {
    return {};
}

bool X11Adapter::warpPointer(int, int) {
    return false;
}

} // namespace TweakPlatform
