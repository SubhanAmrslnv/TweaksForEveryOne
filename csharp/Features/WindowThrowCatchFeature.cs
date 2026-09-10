using System;
using System.Threading.Tasks;
using System.Windows.Forms;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Window Throw & Catch Feature (macOS Ballistic Multi-Monitor Throw Parity).
///
/// Flinging a window toward a secondary monitor preserves its ballistic inertia,
/// projecting and landing it smoothly on the adjacent display using AppleSpringEngine.
/// </summary>
public class WindowThrowCatchFeature : IDisposable
{
    private IntPtr _hookStart;
    private IntPtr _hookEnd;
    private NativeMethods.WinEventDelegate? _winEventProc;

    private readonly VelocitySampler _velocity = new();
    private IntPtr _activeHwnd;

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
    }

    private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(hwnd)) return;

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
        {
            _activeHwnd = hwnd;
            if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
            {
                _velocity.Reset(pt.X, pt.Y);
            }
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (_activeHwnd == hwnd)
            {
                if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
                {
                    _velocity.Sample(pt.X, pt.Y);
                    if (_velocity.Speed >= 800.0) // Ballistic throw threshold
                    {
                        _ = GlideThrowAsync(hwnd, _velocity.VelocityX, _velocity.VelocityY);
                    }
                }
                _activeHwnd = IntPtr.Zero;
            }
        }
    }

    private async Task GlideThrowAsync(IntPtr hwnd, double vx, double vy)
    {
        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect)) return;

        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;

        // Project throw landing offset based on velocity
        double targetX = rect.Left + Math.Clamp(vx * 0.25, -600.0, 600.0);
        double targetY = rect.Top + Math.Clamp(vy * 0.25, -400.0, 400.0);

        double curX = rect.Left;
        double curY = rect.Top;
        double currentVx = vx;
        double currentVy = vy;

        for (int frame = 0; frame < 15; frame++)
        {
            if (!NativeMethods.IsWindow(hwnd)) break;

            AppleSpringEngine.Step(ref curX, ref currentVx, targetX, 0.015, AppleSpringEngine.SpringConfig.Gentle);
            AppleSpringEngine.Step(ref curY, ref currentVy, targetY, 0.015, AppleSpringEngine.SpringConfig.Gentle);

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, (int)curX, (int)curY, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            await Task.Delay(15);
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

        _activeHwnd = IntPtr.Zero;
        _winEventProc = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
