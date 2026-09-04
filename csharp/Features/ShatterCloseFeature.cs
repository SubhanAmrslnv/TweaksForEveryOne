using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Interop;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class ShatterCloseFeature : IDisposable
{
    private class Shard
    {
        public IntPtr ThumbId;
        public double X, Y;
        public double W, H;
        public double SrcX, SrcY;
        public double Vx, Vy;
        public double SpinW, SpinH;
    }

    private class ActiveShatter
    {
        public IntPtr Hwnd;
        public IntPtr OverlayHwnd;
        public int OrigX, OrigY;
        public List<Shard> Shards = new();
        public CancellationTokenSource Cts = new();
    }

    private readonly Dictionary<IntPtr, ActiveShatter> _activeShatters = new();

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        // Ensure we don't shatter the desktop or taskbar
        System.Text.StringBuilder sbCls = new System.Text.StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbCls, sbCls.Capacity);
        string cls = sbCls.ToString();
        if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd") return;

        if (_activeShatters.ContainsKey(hwnd))
            return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT rect))
            return;

        int wx = rect.Left;
        int wy = rect.Top;
        int ww = rect.Right - rect.Left;
        int wh = rect.Bottom - rect.Top;

        int gridX = 4;
        int gridY = 4;
        double pieceW = (double)ww / gridX;
        double pieceH = (double)wh / gridY;

        IntPtr overlayHwnd = CreateOverlayWindow();

        ActiveShatter shatter = new ActiveShatter
        {
            Hwnd = hwnd,
            OverlayHwnd = overlayHwnd,
            OrigX = wx,
            OrigY = wy
        };

        Random rand = new Random();

        for (int col = 0; col < gridX; col++)
        {
            for (int row = 0; row < gridY; row++)
            {
                NativeMethods.DwmRegisterThumbnail(overlayHwnd, hwnd, out IntPtr thumb);

                double srcX = col * pieceW;
                double srcY = row * pieceH;

                double cx = wx + srcX + pieceW / 2;
                double cy = wy + srcY + pieceH / 2;

                double winCx = wx + ww / 2;
                double winCy = wy + wh / 2;

                double vx = (cx - winCx) * (rand.Next(15, 41) / 100.0);
                double vy = (cy - winCy) * (rand.Next(15, 41) / 100.0) - rand.Next(5, 21);

                double spinW = rand.Next(1, 9) * 0.1;
                double spinH = rand.Next(1, 9) * 0.1;

                shatter.Shards.Add(new Shard
                {
                    ThumbId = thumb,
                    X = wx + srcX,
                    Y = wy + srcY,
                    W = pieceW,
                    H = pieceH,
                    SrcX = srcX,
                    SrcY = srcY,
                    Vx = vx,
                    Vy = vy,
                    SpinW = spinW,
                    SpinH = spinH
                });
            }
        }

        _activeShatters[hwnd] = shatter;

        // Hide real window far off-screen
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, -19999, wy, 0, 0,
            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

        Task.Run(() => AnimateShatter(shatter, shatter.Cts.Token));
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
        
        // Ensure WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW
        uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle | NativeMethods.WS_EX_TRANSPARENT | 0x80);

        // Make it cover a massive area in physical pixels so thumbnails don't clip
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, -30000, -30000, 60000, 60000,
            NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

        return hwnd;
    }

    private async Task AnimateShatter(ActiveShatter shatter, CancellationToken token)
    {
        long start = Stopwatch.GetTimestamp();
        double ms = 1000.0;
        double frequency = Stopwatch.Frequency;

        while (!token.IsCancellationRequested)
        {
            long now = Stopwatch.GetTimestamp();
            double t = (now - start) / (frequency * (ms / 1000.0));

            if (t >= 1.0)
            {
                break;
            }

            int alpha = (int)Math.Round(255 * (1 - (t * t)));
            if (alpha < 0) alpha = 0;
            if (alpha > 255) alpha = 255;

            foreach (var s in shatter.Shards)
            {
                s.Vy += 1.2; // Gravity
                s.X += s.Vx;
                s.Y += s.Vy;

                double curW = s.W * Math.Abs(Math.Cos(t * 15 * s.SpinW));
                double curH = s.H * Math.Abs(Math.Cos(t * 15 * s.SpinH));

                if (curW < 1) curW = 1;
                if (curH < 1) curH = 1;

                double curX = s.X + (s.W - curW) / 2;
                double curY = s.Y + (s.H - curH) / 2;

                // Update DWM. Overlay window is at -30000, -30000.
                int destX = (int)Math.Round(curX) + 30000;
                int destY = (int)Math.Round(curY) + 30000;

                NativeMethods.DWM_THUMBNAIL_PROPERTIES props = new NativeMethods.DWM_THUMBNAIL_PROPERTIES
                {
                    dwFlags = NativeMethods.DWM_TNP_VISIBLE | NativeMethods.DWM_TNP_RECTDESTINATION | NativeMethods.DWM_TNP_RECTSOURCE | NativeMethods.DWM_TNP_OPACITY | NativeMethods.DWM_TNP_SOURCECLIENTAREAONLY,
                    fVisible = true,
                    fSourceClientAreaOnly = false, // We want the whole window frame, not just client area, to look like the whole window shattered
                    opacity = (byte)alpha,
                    rcDestination = new NativeMethods.RECT { Left = destX, Top = destY, Right = destX + (int)Math.Round(curW), Bottom = destY + (int)Math.Round(curH) },
                    rcSource = new NativeMethods.RECT { Left = (int)Math.Round(s.SrcX), Top = (int)Math.Round(s.SrcY), Right = (int)Math.Round(s.SrcX + s.W), Bottom = (int)Math.Round(s.SrcY + s.H) }
                };
                NativeMethods.DwmUpdateThumbnailProperties(s.ThumbId, ref props);
            }

            await Task.Delay(15);
        }

        CleanupShatter(shatter, true);
    }

    private void CleanupShatter(ActiveShatter shatter, bool closeWindow)
    {
        foreach (var s in shatter.Shards)
        {
            NativeMethods.DwmUnregisterThumbnail(s.ThumbId);
        }

        NativeMethods.PostMessage(shatter.OverlayHwnd, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);

        if (_activeShatters.ContainsKey(shatter.Hwnd))
        {
            _activeShatters.Remove(shatter.Hwnd);
        }

        if (NativeMethods.IsWindow(shatter.Hwnd))
        {
            // Restore position
            NativeMethods.SetWindowPos(shatter.Hwnd, IntPtr.Zero, shatter.OrigX, shatter.OrigY, 0, 0,
                NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            if (closeWindow)
            {
                // Request normal close
                NativeMethods.PostMessage(shatter.Hwnd, NativeMethods.WM_SYSCOMMAND, new IntPtr(NativeMethods.SC_CLOSE), IntPtr.Zero);
            }
        }
    }

    public void Dispose()
    {
        foreach (var shatter in new List<ActiveShatter>(_activeShatters.Values))
        {
            shatter.Cts.Cancel();
            CleanupShatter(shatter, false);
        }
    }
}
