using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class TrayMinimizeFeature : IDisposable
{
    private Dictionary<IntPtr, NotifyIcon> _hiddenWindows = new();

    public void Toggle()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;

        // Self-exclude by PID
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == (uint)Environment.ProcessId) return;

        // Don't minimize the desktop or taskbar
        StringBuilder sbClass = new StringBuilder(256);
        NativeMethods.GetClassName(hwnd, sbClass, sbClass.Capacity);
        string cls = sbClass.ToString();
        if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW" || cls == "Shell_SecondaryTrayWnd") return;

        HideToTray(hwnd);
    }

    private void HideToTray(IntPtr hwnd)
    {
        if (_hiddenWindows.ContainsKey(hwnd)) return;

        StringBuilder sbTitle = new StringBuilder(256);
        NativeMethods.GetWindowText(hwnd, sbTitle, sbTitle.Capacity);
        string title = sbTitle.ToString();
        if (string.IsNullOrWhiteSpace(title)) title = "Hidden Window";
        if (title.Length > 63) title = title.Substring(0, 63); // NotifyIcon tooltip limit

        Icon? icon = GetWindowIcon(hwnd);

        NotifyIcon trayIcon = new NotifyIcon
        {
            Icon = icon ?? SystemIcons.Application,
            Text = title,
            Visible = true
        };

        trayIcon.Click += (s, e) => RestoreFromTray(hwnd);

        _hiddenWindows[hwnd] = trayIcon;

        // Hide it
        NativeMethods.ShowWindow(hwnd, NativeMethods.SW_HIDE);
    }

    private void RestoreFromTray(IntPtr hwnd)
    {
        if (_hiddenWindows.TryGetValue(hwnd, out NotifyIcon? trayIcon))
        {
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                if (trayIcon.Icon != null && trayIcon.Icon != SystemIcons.Application)
                {
                    trayIcon.Icon.Dispose();
                }
                trayIcon.Dispose();
            }
            _hiddenWindows.Remove(hwnd);

            if (NativeMethods.IsWindow(hwnd))
            {
                NativeMethods.ShowWindow(hwnd, NativeMethods.SW_SHOW);
                NativeMethods.SetForegroundWindow(hwnd);
            }
        }
    }

    public int RestoreAll()
    {
        int count = 0;
        var toRestore = new List<IntPtr>(_hiddenWindows.Keys);
        foreach (var hwnd in toRestore)
        {
            RestoreFromTray(hwnd);
            count++;
        }
        return count;
    }

    private Icon? GetWindowIcon(IntPtr hwnd)
    {
        IntPtr hIcon = IntPtr.Zero;
        
        // Query WM_GETICON directly
        foreach (int which in new[] { NativeMethods.ICON_SMALL2, NativeMethods.ICON_BIG, NativeMethods.ICON_SMALL })
        {
            if (NativeMethods.SendMessageTimeout(hwnd, NativeMethods.WM_GETICON, new IntPtr(which), IntPtr.Zero, 
                NativeMethods.SMTO_ABORTIFHUNG, 100, out IntPtr result) != IntPtr.Zero && result != IntPtr.Zero)
            {
                hIcon = result;
                break;
            }
        }

        // Fallback to class icon (small first, then normal)
        if (hIcon == IntPtr.Zero)
        {
            hIcon = NativeMethods.GetClassLongPtr(hwnd, NativeMethods.GCLP_HICONSM);
            if (hIcon == IntPtr.Zero)
            {
                hIcon = NativeMethods.GetClassLongPtr(hwnd, NativeMethods.GCLP_HICON);
            }
        }

        if (hIcon != IntPtr.Zero)
        {
            try
            {
                // CRITICAL: CopyIcon creates an owned duplicate GDI handle.
                // Disposing the managed Icon wrapper will destroy our copy, never the target app's icon.
                IntPtr hIconCopy = NativeMethods.CopyIcon(hIcon);
                if (hIconCopy != IntPtr.Zero)
                {
                    return Icon.FromHandle(hIconCopy);
                }
            }
            catch
            {
                return null;
            }
        }

        return null;
    }

    public void Dispose()
    {
        foreach (var kvp in _hiddenWindows)
        {
            kvp.Value.Visible = false;
            if (kvp.Value.Icon != null && kvp.Value.Icon != SystemIcons.Application)
            {
                kvp.Value.Icon.Dispose();
            }
            kvp.Value.Dispose();
            if (NativeMethods.IsWindow(kvp.Key))
            {
                NativeMethods.ShowWindow(kvp.Key, NativeMethods.SW_SHOW);
            }
        }
        _hiddenWindows.Clear();
    }
}
