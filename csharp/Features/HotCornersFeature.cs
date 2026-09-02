using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class HotCornersFeature : IDisposable
{
    private bool _enabled = false;
    private CancellationTokenSource? _cts;

    // Actions
    private string _tlAction = "None";
    private string _trAction = "Task View";
    private string _blAction = "None";
    private string _brAction = "Show Desktop";

    private const int THRESHOLD = 5;
    private const int DELAY_MS = 200;

    public bool IsEnabled => _enabled;

    /// <summary>
    /// IDEMPOTENT: FeatureRegistry calls Apply with the state it wants, not with an instruction to
    /// flip. See MagneticSnappingFeature.SetEnabled.
    /// </summary>
    public void SetEnabled(bool enabled)
    {
        if (enabled == _enabled) return;
        _enabled = enabled;

        if (_enabled)
        {
            _cts = new CancellationTokenSource();
            _ = RunMonitorLoop(_cts.Token);
        }
        else
        {
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
        }
    }

    public void Toggle() => SetEnabled(!_enabled);

    private async Task RunMonitorLoop(CancellationToken token)
    {
        string lastCorner = "None";
        long enteredAt = Environment.TickCount64;
        bool fired = false;

        while (!token.IsCancellationRequested)
        {
            await Task.Delay(50, token).ConfigureAwait(false);
            if (token.IsCancellationRequested) break;

            // Check mouse buttons
            bool lButton = (NativeMethods.GetAsyncKeyState(0x01) & 0x8000) != 0;
            bool rButton = (NativeMethods.GetAsyncKeyState(0x02) & 0x8000) != 0;
            bool mButton = (NativeMethods.GetAsyncKeyState(0x04) & 0x8000) != 0;
            if (lButton || rButton || mButton)
                continue;

            NativeMethods.GetCursorPos(out NativeMethods.POINT pt);

            // Get monitors
            var monitors = new List<NativeMethods.RECT>();
            NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                (IntPtr hMonitor, IntPtr hdcMonitor, ref NativeMethods.RECT lprcMonitor, IntPtr dwData) =>
                {
                    monitors.Add(lprcMonitor);
                    return true;
                }, IntPtr.Zero);

            if (monitors.Count == 0) continue;

            // Find active monitor
            NativeMethods.RECT activeMon = monitors[0];
            foreach (var m in monitors)
            {
                if (pt.X >= m.Left && pt.X <= m.Right - 1 && pt.Y >= m.Top && pt.Y <= m.Bottom - 1)
                {
                    activeMon = m;
                    break;
                }
            }

            int L = activeMon.Left;
            int T = activeMon.Top;
            int R = activeMon.Right;
            int B = activeMon.Bottom;

            string currentCorner = "None";
            if (pt.X <= L + THRESHOLD && pt.Y <= T + THRESHOLD)
                currentCorner = "TL";
            else if (pt.X >= R - 1 - THRESHOLD && pt.Y <= T + THRESHOLD)
                currentCorner = "TR";
            else if (pt.X <= L + THRESHOLD && pt.Y >= B - 1 - THRESHOLD)
                currentCorner = "BL";
            else if (pt.X >= R - 1 - THRESHOLD && pt.Y >= B - 1 - THRESHOLD)
                currentCorner = "BR";

            if (currentCorner != lastCorner)
            {
                lastCorner = currentCorner;
                enteredAt = Environment.TickCount64;
                fired = false;
            }

            if (currentCorner == "None" || fired)
                continue;

            if (Environment.TickCount64 - enteredAt < DELAY_MS)
                continue;

            string action = "None";
            switch (currentCorner)
            {
                case "TL": action = _tlAction; break;
                case "TR": action = _trAction; break;
                case "BL": action = _blAction; break;
                case "BR": action = _brAction; break;
            }

            fired = true;

            if (action != "None")
            {
                ExecuteAction(action);
            }
        }
    }

    private void ExecuteAction(string action)
    {
        const uint KEYEVENTF_KEYUP = 0x0002;
        const byte VK_LWIN = 0x5B;
        const byte VK_TAB = 0x09;
        const byte VK_D = 0x44;
        const byte VK_A = 0x41;
        const byte VK_VOLUME_MUTE = 0xAD;

        switch (action)
        {
            case "Task View": // Win + Tab
                NativeMethods.keybd_event(VK_LWIN, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_TAB, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                NativeMethods.keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                break;

            case "Show Desktop": // Win + D
                NativeMethods.keybd_event(VK_LWIN, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_D, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_D, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                NativeMethods.keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                break;

            case "Action Center": // Win + A
                NativeMethods.keybd_event(VK_LWIN, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_A, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_A, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                NativeMethods.keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                break;

            case "Start Menu": // Win
                NativeMethods.keybd_event(VK_LWIN, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                break;

            case "Lock Screen":
                NativeMethods.LockWorkStation();
                break;

            case "Mute Volume": // Volume Mute
                NativeMethods.keybd_event(VK_VOLUME_MUTE, 0, 0, IntPtr.Zero);
                NativeMethods.keybd_event(VK_VOLUME_MUTE, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
                break;
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
