using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using WindowTweaks.Core;
using System.Windows.Threading;
using System.Threading.Tasks;

namespace WindowTweaks.Features;

public class QuickFolderJumpFeature
{
    private const string FILE_DIALOG_CLASS = "#32770";
    private const string EXPLORER_CLASS = "CabinetWClass";

    private const int WM_SETTEXT = 0x000C;
    private const int WM_GETTEXT = 0x000D;
    private const int WM_GETTEXTLENGTH = 0x000E;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int VK_RETURN = 0x0D;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, StringBuilder lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, EntryPoint = "SendMessage")]
    private static extern IntPtr SendMessageString(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr hWnd);

    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumChildWindows(IntPtr hwndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        // 1. Verify it's a file dialog
        StringBuilder className = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, className, className.Capacity);
        if (className.ToString() != FILE_DIALOG_CLASS)
        {
            return;
        }

        // 2. Find the Edit control
        IntPtr editHwnd = IntPtr.Zero;
        EnumChildWindows(hwnd, (childHwnd, lParam) =>
        {
            StringBuilder childClass = new StringBuilder(256);
            NativeMethods.GetClassName(childHwnd, childClass, childClass.Capacity);
            if (childClass.ToString() == "Edit")
            {
                // We want the first visible Edit control (usually the file name box)
                if (NativeMethods.IsWindowVisible(childHwnd))
                {
                    editHwnd = childHwnd;
                    return false; // Stop enumerating
                }
            }
            return true;
        }, IntPtr.Zero);

        if (editHwnd == IntPtr.Zero)
        {
            return;
        }

        // 3. Get the path from the most recent Explorer window
        string path = GetActiveExplorerPath();
        if (string.IsNullOrEmpty(path))
        {
            return;
        }

        Task.Run(() => 
        {
            // 4. Backup the current text
            int length = SendMessage(editHwnd, WM_GETTEXTLENGTH, IntPtr.Zero, IntPtr.Zero).ToInt32();
            StringBuilder oldText = new StringBuilder(length + 1);
            SendMessage(editHwnd, WM_GETTEXT, new IntPtr(oldText.Capacity), oldText);

            // 5. Set focus and text
            SetFocus(editHwnd);
            SendMessageString(editHwnd, WM_SETTEXT, IntPtr.Zero, path);
            Thread.Sleep(50);

            // 6. Send Enter key directly to the edit control to navigate
            NativeMethods.PostMessage(editHwnd, WM_KEYDOWN, new IntPtr(VK_RETURN), IntPtr.Zero);
            NativeMethods.PostMessage(editHwnd, WM_KEYUP, new IntPtr(VK_RETURN), IntPtr.Zero);
            
            Thread.Sleep(150);

            // 7. Restore the old text if it wasn't empty
            if (oldText.Length > 0)
            {
                SendMessageString(editHwnd, WM_SETTEXT, IntPtr.Zero, oldText.ToString());
            }
        });
    }

    private string GetActiveExplorerPath()
    {
        try
        {
            IntPtr explorerHwnd = NativeMethods.FindWindow(EXPLORER_CLASS, null);
            if (explorerHwnd == IntPtr.Zero)
                return null;

            Type shellAppType = Type.GetTypeFromProgID("Shell.Application");
            if (shellAppType != null)
            {
                dynamic shell = Activator.CreateInstance(shellAppType);
                var windows = shell.Windows();
                for (int i = 0; i < windows.Count; i++)
                {
                    var window = windows.Item(i);
                    if (window != null && (IntPtr)window.HWND == explorerHwnd)
                    {
                        string path = window.Document.Folder.Self.Path;
                        return path;
                    }
                }
            }
        }
        catch
        {
            // Ignore COM exceptions
        }
        return null;
    }
}
