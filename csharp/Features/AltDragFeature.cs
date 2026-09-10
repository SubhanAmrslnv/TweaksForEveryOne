using System;
using System.Runtime.InteropServices;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class AltDragFeature : IDisposable
{
    /// <summary>
    /// FALSE, and it matters. This field used to start as true while no hook was installed, so the
    /// feature and the registry disagreed from the first line of OnStartup: the registry defaults
    /// Alt-Drag to ON, called Apply(true), and Apply was wired to Toggle() - which flipped this to
    /// false and unsubscribed. Alt-drag was therefore dead whenever the settings window said it was
    /// on, and ALIVE during Game Mode, which is supposed to switch it off. The state a feature
    /// reports has to be the state it is actually in.
    /// </summary>
    private bool _enabled;

    private const int HTCAPTION = 2;
    private const int HTLEFT = 10;
    private const int HTRIGHT = 11;
    private const int HTTOP = 12;
    private const int HTTOPLEFT = 13;
    private const int HTTOPRIGHT = 14;
    private const int HTBOTTOM = 15;
    private const int HTBOTTOMLEFT = 16;
    private const int HTBOTTOMRIGHT = 17;

    private const int WM_NCLBUTTONDOWN = 0x00A1;
    private const int VK_MENU = 0x12;

    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_RBUTTONDOWN = 0x0204;

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

    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    private const int SW_SHOWMAXIMIZED = 3;

    public AltDragFeature()
    {
    }

    public bool IsEnabled => _enabled;

    /// <summary>
    /// IDEMPOTENT, and it has to stay that way. FeatureRegistry calls a feature's Apply with the
    /// state it WANTS, so an Apply that flips instead of setting only works while the two never
    /// disagree - and Game Mode is precisely the case where they do.
    /// </summary>
    public void SetEnabled(bool enabled)
    {
        if (enabled == _enabled) return;
        _enabled = enabled;

        // Buttons only: this handler reads Alt and then queries the window under the cursor, and
        // calling it for every mouse move would be that work a hundred times a second for nothing.
        if (_enabled) MouseHook.Subscribe("AltDragFeature", MouseEvents.Buttons, HookCallback);
        else MouseHook.Unsubscribe("AltDragFeature");
    }

    public void Toggle() => SetEnabled(!_enabled);

    private bool HookCallback(MouseHook.MouseEvent e)
    {
        if (e.Message != WM_LBUTTONDOWN && e.Message != WM_RBUTTONDOWN)
            return false;

        // Check if Alt is held
        short altState = GetAsyncKeyState(VK_MENU);
        if ((altState & 0x8000) == 0)
            return false;

        // Get window under cursor
        NativeMethods.POINT pt = new NativeMethods.POINT { X = e.X, Y = e.Y };
        IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
        if (hwnd == IntPtr.Zero) return false;

        IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
        if (root == IntPtr.Zero) return false;

        // Skip maximized windows
        WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
        placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
        if (GetWindowPlacement(root, ref placement) && placement.showCmd == SW_SHOWMAXIMIZED)
        {
            return false;
        }

        if (e.Message == WM_LBUTTONDOWN)
        {
            // Activate the window and start native move
            NativeMethods.SetForegroundWindow(root);
            NativeMethods.PostMessage(root, (uint)WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
            return true;
        }
        else if (e.Message == WM_RBUTTONDOWN)
        {
            // Verify window is resizable (has sizing frame)
            uint style = NativeMethods.GetWindowLong(root, NativeMethods.GWL_STYLE);
            const uint WS_THICKFRAME = 0x00040000;
            if ((style & WS_THICKFRAME) == 0)
            {
                return false;
            }

            if (!NativeMethods.GetWindowRect(root, out NativeMethods.RECT r))
                return false;

            int w = r.Right - r.Left;
            int h = r.Bottom - r.Top;
            if (w <= 0 || h <= 0) return false;

            int relX = e.X - r.Left;
            int relY = e.Y - r.Top;

            int col = relX < w / 3 ? 0 : (relX > (2 * w) / 3 ? 2 : 1);
            int row = relY < h / 3 ? 0 : (relY > (2 * h) / 3 ? 2 : 1);

            int hitTest;
            if (row == 0) // Top edge / corners
            {
                hitTest = col switch
                {
                    0 => HTTOPLEFT,
                    2 => HTTOPRIGHT,
                    _ => HTTOP
                };
            }
            else if (row == 2) // Bottom edge / corners
            {
                hitTest = col switch
                {
                    0 => HTBOTTOMLEFT,
                    2 => HTBOTTOMRIGHT,
                    _ => HTBOTTOM
                };
            }
            else // Middle
            {
                hitTest = col switch
                {
                    0 => HTLEFT,
                    2 => HTRIGHT,
                    _ => (relX > w / 2 ? (relY > h / 2 ? HTBOTTOMRIGHT : HTTOPRIGHT) : (relY > h / 2 ? HTBOTTOMLEFT : HTTOPLEFT))
                };
            }

            NativeMethods.SetForegroundWindow(root);
            NativeMethods.PostMessage(root, (uint)WM_NCLBUTTONDOWN, new IntPtr(hitTest), IntPtr.Zero);
            return true;
        }

        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
