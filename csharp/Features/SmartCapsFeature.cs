using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Smart Caps Lock: tap it for Escape, hold it to actually toggle Caps Lock.
///
/// Shares the process's single keyboard hook through KeyboardHook. It watches exactly one key -
/// VK_CAPITAL - and ignores every other key it is shown; no key is stored or logged.
/// See docs/ANTIVIRUS.md.
///
/// This is the ONE subscriber that suppresses, because remapping Caps Lock is impossible otherwise:
/// the hardware press has to be swallowed so the OS never toggles the state, and the replacement key
/// is synthesised instead. Injected events are ignored, or the hook would see its own output and
/// recurse.
/// </summary>
public class SmartCapsFeature : IDisposable
{
    private const string HookOwner = nameof(SmartCapsFeature);

    private const int VK_CAPITAL = 0x14;
    private const int VK_ESCAPE = 0x1B;
    private const int HoldMs = 400;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private readonly Stopwatch _timer = new();
    private bool _capsDown;
    private bool _toggled;

    public bool IsEnabled { get; private set; }

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
            _capsDown = false;
            _toggled = false;
            _timer.Reset();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        // Only Caps Lock is of any interest, and only from real hardware.
        if (e.VirtualKey != VK_CAPITAL || e.IsInjected) return false;

        if (e.IsKeyDown)
        {
            if (!_capsDown)
            {
                _capsDown = true;
                _toggled = false;
                _timer.Restart();

                // Held long enough: let it be a real Caps Lock after all.
                Task.Run(() =>
                {
                    Thread.Sleep(HoldMs);
                    if (_capsDown && !_toggled)
                    {
                        _toggled = true;
                        SimulateKeyPress(VK_CAPITAL);
                    }
                });
            }

            return true; // Swallow the hardware press.
        }

        if (_capsDown)
        {
            _capsDown = false;
            _timer.Stop();

            if (!_toggled && _timer.ElapsedMilliseconds < HoldMs)
            {
                SimulateKeyPress(VK_ESCAPE);
            }
        }

        return true; // Swallow the hardware release.
    }

    private static void SimulateKeyPress(ushort vk)
    {
        try
        {
            NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[2];

            inputs[0].type = NativeMethods.INPUT_KEYBOARD;
            inputs[0].u.ki.wVk = vk;
            inputs[0].u.ki.dwFlags = 0;

            inputs[1].type = NativeMethods.INPUT_KEYBOARD;
            inputs[1].u.ki.wVk = vk;
            inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;

            NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
