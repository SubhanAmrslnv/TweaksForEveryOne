using System;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Black Hole Minimize Feature (macOS Gravitational Singularity Parity).
///
/// Minimizing windows spiral inward toward a singularity point with non-linear
/// spatial compression before collapsing to native minimized state.
/// </summary>
public class BlackHoleMinimizeFeature : IDisposable
{
    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;
        if (enabled) Start();
        else Stop();
    }
    
    public void Toggle() => SetEnabled(!IsEnabled);

    private void Start() { }

    /// <summary>
    /// Animates the window spiraling into a gravitational singularity before minimizing.
    /// </summary>
    public async Task AnimateBlackHoleAsync(IntPtr hwnd)
    {
        if (!IsEnabled || hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT origRect)) return;

        int startX = origRect.Left;
        int startY = origRect.Top;
        int startW = origRect.Right - origRect.Left;
        int startH = origRect.Bottom - origRect.Top;

        // Singularity point: center of taskbar or bottom right
        double targetX = startX + (startW / 2.0);
        double targetY = startY + (startH / 2.0);

        double curX = startX, curY = startY, curW = startW, curH = startH;
        double velX = 0, velY = 0, velW = 0, velH = 0;

        for (int step = 0; step < 14; step++)
        {
            double progress = step / 14.0;
            double angle = progress * Math.PI * 1.5; // Spiral orbit angle
            double orbitRadius = (1.0 - progress) * 60.0;

            double orbitX = targetX + (Math.Cos(angle) * orbitRadius);
            double orbitY = targetY + (Math.Sin(angle) * orbitRadius);

            AppleSpringEngine.Step(ref curX, ref velX, orbitX, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curY, ref velY, orbitY, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curW, ref velW, 20, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curH, ref velH, 20, 0.015, AppleSpringEngine.SpringConfig.Snappy);

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, (int)curX, (int)curY, Math.Max(20, (int)curW), Math.Max(20, (int)curH),
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            await Task.Delay(15);
        }

        // Restore original dimensions and minimize cleanly
        NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, startX, startY, startW, startH,
            NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

        NativeMethods.PostMessage(hwnd, NativeMethods.WM_SYSCOMMAND, new IntPtr(0xF020), IntPtr.Zero); // SC_MINIMIZE
    }

    private void Stop() { }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
