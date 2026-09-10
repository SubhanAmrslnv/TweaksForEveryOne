using System;
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
/// Motion Blur Scroll Feature (macOS Kinetic Scroll Parity).
///
/// Injects transient directional micro-blur scrim during high-speed wheel scrolling
/// to visually communicate velocity without impeding content readability.
/// </summary>
public class MotionBlurScrollFeature : IDisposable
{
    private const string HookOwner = "MotionBlurScrollFeature";
    private Window? _blurOverlay;
    private DispatcherTimer? _decayTimer;
    private int _scrollVelocity;

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
        MouseHook.Subscribe(HookOwner, MouseEvents.Wheel, OnWheel);

        _decayTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(25)
        };
        _decayTimer.Tick += OnDecayTick;
    }

    private bool OnWheel(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        _scrollVelocity += Math.Abs(e.WheelDelta);

        if (_scrollVelocity > 240)
        {
            OsdWindow.Post(() => ShowMicroBlur());
        }

        return false; // Don't suppress wheel event
    }

    private void ShowMicroBlur()
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero || !WindowFilter.IsOrdinaryAppWindow(fg)) return;

        if (!NativeMethods.GetWindowRect(fg, out NativeMethods.RECT rect)) return;

        if (_blurOverlay == null)
        {
            _blurOverlay = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255)),
                Topmost = true,
                ShowActivated = false,
                ShowInTaskbar = false,
                ResizeMode = ResizeMode.NoResize,
                IsHitTestVisible = false,
                Opacity = 0
            };

            _blurOverlay.SourceInitialized += (_, _) =>
            {
                OverlayPlacement.MakeClickThrough(_blurOverlay);
                IntPtr hwnd = new WindowInteropHelper(_blurOverlay).Handle;
                NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
            };

            _blurOverlay.Show();
        }

        int w = rect.Right - rect.Left;
        int h = rect.Bottom - rect.Top;
        IntPtr myHwnd = new WindowInteropHelper(_blurOverlay).Handle;
        NativeMethods.SetWindowPos(myHwnd, fg, rect.Left, rect.Top, w, h,
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);

        _blurOverlay.BeginAnimation(UIElement.OpacityProperty,
            new DoubleAnimation(0.20, 0.0, TimeSpan.FromMilliseconds(120)));

        _decayTimer?.Start();
    }

    private void OnDecayTick(object? sender, EventArgs e)
    {
        _scrollVelocity = Math.Max(0, _scrollVelocity - 40);
        if (_scrollVelocity == 0)
        {
            _decayTimer?.Stop();
        }
    }

    private void Stop()
    {
        MouseHook.Unsubscribe(HookOwner);
        _decayTimer?.Stop();
        _decayTimer = null;

        if (_blurOverlay != null)
        {
            try { _blurOverlay.Close(); } catch { }
            _blurOverlay = null;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
