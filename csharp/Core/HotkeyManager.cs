using System;
using System.Collections.Generic;
using System.Windows.Interop;

namespace WindowTweaks.Core;

public class HotkeyManager : IDisposable
{
    private readonly Dictionary<int, Action> _hotkeyActions = new();
    private int _currentHotkeyId = 9000;
    private bool _isDisposed = false;

    public HotkeyManager()
    {
        ComponentDispatcher.ThreadPreprocessMessage += ComponentDispatcher_ThreadPreprocessMessage;
    }

    public void Register(uint modifiers, uint key, Action action)
    {
        int id = ++_currentHotkeyId;
        if (NativeMethods.RegisterHotKey(IntPtr.Zero, id, modifiers, key))
        {
            _hotkeyActions[id] = action;
        }
    }

    private void ComponentDispatcher_ThreadPreprocessMessage(ref MSG msg, ref bool handled)
    {
        if (msg.message == NativeMethods.WM_HOTKEY)
        {
            int id = msg.wParam.ToInt32();
            if (_hotkeyActions.TryGetValue(id, out Action? action))
            {
                action.Invoke();
                handled = true;
            }
        }
    }

    public void Dispose()
    {
        if (_isDisposed) return;
        
        ComponentDispatcher.ThreadPreprocessMessage -= ComponentDispatcher_ThreadPreprocessMessage;
        foreach (int id in _hotkeyActions.Keys)
        {
            NativeMethods.UnregisterHotKey(IntPtr.Zero, id);
        }
        _hotkeyActions.Clear();
        _isDisposed = true;
    }
}
