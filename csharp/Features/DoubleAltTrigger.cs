using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Double-tap Alt, with nothing pressed in between, to fire an action (the microphone kill-switch).
///
/// Shares the process's single keyboard hook through KeyboardHook rather than installing one of its
/// own. It keeps a tap count and a stopwatch and nothing else: no key is stored, logged or counted
/// beyond "was that Alt, and was anything pressed between the two taps". See docs/ANTIVIRUS.md.
///
/// The hook is PASS-THROUGH here - Alt is never swallowed, so Alt-Tab and menu access keep working.
/// </summary>
public class DoubleAltTrigger : IDisposable
{
    private const string HookOwner = nameof(DoubleAltTrigger);

    private const int VK_MENU = 0x12;
    private const int VK_LMENU = 0xA4;
    private const int VK_RMENU = 0xA5;

    private readonly Action _onDoubleAlt;
    private readonly Stopwatch _timer = new();

    private int _altCount;
    private bool _otherKeyPressed;
    private bool _isAltDown;

    public bool IsEnabled { get; private set; }

    public DoubleAltTrigger(Action onDoubleAlt)
    {
        _onDoubleAlt = onDoubleAlt;
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
            Reset();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void Reset()
    {
        _altCount = 0;
        _otherKeyPressed = false;
        _isAltDown = false;
        _timer.Reset();
    }

    internal bool OnKey(KeyboardHook.KeyEvent e)
    {
        int timeoutMs = TuningRegistry.Int(TuningRegistry.DoubleTapTimeoutMs);

        bool isAlt = e.VirtualKey is VK_MENU or VK_LMENU or VK_RMENU;

        if (e.IsKeyDown)
        {
            if (!isAlt)
            {
                // Something else was pressed, so this is a real Alt chord, not a double tap.
                if (_altCount > 0) _otherKeyPressed = true;
                return false;
            }

            // Holding Alt delivers auto-repeat key-down events. Holding Alt must be treated
            // as ONE continuous key press, not multiple taps. Repeated key-downs while Alt is
            // held are ignored and must not advance or trigger double tap logic.
            if (_isAltDown || e.IsRepeat)
            {
                return false;
            }

            _isAltDown = true;

            if (_altCount == 0 || _timer.ElapsedMilliseconds > timeoutMs)
            {
                _altCount = 1;
                _otherKeyPressed = false;
                _timer.Restart();
            }
            else if (_otherKeyPressed)
            {
                _altCount = 1;
                _otherKeyPressed = false;
                _timer.Restart();
            }
            else
            {
                _altCount = 0;
                _timer.Reset();
                _onDoubleAlt?.Invoke();
            }
        }
        else
        {
            if (isAlt)
            {
                _isAltDown = false;
                if (_otherKeyPressed)
                {
                    _altCount = 0;
                    _timer.Reset();
                }
            }
        }

        // Never suppress: Alt has to keep working as Alt.
        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
