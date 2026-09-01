using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Parallax dragging: a window fades while it is being thrown around and comes back to solid when
/// it stops. Opacity-only, which is the effect family this project actually wants.
///
/// THE RAMP IS CALIBRATED BY ITS ENDPOINTS, NOT BY A GAIN. The original version of this effect
/// elsewhere was written as `alpha = 255 - speed * 0.06`, which left an ordinary 400 px/s drag at
/// 88% opacity - doing exactly what it said and still indistinguishable from switched off. Here
/// both ends are named and settable: nothing happens below FromSpeed, and MinOpacity is reached at
/// FullSpeed. "Invisible at a normal drag speed" is then a number a user can see and change,
/// rather than a constant buried on a hot path.
///
/// Opacity goes through AlphaCompositor as the "drag" layer, so it multiplies with whatever the
/// user set by hand instead of overwriting it.
/// </summary>
public class DragParallaxFeature : IDisposable
{
    private IntPtr _hookStartEnd = IntPtr.Zero;
    private IntPtr _hookLocation = IntPtr.Zero;

    private readonly NativeMethods.WinEventDelegate _procStartEnd;
    private readonly NativeMethods.WinEventDelegate _procLocation;

    private readonly VelocitySampler _sampler = new();
    private IntPtr _dragHwnd = IntPtr.Zero;

    public bool IsEnabled { get; private set; }

    // Captured when the drag STARTS, not per frame. EVENT_OBJECT_LOCATIONCHANGE fires around sixty
    // times a second while a window is moving, and reading three settings there meant three lock
    // acquisitions and three string parses per frame on the one path that has to stay cheap. The
    // values therefore apply from the next drag, which is indistinguishable in use.
    private int _fromSpeed;
    private int _fullSpeed;
    private double _minFactor;

    public DragParallaxFeature()
    {
        _procStartEnd = WinEventProcStartEnd;
        _procLocation = WinEventProcLocation;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            _hookStartEnd = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_SYSTEM_MOVESIZESTART,
                NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
                IntPtr.Zero, _procStartEnd, 0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);

            _hookLocation = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                IntPtr.Zero, _procLocation, 0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
        }
        else
        {
            Unhook();
            EndDrag();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void WinEventProcStartEnd(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        try
        {
            if (idObject != 0 || idChild != 0) return;

            if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
            {
                if (!NativeMethods.IsWindow(hwnd)) return;

                _fromSpeed = TuningRegistry.Int(TuningRegistry.ParallaxFromSpeed);
                _fullSpeed = TuningRegistry.Int(TuningRegistry.ParallaxFullSpeed);
                _minFactor = TuningRegistry.Fraction(TuningRegistry.ParallaxMinOpacity);

                _dragHwnd = hwnd;
                if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r))
                    _sampler.Reset(r.Left, r.Top);
            }
            else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
            {
                if (hwnd == _dragHwnd) EndDrag();
            }
        }
        catch
        {
            // A hook callback must never throw - it would pop a dialog at the user and kill the
            // handler for the rest of the session.
        }
    }

    private void WinEventProcLocation(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        try
        {
            if (idObject != 0 || idChild != 0) return;
            if (_dragHwnd == IntPtr.Zero || hwnd != _dragHwnd) return;

            if (!NativeMethods.IsWindow(hwnd))
            {
                // Window died mid-drag. Nothing to restore, and holding the hwnd would leak a
                // record for a handle Windows can hand to somebody else.
                AlphaCompositor.Forget(_dragHwnd);
                _dragHwnd = IntPtr.Zero;
                return;
            }

            if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r)) return;

            _sampler.Sample(r.Left, r.Top);
            AlphaCompositor.SetLayer(hwnd, AlphaCompositor.LayerDrag, FactorForSpeed(_sampler.Speed));

        }
        catch
        {
        }
    }

    /// <summary>1.0 at or below the start speed, the minimum at or above the full speed, linear between.</summary>
    private double FactorForSpeed(double speed)
    {
        int from = _fromSpeed;
        int full = _fullSpeed;
        double min = _minFactor;

        if (full <= from) return speed > from ? min : 1.0;
        if (speed <= from) return 1.0;
        if (speed >= full) return min;

        double t = (speed - from) / (full - from);
        return 1.0 - t * (1.0 - min);
    }

    private void EndDrag()
    {
        IntPtr hwnd = _dragHwnd;
        _dragHwnd = IntPtr.Zero;
        if (hwnd != IntPtr.Zero) AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerDrag);
    }

    private void Unhook()
    {
        if (_hookStartEnd != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookStartEnd);
            _hookStartEnd = IntPtr.Zero;
        }
        if (_hookLocation != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookLocation);
            _hookLocation = IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        Unhook();
        EndDrag();
        IsEnabled = false;
    }
}
