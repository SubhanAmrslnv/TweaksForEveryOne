#pragma once

namespace TweakCore {

// Drag-release velocity, and the opacity ramp that rides on it.
//
// Mirrors SampleVelocityStep() and ParallaxAlpha() in the Windows
// src/DragPipeline.ahk. Nothing here touches a window; it converts a stream of
// positions into a speed and a target opacity, and the caller decides what to do
// with them. Physics::predictThrow() has had no caller since it was written
// because nothing captured a release velocity - this is that missing half.
//
// VELOCITY IS PIXELS PER SECOND, and every downstream constant on both platforms
// is calibrated in that unit: the throw gain, the monitor-throw and tilt
// thresholds, the parallax ramp, the magnetic-group break. On Windows this
// function was handed dt and ignored it, smoothing the raw per-frame
// displacement instead, so all of those were silently calibrated to one frame
// duration and the same hand motion reported up to 3x the velocity once frames
// got heavy. Do not reintroduce a per-frame delta here.
class VelocitySampler {
public:
    // Time constants, in milliseconds, NOT per-frame blend ratios.
    //
    // tau = 30 reproduces the old 0.4 per-frame blend exactly at the nominal
    // frame and holds that response when frames get heavy; tau = 45 does the
    // same for the 0.7/0.3 opacity blend. A ratio would make the smoothing
    // frame-rate dependent again, which is the whole defect being fixed.
    static constexpr float kVelocityTauMs = 30.0f;
    static constexpr float kAlphaTauMs    = 45.0f;

    // Start (or restart) sampling from this position. Velocity is zeroed and the
    // smoothed alpha is seeded fully opaque.
    void begin(int x, int y);

    // Feed one frame. dt is elapsed MILLISECONDS since the last sample; a
    // non-positive dt is treated as one nominal frame rather than dividing by
    // zero. Returns the smoothed speed in px/s.
    float sample(int x, int y, float dt, float nominalFrameMs = 16.0f);

    float velX() const { return m_velX; }
    float velY() const { return m_velY; }
    float speed() const;

    // The raw, unsmoothed displacement of the last sample, in pixels. Magnetic
    // groups tow their members by this rather than by the smoothed velocity.
    int lastDeltaX() const { return m_lastDx; }
    int lastDeltaY() const { return m_lastDy; }

    // Advance the smoothed drag opacity toward `target` (0..1) and return it.
    // Kept here rather than in the caller so both drag paths - title-bar drag and
    // alt-drag - share one ramp. On Windows the gain was written out longhand in
    // each of them, which is how they had drifted apart.
    float smoothAlpha(float target, float dt, float nominalFrameMs = 16.0f);
    float currentAlpha() const { return m_alpha; }

    // 1 - exp(-dt/tau): the fraction of the way to the target one step of length
    // dt should travel for a first-order lag with this time constant.
    static float emaFactor(float dt, float tauMs);

private:
    int   m_prevX = 0, m_prevY = 0;
    int   m_lastDx = 0, m_lastDy = 0;
    float m_velX = 0.0f, m_velY = 0.0f;
    float m_alpha = 1.0f;
    bool  m_started = false;
};

} // namespace TweakCore
