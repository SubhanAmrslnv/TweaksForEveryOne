using System;
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
/// Focus Pulse Feature (macOS Eye-Guide Focus Parity).
///
/// Switching focus to a window creates a subtle expanding scale pulse ring (1.02x)
/// that rebounds and dissolves to effortlessly guide eye attention.
/// </summary>
public class FocusPulseFeature : IDisposable
{
    private Window? _pulseWindow;
    private Border? _pulseBorder;
    private DispatcherTimer? _pollTimer;
    private DispatcherTimer? _animTimer;
    private IntPtr _lastFg;

    private double _scale = 1.0;
    private double _velScale;
    private double _opacity = 0.0;
    private NativeMethods.RECT _baseRect;

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
        if (_pulseWindow != null) return;

        _pulseBorder = new Border
        {
            BorderThickness = new Thickness(2),
            BorderBrush = new SolidColorBrush(Color.FromArgb(200, 0, 122, 255)),
            CornerRadius = new CornerRadius(12),
            Background = Brushes.Transparent
        };

        _pulseWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Content = _pulseBorder,
            Left = -10000,
            Top = -10000,
            Width = 100,
            Height = 100,
            Opacity = 0
        };

        _pulseWindow.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_pulseWindow);
            IntPtr hwnd = new WindowInteropHelper(_pulseWindow).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _pulseWindow.Show();

        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(100)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();

        _animTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _animTimer.Tick += OnAnimTick;
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero || fg == _lastFg || !WindowFilter.IsOrdinaryAppWindow(fg)) return;
        _lastFg = fg;

        if (NativeMethods.GetWindowRect(fg, out _baseRect))
        {
            _scale = 1.0;
            _velScale = 1.6; // Initial outward pulse impulse
            _opacity = 0.85;

            _animTimer?.Stop();
            _animTimer?.Start();
        }
    }

    private void OnAnimTick(object? sender, EventArgs e)
    {
        if (_pulseWindow == null) return;

        AppleSpringEngine.Step(ref _scale, ref _velScale, 1.0, 0.015, AppleSpringEngine.SpringConfig.Snappy);
        _opacity = Math.Max(0, _opacity - 0.045);

        int baseW = _baseRect.Right - _baseRect.Left;
        int baseH = _baseRect.Bottom - _baseRect.Top;

        int pad = (int)Math.Round((_scale - 1.0) * 120.0);
        int curX = _baseRect.Left - pad;
        int curY = _baseRect.Top - pad;
        int curW = baseW + (pad * 2);
        int curH = baseH + (pad * 2);

        IntPtr myHwnd = new WindowInteropHelper(_pulseWindow).Handle;
        NativeMethods.SetWindowPos(myHwnd, IntPtr.Zero, curX, curY, curW, curH,
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_SHOWWINDOW);

        _pulseWindow.Opacity = _opacity;

        if (_opacity <= 0.02 && Math.Abs(_scale - 1.0) < 0.01)
        {
            _animTimer?.Stop();
            _pulseWindow.Hide();
        }
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;
        _animTimer?.Stop();
        _animTimer = null;

        if (_pulseWindow != null)
        {
            try { _pulseWindow.Close(); } catch { }
            _pulseWindow = null;
        }

        _pulseBorder = null;
        _lastFg = IntPtr.Zero;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
