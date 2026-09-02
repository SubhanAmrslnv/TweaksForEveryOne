using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using WindowTweaks.Core;
// WPF and WinForms are both referenced (UseWPF + UseWindowsForms), so these names are
// ambiguous under ImplicitUsings. This overlay is pure WPF.
using Application = System.Windows.Application;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace WindowTweaks.Features;

/// <summary>
/// Ripple Click: a soft water-drop ring expands from the cursor on every left click, and fades.
///
/// It is a fade, which is why it survives the project's ban on pulse and neon effects - the ring
/// only ever loses opacity, it never flashes or glows.
///
/// The overlay must never eat the click it is illustrating. Three things guarantee that, and all
/// three are needed: WS_EX_TRANSPARENT (hit-testing passes through), WS_EX_NOACTIVATE (it cannot
/// take focus from the window being clicked) and ShowActivated = false (the click that spawned it
/// is not stolen mid-flight). WS_EX_TOOLWINDOW keeps it out of Alt-Tab.
///
/// The hook is PASS-THROUGH: it never swallows the click.
/// </summary>
public class RippleClickFeature : IDisposable
{
    // Read when a ripple is spawned, so a change to either slider shows on the very next click.

    public bool IsEnabled { get; private set; }

    public RippleClickFeature()
    {
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        // Buttons only. A ripple has nothing to say about a mouse move, and subscribing to moves
        // would call this handler a hundred times a second to return false.
        if (enabled) MouseHook.Subscribe("RippleClickFeature", MouseEvents.Buttons, HookCallback);
        else MouseHook.Unsubscribe("RippleClickFeature");
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool HookCallback(MouseHook.MouseEvent e)
    {
        if (e.Message == NativeMethods.WM_LBUTTONDOWN)
        {
            if (e.IsInjected) return false;

            int x = e.X;
            int y = e.Y;
            Application.Current?.Dispatcher.BeginInvoke(new Action(() => Spawn(x, y)));
        }
        return false;
    }

    private static void Spawn(int screenX, int screenY)
    {
        try
        {
            int maxRadius = TuningRegistry.Int(TuningRegistry.RippleRadius);
            int durationMs = TuningRegistry.Int(TuningRegistry.RippleDurationMs);

            // The radius is a physical pixel count, but WPF lays out in device-independent units, so
            // it has to be divided by the scale of the monitor the click landed on - otherwise the
            // ring is half again too big at 150%. Position is applied separately, in physical
            // pixels, by OverlayPlacement: Window.Left is in WPF units and assigning a hook's
            // coordinates to it puts the ripple in the wrong place on any scaled display.
            double scale = OverlayPlacement.ScaleAt(screenX, screenY);
            double logicalDiameter = maxRadius * 2 / scale;

            Ellipse ring = new()
            {
                Width = 8,
                Height = 8,
                Stroke = new SolidColorBrush(Color.FromRgb(0x9A, 0xD4, 0xFF)),
                StrokeThickness = 2.0,
                Fill = new SolidColorBrush(Color.FromArgb(0x22, 0x9A, 0xD4, 0xFF)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                IsHitTestVisible = false
            };

            Window overlay = new()
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                ShowInTaskbar = false,
                ShowActivated = false,
                Topmost = true,
                ResizeMode = ResizeMode.NoResize,
                IsHitTestVisible = false,
                Width = logicalDiameter,
                Height = logicalDiameter,

                // Off screen until OverlayPlacement puts it where the click was, so it never
                // appears at the wrong coordinate for one frame.
                Left = -10000,
                Top = -10000,
                Content = ring,
                // Opacity is set before Show() - showing first would put one fully opaque frame on
                // screen before the animation's first tick.
                Opacity = 0.85
            };

            overlay.SourceInitialized += (_, _) => OverlayPlacement.MakeClickThrough(overlay);

            Duration duration = new(TimeSpan.FromMilliseconds(durationMs));
            IEasingFunction ease = new CubicEase { EasingMode = EasingMode.EaseOut };

            DoubleAnimation grow = new(8, logicalDiameter, duration) { EasingFunction = ease };
            DoubleAnimation fade = new(0.85, 0.0, duration) { EasingFunction = ease };

            // Closing is driven by the animation that shows it, but the window is not left to the
            // animation alone: Completed always fires, and Close() is idempotent here because
            // nothing else holds a reference.
            fade.Completed += (_, _) =>
            {
                try
                {
                    overlay.Close();
                }
                catch
                {
                }
            };

            overlay.Show();

            // After Show, because the window needs a handle before it can be moved with SetWindowPos.
            OverlayPlacement.CentreOn(overlay, screenX, screenY);

            ring.BeginAnimation(FrameworkElement.WidthProperty, grow);
            ring.BeginAnimation(FrameworkElement.HeightProperty, grow);
            overlay.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        catch
        {
            // A failed ripple is cosmetic. Never let it reach the user as an exception.
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
