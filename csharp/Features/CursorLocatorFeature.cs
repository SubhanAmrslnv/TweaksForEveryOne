using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace WindowTweaks.Features;

/// <summary>
/// Shake the mouse to find the pointer: two rings converge on the cursor and fade.
///
/// TWO THINGS MADE THE FIRST VERSION LOOK BROKEN, and they are worth separating because they present
/// identically as "nothing happens":
///
///   1. THE RINGS WERE PLACED IN THE WRONG COORDINATE SPACE. The window's Left and Top were assigned
///      the hook's PHYSICAL pixels, but Window.Left is in WPF units. At 150% scaling the rings
///      appeared two thirds of the way towards the top-left corner of the screen - so on a scaled
///      laptop panel, which is the normal case, the feature was invisible wherever you actually
///      were. Placement now goes through OverlayPlacement, in physical pixels.
///
///   2. THE SHAKE WAS TOO HARD TO PERFORM. It wanted more than five direction reversals, each within
///      300 ms of the last, and any slower reversal reset the count to one - so an ordinary
///      side-to-side shake, which reverses three or four times, never qualified. Detection is now
///      a distance-over-time test: how far the pointer has TRAVELLED against how far it has actually
///      GONE. A shake covers a lot of distance and ends up where it started; crossing the screen to
///      click something covers the same distance in a straight line. The ratio separates them, and
///      it does not care how many reversals a particular hand happens to make.
/// </summary>
public class CursorLocatorFeature : IDisposable
{
    private const string HookOwner = nameof(CursorLocatorFeature);

    /// <summary>How long a window of movement is judged over.</summary>
    private const double WindowMs = 500.0;

    /// <summary>Ignore a reading closer than this: sub-pixel jitter is not travel.</summary>
    private const int MinStepPx = 3;

    /// <summary>After firing, stay quiet this long, or one shake fires three times.</summary>
    private const double CooldownMs = 1200.0;

    /// <summary>How often the rings are re-centred on the pointer while they converge.</summary>
    /// <remarks>
    /// 15 ms, not 16: Windows' clock tick is ~15.6 ms, so a 16 ms deadline always lands just past
    /// one and waits for the next.
    /// </remarks>
    private const int FollowIntervalMs = 15;

    private Window? _window;
    private Ellipse? _outerRing;
    private Ellipse? _innerRing;

    /// <summary>Re-centres the overlay on the pointer for as long as the reveal is playing.</summary>
    private DispatcherTimer? _follow;

    /// <summary>The point the overlay was last moved to, so an unmoved pointer costs no SetWindowPos.</summary>
    private int _followX = int.MinValue;
    private int _followY = int.MinValue;

    private int _lastX = int.MinValue;
    private int _lastY = int.MinValue;

    /// <summary>Total path length in the current window, and the window's start point and time.</summary>
    private double _travelled;
    private int _windowStartX;
    private int _windowStartY;
    private long _windowStart;
    private long _quietUntil;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            ResetTracking();

            // Moves only. This is the one feature that genuinely needs every move event, which is
            // also why its handler does nothing but arithmetic.
            MouseHook.Subscribe(HookOwner, MouseEvents.Move, OnMouse);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            OsdWindow.RunOnUi(TearDown);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void ResetTracking()
    {
        _lastX = int.MinValue;
        _lastY = int.MinValue;
        _travelled = 0;
        _windowStart = 0;
    }

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        // A shake is a hand gesture. Synthetic movement - a remote session, an accessibility tool,
        // this app's own grab and pan - must not be able to trigger it.
        if (e.IsInjected) return false;

        long now = Stopwatch.GetTimestamp();
        double ticksPerMs = Stopwatch.Frequency / 1000.0;

        if (_lastX == int.MinValue)
        {
            StartWindow(e.X, e.Y, now);
            return false;
        }

        int dx = e.X - _lastX;
        int dy = e.Y - _lastY;

        _lastX = e.X;
        _lastY = e.Y;

        double step = Math.Sqrt((double)dx * dx + (double)dy * dy);
        if (step < MinStepPx) return false;

        _travelled += step;

        double elapsedMs = (now - _windowStart) / ticksPerMs;
        if (elapsedMs < WindowMs) return false;

        // The window is up: judge it, then start the next one from here.
        double netX = e.X - _windowStartX;
        double netY = e.Y - _windowStartY;
        double net = Math.Sqrt(netX * netX + netY * netY);

        double travelled = _travelled;
        StartWindow(e.X, e.Y, now);

        if (now < _quietUntil) return false;

        int minTravel = TuningRegistry.Int(TuningRegistry.LocatorShakeDistance);
        double minRatio = TuningRegistry.Int(TuningRegistry.LocatorShakeRatio) / 10.0;

        // Enough distance covered, and it went nowhere. Net of zero is a shake in place, so guard
        // the division rather than the ratio.
        if (travelled < minTravel) return false;
        if (net > 1 && travelled / net < minRatio) return false;

        _quietUntil = now + (long)(CooldownMs * ticksPerMs);

        int x = e.X;
        int y = e.Y;
        OsdWindow.Post(() => Reveal(x, y));

        return false;
    }

    private void StartWindow(int x, int y, long now)
    {
        _lastX = x;
        _lastY = y;
        _windowStartX = x;
        _windowStartY = y;
        _windowStart = now;
        _travelled = 0;
    }

    /// <summary>
    /// Two rings collapsing onto the cursor. A converging ring points AT something; an expanding one
    /// (the ripple-click gesture) reads as "something happened here", which is the wrong sentence for
    /// "your pointer is here".
    /// </summary>
    private void Reveal(int physicalX, int physicalY)
    {
        if (!IsEnabled) return;

        try
        {
            int diameter = TuningRegistry.Int(TuningRegistry.LocatorRingSize);
            double scale = OverlayPlacement.ScaleAt(physicalX, physicalY);

            if (_window == null)
            {
                _outerRing = NewRing(3.0);
                _innerRing = NewRing(2.0);

                Grid host = new();
                host.Children.Add(_outerRing);
                host.Children.Add(_innerRing);

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
                    Content = host,
                    Opacity = 0,
                    Left = -10000,
                    Top = -10000
                };

                _window.SourceInitialized += (_, _) => OverlayPlacement.MakeClickThrough(_window);
            }

            if (_outerRing == null || _innerRing == null) return;

            // The window is sized in WPF units, so a physical diameter has to be divided by the
            // scale of the monitor it is landing on.
            double logical = diameter / scale;

            _window.Width = logical;
            _window.Height = logical;

            if (!_window.IsVisible) _window.Show();

            _followX = physicalX;
            _followY = physicalY;
            OverlayPlacement.CentreOn(_window, physicalX, physicalY);
            OverlayPlacement.MakeClickThrough(_window);

            // The rings converge on the POINTER, not on the spot the shake happened to end at.
            // A hand that shakes the mouse rarely stops dead, so rings pinned to the trigger
            // point drift away from the thing they are pointing at - which is the one job this
            // feature has. Following keeps them under the cursor for the whole 700 ms.
            StartFollowing();

            Duration duration = new(TimeSpan.FromMilliseconds(700));
            IEasingFunction ease = new QuarticEase { EasingMode = EasingMode.EaseOut };

            Animate(_outerRing, logical, logical * 0.12, duration, ease);
            Animate(_innerRing, logical * 0.6, logical * 0.06, duration, ease);

            DoubleAnimation fade = new(0.95, 0.0, duration) { EasingFunction = ease };
            fade.Completed += (_, _) =>
            {
                try
                {
                    if (_window != null && _window.Opacity <= 0.01)
                    {
                        StopFollowing();
                        _window.Hide();
                    }
                }
                catch { }
            };

            _window.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        catch
        {
            // Cosmetic.
        }
    }

    /// <summary>
    /// Starts (or restarts) the timer that keeps the overlay under the pointer. It runs on the UI
    /// thread - never on the hook thread - and only for the length of one reveal, because a timer
    /// left running would poll the cursor for the whole session to move nothing.
    /// </summary>
    private void StartFollowing()
    {
        _follow ??= new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(FollowIntervalMs)
        };

        _follow.Tick -= OnFollowTick;
        _follow.Tick += OnFollowTick;
        _follow.Start();
    }

    private void StopFollowing()
    {
        try { _follow?.Stop(); } catch { }
    }

    /// <summary>
    /// A throw here would kill the timer and leave the rings stranded wherever they were for the
    /// rest of the session, so every path out of it is guarded.
    /// </summary>
    private void OnFollowTick(object? sender, EventArgs e)
    {
        try
        {
            if (!IsEnabled || _window == null || !_window.IsVisible)
            {
                StopFollowing();
                return;
            }

            if (!NativeMethods.GetCursorPos(out NativeMethods.POINT pt)) return;

            // SetWindowPos on a real window is ~260 us; a pointer that has not moved buys nothing
            // by paying it sixty-six times a second.
            if (pt.X == _followX && pt.Y == _followY) return;

            _followX = pt.X;
            _followY = pt.Y;
            OverlayPlacement.CentreOn(_window, pt.X, pt.Y);
        }
        catch
        {
            StopFollowing();
        }
    }

    private static Ellipse NewRing(double thickness)
    {
        return new Ellipse
        {
            Stroke = new SolidColorBrush(Color.FromRgb(0x9A, 0xD4, 0xFF)),
            StrokeThickness = thickness,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false
        };
    }

    private static void Animate(Ellipse ring, double from, double to, Duration duration, IEasingFunction ease)
    {
        DoubleAnimation shrink = new(from, to, duration) { EasingFunction = ease };
        ring.BeginAnimation(FrameworkElement.WidthProperty, shrink);
        ring.BeginAnimation(FrameworkElement.HeightProperty, shrink);
    }

    private void TearDown()
    {
        try
        {
            if (_follow != null)
            {
                _follow.Stop();
                _follow.Tick -= OnFollowTick;
                _follow = null;
            }
        }
        catch
        {
        }

        try
        {
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

        _outerRing = null;
        _innerRing = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
