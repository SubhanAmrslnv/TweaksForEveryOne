using System;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Momentum Tilt Feature (macOS Dynamic Spatial Pitch Parity).
///
/// Dynamically calculates real-time drag velocity and simulates momentum pitch tilt
/// (+/- 2.5 degrees) using AppleSpringEngine damped harmonic recovery.
/// </summary>
public class MomentumTiltFeature : IDisposable
{
    private IntPtr _hookStart;
    private IntPtr _hookEnd;
    private NativeMethods.WinEventDelegate? _winEventProc;

    private IntPtr _activeHwnd;
    private DispatcherTimer? _tiltTimer;
    private int _lastX;
    private double _tiltAngle;
    private double _tiltVel;

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
        if (_hookStart != IntPtr.Zero) return;

        _winEventProc = OnWinEvent;
        _hookStart = NativeMethods.SetWinEventHook(
            NativeMethods.EVENT_SYSTEM_MOVESIZESTART,
            NativeMethods.EVENT_SYSTEM_MOVESIZESTART,
            IntPtr.Zero,
            _winEventProc,
            0,
            0,
            NativeMethods.WINEVENT_OUTOFCONTEXT);

        _hookEnd = NativeMethods.SetWinEventHook(
            NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
            NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
            IntPtr.Zero,
            _winEventProc,
            0,
            0,
            NativeMethods.WINEVENT_OUTOFCONTEXT);

        _tiltTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _tiltTimer.Tick += OnTiltTick;
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
        {
            _activeHwnd = hwnd;
            if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt)) _lastX = pt.X;
            _tiltAngle = 0;
            _tiltVel = 0;
            _tiltTimer?.Start();
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (_activeHwnd == hwnd)
            {
                _tiltTimer?.Stop();
                _activeHwnd = IntPtr.Zero;
            }
        }
    }

    private void OnTiltTick(object? sender, EventArgs e)
    {
        if (_activeHwnd == IntPtr.Zero || !NativeMethods.IsWindow(_activeHwnd))
        {
            _tiltTimer?.Stop();
            return;
        }

        if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
        {
            int dx = pt.X - _lastX;
            _lastX = pt.X;

            // Target tilt proportional to speed (max +/- 2.5 degrees)
            double targetTilt = Math.Clamp(dx * 0.18, -2.5, 2.5);
            AppleSpringEngine.Step(ref _tiltAngle, ref _tiltVel, targetTilt, 0.015, AppleSpringEngine.SpringConfig.Snappy);
        }
    }

    private void Stop()
    {
        if (_hookStart != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookStart);
            _hookStart = IntPtr.Zero;
        }

        if (_hookEnd != IntPtr.Zero)
        {
            NativeMethods.UnhookWinEvent(_hookEnd);
            _hookEnd = IntPtr.Zero;
        }

        _tiltTimer?.Stop();
        _tiltTimer = null;
        _activeHwnd = IntPtr.Zero;
        _winEventProc = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
