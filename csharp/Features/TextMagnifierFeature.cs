using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
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
/// It is also GATED so it does not appear on every left-drag, and horizontal dominance alone is NOT
/// enough of a gate: dragging a window by its title bar moves mostly sideways too, which is why the
/// lens used to open over every window move. Four tests have to agree, and the last three are done
/// on the UI thread because they cost more than a hook callback may spend:
///
///   1. THE DRAG MOVES MOSTLY SIDEWAYS. Free, and rejects scrolling and dragging a file downwards.
///      Once the gesture has declared itself either way it is not reconsidered - a selection that
///      wraps down several lines is still a selection.
///
///   2. THE PRESS LANDED IN A CLIENT AREA. WM_NCHITTEST at the press point: a caption, a border or a
///      scrollbar is never text, and the caption is the window drag this gate exists to reject.
///      Cross-process, so it goes through SendMessageTimeout with SMTO_ABORTIFHUNG.
///
///   3. THE TARGET CHOSE A TEXT CURSOR. Applications with a custom frame (browsers, Electron apps)
///      answer HTCLIENT for their tab strip, so the hit test alone still lets a window drag through.
///      Over text the cursor is an I-beam; over a tab strip, a toolbar or empty client space it is
///      the plain arrow. A cursor the application supplied itself is allowed through, and test 4
///      catches it if it turns out to have been a drag.
///
///   4. THE WINDOW UNDER THE PRESS DID NOT MOVE. Checked every tick while the lens is open, because
///      nothing measured at press time can rule out a frame the application drags itself. If it
///      moves, the lens closes and stays closed for the rest of the press.
/// </summary>
public class TextMagnifierFeature : IDisposable
{
    private const string HookOwner = nameof(TextMagnifierFeature);

    /// <summary>The lens size in physical pixels. The source box it magnifies is this over the zoom.</summary>
    private const int LensPx = 220;

    /// <summary>How long the target gets to answer WM_NCHITTEST before it is treated as hung.</summary>
    private const uint ProbeTimeoutMs = 40;

    private bool _pressed;
    private bool _active;
    private int _startX;
    private int _startY;

    // The top-level window the press landed on, and where it was at that moment. Test 4 above.
    private IntPtr _target;
    private NativeMethods.RECT _targetRect;

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
            _target = IntPtr.Zero;
            MouseHook.Subscribe(HookOwner, MouseEvents.Buttons | MouseEvents.Move, OnMouse);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            _pressed = false;
            _active = false;
            _target = IntPtr.Zero;
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

                // Test 1 only, and it is the free one. The hook thread may not run the others: a
                // low-level hook holds up every input event in the OS until it returns, and the hit
                // test is a cross-process SendMessage. Start() finishes the decision.
                // Once the gesture has declared itself either way, stop reconsidering it - a
                // selection that later wraps down several lines is still a selection.
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

        // Tests 2 and 3. Rejecting here gives up on the whole press, so a window drag cannot re-arm
        // the lens by wobbling the cursor.
        if (!LooksLikeTextSelection())
        {
            _active = false;
            _pressed = false;
            return;
        }

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

    /// <summary>
    /// Answers "was the press that started this drag a press on text" - tests 2 and 3 in the class
    /// comment. Also records the window the press landed on, which is what test 4 watches.
    /// </summary>
    private bool LooksLikeTextSelection()
    {
        _target = IntPtr.Zero;

        try
        {
            NativeMethods.POINT pt = new() { X = _startX, Y = _startY };

            IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
            if (hwnd == IntPtr.Zero) return false;

            // Never our own windows: the lens is click-through, but the settings window is not.
            NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == (uint)Environment.ProcessId) return false;

            IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
            if (root != IntPtr.Zero && NativeMethods.IsWindow(root) &&
                NativeMethods.GetWindowRect(root, out NativeMethods.RECT rect))
            {
                _target = root;
                _targetRect = rect;
            }

            // Test 2. A window that does not answer in time has told us nothing either way, so the
            // decision passes to the cursor rather than turning a busy window into a rejection.
            IntPtr lParam = (IntPtr)(((_startY & 0xFFFF) << 16) | (_startX & 0xFFFF));

            IntPtr sent = NativeMethods.SendMessageTimeout(
                hwnd, NativeMethods.WM_NCHITTEST, IntPtr.Zero, lParam,
                NativeMethods.SMTO_ABORTIFHUNG, ProbeTimeoutMs, out IntPtr area);

            if (sent != IntPtr.Zero && area.ToInt64() != NativeMethods.HTCLIENT) return false;

            // Test 3. System cursor handles are shared, so identifying one is a handle comparison
            // and not a bitmap inspection.
            NativeMethods.CURSORINFO ci = new() { cbSize = Marshal.SizeOf<NativeMethods.CURSORINFO>() };
            if (!NativeMethods.GetCursorInfo(ref ci) || ci.hCursor == IntPtr.Zero) return false;

            if (ci.hCursor == NativeMethods.LoadCursor(IntPtr.Zero, NativeMethods.IDC_IBEAM)) return true;
            if (ci.hCursor == NativeMethods.LoadCursor(IntPtr.Zero, NativeMethods.IDC_ARROW)) return false;
            if (ci.hCursor == NativeMethods.LoadCursor(IntPtr.Zero, NativeMethods.IDC_SIZEALL)) return false;

            // A cursor the application supplied itself. Editors ship their own I-beam, so refusing
            // here would switch the lens off in the applications it is most wanted in.
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Test 4: the window under the press has moved, so this was a drag of a frame the application
    /// draws itself - a browser tab strip, an Electron title bar - and not a text selection.
    /// </summary>
    private bool TargetMoved()
    {
        if (_target == IntPtr.Zero) return false;

        try
        {
            if (!NativeMethods.IsWindow(_target)) return true;
            if (!NativeMethods.GetWindowRect(_target, out NativeMethods.RECT now)) return false;

            return now.Left != _targetRect.Left || now.Top != _targetRect.Top;
        }
        catch
        {
            return false;
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

        // Build() is reached again if a previous attempt threw partway - Start() swallows the
        // exception and the next drag calls in here with _window still null. Releasing whatever the
        // failed attempt managed to create first is what stops that leaking a GDI bitmap and device
        // context per drag.
        ReleaseCaptureBuffers();

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
            // A modest radius, NOT a circle. A large CornerRadius rounds the border's own stroke but
            // does not clip the child - ClipToBounds clips to the rectangle, not to the radius - so
            // asking for a circle produced a square image inside a round outline. Clipping to an
            // ellipse would need a geometry rebuilt on every DPI change, for no gain: what the lens
            // is for is reading the text, and a rectangle shows more of the line than a circle does.
            CornerRadius = new CornerRadius(10),
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

        if (TargetMoved())
        {
            // Give up on the whole press, not just this frame: the window is on the move and every
            // later frame would reach the same answer.
            _active = false;
            _pressed = false;
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

        // Only assigned when it actually changes - which is when the lens crosses onto a monitor with
        // a different scale factor. Writing Width and Height invalidates WPF layout, so assigning
        // the same value 25 times a second bought a full measure-and-arrange pass per frame for a
        // window whose size had not moved.
        double scale = OverlayPlacement.ScaleAt(pt.X, pt.Y);
        double logical = LensPx / scale;

        if (_window.Width != logical)
        {
            _window.Width = logical;
            _window.Height = logical;
        }

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
        }
        catch
        {
        }

        ReleaseCaptureBuffers();
    }

    /// <summary>
    /// Releases the reused GDI capture bitmap and its device context. Separate from TearDown because
    /// Build() also needs it, to clean up after an attempt that failed halfway.
    /// </summary>
    private void ReleaseCaptureBuffers()
    {
        try
        {
            _captureGraphics?.Dispose();
        }
        catch
        {
        }

        try
        {
            _capture?.Dispose();
        }
        catch
        {
        }

        _captureGraphics = null;
        _capture = null;
        _surface = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
