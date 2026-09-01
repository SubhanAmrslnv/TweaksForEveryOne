using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Interop;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class GravityCloseFeature : IDisposable
{
    private class ActiveGravity
    {
        public IntPtr Hwnd;
        public IntPtr OverlayHwnd;
        public IntPtr ThumbId;
        public int OrigX, OrigY, OrigW, OrigH;
        public CancellationTokenSource Cts = new();
    }

    private ActiveGravity? _currentGravity;

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        System.Text.StringBuilder sbCls = new System.Text.StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbCls, sbCls.Capacity);
        string cls = sbCls.ToString();
        if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd") return;

        if (_currentGravity != null && _currentGravity.Hwnd == hwnd)
            return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
            return;

        int wx = rect.Left;
        int wy = rect.Top;
        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;

        if (ww < 1 || wh < 1)
        {
            NativeMethods.PostMessage(hwnd, NativeMethods.WM_SYSCOMMAND, new IntPtr(NativeMethods.SC_CLOSE), IntPtr.Zero);
            return;
        }

        IntPtr overlayHwnd = CreateOverlayWindow();
        NativeMethods.DwmRegisterThumbnail(overlayHwnd, hwnd, out IntPtr thumb);

        ActiveGravity gravity = new ActiveGravity
        {
            Hwnd = hwnd,
            OverlayHwnd = overlayHwnd,
            ThumbId = thumb,
            OrigX = wx,
            OrigY = wy,
            OrigW = ww,
            OrigH = wh
        };

        _currentGravity = gravity;

        // Hide real window far off-screen
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, -19999, wy, 0, 0,
            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

        Task.Run(() => AnimateGravity(gravity, gravity.Cts.Token));
    }

    private IntPtr CreateOverlayWindow()
    {
        var window = new System.Windows.Window
        {
            WindowStyle = System.Windows.WindowStyle.None,
            AllowsTransparency = true,
            Background = System.Windows.Media.Brushes.Transparent,
            Topmost = true,
            ShowInTaskbar = false,
            Width = 1,
            Height = 1,
            Left = -19999
        };
        window.Show();

        IntPtr hwnd = new WindowInteropHelper(window).Handle;
        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | NativeMethods.WS_EX_TRANSPARENT | 0x80);

        return hwnd;
    }

    private async Task AnimateGravity(ActiveGravity gravity, CancellationToken token)
    {
        long start = Stopwatch.GetTimestamp();
        double ms = 320.0;
        double frequency = Stopwatch.Frequency;

        while (!token.IsCancellationRequested)
        {
            long now = Stopwatch.GetTimestamp();
            double t = (now - start) / (frequency * (ms / 1000.0));

            if (t >= 1.0)
            {
                break;
            }

            double ease = t * t; // Quadratic

            double curW = gravity.OrigW * (1 - ease * 0.95);
            double curH = gravity.OrigH * (1 - ease * 0.95);

            double curX = gravity.OrigX + (gravity.OrigW - curW) / 2;
            double curY = gravity.OrigY + ease * (gravity.OrigH * 0.8) + (gravity.OrigH - curH) / 2;

            if (curW < 1) curW = 1;
            if (curH < 1) curH = 1;

            int alpha = 255;
            if (t > 0.4)
            {
                alpha = (int)Math.Round(255 * (1 - ((t - 0.4) / 0.6)));
                if (alpha < 0) alpha = 0;
                if (alpha > 255) alpha = 255;
            }

            NativeMethods.SetWindowPos(gravity.OverlayHwnd, IntPtr.Zero, (int)Math.Round(curX), (int)Math.Round(curY), (int)Math.Round(curW), (int)Math.Round(curH),
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            NativeMethods.DWM_THUMBNAIL_PROPERTIES props = new NativeMethods.DWM_THUMBNAIL_PROPERTIES
            {
                dwFlags = NativeMethods.DWM_TNP_VISIBLE | NativeMethods.DWM_TNP_RECTDESTINATION | NativeMethods.DWM_TNP_OPACITY | NativeMethods.DWM_TNP_SOURCECLIENTAREAONLY,
                fVisible = true,
                fSourceClientAreaOnly = false,
                opacity = (byte)alpha,
                rcDestination = new NativeMethods.RECT { Left = 0, Top = 0, Right = (int)Math.Round(curW), Bottom = (int)Math.Round(curH) }
            };
            NativeMethods.DwmUpdateThumbnailProperties(gravity.ThumbId, ref props);

            await Task.Delay(15);
        }

        CleanupGravity(gravity, true);
    }

    private void CleanupGravity(ActiveGravity gravity, bool closeWindow)
    {
        NativeMethods.DwmUnregisterThumbnail(gravity.ThumbId);
        NativeMethods.PostMessage(gravity.OverlayHwnd, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);

        if (_currentGravity == gravity)
        {
            _currentGravity = null;
        }

        if (NativeMethods.IsWindow(gravity.Hwnd))
        {
            // Always put it back where it belongs
            NativeMethods.SetWindowPos(gravity.Hwnd, IntPtr.Zero, gravity.OrigX, gravity.OrigY, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            if (closeWindow)
            {
                NativeMethods.PostMessage(gravity.Hwnd, NativeMethods.WM_SYSCOMMAND, new IntPtr(NativeMethods.SC_CLOSE), IntPtr.Zero);
            }
        }
    }

    public void Dispose()
    {
        if (_currentGravity != null)
        {
            _currentGravity.Cts.Cancel();
            CleanupGravity(_currentGravity, false);
        }
    }
}
