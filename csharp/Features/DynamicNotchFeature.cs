using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;

namespace WindowTweaks.Features;

/// <summary>
/// Dynamic Notch / Island (macOS-Tier Hardware HUD).
///
/// Floating black squircle pill at the top-center of the display that organically morphs
/// its dimensions via AppleSpringEngine to announce system state changes (volume, mic, timers)
/// without obscuring user content.
/// </summary>
public class DynamicNotchFeature : IDisposable
{
    private Window? _window;
    private Border? _pillBorder;
    private TextBlock? _glyphText;
    private TextBlock? _messageText;
    private DispatcherTimer? _springTimer;
    private DispatcherTimer? _revertTimer;

    private double _currentWidth = 140;
    private double _currentHeight = 28;
    private double _targetWidth = 140;
    private double _targetHeight = 28;
    private double _velWidth;
    private double _velHeight;

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
        if (_window != null) return;

        _glyphText = new TextBlock
        {
            Text = "",
            Foreground = Brushes.White,
            FontSize = 14,
            FontFamily = new FontFamily("Segoe UI Symbol, SF Pro Text"),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(10, 0, 6, 0)
        };

        _messageText = new TextBlock
        {
            Text = "Tweaks",
            Foreground = new SolidColorBrush(Color.FromRgb(210, 210, 215)),
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            FontFamily = new FontFamily("SF Pro Text, Segoe UI Variable Text, Segoe UI"),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 10, 0)
        };
        Typography.SetNumeralAlignment(_messageText, FontNumeralAlignment.Tabular);

        var stack = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        stack.Children.Add(_glyphText);
        stack.Children.Add(_messageText);

        _pillBorder = new Border
        {
            Width = _currentWidth,
            Height = _currentHeight,
            CornerRadius = new CornerRadius(14),
            Background = new SolidColorBrush(Color.FromArgb(245, 0, 0, 0)),
            BorderThickness = new Thickness(1),
            BorderBrush = VibrancyBackdrop.CreateSpecularBorderBrush(),
            Effect = VibrancyBackdrop.CreateKeyShadowEffect(),
            Child = stack
        };

        double screenW = SystemParameters.PrimaryScreenWidth;
        _window = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Width = 400,
            Height = 80,
            Left = (screenW - 400) / 2.0,
            Top = 0,
            Content = _pillBorder
        };

        _window.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_window);
            IntPtr hwnd = new WindowInteropHelper(_window).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _window.Show();

        _springTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _springTimer.Tick += OnSpringTick;
        _springTimer.Start();

        _revertTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2.5)
        };
        _revertTimer.Tick += (_, _) =>
        {
            _revertTimer.Stop();
            _targetWidth = 140;
            _targetHeight = 28;
            if (_messageText != null) _messageText.Text = "Tweaks";
        };
    }

    /// <summary>
    /// Animates the notch into an expanded notification state.
    /// </summary>
    public void Notify(string glyph, string message)
    {
        if (!IsEnabled || _glyphText == null || _messageText == null || _revertTimer == null) return;

        _glyphText.Text = glyph;
        _messageText.Text = message;
        _targetWidth = 260;
        _targetHeight = 38;

        _revertTimer.Stop();
        _revertTimer.Start();
    }

    private void OnSpringTick(object? sender, EventArgs e)
    {
        if (_pillBorder == null) return;

        const double dt = 0.015;
        AppleSpringEngine.Step(ref _currentWidth, ref _velWidth, _targetWidth, dt, AppleSpringEngine.SpringConfig.Snappy);
        AppleSpringEngine.Step(ref _currentHeight, ref _velHeight, _targetHeight, dt, AppleSpringEngine.SpringConfig.Snappy);

        _pillBorder.Width = _currentWidth;
        _pillBorder.Height = _currentHeight;
        _pillBorder.CornerRadius = new CornerRadius(_currentHeight / 2.0);
    }

    private void Stop()
    {
        _springTimer?.Stop();
        _springTimer = null;
        _revertTimer?.Stop();
        _revertTimer = null;

        if (_window != null)
        {
            try { _window.Close(); } catch { }
            _window = null;
        }

        _pillBorder = null;
        _glyphText = null;
        _messageText = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
