using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class FocusModeFeature
{
    private Window? _overlayWindow;
    private DispatcherTimer? _monitorTimer;
    private IntPtr _currentTargetHwnd;

    public bool IsEnabled => _overlayWindow != null;

    public void Toggle()
    {
        if (IsEnabled)
        {
            Disable();
        }
        else
        {
            Enable();
        }
    }

    private void Enable()
    {
        // Spans all monitors
        double left = SystemParameters.VirtualScreenLeft;
        double top = SystemParameters.VirtualScreenTop;
        double width = SystemParameters.VirtualScreenWidth;
        double height = SystemParameters.VirtualScreenHeight;

        _overlayWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = System.Windows.Media.Brushes.Transparent,
            Topmost = false,
            ShowInTaskbar = false,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            IsHitTestVisible = false // Passes clicks through
        };

        // Create the dimming background with a hole
        var path = new Path
        {
            Fill = new SolidColorBrush(System.Windows.Media.Color.FromArgb(200, 0, 0, 0)), // 80% Black
        };

        _overlayWindow.Content = path;
        _overlayWindow.Show();

        // Start monitoring active window
        _monitorTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(30)
        };
        _monitorTimer.Tick += MonitorTimer_Tick;
        _monitorTimer.Start();
        
        UpdateSpotlight();
    }

    private void Disable()
    {
        _monitorTimer?.Stop();
        _overlayWindow?.Close();
        _overlayWindow = null;
    }

    private void MonitorTimer_Tick(object? sender, EventArgs e)
    {
        UpdateSpotlight();
    }

    private void UpdateSpotlight()
    {
        if (_overlayWindow == null) return;

        IntPtr activeWindow = NativeMethods.GetForegroundWindow();
        
        // If no active window or it's our own overlay, ignore
        var helper = new WindowInteropHelper(_overlayWindow);
        if (activeWindow == IntPtr.Zero || activeWindow == helper.Handle)
            return;

        _currentTargetHwnd = activeWindow;

        // Ensure overlay is directly behind the active window
        NativeMethods.SetWindowPos(helper.Handle, _currentTargetHwnd, 0, 0, 0, 0, 
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);

        if (NativeMethods.GetWindowRect(_currentTargetHwnd, out NativeMethods.RECT rect))
        {
            // Convert physical screen coordinates to WPF logical coordinates
            var source = PresentationSource.FromVisual(_overlayWindow);
            double dpiX = 1.0, dpiY = 1.0;
            if (source?.CompositionTarget != null)
            {
                dpiX = source.CompositionTarget.TransformFromDevice.M11;
                dpiY = source.CompositionTarget.TransformFromDevice.M22;
            }

            double x = (rect.Left - SystemParameters.VirtualScreenLeft) * dpiX;
            double y = (rect.Top - SystemParameters.VirtualScreenTop) * dpiY;
            double w = (rect.Right - rect.Left) * dpiX;
            double h = (rect.Bottom - rect.Top) * dpiY;

            // Animate or snap the hole.
            var screenGeometry = new RectangleGeometry(new Rect(0, 0, _overlayWindow.Width, _overlayWindow.Height));
            var holeGeometry = new RectangleGeometry(new Rect(x, y, w, h), 10, 10); // 10px rounded corners

            var group = new GeometryGroup { FillRule = FillRule.EvenOdd };
            group.Children.Add(screenGeometry);
            group.Children.Add(holeGeometry);

            if (_overlayWindow.Content is Path path)
            {
                path.Data = group;
            }
        }
    }
}
