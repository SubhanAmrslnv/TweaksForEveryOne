using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;
// WPF and WinForms are both referenced, so these names are ambiguous under ImplicitUsings.
// This overlay is pure WPF.
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace WindowTweaks.Features;

/// <summary>
/// A clock block drawn on the taskbar, in two rows and two columns:
///
///     [weather glyph]          HH:mm:ss
///     21°C Overcast 12 km/h    dd.MM.yyyy
///
/// THERE IS NO HARDCODED COORDINATE IN THIS FEATURE, and that is the whole design. The previous
/// version positioned itself at `screenWidth - 280`, which is why it covered the native clock and
/// the Control Center button on some machines: it read as a corrupted system tray, with the
/// notification icons apparently moved. Nothing had moved - they were underneath.
///
/// Position is `anchorLeft - gap - contentWidth`, where the anchor is resolved BY CLASS NAME every
/// tick (the notification area's width moves with its icon count - measured at 343 / 391 / 415 / 511
/// px within one session) and the width comes from the laid-out content.
///
/// The block is PAINTED IN THE TASKBAR'S OWN COLOUR, never colour-keyed. Keying looks right in theory
/// and fringes in practice: a keyed background needs every background pixel to equal the key exactly,
/// but antialiased and ClearType glyph edges blend with it, so those pixels are no longer the key,
/// survive the keying, and halo every character. An opaque block in the bar's own colour makes the
/// panel disappear instead. That works because the taskbar is one flat colour, and the sample is
/// taken to the LEFT of the block so it can never sample itself.
/// </summary>
public class CustomClockFeature : IDisposable
{
    // Settings
    private const string TimeFormatKey = "clock.timeFormat";
    private const string DateFormatKey = "clock.dateFormat";
    private const string AnchorKey = "clock.anchor"; // "TrayEdge" or "Clock"
    private const string GapKey = "clock.gap";

    /// <summary>24-hour, because the block has no room for an AM/PM marker.</summary>
    private const string DefaultTimeFormat = "HH:mm:ss";

    private const string DefaultDateFormat = "dd.MM.yyyy";

    private Window? _clockWindow;
    private TextBlock? _glyphText;
    private TextBlock? _infoText;
    private TextBlock? _timeText;
    private TextBlock? _dateText;
    private Border? _panel;

    private DispatcherTimer? _timer;
    private HwndSource? _source;

    private uint _lastSampledColour = uint.MaxValue;

    /// <summary>Set by App from the feature registry - drives whether the network is touched at all.</summary>
    public static bool WeatherEnabled { get; set; }

    public bool IsEnabled { get; private set; }

    /// <summary>
    /// Nothing happens in the constructor. The clock used to enable itself here, which made it the
    /// one feature that was live from launch with no way to switch it off.
    /// </summary>
    public CustomClockFeature()
    {
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled) Enable();
        else Disable();
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void Disable()
    {
        _timer?.Stop();
        _timer = null;

        if (_source != null)
        {
            _source.RemoveHook(WndProc);
            _source = null;
        }

        _clockWindow?.Close();
        _clockWindow = null;
        _glyphText = null;
        _infoText = null;
        _timeText = null;
        _dateText = null;
        _panel = null;
    }

    /// <summary>
    /// THIS OVERLAY MUST FORWARD WM_CLOSE TO SHUTDOWN.
    ///
    /// It is the only permanently visible window the app owns, so taskkill, an installer's stop step
    /// and Windows shutdown all find it FIRST when they post WM_CLOSE to the process's top-level
    /// windows - before the app's own message window. Without this hook the clock simply closed, the
    /// process kept running, OnExit never ran and settings were never flushed.
    /// </summary>
    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == (int)NativeMethods.WM_CLOSE)
        {
            handled = true;
            System.Windows.Application.Current?.Shutdown();
        }
        return IntPtr.Zero;
    }

    private void Enable()
    {
        _glyphText = new TextBlock
        {
            FontSize = 15,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
            // Segoe UI Symbol carries the BMP weather glyphs; see WeatherService.GlyphForCode.
            FontFamily = new FontFamily("Segoe UI Symbol, Segoe UI")
        };

        _infoText = new TextBlock
        {
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0xD0, 0xD0, 0xD0)),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left
        };

        _timeText = new TextBlock
        {
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Foreground = Brushes.White,
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right
        };

        _dateText = new TextBlock
        {
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0xD0, 0xD0, 0xD0)),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right
        };

        Grid grid = new();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); // weather
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) }); // gap
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); // time / date
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        Grid.SetRow(_glyphText, 0);
        Grid.SetColumn(_glyphText, 0);
        Grid.SetRow(_infoText, 1);
        Grid.SetColumn(_infoText, 0);
        Grid.SetRow(_timeText, 0);
        Grid.SetColumn(_timeText, 2);
        Grid.SetRow(_dateText, 1);
        Grid.SetColumn(_dateText, 2);

        grid.Children.Add(_glyphText);
        grid.Children.Add(_infoText);
        grid.Children.Add(_timeText);
        grid.Children.Add(_dateText);

        _panel = new Border
        {
            // Filled with the sampled taskbar colour on the first tick. A visible fallback here
            // rather than transparency, so a sampling failure looks like a panel and not like
            // floating text with fringed edges.
            Background = new SolidColorBrush(Color.FromRgb(0x20, 0x20, 0x20)),
            Padding = new Thickness(10, 1, 10, 1),
            Child = grid
        };

        _clockWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = false, // opaque: we paint the bar's colour, we do not key it
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            SizeToContent = SizeToContent.WidthAndHeight,
            Background = _panel.Background,
            Content = _panel,
            // Off screen until the first tick has measured and placed it, so it never appears in the
            // wrong position for one frame.
            Left = -10000,
            Top = -10000
        };

        Render();
        _clockWindow.Show();

        IntPtr handle = new WindowInteropHelper(_clockWindow).Handle;
        if (handle != IntPtr.Zero)
        {
            _source = HwndSource.FromHwnd(handle);
            _source?.AddHook(WndProc);

            // Tool window so the block can never show up in Alt-Tab.
            try
            {
                uint ex = NativeMethods.GetWindowLong(handle, NativeMethods.GWL_EXSTYLE);
                NativeMethods.SetWindowLong(handle, NativeMethods.GWL_EXSTYLE,
                    ex | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE);
            }
            catch
            {
            }
        }

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _timer.Tick += Timer_Tick;
        _timer.Start();

        Tick();
    }

    private void Timer_Tick(object? sender, EventArgs e)
    {
        // The flag is tested inside the tick, not only at the call site: a feature that owns a
        // permanently visible overlay has to be able to take it down even while being switched off.
        if (!IsEnabled)
        {
            Disable();
            return;
        }

        try
        {
            Tick();
        }
        catch
        {
            // An exception escaping a timer callback kills the timer, and the clock would be frozen
            // for the rest of the session with no visible cause.
        }
    }

    private void Tick()
    {
        // Makes no request at all unless weather is on AND a city is set. See WeatherService.
        WeatherService.Poll(WeatherEnabled);

        Render();
        Reposition();
    }

    private void Render()
    {
        if (_timeText == null || _dateText == null || _glyphText == null || _infoText == null) return;

        DateTime now = DateTime.Now;
        _timeText.Text = SafeFormat(now, SettingsStore.GetString(TimeFormatKey, DefaultTimeFormat), DefaultTimeFormat);
        _dateText.Text = SafeFormat(now, SettingsStore.GetString(DateFormatKey, DefaultDateFormat), DefaultDateFormat);

        if (!WeatherEnabled)
        {
            // Collapse the weather column entirely rather than leaving an empty gap.
            _glyphText.Text = string.Empty;
            _infoText.Text = string.Empty;
            return;
        }

        WeatherService.Reading? r = WeatherService.Current;

        if (r == null)
        {
            // The column exists whenever weather is on; only its VALUE is conditional. Sizing it to
            // nothing while waiting for the first reading is what made a merely unconfigured feature
            // look like a broken one.
            _glyphText.Text = "☁";
            _infoText.Text = WeatherService.Location.Length == 0 ? "set a city" : "--";
            return;
        }

        _glyphText.Text = r.Glyph;

        string condition = r.Condition;
        _infoText.Text = condition.Length > 0
            ? $"{r.TemperatureText}  {condition}  {r.WindText}"
            : $"{r.TemperatureText}  {r.WindText}";
    }

    /// <summary>
    /// A user-supplied format string reaches DateTime.ToString directly, and a bad one throws. In a
    /// timer callback that would kill the clock, so fall back instead.
    /// </summary>
    private static string SafeFormat(DateTime value, string format, string fallback)
    {
        try
        {
            if (format.Length == 0) return value.ToString(fallback);
            return value.ToString(format);
        }
        catch
        {
            return value.ToString(fallback);
        }
    }

    private void Reposition()
    {
        if (_clockWindow == null) return;

        IntPtr taskbar = NativeMethods.FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero || !NativeMethods.GetWindowRect(taskbar, out NativeMethods.RECT bar))
        {
            HideOffScreen();
            return;
        }

        // An auto-hidden taskbar sits mostly off screen. Follow it away rather than floating over
        // whatever is underneath.
        if (bar.Bottom <= bar.Top || bar.Right <= bar.Left)
        {
            HideOffScreen();
            return;
        }

        IntPtr anchor = ResolveAnchor(taskbar);
        int anchorLeft = bar.Right;
        if (anchor != IntPtr.Zero && NativeMethods.GetWindowRect(anchor, out NativeMethods.RECT anchorRect))
            anchorLeft = anchorRect.Left;

        // Device pixels to WPF device-independent units. Skipping this puts the block in the wrong
        // place on any display that is not at 100% scaling.
        double scaleX = 1.0, scaleY = 1.0;
        PresentationSource? src = PresentationSource.FromVisual(_clockWindow);
        if (src?.CompositionTarget != null)
        {
            scaleX = src.CompositionTarget.TransformFromDevice.M11;
            scaleY = src.CompositionTarget.TransformFromDevice.M22;
        }

        // Make sure ActualWidth reflects the text we just set, before measuring against it.
        _clockWindow.UpdateLayout();

        double width = _clockWindow.ActualWidth;
        double height = _clockWindow.ActualHeight;
        if (width <= 0 || height <= 0) return;

        int gap = SettingsStore.GetInt(GapKey, 12, 0, 400);

        double left = anchorLeft * scaleX - gap - width;
        double barTop = bar.Top * scaleY;
        double barHeight = (bar.Bottom - bar.Top) * scaleY;
        double top = barTop + (barHeight - height) / 2.0;

        // Never let the block run off the left edge of the bar.
        double barLeft = bar.Left * scaleX;
        if (left < barLeft) left = barLeft;

        if (Math.Abs(_clockWindow.Left - left) > 0.5) _clockWindow.Left = left;
        if (Math.Abs(_clockWindow.Top - top) > 0.5) _clockWindow.Top = top;

        SampleTaskbarColour(left, barTop, barHeight, scaleX, scaleY);

        // Stay above the taskbar. Re-asserted each tick because the shell raises itself.
        try
        {
            IntPtr handle = new WindowInteropHelper(_clockWindow).Handle;
            if (handle != IntPtr.Zero)
            {
                NativeMethods.SetWindowPos(handle, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
                    NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE);
            }
        }
        catch
        {
        }
    }

    private void HideOffScreen()
    {
        if (_clockWindow == null) return;
        if (_clockWindow.Left > -9000) _clockWindow.Left = -10000;
    }

    /// <summary>
    /// Which tray element the block sits to the left of. This is a SETTING because the two options
    /// are a genuine trade-off, not a matter of taste:
    ///
    ///   TrayEdge (default) - TrayNotifyWnd, left of every tray element. Costs distance: that window
    ///                        is the whole notification area and its width moves with the icon count.
    ///   Clock              - TrayClockWClass. Sits closer, but covers whatever is in those ~115 px,
    ///                        which on some shells includes the Control Center button.
    /// </summary>
    private static IntPtr ResolveAnchor(IntPtr taskbar)
    {
        string preference = SettingsStore.GetString(AnchorKey, "TrayEdge");

        IntPtr tray = NativeMethods.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);

        if (string.Equals(preference, "Clock", StringComparison.OrdinalIgnoreCase) && tray != IntPtr.Zero)
        {
            // The clock is a GRANDCHILD of the taskbar, via TrayNotifyWnd - not a direct child.
            IntPtr clock = NativeMethods.FindWindowEx(tray, IntPtr.Zero, "TrayClockWClass", null);
            if (clock != IntPtr.Zero) return clock;
        }

        return tray;
    }

    /// <summary>
    /// Read the taskbar's colour once per change and paint the panel with it.
    ///
    /// The sample point is to the LEFT of the block and vertically centred in the bar, so the block
    /// can never sample its own pixels. Measured on this shell: the bar is one flat colour (0x202020
    /// at x = 200, 600, 1000, 1200, 1300 and 1400, including over inactive task buttons).
    /// </summary>
    private void SampleTaskbarColour(double blockLeft, double barTop, double barHeight, double scaleX, double scaleY)
    {
        if (_panel == null || _clockWindow == null) return;

        IntPtr dc = IntPtr.Zero;
        try
        {
            int sampleX = (int)((blockLeft / scaleX) - 24);
            int sampleY = (int)((barTop + barHeight / 2.0) / scaleY);
            if (sampleX < 0) return;

            dc = NativeMethods.GetDC(IntPtr.Zero);
            if (dc == IntPtr.Zero) return;

            uint colour = NativeMethods.GetPixel(dc, sampleX, sampleY);
            if (colour == NativeMethods.CLR_INVALID) return;
            if (colour == _lastSampledColour) return;

            _lastSampledColour = colour;

            // COLORREF is 0x00BBGGRR.
            byte r = (byte)(colour & 0xFF);
            byte g = (byte)((colour >> 8) & 0xFF);
            byte b = (byte)((colour >> 16) & 0xFF);

            SolidColorBrush brush = new(Color.FromRgb(r, g, b));
            _panel.Background = brush;
            _clockWindow.Background = brush;

            // Keep the text readable whichever way the theme went.
            bool dark = (0.299 * r + 0.587 * g + 0.114 * b) < 128;
            Brush primary = dark ? Brushes.White : Brushes.Black;
            Brush secondary = dark
                ? new SolidColorBrush(Color.FromRgb(0xD0, 0xD0, 0xD0))
                : new SolidColorBrush(Color.FromRgb(0x40, 0x40, 0x40));

            if (_timeText != null) _timeText.Foreground = primary;
            if (_glyphText != null) _glyphText.Foreground = primary;
            if (_dateText != null) _dateText.Foreground = secondary;
            if (_infoText != null) _infoText.Foreground = secondary;
        }
        catch
        {
        }
        finally
        {
            if (dc != IntPtr.Zero) NativeMethods.ReleaseDC(IntPtr.Zero, dc);
        }
    }

    public void Dispose()
    {
        IsEnabled = false;
        Disable();
    }
}
