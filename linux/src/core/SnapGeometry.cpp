#include "SnapGeometry.h"

#include <cmath>
#include <algorithm>

namespace TweakCore {

SnapGeometry::SnapGeometry(SnapParams params) : m_params(params) {}

SnapGeometry::SnapGeometry(int snapThreshold) : m_params() {
    m_params.threshold = snapThreshold;
}

void SnapGeometry::collectLines(const Rect& moving, const std::vector<Rect>& obstacles,
                                const Rect& workArea,
                                std::vector<int>& vLines, std::vector<int>& hLines) const {
    vLines.clear();
    hLines.clear();

    vLines.push_back(workArea.x);
    vLines.push_back(workArea.x + workArea.width);
    hLines.push_back(workArea.y);
    hLines.push_back(workArea.y + workArea.height);

    const int prox = m_params.neighbourProx;
    const int mL = moving.x;
    const int mT = moving.y;
    const int mR = moving.x + moving.width;
    const int mB = moving.y + moving.height;

    for (const auto& obs : obstacles) {
        const int oL = obs.x;
        const int oT = obs.y;
        const int oR = obs.x + obs.width;
        const int oB = obs.y + obs.height;
        if (oR <= oL || oB <= oT) {
            continue;
        }

        // Perpendicular-overlap gate, widened by `prox` so a window can latch
        // onto a neighbour it does not quite overlap yet.
        //
        // Without this every obstacle contributed to both axes unconditionally,
        // so a window at the top of the screen would snap to the left edge of a
        // window at the bottom that it shares no rows with. SnapCore.ahk has
        // always gated it; this side never did.
        if (mT < oB + prox && mB > oT - prox) {
            vLines.push_back(oL);
            vLines.push_back(oR);
        }
        if (mL < oR + prox && mR > oL - prox) {
            hLines.push_back(oT);
            hLines.push_back(oB);
        }
    }
}

bool SnapGeometry::snapAxis(int lo, int hi, const std::vector<int>& lines, int threshold,
                            int& outDelta, int dir) const {
    const int size = hi - lo;
    outDelta = 0;
    bool locked = false;
    // Acceptance is decided by the distance test below, so the score only orders
    // what already qualifies. Seeding this with the threshold would let the
    // directional penalty push a good candidate back out of range.
    float bestScore = 1e9f;

    for (int v : lines) {
        // BOTH window edges are tested against EVERY line, which is what gives
        // like-edge alignment (left-to-left, top-to-top) as well as the
        // adjacent-edge case. The previous implementation only ever matched a
        // window edge against the opposite obstacle edge, so two windows could
        // never be aligned flush along the same side.
        for (int edge = 0; edge < 2; ++edge) {
            const int delta = (edge == 0) ? (v - lo) : (v - size - lo);
            const int d = std::abs((edge == 0) ? (lo - v) : (hi - v));
            if (d > threshold) {
                continue;
            }

            float score = static_cast<float>(d);
            // A line that would pull the window BACKWARDS against the direction
            // it was thrown has to beat a forward candidate by a clear margin.
            if (dir != 0 && delta != 0 && ((delta > 0) != (dir > 0))) {
                score *= 1.6f;
            }
            // A line the window is already sitting on holds on to it, so nudging
            // an already-snapped window a few pixels does not let a neighbour
            // half a pixel closer steal it.
            //
            // The bonus tapers with distance (score becomes 2d - hyst inside the
            // band) rather than being flat. A flat subtraction is not monotonic:
            // with hyst 6, a line 6 px away would score 0 and beat a line 1 px
            // away scoring 1, so stickiness would pull the window to the FURTHER
            // of two nearby edges.
            if (m_params.hysteresis > 0 && d <= m_params.hysteresis) {
                score -= static_cast<float>(m_params.hysteresis - d);
            }

            if (score < bestScore) {
                bestScore = score;
                outDelta = delta;
                locked = true;
            }
        }
    }
    return locked;
}

void SnapGeometry::computeSnap(const Rect& moving, const std::vector<Rect>& obstacles,
                               const Rect& workArea, int& outDx, int& outDy,
                               float velX, float velY) const {
    outDx = 0;
    outDy = 0;

    // Reach scales with release speed: a slow, deliberate placement reaches less
    // so a window can be parked near an edge on purpose, and a hard flick reaches
    // further so momentum increases attraction. adapt == 0 reproduces the old
    // fixed reach exactly.
    const float speed = std::sqrt(velX * velX + velY * velY);
    const float ref = 900.0f;
    float reach = static_cast<float>(m_params.threshold) *
                  (1.0f + m_params.adapt * (std::min(speed, ref) / ref * 2.0f - 1.0f));
    if (reach < 1.0f) {
        reach = 1.0f;
    }
    const int threshold = static_cast<int>(reach + 0.5f);

    const int dirX = (velX > 0.0f) ? 1 : ((velX < 0.0f) ? -1 : 0);
    const int dirY = (velY > 0.0f) ? 1 : ((velY < 0.0f) ? -1 : 0);

    std::vector<int> vLines;
    std::vector<int> hLines;
    collectLines(moving, obstacles, workArea, vLines, hLines);

    const int mL = moving.x;
    const int mT = moving.y;
    const int mR = moving.x + moving.width;
    const int mB = moving.y + moving.height;

    int dx = 0, dy = 0;
    bool sx = snapAxis(mL, mR, vLines, threshold, dx, dirX);
    bool sy = snapAxis(mT, mB, hLines, threshold, dy, dirY);

    // Corner boost: once one axis has locked, retry the perpendicular one with a
    // larger reach, so a window hugging an edge drops into the corner from
    // noticeably further away than a plain edge would catch it. This is the
    // behaviour that defines the feel on Windows and it was absent here.
    if (m_params.cornerBoost > 1.0f) {
        const int boosted = static_cast<int>(threshold * m_params.cornerBoost + 0.5f);
        if (sx && !sy) {
            sy = snapAxis(mT, mB, hLines, boosted, dy, dirY);
        } else if (sy && !sx) {
            sx = snapAxis(mL, mR, vLines, boosted, dx, dirX);
        }
    }

    if (sx) {
        outDx = dx;
    }
    if (sy) {
        outDy = dy;
    }
}

} // namespace TweakCore
