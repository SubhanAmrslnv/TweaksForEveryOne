using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Double-tap Ctrl, with nothing pressed in between, to open the Spotlight launcher.
///
/// Shares the process's single keyboard hook through KeyboardHook. Holds a tap count and a stopwatch
/// and nothing else - no key is stored or logged. See docs/ANTIVIRUS.md.
///
/// PASS-THROUGH: Ctrl is never swallowed, so every Ctrl chord keeps working.
/// </summary>
public class DoubleCtrlTrigger : IDisposable
{
    private const string HookOwner = nameof(DoubleCtrlTrigger);

    private const int VK_CONTROL = 0x11;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;

    private readonly Action _onDoubleCtrl;
    private readonly Stopwatch _timer = new();

    private int _ctrlCount;
    private bool _otherKeyPressed;

    public bool IsEnabled { get; private set; }

    public DoubleCtrlTrigger(Action onDoubleCtrl)
    {
        _onDoubleCtrl = onDoubleCtrl;
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
        _ctrlCount = 0;
        _otherKeyPressed = false;
        _timer.Reset();
    }

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        int timeoutMs = TuningRegistry.Int(TuningRegistry.DoubleTapTimeoutMs);

        bool isCtrl = e.VirtualKey is VK_CONTROL or VK_LCONTROL or VK_RCONTROL;

        if (e.IsKeyDown)
        {
            if (!isCtrl)
            {
                // A real Ctrl chord (Ctrl+C and friends), not a double tap.
                if (_ctrlCount > 0) _otherKeyPressed = true;
                return false;
            }

            if (_ctrlCount == 0 || _timer.ElapsedMilliseconds > timeoutMs)
            {
                _ctrlCount = 1;
                _otherKeyPressed = false;
                _timer.Restart();
            }
            else if (_otherKeyPressed)
            {
                _ctrlCount = 1;
                _otherKeyPressed = false;
                _timer.Restart();
            }
            else
            {
                _ctrlCount = 0;
                _timer.Reset();
                _onDoubleCtrl?.Invoke();
            }
        }
        else if (isCtrl && _otherKeyPressed)
        {
            _ctrlCount = 0;
            _timer.Reset();
        }

        return false;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
