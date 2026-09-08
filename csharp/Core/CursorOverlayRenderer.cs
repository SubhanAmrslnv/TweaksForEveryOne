using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Application = System.Windows.Application;
using Brushes = System.Windows.Media.Brushes;
using WpfImage = System.Windows.Controls.Image;

namespace WindowTweaks.Core;

/// <summary>
/// High-performance, low-overhead overlay renderer for macOS-style cursor micro-animations.
///
/// Key Architectural Invariants:
/// 1. Hotspot Pinning: Scaling expands radially outward from the physical pointer coordinate,
///    preserving 100% click accuracy (e.g. arrow tip stays pinned at physical mouse X, Y).
/// 2. Zero Trails & Dirty Rect Isolation: Sizing the layered overlay window strictly to the
///    cursor bounds restricts DWM composition strictly to that dirty rect without screen-wide redraws.
/// 3. Zero Injected Lag & Click-Through: Uses WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
///    and WDA_EXCLUDEFROMCAPTURE to guarantee zero input interference and invisibility to screen capture.
/// 4. Native Coordination: Checks GetCursorInfo on every frame. If the OS or an application hides
///    the cursor (e.g. typing or full-screen video), the overlay immediately hides itself.
/// 5. Resource Cleanliness: Always calls DeleteObject on GDI bitmaps returned by GetIconInfo.
/// 6. Resting State Bypass: When CurrentScale &lt;= 1.0005, the overlay is hidden and hardware
///    cursor plane handles 100% of rendering with zero GPU/DWM overhead.
/// </summary>
public sealed class CursorOverlayRenderer : IDisposable
{
    private static readonly Lazy<CursorOverlayRenderer> SharedInstance = new(() => new CursorOverlayRenderer());
    public static CursorOverlayRenderer Instance => SharedInstance.Value;

    private readonly Dispatcher _dispatcher;
    private Window? _window;
    private WpfImage? _image;
    private IntPtr _hwnd = IntPtr.Zero;

    private IntPtr _cachedHCursor = IntPtr.Zero;
    private BitmapSource? _cachedBitmap;
    private int _cachedHotspotX;
    private int _cachedHotspotY;
    private int _cachedBaseWidth = 32;
    private int _cachedBaseHeight = 32;

    private bool _isVisible;
    private bool _disposed;

    public bool IsEnabled { get; private set; }

    public CursorOverlayRenderer()
    {
        _dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
    }

    public void SetEnabled(bool enabled)
    {
        if (_disposed) return;
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            EnsureWindowCreated();
            CursorMotionModel.Instance.MotionUpdated += OnMotionUpdated;
        }
        else
        {
            CursorMotionModel.Instance.MotionUpdated -= OnMotionUpdated;
            HideOverlay();
        }
    }

    private void EnsureWindowCreated()
    {
        if (_window != null) return;

        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.Invoke(EnsureWindowCreated);
            return;
        }

        _image = new WpfImage
        {
            Stretch = Stretch.Fill,
            IsHitTestVisible = false
        };
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);

        _window = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            Content = _image,
            Opacity = 1.0,
            Width = 32,
            Height = 32,
            Left = -10000,
            Top = -10000,
            Visibility = Visibility.Hidden
        };

        _window.SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(_window).Handle;
            if (_hwnd != IntPtr.Zero)
            {
                OverlayPlacement.MakeClickThrough(_window);
                try
                {
                    NativeMethods.SetWindowDisplayAffinity(_hwnd, NativeMethods.WDA_EXCLUDEFROMCAPTURE);
                }
                catch
                {
                }
            }
        };

        _window.Show();
    }

    private void OnMotionUpdated(double scale, double speed, int physicalX, int physicalY, CursorMotionState state)
    {
        if (!IsEnabled || _disposed)
        {
            HideOverlay();
            return;
        }

        // Dormant, Suspended, or resting scale: let the hardware cursor handle rendering with 0 overhead
        if (state == CursorMotionState.Suspended || scale <= 1.0005)
        {
            HideOverlay();
            return;
        }

        // Hardware Cursor Check: If cursor is hidden by another app or OS, hide overlay
        NativeMethods.CURSORINFO ci = new() { cbSize = Marshal.SizeOf<NativeMethods.CURSORINFO>() };
        if (!NativeMethods.GetCursorInfo(ref ci))
        {
            HideOverlay();
            return;
        }

        bool isShowing = (ci.flags & NativeMethods.CURSOR_SHOWING) != 0 && (ci.flags & NativeMethods.CURSOR_SUPPRESSED) == 0;
        if (!isShowing || ci.hCursor == IntPtr.Zero)
        {
            HideOverlay();
            return;
        }

        // Update cached cursor bitmap and hotspot if hCursor changed
        if (ci.hCursor != _cachedHCursor || _cachedBitmap == null)
        {
            if (!UpdateCursorCache(ci.hCursor))
            {
                HideOverlay();
                return;
            }
        }

        if (_cachedBitmap == null || _window == null || _image == null)
        {
            HideOverlay();
            return;
        }

        // Per-Monitor V2 DPI Scaling
        double dpiScale = OverlayPlacement.ScaleAt(physicalX, physicalY);
        if (dpiScale <= 0.0) dpiScale = 1.0;

        // Scaled physical dimensions
        double widthPhys = _cachedBaseWidth * scale;
        double heightPhys = _cachedBaseHeight * scale;

        // Hotspot Pinning Math:
        // Scaled hotspot expands outward from unscaled hotspot,
        // so top-left screen coordinate must shift by hotspot * scale.
        double hotspotPhysX = _cachedHotspotX * scale;
        double hotspotPhysY = _cachedHotspotY * scale;

        int screenX = (int)Math.Round(physicalX - hotspotPhysX);
        int screenY = (int)Math.Round(physicalY - hotspotPhysY);
        int intW = Math.Max(1, (int)Math.Round(widthPhys));
        int intH = Math.Max(1, (int)Math.Round(heightPhys));

        // Sync logical WPF units
        _window.Width = widthPhys / dpiScale;
        _window.Height = heightPhys / dpiScale;

        if (_image.Source != _cachedBitmap)
        {
            _image.Source = _cachedBitmap;
        }

        if (_hwnd != IntPtr.Zero)
        {
            NativeMethods.SetWindowPos(
                _hwnd,
                NativeMethods.HWND_TOPMOST,
                screenX,
                screenY,
                intW,
                intH,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
            _isVisible = true;
        }
        else
        {
            _window.Visibility = Visibility.Visible;
            _isVisible = true;
        }
    }

    private bool UpdateCursorCache(IntPtr hCursor)
    {
        try
        {
            if (!NativeMethods.GetIconInfo(hCursor, out NativeMethods.ICONINFO ii))
            {
                return false;
            }

            _cachedHotspotX = ii.xHotspot;
            _cachedHotspotY = ii.yHotspot;

            // Free GDI objects immediately to prevent resource leaks
            if (ii.hbmMask != IntPtr.Zero) NativeMethods.DeleteObject(ii.hbmMask);
            if (ii.hbmColor != IntPtr.Zero) NativeMethods.DeleteObject(ii.hbmColor);

            BitmapSource bmp = Imaging.CreateBitmapSourceFromHIcon(
                hCursor,
                Int32Rect.Empty,
                BitmapSizeOptions.FromEmptyOptions());

            bmp.Freeze();

            _cachedBitmap = bmp;
            _cachedBaseWidth = Math.Max(16, bmp.PixelWidth);
            _cachedBaseHeight = Math.Max(16, bmp.PixelHeight);
            _cachedHCursor = hCursor;
            return true;
        }
        catch
        {
            _cachedHCursor = IntPtr.Zero;
            _cachedBitmap = null;
            return false;
        }
    }

    public void HideOverlay()
    {
        if (!_isVisible) return;
        _isVisible = false;

        if (_hwnd != IntPtr.Zero)
        {
            NativeMethods.SetWindowPos(
                _hwnd,
                IntPtr.Zero,
                0, 0, 0, 0,
                NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_HIDEWINDOW);
        }
        else if (_window != null)
        {
            _window.Visibility = Visibility.Hidden;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        SetEnabled(false);

        if (_window != null)
        {
            try
            {
                _window.Close();
            }
            catch
            {
            }
            _window = null;
        }
    }
}
