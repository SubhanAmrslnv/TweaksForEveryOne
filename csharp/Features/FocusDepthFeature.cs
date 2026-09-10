using System;
using System.Collections.Generic;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Focus Depth Feature.
///
/// Simulates optical depth-of-field by pushing background windows backward in perceptual
/// depth using AlphaCompositor's named "focus" layer, leaving only the active foreground
/// window in sharp full luminance.
/// </summary>
public class FocusDepthFeature : IDisposable
{
    private DispatcherTimer? _pollTimer;
    private IntPtr _lastForeground;
    private readonly HashSet<IntPtr> _dimmedWindows = new();

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
        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(150)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();
        UpdateDepth();
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg != _lastForeground)
        {
            _lastForeground = fg;
            UpdateDepth();
        }
    }

    private void UpdateDepth()
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero || !NativeMethods.IsWindow(fg)) return;

        // Clear focus dimming on active foreground window
        AlphaCompositor.ClearLayer(fg, "focus");
        _dimmedWindows.Remove(fg);

        // Dim background windows via the named "focus" compositor layer
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (hwnd == fg) return true;
            if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return true;

            AlphaCompositor.SetLayer(hwnd, "focus", 0.72);
            _dimmedWindows.Add(hwnd);
            return true;
        }, IntPtr.Zero);
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;

        foreach (IntPtr hwnd in _dimmedWindows)
        {
            AlphaCompositor.ClearLayer(hwnd, "focus");
        }
        _dimmedWindows.Clear();
        _lastForeground = IntPtr.Zero;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
