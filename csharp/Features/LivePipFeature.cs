using System;
using System.Collections.Generic;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class LivePipFeature : IDisposable
{
    private readonly Dictionary<IntPtr, PipWindow> _pipWindows = new();

    public void Toggle()
    {
        IntPtr srcHwnd = NativeMethods.GetForegroundWindow();
        if (srcHwnd == IntPtr.Zero) return;

        StringBuilder sbCls = new StringBuilder(256);
        NativeMethods.GetClassName(srcHwnd, sbCls, sbCls.Capacity);
        string cls = sbCls.ToString();

        if (string.IsNullOrEmpty(cls) || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || cls == "Progman" || cls == "WorkerW")
            return;

        // If active window is one of our PiP windows, close it
        foreach (var kvp in _pipWindows)
        {
            if (new WindowInteropHelper(kvp.Value).Handle == srcHwnd)
            {
                ClosePip(kvp.Key);
                return;
            }
        }

        if (_pipWindows.ContainsKey(srcHwnd))
        {
            ClosePip(srcHwnd);
            return;
        }

        NativeMethods.GetClientRect(srcHwnd, out NativeMethods.RECT rect);
        int sw = rect.Right - rect.Left;
        int sh = rect.Bottom - rect.Top;

        int pw = 320, ph = 180;
        if (sw > 0 && sh > 0)
        {
            ph = 200;
            pw = (int)Math.Round(ph * ((double)sw / sh));
        }

        PipWindow pip = new PipWindow(srcHwnd, pw, ph);
        pip.Closed += (s, e) => ClosePip(srcHwnd);
        pip.Show();

        _pipWindows[srcHwnd] = pip;
    }

    private void ClosePip(IntPtr srcHwnd)
    {
        if (_pipWindows.TryGetValue(srcHwnd, out PipWindow? pip))
        {
            _pipWindows.Remove(srcHwnd);
            pip.ClosePip();
        }
    }

    public void Dispose()
    {
        foreach (var hwnd in new List<IntPtr>(_pipWindows.Keys))
        {
            ClosePip(hwnd);
        }
    }

    private class PipWindow : Window
    {
        private IntPtr _srcHwnd;
        private IntPtr _thumbId;
        private DispatcherTimer _monitorTimer;

        public PipWindow(IntPtr srcHwnd, int width, int height)
        {
            _srcHwnd = srcHwnd;

            this.Title = "Live PiP";
            this.Width = width;
            this.Height = height;
            this.WindowStyle = WindowStyle.ToolWindow;
            this.Topmost = true;
            this.Background = System.Windows.Media.Brushes.Black;
            this.ShowInTaskbar = false;

            this.Loaded += OnLoaded;
            this.SizeChanged += OnSizeChanged;

            _monitorTimer = new DispatcherTimer();
            _monitorTimer.Interval = TimeSpan.FromMilliseconds(100);
            _monitorTimer.Tick += OnMonitorTick;
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            IntPtr myHwnd = new WindowInteropHelper(this).Handle;

            int hr = NativeMethods.DwmRegisterThumbnail(myHwnd, _srcHwnd, out _thumbId);
            if (hr != 0)
            {
                this.Close();
                return;
            }

            UpdateThumbnail();
            _monitorTimer.Start();
        }

        private void OnSizeChanged(object sender, SizeChangedEventArgs e)
        {
            if (_thumbId != IntPtr.Zero)
            {
                UpdateThumbnail();
            }
        }

        private void UpdateThumbnail()
        {
            IntPtr myHwnd = new WindowInteropHelper(this).Handle;
            NativeMethods.GetClientRect(myHwnd, out NativeMethods.RECT clientRect);

            NativeMethods.DWM_THUMBNAIL_PROPERTIES props = new NativeMethods.DWM_THUMBNAIL_PROPERTIES
            {
                dwFlags = NativeMethods.DWM_TNP_VISIBLE | NativeMethods.DWM_TNP_RECTDESTINATION | NativeMethods.DWM_TNP_OPACITY | NativeMethods.DWM_TNP_SOURCECLIENTAREAONLY,
                fVisible = true,
                fSourceClientAreaOnly = true,
                opacity = 255,
                rcDestination = clientRect
            };

            NativeMethods.DwmUpdateThumbnailProperties(_thumbId, ref props);
        }

        private void OnMonitorTick(object? sender, EventArgs e)
        {
            if (!NativeMethods.IsWindow(_srcHwnd))
            {
                this.Close(); // Will trigger ClosePip via Closed event
            }
        }

        public void ClosePip()
        {
            if (_thumbId != IntPtr.Zero)
            {
                NativeMethods.DwmUnregisterThumbnail(_thumbId);
                _thumbId = IntPtr.Zero;
            }
            _monitorTimer?.Stop();
            this.Close();
        }
    }
}
