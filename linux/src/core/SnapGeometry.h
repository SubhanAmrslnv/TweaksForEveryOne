#pragma once

#include <vector>

namespace TweakCore {

struct Rect {
    int x, y, width, height;
};

class SnapGeometry {
public:
    SnapGeometry(int snapThreshold);
    
    // Calculates snap offsets (dx, dy) for a moving window against given edges/obstacles
    void computeSnap(const Rect& movingWindow, const std::vector<Rect>& obstacles, const Rect& workArea, int& outDx, int& outDy);

private:
    int m_snapThreshold;
};

} // namespace TweakCore
