using System;
using System.Collections.Generic;

namespace WindowTweaks.Core;

internal static class LayoutHistoryManager
{
    private static readonly Dictionary<IntPtr, NativeMethods.RECT> _undoHistory = new();

    public static void SaveLayout(IntPtr hwnd, NativeMethods.RECT rect)
    {
        _undoHistory[hwnd] = rect;
    }

    public static bool TryPopLayout(IntPtr hwnd, out NativeMethods.RECT rect)
    {
        if (_undoHistory.TryGetValue(hwnd, out rect))
        {
            _undoHistory.Remove(hwnd);
            return true;
        }
        return false;
    }

    /// <summary>Drop records for windows that no longer exist. Cheap; call from any slow poll.</summary>
    public static void Sweep()
    {
        if (_undoHistory.Count == 0) return;

        List<IntPtr>? dead = null;
        foreach (IntPtr h in _undoHistory.Keys)
        {
            if (!NativeMethods.IsWindow(h)) (dead ??= new List<IntPtr>()).Add(h);
        }
        if (dead == null) return;
        foreach (IntPtr h in dead) _undoHistory.Remove(h);
    }
}
