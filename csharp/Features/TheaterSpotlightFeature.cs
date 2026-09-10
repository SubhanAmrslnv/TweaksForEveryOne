using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WindowTweaks.Core;
using Point = System.Windows.Point;

namespace WindowTweaks.Features;

/// <summary>
/// Theater Spotlight Feature.
///
/// Dims the desktop surface with a dark vignette while casting a soft-edged, 350px
/// radial spotlight that smoothly tracks the cursor using damped harmonic motion.
/// </summary>
public class TheaterSpotlightFeature : IDisposable
{
    private Window? _overlay;
    private RadialGradientBrush? _mask;
    private DispatcherTimer? _trackTimer;

    private double _curX, _curY;
    private double _velX, _velY;

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
        if (_overlay != null) return;

        double left = SystemParameters.VirtualScreenLeft;
        double top = SystemParameters.VirtualScreenTop;
        double width = SystemParameters.VirtualScreenWidth;
        double height = SystemParameters.VirtualScreenHeight;

        _mask = new RadialGradientBrush
        {
            GradientOrigin = new Point(0.5, 0.5),
            Center = new Point(0.5, 0.5),
            RadiusX = 175,
            RadiusY = 175,
            MappingMode = BrushMappingMode.Absolute
        };
        _mask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(0, 0, 0, 0), 0.0));
        _mask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(0, 0, 0, 0), 0.55));
        _mask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(255, 0, 0, 0), 1.0));

        _overlay = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(200, 0, 0, 0)),
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            OpacityMask = _mask,
            Opacity = 0
        };

        _overlay.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_overlay);
            IntPtr hwnd = new WindowInteropHelper(_overlay).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _overlay.Show();

        DoubleAnimation fadeIn = new(0, 1, TimeSpan.FromMilliseconds(250));
        _overlay.BeginAnimation(UIElement.OpacityProperty, fadeIn);

        if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
        {
            _curX = pt.X - left;
            _curY = pt.Y - top;
        }

        _trackTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _trackTimer.Tick += OnTrackTick;
        _trackTimer.Start();
    }

    private void OnTrackTick(object? sender, EventArgs e)
    {
        if (_overlay == null || _mask == null) return;

        if (NativeMethods.GetCursorPos(out NativeMethods.POINT pt))
        {
            double targetX = pt.X - SystemParameters.VirtualScreenLeft;
            double targetY = pt.Y - SystemParameters.VirtualScreenTop;

            AppleSpringEngine.Step(ref _curX, ref _velX, targetX, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref _curY, ref _velY, targetY, 0.015, AppleSpringEngine.SpringConfig.Snappy);

            var p = new Point(_curX, _curY);
            _mask.Center = p;
            _mask.GradientOrigin = p;
        }
    }

    private void Stop()
    {
        _trackTimer?.Stop();
        _trackTimer = null;

        if (_overlay != null)
        {
            var win = _overlay;
            DoubleAnimation fadeOut = new(win.Opacity, 0, TimeSpan.FromMilliseconds(180));
            fadeOut.Completed += (_, _) =>
            {
                try { win.Close(); } catch { }
            };
            win.BeginAnimation(UIElement.OpacityProperty, fadeOut);
            _overlay = null;
        }

        _mask = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
