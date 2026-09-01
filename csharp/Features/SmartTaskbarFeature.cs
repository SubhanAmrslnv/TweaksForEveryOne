using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class SmartTaskbarFeature : IDisposable
{
    private bool _enabled = false;
    private CancellationTokenSource? _cts;
    private int _lastState = -1;

    public void Toggle()
    {
        _enabled = !_enabled;

        if (_enabled)
        {
            _lastState = -1;
            _cts = new CancellationTokenSource();
            _ = RunMonitorLoop(_cts.Token);
        }
        else
        {
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
            
            // Revert taskbar to visible
            SetTaskbarAutoHide(false);
        }
    }

    private async Task RunMonitorLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await Task.Delay(200, token).ConfigureAwait(false);
            if (token.IsCancellationRequested) break;

            IntPtr tbHwnd = FindWindow("Shell_TrayWnd", null);
            if (tbHwnd == IntPtr.Zero) continue;

            NativeMethods.GetWindowRect(tbHwnd, out NativeMethods.RECT tbRect);
            int th = tbRect.Bottom - tbRect.Top;
            if (th < 10) th = 48; // Fallback

            var primaryMonitorInfo = new NativeMethods.MONITORINFO();
            primaryMonitorInfo.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
            // Find primary monitor by finding monitor from desktop origin (0, 0)
            IntPtr primaryMon = NativeMethods.MonitorFromWindow(NativeMethods.GetForegroundWindow(), NativeMethods.MONITOR_DEFAULTTONEAREST); // actually better to get primary display specifically or from 0,0
            
            var monitors = new System.Collections.Generic.List<NativeMethods.RECT>();
            NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                (IntPtr hMonitor, IntPtr hdcMonitor, ref NativeMethods.RECT lprcMonitor, IntPtr dwData) =>
                {
                    NativeMethods.MONITORINFO mi = new NativeMethods.MONITORINFO();
                    mi.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.MONITORINFO));
                    NativeMethods.GetMonitorInfo(hMonitor, ref mi);
                    if ((mi.dwFlags & 1) == 1) // MONITORINFOF_PRIMARY
                    {
                        primaryMonitorInfo = mi;
                    }
                    return true;
                }, IntPtr.Zero);

            int ML = primaryMonitorInfo.rcMonitor.Left;
            int MT = primaryMonitorInfo.rcMonitor.Top;
            int MR = primaryMonitorInfo.rcMonitor.Right;
            int MB = primaryMonitorInfo.rcMonitor.Bottom;

            int tbActiveTop = MB - th;

            bool shouldHide = false;

            NativeMethods.EnumWindows((IntPtr hwnd, IntPtr lParam) =>
            {
                if (!NativeMethods.IsWindowVisible(hwnd))
                    return true;

                // Minimized Check
                var placement = new WINDOWPLACEMENT();
                placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                GetWindowPlacement(hwnd, ref placement);
                if (placement.showCmd == NativeMethods.SW_HIDE || placement.showCmd == 2) // SW_SHOWMINIMIZED
                    return true;

                StringBuilder cls = new StringBuilder(256);
                NativeMethods.GetClassName(hwnd, cls, cls.Capacity);
                string className = cls.ToString();
                
                if (IsShellSurface(className))
                    return true;

                uint exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
                if ((exStyle & 0x80) != 0) // WS_EX_TOOLWINDOW
                    return true;

                NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT wxRect);
                int ww = wxRect.Right - wxRect.Left;
                int wh = wxRect.Bottom - wxRect.Top;

                if (ww == 0 || wh == 0)
                    return true;

                // Check if on primary monitor
                if (wxRect.Left >= MR || wxRect.Right <= ML || wxRect.Top >= MB || wxRect.Bottom <= MT)
                    return true;

                if (placement.showCmd == 3 /* SW_SHOWMAXIMIZED */ || wxRect.Bottom > tbActiveTop)
                {
                    shouldHide = true;
                    return false; // Stop enumeration
                }

                return true;
            }, IntPtr.Zero);

            if (shouldHide != (_lastState == 1))
            {
                SetTaskbarAutoHide(shouldHide);
                _lastState = shouldHide ? 1 : 0;
            }
        }
    }

    private void SetTaskbarAutoHide(bool hide)
    {
        IntPtr hwnd = FindWindow("Shell_TrayWnd", null);
        if (hwnd == IntPtr.Zero) return;

        var data = new APPBARDATA();
        data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
        data.hWnd = hwnd;
        data.lParam = new IntPtr(hide ? 1 : 2); // ABS_AUTOHIDE : ABS_ALWAYSONTOP

        SHAppBarMessage(10, ref data); // ABM_SETSTATE
    }

    private bool IsShellSurface(string cls)
    {
        return cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || 
               cls == "Windows.UI.Core.CoreWindow" || cls == "TopLevelWindowForOverflowXamlIsland";
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

    [DllImport("shell32.dll")]
    private static extern int SHAppBarMessage(int dwMessage, ref APPBARDATA pData);

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uCallbackMessage;
        public int uEdge;
        public NativeMethods.RECT rc;
        public IntPtr lParam;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    [StructLayout(LayoutKind.Sequential)]
    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public NativeMethods.POINT ptMinPosition;
        public NativeMethods.POINT ptMaxPosition;
        public NativeMethods.RECT rcNormalPosition;
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        SetTaskbarAutoHide(false);
    }
}
