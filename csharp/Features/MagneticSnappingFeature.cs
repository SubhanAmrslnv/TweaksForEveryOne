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

    private IntPtr _dragHwnd = IntPtr.Zero;
    private int _lastX = 0;
    private int _lastY = 0;
    private long _lastTime = 0;
    private double _velX = 0;
    private double _velY = 0;

    public bool IsEnabled => _isEnabled;

    public MagneticSnappingFeature()
    {
        _procStartEnd = new NativeMethods.WinEventDelegate(WinEventProcStartEnd);
        _procLocation = new NativeMethods.WinEventDelegate(WinEventProcLocation);
    }

    public void Toggle()
    {
        _isEnabled = !_isEnabled;
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
            }
            _lastTime = Stopwatch.GetTimestamp();
        }
        else if (eventType == NativeMethods.EVENT_SYSTEM_MOVESIZEEND)
        {
            if (hwnd == _dragHwnd)
            {
                SnapWindow(hwnd, _velX, _velY);
                _dragHwnd = IntPtr.Zero;
            }
        }
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
        uint ownPid = (uint)Process.GetCurrentProcess().Id;
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

            int winW = winRect.Right - winRect.Left;
            int winH = winRect.Bottom - winRect.Top;

            GlideTo(hwnd, winRect.Left, winRect.Top, finalX, finalY, crashX, crashY, winW, winH);
        }
    }

    private async void GlideTo(IntPtr hwnd, int fromX, int fromY, int toX, int toY, int crashX, int crashY, int winW, int winH)
    {
        double dx = toX - fromX;
        double dy = toY - fromY;
        double dist = Math.Sqrt(dx * dx + dy * dy);

        if (dist < 2)
        {
            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, toX, toY, winW, winH, NativeMethods.SWP_NOACTIVATE);
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
        while (true)
        {
            double t = sw.ElapsedMilliseconds / ms;
            if (t >= 1.0) break;

            double e = 1 - Math.Pow(1 - t, 5);
            double o = 9.4815 * t * Math.Pow(1 - t, 3);

            int nx = (int)Math.Round(fromX + dx * e + ox * o);
            int ny = (int)Math.Round(fromY + dy * e + oy * o);

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, nx, ny, winW, winH, NativeMethods.SWP_NOACTIVATE);
            await System.Threading.Tasks.Task.Delay(15);
        }

        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, toX, toY, winW, winH, NativeMethods.SWP_NOACTIVATE);
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
