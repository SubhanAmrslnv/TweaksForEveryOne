using System;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Features;

/// <summary>
/// Start Menu Blur Feature.
///
/// Dynamically fades a full-screen frosted acrylic backdrop behind the Start Menu
/// when invoked, matching the macOS App Exposé visual backdrop experience.
/// </summary>
public class StartMenuBlurFeature : IDisposable
{
    private Window? _scrimWindow;
    private DispatcherTimer? _pollTimer;
    private bool _isScrimVisible;

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
        if (_scrimWindow != null) return;

        double left = SystemParameters.VirtualScreenLeft;
        double top = SystemParameters.VirtualScreenTop;
        double width = SystemParameters.VirtualScreenWidth;
        double height = SystemParameters.VirtualScreenHeight;

        _scrimWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = new SolidColorBrush(Color.FromArgb(140, 15, 15, 18)),
            Topmost = false,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            Opacity = 0
        };

        _scrimWindow.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_scrimWindow);
            IntPtr hwnd = new WindowInteropHelper(_scrimWindow).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
            VibrancyBackdrop.ApplyNativeBackdrop(_scrimWindow, VibrancyBackdrop.BackdropType.Acrylic);
        };

        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(80)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        if (_scrimWindow == null) return;

        IntPtr fg = NativeMethods.GetForegroundWindow();
        bool startActive = IsStartMenu(fg);

        if (startActive && !_isScrimVisible)
        {
            _isScrimVisible = true;
            _scrimWindow.Show();
            _scrimWindow.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(120)));
        }
        else if (!startActive && _isScrimVisible)
        {
            _isScrimVisible = false;
            var fadeOut = new DoubleAnimation(_scrimWindow.Opacity, 0, TimeSpan.FromMilliseconds(100));
            fadeOut.Completed += (_, _) =>
            {
                if (!_isScrimVisible) _scrimWindow?.Hide();
            };
            _scrimWindow.BeginAnimation(UIElement.OpacityProperty, fadeOut);
        }
    }

    private static bool IsStartMenu(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;

        var sb = new StringBuilder(128);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();

        if (cls is "Windows.UI.Core.CoreWindow" or "XamlExplorerHostIslandWindow")
        {
            sb.Clear();
            NativeMethods.GetWindowText(hwnd, sb, sb.Capacity);
            string title = sb.ToString();
            return string.Equals(title, "Start", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(title, "Search", StringComparison.OrdinalIgnoreCase);
        }

        return false;
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;

        if (_scrimWindow != null)
        {
            try { _scrimWindow.Close(); } catch { }
            _scrimWindow = null;
        }
        _isScrimVisible = false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
