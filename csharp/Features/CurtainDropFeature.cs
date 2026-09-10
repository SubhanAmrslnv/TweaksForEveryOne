using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Windows.Forms;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Curtain Drop Feature (macOS Exposé Desktop Drop Parity).
///
/// Drops all desktop windows downward off-screen with directional kinetic velocity
/// to instantly reveal the desktop wallpaper.
/// </summary>
public class CurtainDropFeature : IDisposable
{
    private class WindowState
    {
        public IntPtr Hwnd;
        public int OrigX, OrigY, Width, Height;
    }

    private readonly List<WindowState> _savedWindows = new();
    private bool _isDropped;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle()
    {
        if (!IsEnabled) return;
        _ = ToggleCurtainAsync();
    }

    private void Start() { }

    public async Task ToggleCurtainAsync()
    {
        if (!_isDropped)
        {
            // Drop windows
            _savedWindows.Clear();
            int screenHeight = Screen.PrimaryScreen?.Bounds.Height ?? 1080;

            NativeMethods.EnumWindows((hwnd, _) =>
            {
                if (!WindowFilter.IsOrdinaryAppWindow(hwnd)) return true;
                if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT r)) return true;

                _savedWindows.Add(new WindowState
                {
                    Hwnd = hwnd,
                    OrigX = r.Left,
                    OrigY = r.Top,
                    Width = r.Right - r.Left,
                    Height = r.Bottom - r.Top
                });
                return true;
            }, IntPtr.Zero);

            SoundEngine.Play(SoundId.ShowDesktop);

            // Animate downward off-screen
            for (int step = 1; step <= 8; step++)
            {
                double fraction = step / 8.0;
                int dropY = (int)(screenHeight * fraction);

                foreach (var w in _savedWindows)
                {
                    if (NativeMethods.IsWindow(w.Hwnd))
                    {
                        NativeMethods.SetWindowPos(w.Hwnd, IntPtr.Zero, w.OrigX, w.OrigY + dropY, 0, 0,
                            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    }
                }
                await Task.Delay(15);
            }

            _isDropped = true;
        }
        else
        {
            // Restore windows upward
            int screenHeight = Screen.PrimaryScreen?.Bounds.Height ?? 1080;

            for (int step = 8; step >= 0; step--)
            {
                double fraction = step / 8.0;
                int dropY = (int)(screenHeight * fraction);

                foreach (var w in _savedWindows)
                {
                    if (NativeMethods.IsWindow(w.Hwnd))
                    {
                        NativeMethods.SetWindowPos(w.Hwnd, IntPtr.Zero, w.OrigX, w.OrigY + dropY, 0, 0,
                            NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                    }
                }
                await Task.Delay(15);
            }

            _savedWindows.Clear();
            _isDropped = false;
        }
    }

    private void Stop()
    {
        if (_isDropped)
        {
            foreach (var w in _savedWindows)
            {
                if (NativeMethods.IsWindow(w.Hwnd))
                {
                    NativeMethods.SetWindowPos(w.Hwnd, IntPtr.Zero, w.OrigX, w.OrigY, 0, 0,
                        NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);
                }
            }
            _savedWindows.Clear();
            _isDropped = false;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
