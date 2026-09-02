using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class InfiniteWrapFeature : IDisposable
{
    private bool _enabled = false;
    private CancellationTokenSource? _cts;

    private const int TOLERANCE = 2; // px band that counts as the edge
    private const int DELAY_MS = 250; // Hold time ms against the edge
    private const int SPEED_MIN = 250; // Approach speed px/s minimum
    private const int COOLDOWN_MS = 700; // ms before it can wrap again

    public bool IsEnabled => _enabled;

    /// <summary>
    /// IDEMPOTENT: FeatureRegistry calls Apply with the state it wants, not with an instruction to
    /// flip. See MagneticSnappingFeature.SetEnabled.
    /// </summary>
    public void SetEnabled(bool enabled)
    {
        if (enabled == _enabled) return;
        _enabled = enabled;

        if (_enabled)
        {
            _cts = new CancellationTokenSource();
            _ = RunMonitorLoop(_cts.Token);
        }
        else
        {
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
        }
    }

    public void Toggle() => SetEnabled(!_enabled);

    private async Task RunMonitorLoop(CancellationToken token)
    {
        int lastX = 0, lastY = 0;
        long lastAt = 0;
        long contactAt = 0;
        int contactSide = 0;
        bool approachOk = false;
        long cooldownUntil = 0;

        while (!token.IsCancellationRequested)
        {
            await Task.Delay(20, token).ConfigureAwait(false);
            if (token.IsCancellationRequested) break;

            long now = Environment.TickCount64;
            NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
            int mx = pt.X;
            int my = pt.Y;

            int prevX = lastX, prevY = lastY;
            long prevAt = lastAt;
            lastX = mx; lastY = my; lastAt = now;

            // Check mouse buttons - no wrapping while dragging
            bool lButton = (NativeMethods.GetAsyncKeyState(0x01) & 0x8000) != 0;
            bool rButton = (NativeMethods.GetAsyncKeyState(0x02) & 0x8000) != 0;
            bool mButton = (NativeMethods.GetAsyncKeyState(0x04) & 0x8000) != 0;
            if (lButton || rButton || mButton)
            {
                contactSide = 0;
                continue;
            }

            var monitors = new List<NativeMethods.RECT>();
            NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                (IntPtr hMonitor, IntPtr hdcMonitor, ref NativeMethods.RECT lprcMonitor, IntPtr dwData) =>
                {
                    monitors.Add(lprcMonitor);
                    return true;
                }, IntPtr.Zero);

            if (monitors.Count == 0) continue;

            // Compute global bounds
            int gLeft = int.MaxValue;
            int gRight = int.MinValue;
            foreach (var m in monitors)
            {
                if (m.Left < gLeft) gLeft = m.Left;
                if (m.Right > gRight) gRight = m.Right;
            }

            int side = 0;
            if (mx <= gLeft + TOLERANCE)
                side = -1;
            else if (mx >= gRight - 1 - TOLERANCE)
                side = 1;

            if (side == 0)
            {
                contactSide = 0;
                continue;
            }

            if (now < cooldownUntil)
                continue;

            if (side != contactSide)
            {
                // First tick of contact
                contactSide = side;
                contactAt = now;
                approachOk = SPEED_MIN <= 0;
                if (!approachOk && prevAt > 0 && now > prevAt)
                {
                    double dist = Math.Sqrt(Math.Pow(mx - prevX, 2) + Math.Pow(my - prevY, 2));
                    double speed = dist * 1000.0 / (now - prevAt);
                    approachOk = speed >= SPEED_MIN;
                }
                continue;
            }

            if (!approachOk) continue;
            if (now - contactAt < DELAY_MS) continue;

            // Teleport
            int inset = TOLERANCE + 8;
            int tx = (side < 0) ? (gRight - 1 - inset) : (gLeft + inset);
            int ty = my;

            // Project onto nearest monitor that spans tx
            bool inside = false;
            foreach (var m in monitors)
            {
                if (tx >= m.Left && tx < m.Right && ty >= m.Top && ty < m.Bottom)
                {
                    inside = true;
                    break;
                }
            }

            if (!inside)
            {
                int bestDy = int.MaxValue;
                int? bestY = null;
                int edgePad = 5;

                foreach (var m in monitors)
                {
                    if (tx < m.Left || tx >= m.Right) continue;

                    int dy = 0;
                    int projY = ty;

                    if (ty < m.Top)
                    {
                        dy = m.Top - ty;
                        projY = m.Top + edgePad;
                    }
                    else if (ty >= m.Bottom)
                    {
                        dy = ty - m.Bottom + 1;
                        projY = m.Bottom - 1 - edgePad;
                    }

                    if (bestY == null || dy < bestDy)
                    {
                        bestDy = dy;
                        bestY = projY;
                    }
                }

                if (bestY == null)
                {
                    contactSide = 0;
                    continue; // No surface on that side at this height
                }
                ty = bestY.Value;
            }

            NativeMethods.SetCursorPos(tx, ty);
            cooldownUntil = now + COOLDOWN_MS;
            contactSide = 0;
            lastX = tx;
            lastY = ty;
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
