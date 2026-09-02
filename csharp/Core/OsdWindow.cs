using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace WindowTweaks.Core;

/// <summary>
/// A small on-screen readout: a line of text, optionally with a meter bar under it. Used by the
/// clipboard feedback and by the taskbar volume wheel.
///
/// It exists as one class rather than one per feature because the fiddly parts are identical and
/// were each wrong in their own way when duplicated: the window has to be click-through at the WIN32
/// level (WPF's IsHitTestVisible only covers the WPF tree, so without WS_EX_TRANSPARENT the overlay
/// becomes an invisible dead zone that swallows clicks), it has to be placed in PHYSICAL pixels
/// (Window.Left is in WPF units, so a hook's coordinates put it in the wrong place on any scaled
/// display), and it has to be reused rather than recreated (creating and destroying a layered WPF
/// window per event is tens of milliseconds of UI-thread work in response to a keystroke).
///
/// EVERY MEMBER MUST BE CALLED ON THE DISPATCHER. Callers coming off a hook use <see cref="Post"/>.
/// </summary>
internal sealed class OsdWindow : IDisposable
{
    private readonly double _minWidth;

    private Window? _window;
    private TextBlock? _label;
    private Border? _meterTrack;
    private Border? _meterFill;
    private Grid? _meterHost;
    private DispatcherTimer? _hideTimer;

    public OsdWindow(double minWidth = 0)
    {
        _minWidth = minWidth;
    }

    /// <summary>
    /// Runs <paramref name="work"/> on the dispatcher, unless the app is shutting down - in which
    /// case it does nothing. That guard is the reason this helper exists: a hook that keeps posting
    /// to the dispatcher during teardown is what stopped the app from exiting.
    /// </summary>
    public static void Post(Action work)
    {
        if (AppLifetime.IsExiting) return;

        Dispatcher? dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher == null) return;

        try
        {
            dispatcher.BeginInvoke(work);
        }
        catch
        {
            // The dispatcher can begin shutting down between the check and the call.
        }
    }

    /// <summary>
    /// Runs teardown work on the dispatcher, and unlike <see cref="Post"/> it still runs while the
    /// app is exiting.
    ///
    /// The distinction matters. Post exists to REFUSE hook-driven work during shutdown, which is how
    /// the app reaches exit at all. But closing a window a feature owns is the opposite case: it has
    /// to happen, and it happens on the UI thread from OnExit - where CheckAccess is true and this
    /// is a direct call. Routing teardown through Post silently skipped it.
    /// </summary>
    public static void RunOnUi(Action work)
    {
        Dispatcher? dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher == null) return;

        try
        {
            if (dispatcher.CheckAccess())
            {
                work();
                return;
            }

            // Bounded, because a feature switched off from a hook thread must not be able to hang
            // waiting on a dispatcher that is already shutting down.
            dispatcher.Invoke(work, DispatcherPriority.Send, System.Threading.CancellationToken.None,
                TimeSpan.FromSeconds(1));
        }
        catch
        {
            // The dispatcher can shut down between the check and the call.
        }
    }

    /// <summary>
    /// Shows the readout centred horizontally on a physical point and just below it.
    /// <paramref name="fraction"/> of null hides the meter bar entirely.
    /// </summary>
    public void Show(string text, int physicalX, int physicalY, int holdMs, double? fraction = null)
    {
        if (AppLifetime.IsExiting) return;

        try
        {
            Build();

            if (_window == null || _label == null) return;

            _label.Text = text;

            if (_meterHost != null)
            {
                _meterHost.Visibility = fraction.HasValue ? Visibility.Visible : Visibility.Collapsed;

                if (fraction.HasValue && _meterFill != null && _meterTrack != null)
                {
                    double clamped = Math.Clamp(fraction.Value, 0, 1);
                    _meterFill.Width = Math.Max(0, _meterTrack.Width * clamped);
                }
            }

            // ALWAYS clear the fade, running or finished. This is unconditional for a reason: a
            // DoubleAnimation defaults to FillBehavior.HoldEnd, so a fade that has COMPLETED still
            // owns OpacityProperty and still holds it at 0 - and an animated value beats a plain
            // assignment, so the line below is silently discarded while it is installed.
            //
            // Clearing it only while a fade was in flight is what made every readout in the app a
            // one-shot: the first Show worked, the fade ran, and from then on the window was shown,
            // placed and timed out completely invisibly. That reads as "the volume wheel broke after
            // one use", which is exactly what it was reported as.
            _window.BeginAnimation(UIElement.OpacityProperty, null);
            _window.Opacity = 1;

            if (!_window.IsVisible) _window.Show();

            // Measure after the content is set, so the placement uses the width this text needs.
            _window.UpdateLayout();

            OverlayPlacement.CentreOn(_window, physicalX, physicalY + 28);
            OverlayPlacement.MakeClickThrough(_window);

            // Build always leaves this wired, but create it with its handler attached rather than
            // bare: a DispatcherTimer with no Tick subscriber never hides the readout, so the
            // overlay would sit on screen for the rest of the session.
            if (_hideTimer == null)
            {
                _hideTimer = new DispatcherTimer();
                _hideTimer.Tick += OnHideTick;
            }

            _hideTimer.Stop();
            _hideTimer.Interval = TimeSpan.FromMilliseconds(Math.Max(50, holdMs));
            _hideTimer.Start();
        }
        catch
        {
            // Cosmetic. Never surface.
        }
    }

    public void Hide()
    {
        try
        {
            _hideTimer?.Stop();

            if (_window != null)
            {
                _window.BeginAnimation(UIElement.OpacityProperty, null);
                _window.Hide();
            }
        }
        catch
        {
        }
    }

    private void Build()
    {
        if (_window != null) return;

        _label = new TextBlock
        {
            Foreground = Brushes.White,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        _meterTrack = new Border
        {
            Width = 160,
            Height = 6,
            CornerRadius = new CornerRadius(3),
            Background = new SolidColorBrush(Color.FromArgb(0x55, 0xFF, 0xFF, 0xFF)),
            HorizontalAlignment = HorizontalAlignment.Left
        };

        _meterFill = new Border
        {
            Width = 0,
            Height = 6,
            CornerRadius = new CornerRadius(3),
            Background = new SolidColorBrush(Color.FromRgb(0x9A, 0xD4, 0xFF)),
            HorizontalAlignment = HorizontalAlignment.Left
        };

        _meterHost = new Grid
        {
            Margin = new Thickness(0, 8, 0, 2),
            HorizontalAlignment = HorizontalAlignment.Center,
            Visibility = Visibility.Collapsed
        };
        _meterHost.Children.Add(_meterTrack);
        _meterHost.Children.Add(_meterFill);

        StackPanel stack = new();
        stack.Children.Add(_label);
        stack.Children.Add(_meterHost);

        Border panel = new()
        {
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(14, 9, 14, 9),
            MinWidth = _minWidth,

            // Opaque enough to read over anything, dark enough not to be a flashbang on a light
            // background. No blur: see the owner's taste in CLAUDE.md.
            Background = new SolidColorBrush(Color.FromArgb(0xE0, 0x1E, 0x1E, 0x1E)),
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF)),
            Child = stack
        };

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
            SizeToContent = SizeToContent.WidthAndHeight,
            Content = panel,

            // Off screen until placed, so it never appears at the wrong coordinate for one frame.
            Left = -10000,
            Top = -10000
        };

        _window.SourceInitialized += (_, _) => OverlayPlacement.MakeClickThrough(_window);

        _hideTimer = new DispatcherTimer();
        _hideTimer.Tick += OnHideTick;
    }

    private void OnHideTick(object? sender, EventArgs e)
    {
        _hideTimer?.Stop();

        if (_window == null) return;

        try
        {
            DoubleAnimation fade = new(_window.Opacity, 0, TimeSpan.FromMilliseconds(220));

            // Hide on completion rather than leaving a fully transparent window mapped: a mapped
            // layered window still costs a redirection surface and still answers WindowFromPoint.
            fade.Completed += (_, _) =>
            {
                try { _window?.Hide(); } catch { }
            };

            // The animation is deliberately left installed here rather than cleared on completion:
            // clearing it reverts Opacity to the base value, which is 1, so the overlay would flash
            // back to fully opaque for a frame before Hide ran. Show clears it instead.
            _window.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        catch
        {
            try { _window.Hide(); } catch { }
        }
    }

    /// <summary>Closes the window. Must be called on the dispatcher.</summary>
    public void Dispose()
    {
        try
        {
            if (_hideTimer != null)
            {
                _hideTimer.Stop();
                _hideTimer.Tick -= OnHideTick;
                _hideTimer = null;
            }

            if (_window != null)
            {
                _window.BeginAnimation(UIElement.OpacityProperty, null);
                _window.Close();
                _window = null;
            }
        }
        catch
        {
        }

        _label = null;
        _meterFill = null;
        _meterTrack = null;
        _meterHost = null;
    }
}
