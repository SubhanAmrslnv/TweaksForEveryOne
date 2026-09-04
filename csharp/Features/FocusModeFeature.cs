using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class FocusModeFeature : IDisposable
{
    private Window? _overlayWindow;
    private DispatcherTimer? _monitorTimer;
    private IntPtr _currentTargetHwnd;
    private RadialGradientBrush? _spotlightMask;
    
    // Smooth trailing variables for the cinematic spotlight movement
    private double _currentX, _currentY, _currentW, _currentH;

    public bool IsEnabled => _overlayWindow != null;

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        if (enabled) Enable();
        else Disable();
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void Enable()
    {
        double left = SystemParameters.VirtualScreenLeft;
        double top = SystemParameters.VirtualScreenTop;
        double width = SystemParameters.VirtualScreenWidth;
        double height = SystemParameters.VirtualScreenHeight;

        _overlayWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(230, 0, 0, 0)), // Very dark vignette
            Topmost = false,
            ShowInTaskbar = false,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            IsHitTestVisible = false,
            Opacity = 0 // Start fully transparent
        };

        // Create a radial opacity mask to punch a soft hole
        _spotlightMask = new RadialGradientBrush
        {
            GradientOrigin = new System.Windows.Point(0.5, 0.5),
            Center = new System.Windows.Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5,
            MappingMode = BrushMappingMode.Absolute
        };

        // The center of the window is fully visible (0 opacity in the mask means we don't draw the dark overlay)
        _spotlightMask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(0, 0, 0, 0), 0.0));
        _spotlightMask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(0, 0, 0, 0), 0.7)); // Inner clear zone
        _spotlightMask.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(255, 0, 0, 0), 1.0)); // Soft cinematic fade out to darkness

        _overlayWindow.OpacityMask = _spotlightMask;
        _overlayWindow.Show();

        // Cinematic Fade In
        DoubleAnimation fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.6))
        {
            EasingFunction = new QuarticEase { EasingMode = EasingMode.EaseOut }
        };
        _overlayWindow.BeginAnimation(Window.OpacityProperty, fadeIn);

        // Start tracking
        _monitorTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16) // 60 FPS
        };
        _monitorTimer.Tick += MonitorTimer_Tick;
        _monitorTimer.Start();
        
        UpdateSpotlight(true);
    }

    private void Disable()
    {
        if (_overlayWindow == null) return;

        _monitorTimer?.Stop();

        // Cinematic Fade Out
        DoubleAnimation fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.4))
        {
            EasingFunction = new QuarticEase { EasingMode = EasingMode.EaseOut }
        };
        
        fadeOut.Completed += (s, e) => 
        {
            _overlayWindow?.Close();
            _overlayWindow = null;
        };

        _overlayWindow.BeginAnimation(Window.OpacityProperty, fadeOut);
    }

    private void MonitorTimer_Tick(object? sender, EventArgs e)
    {
        UpdateSpotlight(false);
    }

    private void UpdateSpotlight(bool snap)
    {
        if (_overlayWindow == null || _spotlightMask == null) return;

        IntPtr activeWindow = NativeMethods.GetForegroundWindow();
        var helper = new WindowInteropHelper(_overlayWindow);
        if (activeWindow == IntPtr.Zero || activeWindow == helper.Handle)
            return;

        _currentTargetHwnd = activeWindow;

        NativeMethods.SetWindowPos(helper.Handle, _currentTargetHwnd, 0, 0, 0, 0, 
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);

        if (NativeMethods.GetWindowRect(_currentTargetHwnd, out NativeMethods.RECT rect))
        {
            var source = PresentationSource.FromVisual(_overlayWindow);
            double dpiX = 1.0, dpiY = 1.0;
            if (source?.CompositionTarget != null)
            {
                dpiX = source.CompositionTarget.TransformFromDevice.M11;
                dpiY = source.CompositionTarget.TransformFromDevice.M22;
            }

            double targetX = (rect.Left - SystemParameters.VirtualScreenLeft) * dpiX;
            double targetY = (rect.Top - SystemParameters.VirtualScreenTop) * dpiY;
            double targetW = (rect.Right - rect.Left) * dpiX;
            double targetH = (rect.Bottom - rect.Top) * dpiY;

            if (snap || _currentW == 0)
            {
                _currentX = targetX;
                _currentY = targetY;
                _currentW = targetW;
                _currentH = targetH;
            }
            else
            {
                // Cinematic physics trailing (Lerp)
                double speed = 0.15;
                _currentX += (targetX - _currentX) * speed;
                _currentY += (targetY - _currentY) * speed;
                _currentW += (targetW - _currentW) * speed;
                _currentH += (targetH - _currentH) * speed;
            }

            // Define the spotlight based on the window center and size
            double centerX = _currentX + (_currentW / 2);
            double centerY = _currentY + (_currentH / 2);

            _spotlightMask.Center = new System.Windows.Point(centerX, centerY);
            _spotlightMask.GradientOrigin = new System.Windows.Point(centerX, centerY);
            
            // The radius should encircle the window entirely + some padding
            double padding = 50;
            _spotlightMask.RadiusX = (_currentW / 2) + padding;
            _spotlightMask.RadiusY = (_currentH / 2) + padding;
        }
    }

    public void Dispose()
    {
        _monitorTimer?.Stop();
        if (_overlayWindow != null)
        {
            _overlayWindow.Close();
            _overlayWindow = null;
        }
    }
}
