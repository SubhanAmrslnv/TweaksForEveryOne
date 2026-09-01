using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Shift+Alt+G makes the active window a ghost: mostly transparent and click-through, fading in and
/// becoming clickable again only as the cursor approaches it. Useful for a reference window parked
/// over what you are working on.
///
/// Opacity goes through AlphaCompositor as the "ghost" layer.
///
/// THE LAYER IS INSTALLED AT FACTOR 1.0 WHEN THE CURSOR IS ON THE WINDOW - it is never cleared
/// while the window is still a ghost. Clearing it would leave a structurally neutral record, the
/// compositor would strip WS_EX_LAYERED, and the next tick 25 ms later would add it back: the style
/// would be toggled dozens of times a second while the cursor rests on a ghost, and in between the
/// window is opaque, click-through and always-on-top with no visual cue that anything is wrong.
/// </summary>
public class ProximityGhostFeature : IDisposable
{
    private sealed class GhostInfo
    {
        public uint OriginalExStyle;
    }

    private readonly Dictionary<IntPtr, GhostInfo> _ghostWindows = new();
    private bool _isMonitoring;
    private CancellationTokenSource? _cancellationTokenSource;

    // Read once per loop pass rather than per ghosted window: the loop runs every 25 ms and a
    // settings read takes the store's lock.
    private int _maxDist;
    private double _minFactor;
    private int _clickDist;

    public bool IsEnabled => _ghostWindows.Count > 0;

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        if (_ghostWindows.ContainsKey(hwnd))
        {
            UnGhostWindow(hwnd);
            return;
        }

        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);

        // Already click-through: leave it alone, we would not know how to restore it.
        if ((exStyle & NativeMethods.WS_EX_TRANSPARENT) == NativeMethods.WS_EX_TRANSPARENT)
            return;

        _ghostWindows[hwnd] = new GhostInfo { OriginalExStyle = exStyle };

        // Install the layer before anything else becomes visible, so there is no frame where the
        // window is click-through and fully opaque.
        AlphaCompositor.SetLayer(hwnd, AlphaCompositor.LayerGhost, 1.0);

        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
            NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_TRANSPARENT);

        NativeMethods.SetWindowPos(hwnd, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);

        if (!_isMonitoring) StartMonitoring();
    }

    private void UnGhostWindow(IntPtr hwnd)
    {
        if (!_ghostWindows.TryGetValue(hwnd, out GhostInfo? info)) return;
        _ghostWindows.Remove(hwnd);

        if (!NativeMethods.IsWindow(hwnd))
        {
            AlphaCompositor.Forget(hwnd);
            return;
        }

        // Drop our layer. The compositor returns the window to the user's own base opacity, and
        // strips WS_EX_LAYERED only if it was the one that added it.
        AlphaCompositor.ClearLayer(hwnd, AlphaCompositor.LayerGhost);

        uint currentExStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        if ((info.OriginalExStyle & NativeMethods.WS_EX_TRANSPARENT) == 0)
            currentExStyle &= ~NativeMethods.WS_EX_TRANSPARENT;

        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, currentExStyle);

        NativeMethods.SetWindowPos(hwnd, NativeMethods.HWND_NOTOPMOST, 0, 0, 0, 0,
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
    }

    private void StartMonitoring()
    {
        _isMonitoring = true;
        _cancellationTokenSource = new CancellationTokenSource();
        Task.Run(() => MonitorLoop(_cancellationTokenSource.Token));
    }

    private async Task MonitorLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                if (_ghostWindows.Count == 0)
                {
                    _isMonitoring = false;
                    break;
                }

                _maxDist = TuningRegistry.Int(TuningRegistry.GhostMaxDistance);
                _minFactor = TuningRegistry.Fraction(TuningRegistry.GhostMinOpacity);
                _clickDist = TuningRegistry.Int(TuningRegistry.GhostClickDistance);

                NativeMethods.GetCursorPos(out NativeMethods.POINT pt);

                List<IntPtr> dead = new();

                IntPtr[] keys = new IntPtr[_ghostWindows.Count];
                _ghostWindows.Keys.CopyTo(keys, 0);

                foreach (IntPtr hwnd in keys)
                {
                    if (!NativeMethods.IsWindow(hwnd))
                    {
                        dead.Add(hwnd);
                        continue;
                    }

                    if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect)) continue;

                    int dist = GetDistToRect(pt.X, pt.Y, rect.Left, rect.Top,
                        rect.Right - rect.Left, rect.Bottom - rect.Top);

                    double factor;
                    if (dist == 0) factor = 1.0;
                    else if (dist >= _maxDist) factor = _minFactor;
                    else
                    {
                        double ratio = 1.0 - (double)dist / _maxDist;
                        factor = _minFactor + ratio * (1.0 - _minFactor);
                    }

                    // Always SetLayer, never ClearLayer: see the class comment.
                    AlphaCompositor.SetLayer(hwnd, AlphaCompositor.LayerGhost, factor);

                    uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
                    bool isClickThrough = (exStyle & NativeMethods.WS_EX_TRANSPARENT) != 0;

                    if (dist < _clickDist)
                    {
                        if (isClickThrough)
                            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
                                exStyle & ~NativeMethods.WS_EX_TRANSPARENT);
                    }
                    else if (dist > _clickDist + 12)
                    {
                        if (!isClickThrough)
                            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
                                exStyle | NativeMethods.WS_EX_TRANSPARENT);
                    }
                }

                foreach (IntPtr h in dead)
                {
                    _ghostWindows.Remove(h);
                    AlphaCompositor.Forget(h);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                // Never let a background loop die on one bad window.
            }

            try
            {
                await Task.Delay(25, token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private static int GetDistToRect(int px, int py, int rx, int ry, int rw, int rh)
    {
        int dx = 0;
        int dy = 0;

        if (px < rx) dx = rx - px;
        else if (px > rx + rw) dx = px - (rx + rw);

        if (py < ry) dy = ry - py;
        else if (py > ry + rh) dy = py - (ry + rh);

        return (int)Math.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>Release every ghosted window. Called on exit and by Restore All.</summary>
    public void RestoreAll()
    {
        foreach (IntPtr hwnd in new List<IntPtr>(_ghostWindows.Keys))
        {
            UnGhostWindow(hwnd);
        }
    }

    public void Dispose()
    {
        _cancellationTokenSource?.Cancel();
        RestoreAll();
    }
}
