using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace WindowTweaks.Features;

/// <summary>
/// Lightsaber Seam Glow Feature (macOS Dynamic Window Splitter Parity).
///
/// Hovering over the junction between two snapped adjacent windows illuminates
/// a bright, glowing neon splitter line to visually indicate mutual boundary manipulation.
/// </summary>
public class LightsaberSeamGlowFeature : IDisposable
{
    private const string HookOwner = "LightsaberSeamGlowFeature";
    private Window? _splitterOverlay;
    private Border? _glowLine;
    private DispatcherTimer? _hideTimer;

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
        MouseHook.Subscribe(HookOwner, MouseEvents.Move, OnMouseMove);

        _hideTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(200)
        };
        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            _splitterOverlay?.Hide();
        };
    }

    private bool OnMouseMove(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        // Check if pointer is within 4px of foreground window border
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(fg)) return false;

        if (NativeMethods.GetWindowRect(fg, out NativeMethods.RECT r))
        {
            bool nearLeft = Math.Abs(e.X - r.Left) <= 4 && e.Y >= r.Top && e.Y <= r.Bottom;
            bool nearRight = Math.Abs(e.X - r.Right) <= 4 && e.Y >= r.Top && e.Y <= r.Bottom;
            bool nearTop = Math.Abs(e.Y - r.Top) <= 4 && e.X >= r.Left && e.X <= r.Right;
            bool nearBottom = Math.Abs(e.Y - r.Bottom) <= 4 && e.X >= r.Left && e.X <= r.Right;

            if (nearLeft || nearRight)
            {
                int seamX = nearLeft ? r.Left - 1 : r.Right - 1;
                OsdWindow.Post(() => ShowGlow(seamX, r.Top, 3, r.Bottom - r.Top));
            }
            else if (nearTop || nearBottom)
            {
                int seamY = nearTop ? r.Top - 1 : r.Bottom - 1;
                OsdWindow.Post(() => ShowGlow(r.Left, seamY, r.Right - r.Left, 3));
            }
        }

        return false;
    }

    private void ShowGlow(int x, int y, int w, int h)
    {
        if (_splitterOverlay == null)
        {
            _glowLine = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(240, 0, 195, 255)), // Lightsaber Cyan
                Effect = VibrancyBackdrop.CreateKeyShadowEffect()
            };

            _splitterOverlay = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                Topmost = true,
                ShowActivated = false,
                ShowInTaskbar = false,
                ResizeMode = ResizeMode.NoResize,
                IsHitTestVisible = false,
                Content = _glowLine
            };

            _splitterOverlay.SourceInitialized += (_, _) =>
            {
                OverlayPlacement.MakeClickThrough(_splitterOverlay);
                IntPtr hwnd = new WindowInteropHelper(_splitterOverlay).Handle;
                NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
            };

            _splitterOverlay.Show();
        }

        IntPtr myHwnd = new WindowInteropHelper(_splitterOverlay).Handle;
        NativeMethods.SetWindowPos(myHwnd, IntPtr.Zero, x, y, Math.Max(2, w), Math.Max(2, h),
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_SHOWWINDOW);

        if (!_splitterOverlay.IsVisible) _splitterOverlay.Show();

        _hideTimer?.Stop();
        _hideTimer?.Start();
    }

    private void Stop()
    {
        MouseHook.Unsubscribe(HookOwner);
        _hideTimer?.Stop();
        _hideTimer = null;

        if (_splitterOverlay != null)
        {
            try { _splitterOverlay.Close(); } catch { }
            _splitterOverlay = null;
        }

        _glowLine = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
