using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class BossKeyFeature
{
    private bool _isActive = false;
    private List<IntPtr> _hiddenWindows = new();
    private bool _previousMuteState = false;
    private bool _isBusy = false;

    public void Toggle()
    {
        if (_isBusy) return;
        _isBusy = true;

        try
        {
            if (_isActive)
            {
                // RESTORE
                foreach (var hwnd in _hiddenWindows)
                {
                    if (NativeMethods.IsWindow(hwnd))
                    {
                        NativeMethods.ShowWindow(hwnd, NativeMethods.SW_SHOW);
                    }
                }
                _hiddenWindows.Clear();

                AudioManager.SetMute(_previousMuteState);
                _isActive = false;
            }
            else
            {
                // HIDE
                _previousMuteState = AudioManager.GetMute();
                AudioManager.SetMute(true);

                _hiddenWindows.Clear();
                uint ownPid = (uint)Process.GetCurrentProcess().Id;

                NativeMethods.EnumWindows((IntPtr hwnd, IntPtr lParam) =>
                {
                    if (!NativeMethods.IsWindowVisible(hwnd)) return true;

                    StringBuilder sb = new StringBuilder(256);
                    NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
                    string cls = sb.ToString();

                    if (string.IsNullOrEmpty(cls)) return true;
                    if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW" || cls == "Shell_SecondaryTrayWnd") return true;

                    NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
                    if (pid == ownPid) return true;

                    _hiddenWindows.Add(hwnd);
                    NativeMethods.ShowWindow(hwnd, NativeMethods.SW_HIDE);

                    return true;
                }, IntPtr.Zero);

                _isActive = true;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Boss Key error: {ex.Message}");
        }
        finally
        {
            _isBusy = false;
        }
    }
}
