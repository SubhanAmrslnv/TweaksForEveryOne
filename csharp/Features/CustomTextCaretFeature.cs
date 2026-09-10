using System;
using System.Runtime.InteropServices;
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
/// Custom Text Caret Feature (macOS Continuous Smooth Caret Parity).
///
/// Replaces the rigid 1px blinking system caret with a smooth, continuous-breathing,
/// horizontally sliding 2.5px Apple caret indicator driven by AppleSpringEngine.
/// </summary>
public class CustomTextCaretFeature : IDisposable
{
    private Window? _caretWindow;
    private Border? _caretPill;
    private DispatcherTimer? _pollTimer;

    private double _curX, _curY;
    private double _velX, _velY;
    private double _blinkPhase;

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
        if (_caretWindow != null) return;

        _caretPill = new Border
        {
            Width = 2.5,
            Height = 18,
            CornerRadius = new CornerRadius(1.25),
            Background = new SolidColorBrush(Color.FromRgb(0x00, 0x7A, 0xFF)) // Apple Blue Caret
        };

        _caretWindow = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Width = 10,
            Height = 24,
            Content = _caretPill,
            Left = -10000,
            Top = -10000,
            Opacity = 0
        };

        _caretWindow.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_caretWindow);
            IntPtr hwnd = new WindowInteropHelper(_caretWindow).Handle;
            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        };

        _caretWindow.Show();

        _pollTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(15)
        };
        _pollTimer.Tick += OnPollTick;
        _pollTimer.Start();
    }

    private void OnPollTick(object? sender, EventArgs e)
    {
        if (_caretWindow == null || _caretPill == null) return;

        var gui = new NativeMethods.GUITHREADINFO { cbSize = Marshal.SizeOf<NativeMethods.GUITHREADINFO>() };
        if (NativeMethods.GetGUIThreadInfo(0, ref gui) && gui.hwndCaret != IntPtr.Zero)
        {
            var pt = new NativeMethods.POINT { X = gui.rcCaret.Left, Y = gui.rcCaret.Top };
            NativeMethods.ClientToScreen(gui.hwndCaret, ref pt);

            int caretH = Math.Max(14, gui.rcCaret.Bottom - gui.rcCaret.Top);
            _caretPill.Height = caretH;

            AppleSpringEngine.Step(ref _curX, ref _velX, pt.X, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref _curY, ref _velY, pt.Y, 0.015, AppleSpringEngine.SpringConfig.Snappy);

            IntPtr myHwnd = new WindowInteropHelper(_caretWindow).Handle;
            NativeMethods.SetWindowPos(myHwnd, IntPtr.Zero, (int)Math.Round(_curX), (int)Math.Round(_curY), 6, caretH + 2,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_SHOWWINDOW);

            // Breathing blink cycle
            _blinkPhase += 0.12;
            if (_blinkPhase > Math.PI * 2) _blinkPhase -= Math.PI * 2;
            double alpha = 0.25 + (0.75 * (0.5 * (1.0 + Math.Sin(_blinkPhase))));

            _caretWindow.Opacity = alpha;
        }
        else
        {
            _caretWindow.Opacity = 0;
        }
    }

    private void Stop()
    {
        _pollTimer?.Stop();
        _pollTimer = null;

        if (_caretWindow != null)
        {
            try { _caretWindow.Close(); } catch { }
            _caretWindow = null;
        }

        _caretPill = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
