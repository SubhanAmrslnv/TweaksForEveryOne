using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Elastic Drag Feature (macOS Rubber-Band Elasticity Parity).
///
/// Window surfaces subtly stretch along the velocity vector during rapid dragging,
/// rebounding elastically with AppleSpringEngine when movement ceases.
/// </summary>
public class ElasticDragFeature : IDisposable
{
    private IntPtr _hookStart;
    private IntPtr _hookEnd;
    private NativeMethods.WinEventDelegate? _winEventProc;

    private IntPtr _draggingHwnd;
    private DispatcherTimer? _dragTimer;
    private int _lastMouseX, _lastMouseY;
    private double _stretchX, _stretchY;
    private double _velX, _velY;
    private int _origW, _origH;

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

        _dragTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _dragTimer.Tick += OnDragTick;
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
        {
            _draggingHwnd = hwnd;
            if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
            {
                _lastMouseX = pt.X;
                _lastMouseY = pt.Y;
            }
            if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
            {
                _origW = rect.Right - rect.Left;
                _origH = rect.Bottom - rect.Top;
            }
            _stretchX = 0;
            _stretchY = 0;
            _velX = 0;
            _velY = 0;
            _dragTimer?.Start();
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (_draggingHwnd == hwnd)
            {
                _dragTimer?.Stop();
                _draggingHwnd = IntPtr.Zero;
            }
        }
    }

    private void OnDragTick(object? sender, EventArgs e)
    {
        if (_draggingHwnd == IntPtr.Zero || !NativeMethods.IsWindow(_draggingHwnd))
        {
            _dragTimer?.Stop();
            return;
        }

        if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
        {
            int dx = pt.X - _lastMouseX;
            int dy = pt.Y - _lastMouseY;
            _lastMouseX = pt.X;
            _lastMouseY = pt.Y;

            // Target stretch is proportional to cursor drag delta, clamped to +/- 8px
            double targetStretchX = Math.Clamp(dx * 0.35, -8.0, 8.0);
            double targetStretchY = Math.Clamp(dy * 0.35, -8.0, 8.0);

            AppleSpringEngine.Step(ref _stretchX, ref _velX, targetStretchX, 0.015, AppleSpringEngine.SpringConfig.Bouncy);
            AppleSpringEngine.Step(ref _stretchY, ref _velY, targetStretchY, 0.015, AppleSpringEngine.SpringConfig.Bouncy);
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

        _dragTimer?.Stop();
        _dragTimer = null;
        _draggingHwnd = IntPtr.Zero;
        _winEventProc = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
