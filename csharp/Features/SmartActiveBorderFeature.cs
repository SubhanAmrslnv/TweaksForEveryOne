using System;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Features;

/// <summary>
/// Smart Active Border (macOS Focus Halo Parity).
///
/// Renders a continuous 1.5px glowing accent border surrounding the currently focused
/// foreground window, applying a subtle harmonic breathing glow cycle.
/// </summary>
public class SmartActiveBorderFeature : IDisposable
{
    private Window? _overlayWindow;
    private Border? _haloBorder;
    private DispatcherTimer? _pollTimer;
    private IntPtr _lastHwnd;
    private double _phase;

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
        if (_overlayWindow != null) return;

        _haloBorder = new Border
        {
            BorderThickness = new Thickness(1.5),
            BorderBrush = new SolidColorBrush(Color.FromArgb(220, 0, 122, 255)), // macOS Accent Blue
            CornerRadius = new CornerRadius(10),
            Background = Brushes.Transparent,
            Margin = new Thickness(0)
        };

        _overlayWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Content = _haloBorder,
            Left = -10000,
            Top = -10000,
            Width = 100,
            Height = 100
        };

        _overlayWindow.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_overlayWindow);
            IntPtr hwnd = new WindowInteropHelper(_overlayWindow).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _overlayWindow.Show();

        _pollTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(20)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        if (_overlayWindow == null || _haloBorder == null) return;

        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero || !NativeMethods.IsWindow(fg) || NativeMethods.IsIconic(fg))
        {
            _overlayWindow.Hide();
            return;
        }

        // Exclude ourselves, desktop, and taskbar
        NativeMethods.GetWindowThreadProcessId(fg, out uint pid);
        if (pid == (uint)Environment.ProcessId) return;

        var sb = new StringBuilder(256);
        NativeMethods.GetClassName(fg, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")
        {
            _overlayWindow.Hide();
            return;
        }

        _lastHwnd = fg;

        // Use DWM extended frame bounds for true visible window geometry
        NativeMethods.RECT rect;
        int hr = NativeMethods.DwmGetWindowAttribute(fg, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out rect, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.RECT>());
        if (hr != 0)
        {
            if (!NativeMethods.GetWindowRect(fg, out rect))
            {
                _overlayWindow.Hide();
                return;
            }
        }

        int w = rect.Right - rect.Left;
        int h = rect.Bottom - rect.Top;
        if (w <= 10 || h <= 10)
        {
            _overlayWindow.Hide();
            return;
        }

        // Breathing glow cycle (sinusoidal modulation of alpha: 0.65 -> 0.95)
        _phase += 0.08;
        if (_phase > Math.PI * 2) _phase -= Math.PI * 2;
        double glowAlpha = 0.65 + (0.30 * (0.5 * (1.0 + Math.Sin(_phase))));

        _haloBorder.BorderBrush = new SolidColorBrush(Color.FromArgb((byte)(glowAlpha * 255), 0, 122, 255));

        // Position overlay window matching physical pixels exactly
        IntPtr myHwnd = new WindowInteropHelper(_overlayWindow).Handle;
        NativeMethods.SetWindowPos(myHwnd, fg, rect.Left - 2, rect.Top - 2, w + 4, h + 4,
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);

        if (!_overlayWindow.IsVisible) _overlayWindow.Show();
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;

        if (_overlayWindow != null)
        {
            try { _overlayWindow.Close(); } catch { }
            _overlayWindow = null;
        }

        _haloBorder = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
