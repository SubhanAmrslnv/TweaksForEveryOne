using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Cursor Yawn &amp; Breathe: makes an idle cursor subtly breathe when left untouched.
///
/// Supersedes the legacy halo overlay implementation:
/// 1. Purely subtle cursor scaling via CursorMotionModel (Priority 4).
/// 2. Strictly enforces Priority Hierarchy:
///    - Priority 1: Click interaction (independent overlay event)
///    - Priority 2: Active mouse movement (velocity scaling overrides breathing instantly)
///    - Priority 3: Dragging operations (suppress breathing; preserve Parallax Dragging)
///    - Priority 4: Idle breathing (active only when cursor has been completely stationary)
/// 3. Zero visual distortion, rings, or halos; purely smooth, low-frequency sine scaling between 1.00x and 1.02-1.03x.
/// 4. Instant preemption with zero input latency upon any mouse movement.
/// </summary>
public class CursorYawnBreatheFeature : IDisposable
{
    public bool IsEnabled => CursorMotionModel.Instance.IsBreathingEnabled && CursorMotionModel.Instance.IsEnabled;

    public CursorMotionState CurrentState => CursorMotionModel.Instance.CurrentState;
    public double CurrentScale => CursorMotionModel.Instance.CurrentScale;

    public CursorYawnBreatheFeature()
    {
    }

    public void SetEnabled(bool enabled)
    {
        CursorMotionModel.Instance.SetBreathingEnabled(enabled);
        if (enabled)
        {
            CursorMotionModel.Instance.SetEnabled(true);
            CursorOverlayRenderer.Instance.SetEnabled(true);
        }
        else
        {
            CursorOverlayRenderer.Instance.SetEnabled(false);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    public void Dispose()
    {
        SetEnabled(false);
    }
}
