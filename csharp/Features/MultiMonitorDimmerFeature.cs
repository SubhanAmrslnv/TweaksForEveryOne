using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class MultiMonitorDimmerFeature : IDisposable
{
    private bool _enabled = false;
    private CancellationTokenSource? _cts;
    private readonly Dictionary<string, Window> _dimmerWindows = new();

    private const double DIMMER_OPACITY = 0.47; // 47% alpha

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
            _ = RunDimmerLoop(_cts.Token);
        }
        else
        {
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
            
            System.Windows.Application.Current.Dispatcher.Invoke(() =>
            {
                foreach (var win in _dimmerWindows.Values)
                {
                    win.Close();
                }
                _dimmerWindows.Clear();
            });
        }
    }

    public void Toggle() => SetEnabled(!_enabled);

    private async Task RunDimmerLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await Task.Delay(200, token).ConfigureAwait(false);
            if (token.IsCancellationRequested) break;

            NativeMethods.GetCursorPos(out NativeMethods.POINT pt);

            var monitors = new List<NativeMethods.RECT>();
            NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                (IntPtr hMonitor, IntPtr hdcMonitor, ref NativeMethods.RECT lprcMonitor, IntPtr dwData) =>
                {
                    monitors.Add(lprcMonitor);
                    return true;
                }, IntPtr.Zero);

            if (monitors.Count < 2)
            {
                // If fewer than 2 monitors, close all
                System.Windows.Application.Current.Dispatcher.Invoke(() =>
                {
                    foreach (var win in _dimmerWindows.Values)
                    {
                        win.Close();
                    }
                    _dimmerWindows.Clear();
                });
                continue;
            }

            // Find active monitor
            int activeIndex = 0;
            for (int i = 0; i < monitors.Count; i++)
            {
                var m = monitors[i];
                if (pt.X >= m.Left && pt.X < m.Right && pt.Y >= m.Top && pt.Y < m.Bottom)
                {
                    activeIndex = i;
                    break;
                }
            }

            System.Windows.Application.Current.Dispatcher.Invoke(() =>
            {
                // Close dimmer on active monitor
                string activeKey = GetMonitorKey(monitors[activeIndex]);
                if (_dimmerWindows.TryGetValue(activeKey, out Window? activeWin))
                {
                    activeWin.Close();
                    _dimmerWindows.Remove(activeKey);
                }

                // Create dimmers on inactive monitors
                for (int i = 0; i < monitors.Count; i++)
                {
                    if (i == activeIndex) continue;

                    var m = monitors[i];
                    string key = GetMonitorKey(m);

                    if (!_dimmerWindows.ContainsKey(key))
                    {
                        var win = new Window
                        {
                            WindowStyle = WindowStyle.None,
                            AllowsTransparency = true,
                            Background = System.Windows.Media.Brushes.Black,
                            Opacity = DIMMER_OPACITY,
                            Topmost = true,
                            ShowInTaskbar = false,
                            IsHitTestVisible = false,
                            Left = m.Left,
                            Top = m.Top,
                            Width = m.Right - m.Left,
                            Height = m.Bottom - m.Top,
                            ResizeMode = ResizeMode.NoResize,
                            ShowActivated = false
                        };
                        
                        // Set WS_EX_TOOLWINDOW and WS_EX_TRANSPARENT
                        win.SourceInitialized += (s, e) =>
                        {
                            var hwnd = new WindowInteropHelper(win).Handle;
                            uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
                            const uint WS_EX_TOOLWINDOW = 0x00000080;
                            const uint WS_EX_TRANSPARENT = 0x00000020;
                            NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT);
                        };

                        win.Show();
                        _dimmerWindows[key] = win;
                    }
                }
                
                // Cleanup windows for detached monitors
                var keysToRemove = new List<string>();
                foreach (var key in _dimmerWindows.Keys)
                {
                    bool found = false;
                    for (int i = 0; i < monitors.Count; i++)
                    {
                        if (i == activeIndex) continue;
                        if (key == GetMonitorKey(monitors[i]))
                        {
                            found = true;
                            break;
                        }
                    }
                    if (!found) keysToRemove.Add(key);
                }
                
                foreach (var key in keysToRemove)
                {
                    _dimmerWindows[key].Close();
                    _dimmerWindows.Remove(key);
                }
            });
        }
    }

    private string GetMonitorKey(NativeMethods.RECT rect)
    {
        return $"{rect.Left},{rect.Top},{rect.Right},{rect.Bottom}";
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        foreach (var win in _dimmerWindows.Values)
        {
            win.Close();
        }
        _dimmerWindows.Clear();
    }
}
