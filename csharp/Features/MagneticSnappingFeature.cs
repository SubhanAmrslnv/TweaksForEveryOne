using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class MagneticSnappingFeature : IDisposable
{
    private bool _isEnabled = false;
    private IntPtr _hookStartEnd = IntPtr.Zero;
    private IntPtr _hookLocation = IntPtr.Zero;
    private NativeMethods.WinEventDelegate _procStartEnd;
    private NativeMethods.WinEventDelegate _procLocation;
    
    // These four were consts. They are settings now (see TuningRegistry), read ONCE per drop into
    // locals in SnapWindow - never inside the window enumeration or the per-line loops, which run
    // for every candidate edge on screen.

    /// <summary>
    /// How long to wait after the drag ends before deciding whether to snap. See SnapAfterSettle -
    /// this is what stops the feature fighting Windows' own Aero Snap.
    /// </summary>
    private const int SettleMs = 45;

    private IntPtr _dragHwnd = IntPtr.Zero;
    private int _lastX = 0;
    private int _lastY = 0;

    /// <summary>The size the window had when the drag STARTED. A change means Windows resized it.</summary>
    private int _startW = 0;
    private int _startH = 0;

    private long _lastTime = 0;
    private double _velX = 0;
    private double _velY = 0;

    public bool IsEnabled => _isEnabled;

    public MagneticSnappingFeature()
    {
        _procStartEnd = new NativeMethods.WinEventDelegate(WinEventProcStartEnd);
        _procLocation = new NativeMethods.WinEventDelegate(WinEventProcLocation);
    }

    /// <summary>
    /// IDEMPOTENT. FeatureRegistry calls a feature's Apply with the state it WANTS, so this takes a
    /// state rather than flipping one - an Apply that flips only stays correct while the feature and
    /// the registry never disagree, and Game Mode is exactly the case where they do.
    /// </summary>
    public void SetEnabled(bool enabled)
    {
        if (enabled == _isEnabled) return;
        _isEnabled = enabled;

        if (_isEnabled)
        {
            _hookStartEnd = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_SYSTEM_MOVESIZESTART,
                NativeMethods.EVENT_SYSTEM_MOVESIZEEND,
                IntPtr.Zero,
                _procStartEnd,
                0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
                
            _hookLocation = NativeMethods.SetWinEventHook(
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                NativeMethods.EVENT_OBJECT_LOCATIONCHANGE,
                IntPtr.Zero,
                _procLocation,
                0, 0,
                NativeMethods.WINEVENT_OUTOFCONTEXT);
        }
        else
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
            _dragHwnd = IntPtr.Zero;
        }
    }

    public void Toggle() => SetEnabled(!_isEnabled);

    private void WinEventProcStartEnd(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || idChild != 0) return;

        if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZESTART)
        {
            _dragHwnd = hwnd;
            _velX = 0;
            _velY = 0;
            if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r))
            {
                _lastX = r.Left;
                _lastY = r.Top;
                _startW = r.Right - r.Left;
                _startH = r.Bottom - r.Top;
            }
            _lastTime = Stopwatch.GetTimestamp();
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (hwnd != _dragHwnd) return;

            _dragHwnd = IntPtr.Zero;

            // Copied out before the await: the fields belong to the next drag from here on.
            _ = SnapAfterSettle(hwnd, _velX, _velY, _startW, _startH);
        }
    }

    /// <summary>
    /// WHY THERE IS A DELAY HERE, AND WHY IT IS THE FIX FOR "the window ends up in the middle of the
    /// screen when I use Windows' own snap".
    ///
    /// Dragging a window to a screen edge triggers Windows' own Aero Snap, which RESIZES the window
    /// to half or a quarter of the work area. That resize is not always finished when
    /// EVENT_SYSTEM_MOVESIZEEND arrives, so reading the rectangle immediately can still show the
    /// pre-snap size - after which this feature computed a magnetic snap from the old geometry and
    /// glided the window there. The result was a window that Windows had just snapped to the left
    /// half sitting somewhere in the middle at its original size, which is exactly the report.
    ///
    /// A short settle - well under the time it takes to let go of a mouse and look at the screen -
    /// makes the check reliable, and then <see cref="WasArrangedByWindows"/> hands the gesture over.
    /// CLAUDE.md already recorded the principle: Windows' own snap wins at screen edges, by design,
    /// and this feature is judged on window-to-window magnetism.
    /// </summary>
    private async System.Threading.Tasks.Task SnapAfterSettle(IntPtr hwnd, double vX, double vY, int startW, int startH)
    {
        try
        {
            await System.Threading.Tasks.Task.Delay(SettleMs);

            if (!NativeMethods.IsWindow(hwnd)) return;
            if (WasArrangedByWindows(hwnd, startW, startH)) return;

            SnapWindow(hwnd, vX, vY);
        }
        catch
        {
            // A window can close between the release and the settle. Never let that surface.
        }
    }

    /// <summary>
    /// True when Windows has taken charge of this window's geometry, in which case this feature must
    /// keep its hands off it: the size changed during the drag (Aero Snap to a half or a quarter), or
    /// the window is now maximised (dragged to the top edge).
    /// </summary>
    private static bool WasArrangedByWindows(IntPtr hwnd, int startW, int startH)
    {
        if (NativeMethods.IsIconic(hwnd)) return true;

        NativeMethods.WINDOWPLACEMENT placement = new();
        placement.length = Marshal.SizeOf(typeof(NativeMethods.WINDOWPLACEMENT));

        if (NativeMethods.GetWindowPlacement(hwnd, ref placement)
            && placement.showCmd == NativeMethods.SW_SHOWMAXIMIZED)
        {
            return true;
        }

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r)) return true;

        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;

        // A couple of pixels of tolerance: a window that reflows its own layout on a move can report
        // a rectangle a pixel different without anything having snapped it.
        return Math.Abs(w - startW) > 2 || Math.Abs(h - startH) > 2;
    }

    private void WinEventProcLocation(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != 0 || idChild != 0) return;
        if (hwnd != _dragHwnd || _dragHwnd == IntPtr.Zero) return;

        if (NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r))
        {
            long now = Stopwatch.GetTimestamp();
            double dtMs = (now - _lastTime) / (double)Stopwatch.Frequency * 1000.0;
            if (dtMs > 0)
            {
                double vx = (r.Left - _lastX) / dtMs * 1000.0; // px/sec
                double vy = (r.Top - _lastY) / dtMs * 1000.0; // px/sec

                // Low pass filter
                double k = 1 - Math.Exp(-dtMs / 30.0);
                _velX = _velX + (vx - _velX) * k;
                _velY = _velY + (vy - _velY) * k;

                _lastX = r.Left;
                _lastY = r.Top;
                _lastTime = now;
            }
        }
    }

    private void SnapWindow(IntPtr hwnd, double vX, double vY)
    {
        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT winRect))
            return;

        int baseSnapDistance = TuningRegistry.Int(TuningRegistry.SnapDistance);
        double cornerBoost = TuningRegistry.Fraction(TuningRegistry.SnapCornerBoost);
        int neighbourProx = TuningRegistry.Int(TuningRegistry.SnapNeighbourProximity);
        int hyst = TuningRegistry.Int(TuningRegistry.SnapHysteresis);

        // Get the visual frame bounds (without invisible DWM shadow borders)
        if (NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT frameRect, Marshal.SizeOf(typeof(NativeMethods.RECT))) != 0)
        {
            frameRect = winRect;
        }

        int frameW = frameRect.Right - frameRect.Left;
        int frameH = frameRect.Bottom - frameRect.Top;

        int pL = frameRect.Left;
        int pT = frameRect.Top;
        int pR = frameRect.Right;
        int pB = frameRect.Bottom;

        List<int> vLines = new List<int>();
        List<int> hLines = new List<int>();

        // 1. Get Monitor Edges
        IntPtr hMonitor = NativeMethods.MonitorFromWindow(hwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (hMonitor != IntPtr.Zero)
        {
            NativeMethods.MONITORINFO monitorInfo = new NativeMethods.MONITORINFO();
            monitorInfo.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
            if (NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo))
            {
                vLines.Add(monitorInfo.rcWork.Left);
                vLines.Add(monitorInfo.rcWork.Right);
                hLines.Add(monitorInfo.rcWork.Top);
                hLines.Add(monitorInfo.rcWork.Bottom);
            }
        }

        // 2. Get Other Windows Edges
        // Environment.ProcessId rather than Process.GetCurrentProcess().Id: the latter allocates a
        // Process object, and this runs on every drop.
        uint ownPid = (uint)Environment.ProcessId;
        NativeMethods.EnumWindows((IntPtr otherHwnd, IntPtr lParam) =>
        {
            if (otherHwnd != hwnd && NativeMethods.IsWindowVisible(otherHwnd))
            {
                NativeMethods.GetWindowThreadProcessId(otherHwnd, out uint pid);
                if (pid == ownPid) return true;

                StringBuilder sb = new StringBuilder(256);
                NativeMethods.GetClassName(otherHwnd, sb, sb.Capacity);
                string cls = sb.ToString();
                if (cls != "Shell_TrayWnd" && cls != "Progman" && cls != "WorkerW")
                {
                    if (NativeMethods.DwmGetWindowAttribute(otherHwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT oFrame, Marshal.SizeOf(typeof(NativeMethods.RECT))) == 0)
                    {
                        if (pT < oFrame.Bottom + neighbourProx && pB > oFrame.Top - neighbourProx)
                        {
                            vLines.Add(oFrame.Left);
                            vLines.Add(oFrame.Right);
                        }
                        if (pL < oFrame.Right + neighbourProx && pR > oFrame.Left - neighbourProx)
                        {
                            hLines.Add(oFrame.Top);
                            hLines.Add(oFrame.Bottom);
                        }
                    }
                }
            }
            return true;
        }, IntPtr.Zero);

        // Calculate Crash/Overshoot
        int tx = (int)Math.Clamp(Math.Round(vX * 0.9 * 0.18), -500, 500); // GLIDE_THROW = 0.9, GLIDE_MAX = 500
        int ty = (int)Math.Clamp(Math.Round(vY * 0.9 * 0.18), -500, 500);

        pL = frameRect.Left + tx;
        pT = frameRect.Top + ty;
        pR = frameRect.Right + tx;
        pB = frameRect.Bottom + ty;

        // Ensure projected rect stays on monitor (basic clamp)
        if (hMonitor != IntPtr.Zero)
        {
            NativeMethods.MONITORINFO monitorInfo = new NativeMethods.MONITORINFO();
            monitorInfo.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
            if (NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo))
            {
                int maxW = monitorInfo.rcWork.Right - monitorInfo.rcWork.Left;
                int maxH = monitorInfo.rcWork.Bottom - monitorInfo.rcWork.Top;
                int w = Math.Min(pR - pL, maxW);
                int h = Math.Min(pB - pT, maxH);
                pL = Math.Clamp(pL, monitorInfo.rcWork.Left, monitorInfo.rcWork.Right - w);
                pT = Math.Clamp(pT, monitorInfo.rcWork.Top, monitorInfo.rcWork.Bottom - h);
                pR = pL + w;
                pB = pT + h;
            }
        }

        double spd = Math.Sqrt(vX * vX + vY * vY);
        double adapt = 0.55;
        double reachD = baseSnapDistance * (1 + adapt * (Math.Min(spd, 900) / 900.0 * 2 - 1));
        int reach = (int)Math.Max(1, Math.Round(reachD));

        int dirX = (vX > 0) ? 1 : ((vX < 0) ? -1 : 0);
        int dirY = (vY > 0) ? 1 : ((vY < 0) ? -1 : 0);

        // 3. Compute Closest Snap
        int newL, newT;
        bool snapped = ComputeSnap(pL, pT, pR, pB, vLines, hLines, reach, out newL, out newT, cornerBoost, dirX, dirY, hyst);

        if (!snapped)
        {
            newL = pL;
            newT = pT;
        }

        int crashX = 0, crashY = 0;
        if (Math.Abs(vX) > 100 && tx != 0 && Math.Abs(newL - frameRect.Left) < Math.Abs(tx))
            crashX = tx - (newL - frameRect.Left);
        if (Math.Abs(vY) > 100 && ty != 0 && Math.Abs(newT - frameRect.Top) < Math.Abs(ty))
            crashY = ty - (newT - frameRect.Top);

        // 4. Move if needed (Glide)
        if (newL != frameRect.Left || newT != frameRect.Top)
        {
            int offsetX = winRect.Left - frameRect.Left;
            int offsetY = winRect.Top - frameRect.Top;

            int finalX = newL + offsetX;
            int finalY = newT + offsetY;

            GlideTo(hwnd, winRect.Left, winRect.Top, finalX, finalY, crashX, crashY);
        }
    }

    /// <summary>
    /// Moves the window to the snap target over a quintic ease-out.
    ///
    /// EVERY CALL IS MOVE-ONLY - SWP_NOSIZE, and no width or height is passed in at all. The glide
    /// used to re-apply the size captured before the animation started, which meant that if anything
    /// resized the window while the glide was running - Windows' own snap, the application reflowing
    /// itself, the user hitting a layout hotkey - the glide silently put the old size back on its
    /// next frame. A magnetic snap has no business changing a window's size.
    /// </summary>
    private async void GlideTo(IntPtr hwnd, int fromX, int fromY, int toX, int toY, int crashX, int crashY)
    {
        double dx = toX - fromX;
        double dy = toY - fromY;
        double dist = Math.Sqrt(dx * dx + dy * dy);

        if (dist < 2)
        {
            Move(hwnd, toX, toY);
            return;
        }

        double GLIDE_MS = 650.0;
        double ms = Math.Max(140.0, Math.Min(GLIDE_MS, 140.0 + dist * 0.9));
        
        int settle = 15; // default glideSettle tune
        double ox = 0, oy = 0;
        if (settle > 0)
        {
            if (crashX != 0) ox = Math.Clamp(crashX * 0.35, -settle, settle);
            if (crashY != 0) oy = Math.Clamp(crashY * 0.35, -settle, settle);
        }

        Stopwatch sw = Stopwatch.StartNew();

        // The last position actually applied, so a frame that would not move a single pixel is
        // skipped. SetWindowPos on a real window costs about 260 microseconds and forces the target
        // application to re-layout, so the cheapest frame is the one that is never sent.
        int lastAppliedX = int.MinValue;
        int lastAppliedY = int.MinValue;

        while (true)
        {
            // Parameterised on ELAPSED TIME, not on a frame count: a fixed step per frame makes the
            // duration depend on how heavy the frames turn out to be.
            double t = sw.Elapsed.TotalMilliseconds / ms;
            if (t >= 1.0) break;

            // The window can be closed, minimised or snapped by Windows while the glide runs.
            if (!NativeMethods.IsWindow(hwnd)) return;

            double e = 1 - Math.Pow(1 - t, 5);
            double o = 9.4815 * t * Math.Pow(1 - t, 3);

            int nx = (int)Math.Round(fromX + dx * e + ox * o);
            int ny = (int)Math.Round(fromY + dy * e + oy * o);

            if (nx != lastAppliedX || ny != lastAppliedY)
            {
                Move(hwnd, nx, ny);
                lastAppliedX = nx;
                lastAppliedY = ny;
            }

            // 15 ms rather than 16: Windows' clock tick is about 15.6 ms, so a 16 ms deadline always
            // lands just past a tick and waits for the next one. Measured over 100 idle frames, 16
            // gave a 25.15 ms mean with 7.59 ms of jitter; 15 gave 15.92 ms with 0.37 ms.
            await System.Threading.Tasks.Task.Delay(15);
        }

        if (NativeMethods.IsWindow(hwnd)) Move(hwnd, toX, toY);
    }

    private static void Move(IntPtr hwnd, int x, int y)
    {
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0,
            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
    }

    private bool ComputeSnap(int L, int T, int R, int B, List<int> vLines, List<int> hLines, int threshold, out int newL, out int newT, double cornerBoost, int dirX, int dirY, int hyst)
    {
        bool sx = SnapAxis(L, R, vLines, threshold, out newL, dirX, hyst);
        bool sy = SnapAxis(T, B, hLines, threshold, out newT, dirY, hyst);

        if (cornerBoost > 1.0)
        {
            int boosted = (int)Math.Round(threshold * cornerBoost);
            if (sx && !sy)
                sy = SnapAxis(T, B, hLines, boosted, out newT, dirY, hyst);
            else if (sy && !sx)
                sx = SnapAxis(L, R, vLines, boosted, out newL, dirX, hyst);
        }
        return sx || sy;
    }

    private bool SnapAxis(int lo, int hi, List<int> lines, int threshold, out int newLo, int dir, int hyst)
    {
        int size = hi - lo;
        newLo = lo;
        double bestScore = 999999;
        bool locked = false;

        foreach (int v in lines)
        {
            for (int i = 0; i < 2; i++)
            {
                int d, cand, moving;
                if (i == 0) // Leading
                {
                    d = Math.Abs(lo - v);
                    cand = v;
                    moving = v - lo;
                }
                else // Trailing
                {
                    d = Math.Abs(hi - v);
                    cand = v - size;
                    moving = v - hi;
                }

                if (d > threshold) continue;

                double score = d;

                if (dir != 0 && moving != 0 && ((moving > 0) != (dir > 0)))
                    score *= 1.6;

                if (hyst > 0 && d <= hyst)
                    score -= (hyst - d);

                if (score < bestScore)
                {
                    bestScore = score;
                    newLo = cand;
                    locked = true;
                }
            }
        }
        return locked;
    }

    public void Dispose()
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
}
