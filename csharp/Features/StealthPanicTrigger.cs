using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Triple-tap Escape to fire the boss key.
///
/// Shares the process's single keyboard hook through KeyboardHook. Holds a tap count and a stopwatch
/// and nothing else - no key is stored or logged. See docs/ANTIVIRUS.md.
///
/// PASS-THROUGH: Escape is never swallowed, so it still reaches whatever has focus. A dialog must not
/// stop being cancellable because this feature is on.
/// </summary>
public class StealthPanicTrigger : IDisposable
{
    private const string HookOwner = nameof(StealthPanicTrigger);
    private const int TimeoutMs = 600;
    private const int VK_ESCAPE = 0x1B;

    private readonly Action _onTripleEsc;
    private readonly Stopwatch _timer = new();

    private int _escCount;

    public bool IsEnabled { get; private set; }

    public StealthPanicTrigger(Action onTripleEsc)
    {
        _onTripleEsc = onTripleEsc;
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            KeyboardHook.Subscribe(HookOwner, OnKey);
        }
        else
        {
            KeyboardHook.Unsubscribe(HookOwner);
            _escCount = 0;
            _timer.Reset();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        if (!e.IsKeyDown || e.VirtualKey != VK_ESCAPE) return false;

        // A tap outside the window starts a fresh sequence rather than extending a stale one.
        if (_escCount == 0 || _timer.ElapsedMilliseconds > TimeoutMs)
        {
            _escCount = 1;
            _timer.Restart();
            return false;
        }

        _escCount++;

        if (_escCount >= 3)
        {
            _escCount = 0;
            _timer.Reset();
            _onTripleEsc?.Invoke();
        }

        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
