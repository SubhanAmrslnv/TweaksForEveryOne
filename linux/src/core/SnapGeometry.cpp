#include "SnapGeometry.h"
#include <cmath>
#include <algorithm>

namespace TweakCore {

SnapGeometry::SnapGeometry(int snapThreshold) : m_snapThreshold(snapThreshold) {}

void SnapGeometry::computeSnap(const Rect& moving, const std::vector<Rect>& obstacles, const Rect& workArea, int& outDx, int& outDy) {
    outDx = 0;
    outDy = 0;

    int minDx = m_snapThreshold + 1;
    int minDy = m_snapThreshold + 1;

    // 1. Check WorkArea (Screen Edges)
    if (std::abs(moving.x - workArea.x) < std::abs(minDx)) minDx = workArea.x - moving.x;
    if (std::abs((moving.x + moving.width) - (workArea.x + workArea.width)) < std::abs(minDx)) 
        minDx = (workArea.x + workArea.width) - (moving.x + moving.width);

    if (std::abs(moving.y - workArea.y) < std::abs(minDy)) minDy = workArea.y - moving.y;
    if (std::abs((moving.y + moving.height) - (workArea.y + workArea.height)) < std::abs(minDy)) 
        minDy = (workArea.y + workArea.height) - (moving.y + moving.height);

    // 2. Check Obstacles (Window-to-Window Snapping)
    for (const auto& obs : obstacles) {
        // Vertical edges
        if (std::abs((moving.x + moving.width) - obs.x) < std::abs(minDx)) minDx = obs.x - (moving.x + moving.width);
        if (std::abs(moving.x - (obs.x + obs.width)) < std::abs(minDx)) minDx = (obs.x + obs.width) - moving.x;
        
        // Horizontal edges
        if (std::abs((moving.y + moving.height) - obs.y) < std::abs(minDy)) minDy = obs.y - (moving.y + moving.height);
        if (std::abs(moving.y - (obs.y + obs.height)) < std::abs(minDy)) minDy = (obs.y + obs.height) - moving.y;
    }

    if (std::abs(minDx) <= m_snapThreshold) outDx = minDx;
    if (std::abs(minDy) <= m_snapThreshold) outDy = minDy;
}

} // namespace TweakCore
