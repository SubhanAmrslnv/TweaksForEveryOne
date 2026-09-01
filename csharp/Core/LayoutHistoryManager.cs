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
}
