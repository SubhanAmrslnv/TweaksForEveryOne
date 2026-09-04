using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class RollUpFeature : IDisposable
{
    private Dictionary<IntPtr, int> _rolledUpWindows = new();

    public async void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT winRect)) return;
        int w = winRect.Right - winRect.Left;
        int h = winRect.Bottom - winRect.Top;

        int caption = CaptionHeight(hwnd, h);

        if (_rolledUpWindows.ContainsKey(hwnd))
        {
            // UNROLL
            int origH = _rolledUpWindows[hwnd];
            _rolledUpWindows.Remove(hwnd);

            // Animate down
            await AnimateRegion(hwnd, w, caption, origH);
            
            // Clear region
            NativeMethods.SetWindowRgn(hwnd, IntPtr.Zero, true);
        }
        else
        {
            // ROLL UP
            _rolledUpWindows[hwnd] = h;

            // Animate up
            await AnimateRegion(hwnd, w, h, caption);
            
            // Ensure final state
            IntPtr hRgn = NativeMethods.CreateRectRgn(0, 0, w, caption);
            NativeMethods.SetWindowRgn(hwnd, hRgn, true);
        }
    }

    public async Task<int> RestoreAll()
    {
        int count = 0;
        var toRestore = new List<IntPtr>(_rolledUpWindows.Keys);
        foreach (var hwnd in toRestore)
        {
            if (NativeMethods.IsWindow(hwnd))
            {
                if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT winRect)) continue;
                int w = winRect.Right - winRect.Left;
                int origH = _rolledUpWindows[hwnd];
                int caption = CaptionHeight(hwnd, origH);
                
                _rolledUpWindows.Remove(hwnd);
                
                // Fire and forget animation for batch restore
                _ = AnimateRegion(hwnd, w, caption, origH).ContinueWith(_ => 
                {
                    NativeMethods.SetWindowRgn(hwnd, IntPtr.Zero, true);
                });
                
                count++;
            }
            else
            {
                _rolledUpWindows.Remove(hwnd);
            }
        }
        return count;
    }

    private int CaptionHeight(IntPtr hwnd, int windowHeight)
    {
        if (NativeMethods.GetClientRect(hwnd, out NativeMethods.RECT clientRect))
        {
            int clientH = clientRect.Bottom - clientRect.Top;
            int caption = windowHeight - clientH;
            return (caption < 30) ? 35 : caption;
        }
        return 35;
    }

    private async Task AnimateRegion(IntPtr hwnd, int w, int startH, int endH)
    {
        int ms = 200; // Animation duration
        Stopwatch sw = Stopwatch.StartNew();

        while (sw.ElapsedMilliseconds < ms)
        {
            if (!NativeMethods.IsWindow(hwnd)) return;

            float t = (float)sw.ElapsedMilliseconds / ms;
            float ease = 1 - (1 - t) * (1 - t);
            
            int curH = startH + (int)((endH - startH) * ease);
            
            IntPtr hRgn = NativeMethods.CreateRectRgn(0, 0, w, curH);
            NativeMethods.SetWindowRgn(hwnd, hRgn, true);

            await Task.Delay(16); // ~60 FPS
        }
    }

    public void Dispose()
    {
        foreach (var hwnd in new List<IntPtr>(_rolledUpWindows.Keys))
        {
            if (NativeMethods.IsWindow(hwnd))
            {
                NativeMethods.SetWindowRgn(hwnd, IntPtr.Zero, true);
            }
        }
        _rolledUpWindows.Clear();
    }
}
