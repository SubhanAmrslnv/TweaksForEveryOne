using System;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Fly-To-Mouse Minimize Feature (macOS Genie Effect Parity).
///
/// Collapses minimizing windows directly toward the cursor tip along an elliptical
/// trajectory with non-linear scale reduction using AppleSpringEngine.
/// </summary>
public class FlyToMouseMinimizeFeature : IDisposable
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
    /// Animates the given window collapsing toward the cursor before minimizing.
    /// </summary>
    public async Task AnimateMinimizeAsync(IntPtr hwnd)
    {
        if (!IsEnabled || hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        if (!NativeMethods.GetWindowRect(hwnd, out NativeMethods.RECT origRect)) return;
        if (!NativeMethods.GetCursorPos(out NativeMethods.POINT mousePt)) return;

        int startX = origRect.Left;
        int startY = origRect.Top;
        int startW = origRect.Right - origRect.Left;
        int startH = origRect.Bottom - origRect.Top;

        double curX = startX;
        double curY = startY;
        double curW = startW;
        double curH = startH;

        double velX = 0, velY = 0, velW = 0, velH = 0;

        for (int frame = 0; frame < 12; frame++)
        {
            AppleSpringEngine.Step(ref curX, ref velX, mousePt.X - 20, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curY, ref velY, mousePt.Y - 20, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curW, ref velW, 40, 0.015, AppleSpringEngine.SpringConfig.Snappy);
            AppleSpringEngine.Step(ref curH, ref velH, 40, 0.015, AppleSpringEngine.SpringConfig.Snappy);

            NativeMethods.SetWindowPos(hwnd, IntPtr.Zero, (int)curX, (int)curY, Math.Max(40, (int)curW), Math.Max(40, (int)curH),
                NativeMethods.SWP_NOZORDER | NativeMethods.SWP_NOACTIVATE);

            await Task.Delay(15);
        }

        // Restore original bounds and minimize normally
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
