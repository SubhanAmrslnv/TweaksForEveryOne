using System;
using System.Windows.Forms;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Resistance Edge Feature (macOS Boundary Tension Parity).
///
/// Approaching display boundaries introduces non-linear cursor friction, preventing
/// accidental mouse runaways across monitor borders while letting fast intentional flicks pass freely.
/// </summary>
public class ResistanceEdgeFeature : IDisposable
{
    private const string HookOwner = "ResistanceEdgeFeature";
    private bool _hooked;
    private int _lastX, _lastY;
    private const int EdgeTensionPx = 10;
    private const int EscapeVelocityPx = 450;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle() => SetEnabled(!IsEnabled);

    private void Start()
    {
        if (_hooked) return;
        _hooked = true;
        MouseHook.Subscribe(HookOwner, MouseEvents.Move, OnMouse);
    }

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        int x = e.X;
        int y = e.Y;

        int dx = x - _lastX;
        int dy = y - _lastY;
        _lastX = x;
        _lastY = y;

        double speed = Math.Sqrt((dx * dx) + (dy * dy)) * 66.0; // Approx px/sec
        if (speed >= EscapeVelocityPx) return false; // Fast deliberate movements pass freely

        var screen = Screen.FromPoint(new System.Drawing.Point(x, y));
        var bounds = screen.Bounds;

        bool nearEdge = (x - bounds.Left < EdgeTensionPx && dx < 0) ||
                        (bounds.Right - x < EdgeTensionPx && dx > 0) ||
                        (y - bounds.Top < EdgeTensionPx && dy < 0) ||
                        (bounds.Bottom - y < EdgeTensionPx && dy > 0);

        if (nearEdge && (dx != 0 || dy != 0))
        {
            // Apply 60% resistance pull-back
            int resistX = x - (int)(dx * 0.60);
            int resistY = y - (int)(dy * 0.60);
            NativeMethods.SetCursorPos(resistX, resistY);
            return true; // Dampen input
        }

        return false;
    }

    private void Stop()
    {
        if (_hooked)
        {
            MouseHook.Unsubscribe(HookOwner);
            _hooked = false;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
