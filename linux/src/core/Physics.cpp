#include "Physics.h"

namespace TweakCore {

void Physics::calculateGlide(int startX, int startY, float velX, float velY, int& outX, int& outY) {
    // Basic kinetic friction model: d = v^2 / (2 * a)
    // Tweak properties would be read from configuration in reality
    const float friction = 500.0f; // px/s^2
    
    // Calculate distance
    float dist = (velX*velX + velY*velY) / (2.0f * friction);
    
    // Normalise velocity vector and multiply by distance
    float speed = std::sqrt(velX*velX + velY*velY);
    if (speed > 0.01f) {
        outX = startX + static_cast<int>((velX / speed) * dist);
        outY = startY + static_cast<int>((velY / speed) * dist);
    } else {
        outX = startX;
        outY = startY;
    }
}

} // namespace TweakCore
