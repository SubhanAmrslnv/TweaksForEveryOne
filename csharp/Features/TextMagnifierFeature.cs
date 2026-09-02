using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Image = System.Windows.Controls.Image;
using PixelFormat = System.Drawing.Imaging.PixelFormat;

namespace WindowTweaks.Features;

/// <summary>
/// A lens that follows the cursor while text is being selected, so small type can be read while it
/// is being dragged over.
///
/// WHY IT DID NOT APPEAR, which was three separate faults stacked on each other:
///
///   1. IT WAS PLACED IN WPF UNITS FROM PHYSICAL COORDINATES. Same bug as the cursor locator: at
///      150% scaling the lens went to two thirds of the cursor's position, and near the top-left of
///      the screen it went off screen entirely. Placement is now physical, via OverlayPlacement.
///
///   2. IT CAPTURED ITSELF. The lens sat 120 px up and to the left of the cursor while capturing a
///      100 px box AROUND the cursor, so the two overlapped and the lens showed a recursive picture
///      of itself. SetWindowDisplayAffinity with WDA_EXCLUDEFROMCAPTURE takes the window out of
///      screen capture entirely, which is the only clean answer.
///
///   3. IT WAS EXPENSIVE ENOUGH TO BE PART OF THE "EVERYTHING LAGS" REPORT. Every 30 ms it allocated
///      a Bitmap, a Graphics, an HBITMAP and a new BitmapSource, on the UI thread, and did that for
///      the whole duration of a drag. All four are now created once and reused: the capture goes
///      into one Bitmap and is copied into one WriteableBitmap.
///
/// It is also GATED so it does not appear on every left-drag. A drag that moves mostly sideways is a
/// text selection; a drag that moves mostly vertically is a scroll, a window move or dragging a file.
/// Requiring horizontal dominance keeps the lens out of the way of all three without needing to know
/// what is under the cursor.
/// </summary>
public class TextMagnifierFeature : IDisposable
{
    private const string HookOwner = nameof(TextMagnifierFeature);

    /// <summary>The lens diameter in physical pixels, and the source box it magnifies.</summary>
    private const int LensPx = 220;

    private bool _pressed;
    private bool _active;
    private int _startX;
    private int _startY;

    private Window? _window;
    private Image? _image;
    private DispatcherTimer? _timer;

    // Created once per session and reused every frame. See fault 3 above.
    private Bitmap? _capture;
    private Graphics? _captureGraphics;
    private WriteableBitmap? _surface;
    private int _sourcePx;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            _pressed = false;
            _active = false;
            MouseHook.Subscribe(HookOwner, MouseEvents.Buttons | MouseEvents.Move, OnMouse);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            _pressed = false;
            _active = false;
            OsdWindow.RunOnUi(TearDown);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        if (e.IsOurs) return false;

        switch (e.Message)
        {
            case NativeMethods.WM_LBUTTONDOWN:
                _pressed = true;
                _active = false;
                _startX = e.X;
                _startY = e.Y;
                return false;

            case NativeMethods.WM_LBUTTONUP:
                _pressed = false;
                if (_active)
                {
                    _active = false;
                    OsdWindow.Post(Stop);
                }
                return false;

            case NativeMethods.WM_MOUSEMOVE:
                if (!_pressed || _active) return false;

                int dx = Math.Abs(e.X - _startX);
                int dy = Math.Abs(e.Y - _startY);

                int threshold = TuningRegistry.Int(TuningRegistry.MagnifierDragThreshold);
                if (dx < threshold && dy < threshold) return false;

                // Horizontal dominance: a selection sweeps sideways, a scroll or a window drag does
                // not. Once the gesture has declared itself either way, stop reconsidering it -
                // a selection that later wraps down several lines is still a selection.
                if (dx <= dy)
                {
                    // Committed to "not a selection" for the rest of this press.
                    _pressed = false;
                    return false;
                }

                _active = true;
                OsdWindow.Post(Start);
                return false;

            default:
                return false;
        }
    }

    private void Start()
    {
        if (!IsEnabled || !_active) return;

        try
        {
            Build();

            if (_window == null || _timer == null) return;

            if (!_window.IsVisible) _window.Show();

            // First frame before the timer, so the lens is never shown empty.
            Refresh();
            _timer.Start();
        }
        catch
        {
        }
    }

    private void Stop()
    {
        try
        {
            _timer?.Stop();
            _window?.Hide();
        }
        catch
        {
        }
    }

    private void Build()
    {
        if (_window != null) return;

        int zoom = Math.Max(2, TuningRegistry.Int(TuningRegistry.MagnifierZoom));
        _sourcePx = Math.Max(16, LensPx / zoom);

        _capture = new Bitmap(_sourcePx, _sourcePx, PixelFormat.Format32bppRgb);
        _captureGraphics = Graphics.FromImage(_capture);
        _surface = new WriteableBitmap(_sourcePx, _sourcePx, 96, 96, PixelFormats.Bgr32, null);

        _image = new Image
        {
            Source = _surface,
            Stretch = Stretch.Fill,

            // Point sampling would show hard pixel blocks; the lens is for READING, so the
            // interpolated version is the useful one.
            SnapsToDevicePixels = false
        };

        Border frame = new()
        {
            CornerRadius = new CornerRadius(LensPx),
            BorderThickness = new Thickness(2),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0xB0, 0xFF, 0xFF, 0xFF)),
            Background = Brushes.Black,
            Child = _image,
            ClipToBounds = true
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
            Content = frame,
            Left = -10000,
            Top = -10000
        };

        _window.SourceInitialized += (_, _) =>
        {
            OverlayPlacement.MakeClickThrough(_window);
            ExcludeFromCapture();
        };

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        _timer.Tick += OnTick;
    }

    /// <summary>
    /// Takes the lens out of screen capture, so it cannot photograph itself. Without this the lens
    /// has to be kept clear of the box it is magnifying, which is impossible near a screen edge.
    /// </summary>
    private void ExcludeFromCapture()
    {
        try
        {
            IntPtr hwnd = new System.Windows.Interop.WindowInteropHelper(_window).Handle;
            if (hwnd == IntPtr.Zero) return;

            NativeMethods.SetWindowDisplayAffinity(hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
        }
        catch
        {
            // Pre-2004 builds do not have it. The lens then shows a copy of itself when it overlaps
            // the source box, which is ugly but not broken.
        }
    }

    private void OnTick(object? sender, EventArgs e)
    {
        // The flag test lives inside the tick, not only at the call site: switching the feature off
        // must be able to stop the timer that a disabled feature would otherwise keep running.
        if (!IsEnabled || !_active)
        {
            Stop();
            return;
        }

        try
        {
            Refresh();
        }
        catch
        {
            // An exception escaping a timer callback kills the timer, and the lens would be frozen
            // for the rest of the session with no visible cause.
        }
    }

    private void Refresh()
    {
        if (_window == null || _capture == null || _captureGraphics == null || _surface == null) return;

        if (!NativeMethods.GetCursorPos(out NativeMethods.POINT pt)) return;

        double scale = OverlayPlacement.ScaleAt(pt.X, pt.Y);
        _window.Width = LensPx / scale;
        _window.Height = LensPx / scale;

        // Above the cursor, clear of the line being selected. The lens is excluded from capture, so
        // the only reason for the offset is to not cover the text the user is reading.
        OverlayPlacement.MoveTo(_window, pt.X - LensPx / 2, pt.Y - LensPx - 24);

        _captureGraphics.CopyFromScreen(
            pt.X - _sourcePx / 2, pt.Y - _sourcePx / 2, 0, 0,
            new System.Drawing.Size(_sourcePx, _sourcePx),
            CopyPixelOperation.SourceCopy);

        // Straight from the GDI bitmap's bits into the WriteableBitmap's back buffer: no HBITMAP, no
        // new BitmapSource, nothing allocated per frame.
        BitmapData data = _capture.LockBits(
            new Rectangle(0, 0, _sourcePx, _sourcePx), ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);

        try
        {
            _surface.WritePixels(
                new Int32Rect(0, 0, _sourcePx, _sourcePx),
                data.Scan0, data.Stride * _sourcePx, data.Stride);
        }
        finally
        {
            _capture.UnlockBits(data);
        }
    }

    private void TearDown()
    {
        try
        {
            if (_timer != null)
            {
                _timer.Stop();
                _timer.Tick -= OnTick;
                _timer = null;
            }

            _window?.Close();
            _window = null;
            _image = null;
            _surface = null;

            _captureGraphics?.Dispose();
            _captureGraphics = null;

            _capture?.Dispose();
            _capture = null;
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
