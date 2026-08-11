#pragma once

namespace TweakCore {

class Physics {
public:
    static float quinticEaseOut(float t) {
        return 1.0f - (--t) * t * t * t * t;
    }
    
    // Calculates the final resting position of a window thrown with given velocity
    static void calculateGlide(int startX, int startY, float velX, float velY, int& outX, int& outY);
};

} // namespace TweakCore
