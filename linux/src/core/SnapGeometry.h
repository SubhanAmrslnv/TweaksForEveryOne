#pragma once

#include <vector>

// Rect moved to Geometry.h so RenderQueue can use it without depending on the
// snapping module. Included rather than redeclared: two definitions of a
// geometry type is exactly the drift this tree is trying to stop.
#include "Geometry.h"

namespace TweakCore {

// Tunables for one snap resolution. Mirrors the snap rows of TUNE_SPEC on the
// Windows side; there is no config parser here yet, so a caller fills this in.
struct SnapParams {
    int threshold = 30;       // base reach in px, at an average drag speed
    float cornerBoost = 2.2f; // perpendicular axis reach multiplier once one axis locks
    int neighbourProx = 90;   // widens the overlap test toward nearby windows; 0 = edges only
    float adapt = 0.55f;      // 0 = fixed reach, 1 = strongly speed-scaled
    int hysteresis = 6;       // px an edge the window already touches wins ties by
};

// Pure geometry, no side effects. Axes resolve independently.
class SnapGeometry {
public:
    explicit SnapGeometry(SnapParams params);

    // Backwards-compatible constructor: threshold only, everything else default.
    explicit SnapGeometry(int snapThreshold);

    // Resolve a snap for `moving` against the work area and any obstacles.
    //
    // velX/velY are PIXELS PER SECOND and may be zero, in which case the reach is
    // the plain threshold and no directional bias is applied - which reproduces
    // the previous behaviour exactly.
    void computeSnap(const Rect& moving, const std::vector<Rect>& obstacles, const Rect& workArea,
                     int& outDx, int& outDy, float velX = 0.0f, float velY = 0.0f) const;

    const SnapParams& params() const { return m_params; }

private:
    // Candidate lines for one axis, gathered with the perpendicular-overlap gate.
    void collectLines(const Rect& moving, const std::vector<Rect>& obstacles, const Rect& workArea,
                      std::vector<int>& vLines, std::vector<int>& hLines) const;

    // Returns true when a line was found within `threshold`, NOT whether the
    // window had to move. Those differ for a window that is already exactly
    // flush, and conflating them breaks the corner boost in precisely the case
    // it exists for.
    bool snapAxis(int lo, int hi, const std::vector<int>& lines, int threshold,
                  int& outDelta, int dir) const;

    SnapParams m_params;
};

} // namespace TweakCore
