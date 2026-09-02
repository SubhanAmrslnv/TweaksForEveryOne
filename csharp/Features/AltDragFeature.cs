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
    private const int WM_NCLBUTTONDOWN = 0x00A1;
    private const int VK_MENU = 0x12;

    private const int WM_LBUTTONDOWN = 0x0201;

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
        if (e.Message == WM_LBUTTONDOWN)
        {
            // Check if Alt is held
            short altState = GetAsyncKeyState(VK_MENU);
            if ((altState & 0x8000) != 0)
            {
                // Get window under cursor
                NativeMethods.POINT pt = new NativeMethods.POINT { X = e.X, Y = e.Y };
                IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
                if (hwnd != IntPtr.Zero)
                {
                    IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
                    if (root != IntPtr.Zero)
                    {
                        // Skip maximized windows
                        WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
                        placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                        if (GetWindowPlacement(root, ref placement))
                        {
                            if (placement.showCmd == SW_SHOWMAXIMIZED)
                            {
                                // Don't drag maximized windows
                                return false;
                            }
                        }

                        // Activate the window
                        NativeMethods.SetForegroundWindow(root);

                        // Trigger native drag
                        NativeMethods.PostMessage(root, (uint)WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);

                        // Swallow the original click so we don't click on buttons inside the window
                        return true;
                    }
                }
            }
        }

        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
