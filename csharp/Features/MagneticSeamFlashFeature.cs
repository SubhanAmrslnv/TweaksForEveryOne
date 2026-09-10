using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Features;

/// <summary>
/// Magnetic Seam Flash Feature (macOS Spatial Connection Parity).
///
/// Emits a transient 100ms neon accent line along the exact seam where two windows
/// or a window and screen boundary magnetically connect.
/// </summary>
public class MagneticSeamFlashFeature : IDisposable
{
    private Window? _flashWindow;
    private Border? _lineBorder;

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
        if (_flashWindow != null) return;

        _lineBorder = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(255, 0, 210, 255)), // Neon Cyan
            Effect = VibrancyBackdrop.CreateAmbientShadowEffect()
        };

        _flashWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Content = _lineBorder,
            Left = -10000,
            Top = -10000,
            Width = 10,
            Height = 10,
            Opacity = 0
        };

        _flashWindow.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_flashWindow);
            IntPtr hwnd = new WindowInteropHelper(_flashWindow).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _flashWindow.Show();
    }

    /// <summary>
    /// Flashes a 2px neon line along the given seam coordinates for 100ms.
    /// </summary>
    public void Flash(int x, int y, int width, int height)
    {
        if (!IsEnabled || _flashWindow == null) return;

        _flashWindow.Left = x;
        _flashWindow.Top = y;
        _flashWindow.Width = Math.Max(2, width);
        _flashWindow.Height = Math.Max(2, height);
        _flashWindow.Opacity = 1.0;

        DoubleAnimation fade = new(1.0, 0.0, TimeSpan.FromMilliseconds(100));
        _flashWindow.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    private void Stop()
    {
        if (_flashWindow != null)
        {
            try { _flashWindow.Close(); } catch { }
            _flashWindow = null;
        }

        _lineBorder = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
