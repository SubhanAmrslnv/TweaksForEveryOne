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
    private const int VK_ESCAPE = 0x1B;

    private readonly Action _onTripleEsc;
    private readonly Stopwatch _timer = new();

    private int _escCount;
    private bool _isEscDown;

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
            _isEscDown = false;
            _timer.Reset();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    internal bool OnKey(KeyboardHook.KeyEvent e)
    {
        if (e.VirtualKey != VK_ESCAPE)
        {
            if (e.IsKeyDown && _escCount > 0)
            {
                _escCount = 0;
                _timer.Reset();
            }
            return false;
        }

        if (e.IsKeyDown)
        {
            // Auto-repeat while holding Escape must not count towards the triple-tap gesture.
            // Holding Escape is ONE continuous press, not multiple taps.
            if (_isEscDown || e.IsRepeat) return false;
            _isEscDown = true;

            int timeoutMs = TuningRegistry.Int(TuningRegistry.StealthTimeoutMs);

            // A tap outside the window starts a fresh sequence rather than extending a stale one.
            if (_escCount == 0 || _timer.ElapsedMilliseconds > timeoutMs)
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
        }
        else
        {
            _isEscDown = false;
        }

        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
