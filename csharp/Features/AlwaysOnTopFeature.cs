using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class AlwaysOnTopFeature
{
    public void Toggle()
    {
        IntPtr activeWindow = NativeMethods.GetForegroundWindow();
        if (activeWindow == IntPtr.Zero) return;

        // Self-exclude by PID
        NativeMethods.GetWindowThreadProcessId(activeWindow, out uint activePid);
        uint ownPid = (uint)Environment.ProcessId;
        if (activePid == ownPid) return;

        uint exStyle = NativeMethods.GetWindowLong(activeWindow, NativeMethods.GWL_EXSTYLE);
        bool isTopmost = (exStyle & NativeMethods.WS_EX_TOPMOST) == NativeMethods.WS_EX_TOPMOST;

        IntPtr insertAfter = isTopmost ? NativeMethods.HWND_NOTOPMOST : NativeMethods.HWND_TOPMOST;

        NativeMethods.SetWindowPos(
            activeWindow, 
            insertAfter, 
            0, 0, 0, 0, 
            NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE);
    }
}
