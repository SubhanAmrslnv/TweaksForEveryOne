using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class CustomClockFeature : IDisposable
{
    private Window? _clockWindow;
    private TextBlock? _timeText;
    private DispatcherTimer? _timer;

    public CustomClockFeature()
    {
        Enable();
    }

    private void Enable()
    {
        _clockWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = System.Windows.Media.Brushes.Transparent,
            Topmost = true,
            ShowInTaskbar = false,
            IsHitTestVisible = false,
            SizeToContent = SizeToContent.WidthAndHeight
        };

        _timeText = new TextBlock
        {
            Foreground = System.Windows.Media.Brushes.White,
            FontSize = 14,
            FontWeight = FontWeights.Bold,
            TextAlignment = TextAlignment.Right,
            Margin = new Thickness(0, 0, 20, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                Color = System.Windows.Media.Colors.Black,
                Direction = 320,
                ShadowDepth = 1,
                Opacity = 0.8,
                BlurRadius = 2
            }
        };

        var grid = new Grid();
        grid.Children.Add(_timeText);
        _clockWindow.Content = grid;
        _clockWindow.Show();

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _timer.Tick += Timer_Tick;
        _timer.Start();

        UpdateClock();
    }

    private void Timer_Tick(object? sender, EventArgs e)
    {
        UpdateClock();
    }

    private void UpdateClock()
    {
        if (_clockWindow == null || _timeText == null) return;

        // Update Text
        _timeText.Text = DateTime.Now.ToString("HH:mm:ss\ndd MMM yyyy");

        // Find Taskbar
        IntPtr taskbarHwnd = NativeMethods.FindWindow("Shell_TrayWnd", null);
        if (taskbarHwnd != IntPtr.Zero && NativeMethods.GetWindowRect(taskbarHwnd, out NativeMethods.RECT rect))
        {
            // Position the clock on the taskbar. 
            // We want it on the left side of the tray area. Let's just put it roughly near the right edge for now, but not covering the native clock.
            // A simple approach is positioning it at X = ScreenWidth - 300
            
            double screenW = SystemParameters.PrimaryScreenWidth;
            double screenH = SystemParameters.PrimaryScreenHeight;
            
            // Convert physical taskbar Y to logical
            var source = PresentationSource.FromVisual(_clockWindow);
            double dpiY = 1.0;
            if (source?.CompositionTarget != null)
            {
                dpiY = source.CompositionTarget.TransformFromDevice.M22;
            }

            double taskbarY = rect.Top * dpiY;
            double taskbarHeight = (rect.Bottom - rect.Top) * dpiY;

            _clockWindow.Left = screenW - 280; // Hardcoded offset from right to avoid covering native tray
            _clockWindow.Top = taskbarY + (taskbarHeight / 2) - (_clockWindow.ActualHeight / 2);
            
            // Keep on top of taskbar
            var helper = new WindowInteropHelper(_clockWindow);
            NativeMethods.SetWindowPos(helper.Handle, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0, 
                NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
        }
        else
        {
            // If taskbar is hidden, hide the clock
            _clockWindow.Left = -9999;
        }
    }

    public void Dispose()
    {
        _timer?.Stop();
        _clockWindow?.Close();
        _clockWindow = null;
    }
}
