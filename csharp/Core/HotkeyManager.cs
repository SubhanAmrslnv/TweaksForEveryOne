using System;
using System.Collections.Generic;
using System.Windows.Interop;

namespace WindowTweaks.Core;

/// <summary>
/// Global hotkeys, via RegisterHotKey and WM_HOTKEY off the WPF component dispatcher.
///
/// A FAILED REGISTRATION IS REPORTED, not swallowed. RegisterHotKey fails when another process
/// already owns the chord, and the old version stored the action only on success and said nothing -
/// so a hotkey claimed by some other tool was a feature that simply never fired, with no error
/// anywhere and nothing for a user to notice except that pressing the key did nothing.
/// </summary>
public class HotkeyManager : IDisposable
{
    private readonly Dictionary<int, Action> _hotkeyActions = new();
    private readonly List<string> _failed = new();
    private int _currentHotkeyId = 9000;
    private bool _isDisposed;

    /// <summary>Human-readable descriptions of the chords that could not be registered.</summary>
    public IReadOnlyList<string> FailedRegistrations => _failed;

    public HotkeyManager()
    {
        ComponentDispatcher.ThreadPreprocessMessage += ComponentDispatcher_ThreadPreprocessMessage;
    }

    /// <param name="description">
    /// What to call this chord if it cannot be registered, e.g. "Shift+Alt+S".
    /// </param>
    /// <returns>True if the chord is now ours.</returns>
    public bool Register(uint modifiers, uint key, Action action, string? description = null)
    {
        int id = ++_currentHotkeyId;

        if (NativeMethods.RegisterHotKey(IntPtr.Zero, id, modifiers, key))
        {
            _hotkeyActions[id] = action;
            return true;
        }

        _failed.Add(description ?? Describe(modifiers, key));
        return false;
    }

    private static string Describe(uint modifiers, uint key)
    {
        string mods = string.Empty;
        if ((modifiers & 0x0002) != 0) mods += "Ctrl+";
        if ((modifiers & NativeMethods.MOD_SHIFT) != 0) mods += "Shift+";
        if ((modifiers & NativeMethods.MOD_ALT) != 0) mods += "Alt+";
        return mods + "0x" + key.ToString("X2");
    }

    private void ComponentDispatcher_ThreadPreprocessMessage(ref MSG msg, ref bool handled)
    {
        if (msg.message != NativeMethods.WM_HOTKEY) return;

        int id = msg.wParam.ToInt32();
        if (!_hotkeyActions.TryGetValue(id, out Action? action)) return;

        handled = true;
        try
        {
            action.Invoke();
        }
        catch (Exception ex)
        {
            // An exception here reaches the WPF message pump and takes the app down. A feature
            // failing on one press must not do that.
            System.Diagnostics.Debug.WriteLine("Hotkey action failed: " + ex);
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
