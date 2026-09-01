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
    private const int MaxRadius = 44;
    private const int DurationMs = 420;

    private readonly NativeMethods.LowLevelMouseProc _proc;
    private IntPtr _hookId = IntPtr.Zero;

    public bool IsEnabled { get; private set; }

    public RippleClickFeature()
    {
        _proc = HookCallback;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            using Process curProcess = Process.GetCurrentProcess();
            using ProcessModule? curModule = curProcess.MainModule;
            if (curModule != null)
            {
                _hookId = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _proc,
                    NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
            }
        }
        else
        {
            if (_hookId != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0 && wParam == (IntPtr)NativeMethods.WM_LBUTTONDOWN)
            {
                NativeMethods.MSLLHOOKSTRUCT data =
                    Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

                int x = data.pt.X;
                int y = data.pt.Y;

                // Never build UI inside the hook itself: it has to return promptly, and the ripple
                // is not urgent. BeginInvoke also puts us on the dispatcher regardless of which
                // thread the hook was delivered on.
                Application.Current?.Dispatcher.BeginInvoke(new Action(() => Spawn(x, y)));
            }
        }
        catch
        {
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private static void Spawn(int screenX, int screenY)
    {
        try
        {
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
                Width = MaxRadius * 2,
                Height = MaxRadius * 2,
                Left = screenX - MaxRadius,
                Top = screenY - MaxRadius,
                Content = ring,
                // Opacity is set before Show() - showing first would put one fully opaque frame on
                // screen before the animation's first tick.
                Opacity = 0.85
            };

            overlay.SourceInitialized += (_, _) =>
            {
                try
                {
                    IntPtr hwnd = new System.Windows.Interop.WindowInteropHelper(overlay).Handle;
                    if (hwnd == IntPtr.Zero) return;

                    uint ex = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
                    NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
                        ex | NativeMethods.WS_EX_TRANSPARENT
                           | NativeMethods.WS_EX_NOACTIVATE
                           | NativeMethods.WS_EX_TOOLWINDOW);
                }
                catch
                {
                }
            };

            Duration duration = new(TimeSpan.FromMilliseconds(DurationMs));
            IEasingFunction ease = new CubicEase { EasingMode = EasingMode.EaseOut };

            DoubleAnimation grow = new(8, MaxRadius * 2, duration) { EasingFunction = ease };
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
