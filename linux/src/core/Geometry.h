#pragma once

#include <cstdint>
#include <vector>

namespace TweakCore {

// Rect lived in SnapGeometry.h, which meant anything wanting a rectangle had to
// depend on the snapping module. RenderQueue needs one for regions and z-order
// and has no business knowing snapping exists, so the type moved down here.
// Depends on nothing.
struct Rect {
    int x = 0, y = 0, width = 0, height = 0;

    int left()   const { return x; }
    int top()    const { return y; }
    int right()  const { return x + width; }
    int bottom() const { return y + height; }

    bool isEmpty() const { return width <= 0 || height <= 0; }

    bool operator==(const Rect& o) const {
        return x == o.x && y == o.y && width == o.width && height == o.height;
    }
    bool operator!=(const Rect& o) const { return !(*this == o); }
};

struct Point {
    int x = 0, y = 0;
    bool operator==(const Point& o) const { return x == o.x && y == o.y; }
    bool operator!=(const Point& o) const { return !(*this == o); }
};

// Window-relative clip.
//
// `cleared` is NOT the same as an empty rect list, and conflating them is a
// visible bug rather than a subtlety: cleared REMOVES any shape, an empty list
// hides the window entirely. Windows carries the identical distinction as ""
// versus a region string. Roll-up depends on it - clearing the region is how a
// window is un-rolled, and hiding it instead would look like the window died.
struct RegionSpec {
    bool cleared = true;
    std::vector<Rect> rects;

    bool operator==(const RegionSpec& o) const {
        return cleared == o.cleared && rects == o.rects;
    }
    bool operator!=(const RegionSpec& o) const { return !(*this == o); }
};

enum class ZOrderMode {
    Top,            // raise to the front of the normal stack
    Bottom,         // lower to the back
    AboveSibling,   // directly above `sibling`
    KeepAbove,      // always-on-top   (X11: _NET_WM_STATE_ABOVE)
    KeepBelow,      // always-on-bottom (X11: _NET_WM_STATE_BELOW)
    Normal          // clear both keep-above and keep-below
};

struct ZOrderSpec {
    ZOrderMode mode    = ZOrderMode::Top;
    uint32_t   sibling = 0;   // only meaningful for AboveSibling

    bool operator==(const ZOrderSpec& o) const {
        return mode == o.mode && sibling == o.sibling;
    }
    bool operator!=(const ZOrderSpec& o) const { return !(*this == o); }
};

// Opacity has THREE states, not two.
//
// `off` means REMOVE the opacity property entirely - on X11, DELETE
// _NET_WM_WINDOW_OPACITY rather than setting it to 0xFFFFFFFF. It is the
// analogue of Windows stripping WS_EX_LAYERED, and compositors do not treat the
// two as identical.
//
// It is emitted ONLY for a STRUCTURALLY neutral AlphaState - base 1.0 and zero
// layers - never because a product happened to round to 1.0. A layer present at
// factor 1.0 is not the same as no layer: its presence keeps the record
// non-neutral, which is what stops a proximity ghost from being handed back to
// unlayered state 60 times a second while the cursor rests on it, opaque and
// click-through in between with no visible cue.
struct AlphaCommand {
    bool  off   = false;
    float value = 1.0f;

    bool operator==(const AlphaCommand& o) const {
        return off == o.off && (off || value == o.value);
    }
    bool operator!=(const AlphaCommand& o) const { return !(*this == o); }
};

} // namespace TweakCore
