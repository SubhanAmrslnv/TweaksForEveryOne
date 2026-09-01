using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Middle-click a window's title bar to close it, the way a browser tab closes.
///
/// The title-bar test is a WM_NCHITTEST probe, and it MUST go through SendMessageTimeout with
/// SMTO_ABORTIFHUNG. A plain SendMessage to a window whose thread is not pumping messages ("Not
/// Responding") never returns, and it would freeze this entire process - every timer, every hook,
/// every hotkey - waiting on an app that is already hung. A hung window is exactly the kind a user
/// reaches for the close button on, so this is the common case, not the edge case.
///
/// Close is a PostMessage(WM_CLOSE), never a TerminateProcess: the app still gets to prompt about
/// unsaved work.
/// </summary>
public class MiddleClickCloseFeature : IDisposable
{
    private const uint ProbeTimeoutMs = 120;

    private readonly NativeMethods.LowLevelMouseProc _proc;
    private IntPtr _hookId = IntPtr.Zero;

    public bool IsEnabled { get; private set; }

    public MiddleClickCloseFeature()
    {
        _proc = HookCallback;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            using Process curProcess = Process.GetCurrentProcess();
            using ProcessModule? curModule = curProcess.MainModule;
            if (curModule != null)
            {
                _hookId = NativeMethods.SetWindowsHookEx(NativeMethods.WH_MOUSE_LL, _proc,
                    NativeMethods.GetModuleHandle(curModule.ModuleName), 0);
            }
        }
        else
        {
            if (_hookId != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0 && wParam == (IntPtr)NativeMethods.WM_MBUTTONDOWN)
            {
                NativeMethods.MSLLHOOKSTRUCT data =
                    Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

                if (TryCloseTitleBarUnder(data.pt))
                {
                    // Swallow the click. Letting it through would deliver a middle-click to a
                    // window that is already closing.
                    return (IntPtr)1;
                }
            }
        }
        catch
        {
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private static bool TryCloseTitleBarUnder(NativeMethods.POINT pt)
    {
        IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
        if (hwnd == IntPtr.Zero) return false;

        hwnd = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;

        // Never close the shell.
        StringBuilder sb = new(256);
        NativeMethods.GetClassName(hwnd, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls is "Shell_TrayWnd" or "Progman" or "WorkerW" or "Shell_SecondaryTrayWnd") return false;

        // Never close our own settings window this way - it is not what a user means by it.
        NativeMethods.GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == (uint)Environment.ProcessId) return false;

        IntPtr lParam = MakeLParam(pt.X, pt.Y);
        IntPtr sent = NativeMethods.SendMessageTimeout(
            hwnd, NativeMethods.WM_NCHITTEST, IntPtr.Zero, lParam,
            NativeMethods.SMTO_ABORTIFHUNG, ProbeTimeoutMs, out IntPtr result);

        // sent == 0 means the window did not answer in time. Treat that as "not the title bar"
        // rather than guessing: closing a window on a timed-out probe would be a coin flip.
        if (sent == IntPtr.Zero) return false;
        if (result.ToInt64() != NativeMethods.HTCAPTION) return false;

        NativeMethods.PostMessage(hwnd, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        return true;
    }

    private static IntPtr MakeLParam(int x, int y)
    {
        return (IntPtr)((y << 16) | (x & 0xFFFF));
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
