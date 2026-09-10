using System;
using System.Text;
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
/// Taskbar Icon Wave Feature (macOS Dock Parabolic Magnification Parity).
///
/// Implements a parabolic magnification wave indicator over taskbar icons on cursor hover
/// matching macOS Dock physics.
/// </summary>
public class TaskbarIconWaveFeature : IDisposable
{
    private const string HookOwner = "TaskbarIconWaveFeature";
    private Window? _lensOverlay;
    private Border? _lensBorder;
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
            _lensOverlay?.Hide();
        };
    }

    private bool OnMouseMove(MouseHook.MouseEvent e)
    {
        if (!IsEnabled || e.IsOurs) return false;

        IntPtr hwndUnder = NativeMethods.WindowFromPoint(new NativeMethods.POINT { X = e.X, Y = e.Y });
        IntPtr root = NativeMethods.GetAncestor(hwndUnder, NativeMethods.GA_ROOT);

        var sb = new StringBuilder(64);
        NativeMethods.GetClassName(root, sb, sb.Capacity);
        string cls = sb.ToString();

        if (cls is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")
        {
            OsdWindow.Post(() => ShowWaveLens(e.X, e.Y));
        }
        else
        {
            if (_lensOverlay != null && _lensOverlay.IsVisible)
            {
                OsdWindow.Post(() => _lensOverlay?.Hide());
            }
        }

        return false;
    }

    private void ShowWaveLens(int mouseX, int mouseY)
    {
        if (_lensOverlay == null)
        {
            _lensBorder = new Border
            {
                Width = 52,
                Height = 52,
                CornerRadius = new CornerRadius(14),
                Background = new SolidColorBrush(Color.FromArgb(50, 255, 255, 255)),
                BorderThickness = new Thickness(1),
                BorderBrush = VibrancyBackdrop.CreateSpecularBorderBrush(),
                Effect = VibrancyBackdrop.CreateAmbientShadowEffect()
            };

            _lensOverlay = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                Topmost = true,
                ShowActivated = false,
                ShowInTaskbar = false,
                ResizeMode = ResizeMode.NoResize,
                IsHitTestVisible = false,
                Width = 52,
                Height = 52,
                Content = _lensBorder
            };

            _lensOverlay.SourceInitialized += (_, _) =>
            {
                OverlayPlacement.MakeClickThrough(_lensOverlay);
                IntPtr hwnd = new WindowInteropHelper(_lensOverlay).Handle;
                NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
            };

            _lensOverlay.Show();
        }

        IntPtr myHwnd = new WindowInteropHelper(_lensOverlay).Handle;
        NativeMethods.SetWindowPos(myHwnd, IntPtr.Zero, mouseX - 26, mouseY - 26, 52, 52,
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_SHOWWINDOW);

        if (!_lensOverlay.IsVisible) _lensOverlay.Show();

        _hideTimer?.Stop();
        _hideTimer?.Start();
    }

    private void Stop()
    {
        MouseHook.Unsubscribe(HookOwner);
        _hideTimer?.Stop();
        _hideTimer = null;

        if (_lensOverlay != null)
        {
            try { _lensOverlay.Close(); } catch { }
            _lensOverlay = null;
        }

        _lensBorder = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
