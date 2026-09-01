using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class MaximizeRestoreFeature
{
    private const int GWL_STYLE = -16;
    private const uint WS_MAXIMIZEBOX = 0x00010000;

    // Window placement constants
    private const int SW_MAXIMIZE = 3;
    private const int SW_RESTORE = 9;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    private struct POINT
    {
        public int x;
        public int y;
    }

    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public NativeMethods.RECT rcNormalPosition;
    }

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        // Skip if window doesn't have a maximize box (cannot be maximized)
        int style = GetWindowLong(hwnd, GWL_STYLE);
        if ((style & WS_MAXIMIZEBOX) == 0) return;

        WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
        placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
        if (GetWindowPlacement(hwnd, ref placement))
        {
            if (placement.showCmd == SW_MAXIMIZE)
            {
                NativeMethods.ShowWindow(hwnd, SW_RESTORE);
            }
            else
            {
                NativeMethods.ShowWindow(hwnd, SW_MAXIMIZE);
            }
        }
    }
}
