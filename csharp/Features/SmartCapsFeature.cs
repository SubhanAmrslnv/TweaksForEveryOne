using System;
using System.Threading;
using WindowTweaks.Core;

// WPF and WinForms are both referenced, so Timer is ambiguous under ImplicitUsings. This is the
// thread-pool timer, not the WinForms one - the callback must not need a message pump.
using Timer = System.Threading.Timer;

namespace WindowTweaks.Features;

/// <summary>
/// Smart Caps Lock: a tap sends another key, holding it toggles Caps Lock for real.
///
/// Caps Lock is the best-placed key on the board and the least useful, so the point is to get TWO
/// keys out of it without losing Caps Lock itself: a bare tap sends one key, Shift and a tap send
/// the other, and both are configurable - so it can be Escape and Backspace at the same time, which
/// is what was asked for.
///
/// This is the ONE keyboard-hook subscriber that suppresses, because remapping Caps Lock is
/// impossible otherwise: the hardware press has to be swallowed so the OS never toggles the lock
/// state, and the replacement key is synthesised instead. Injected events are ignored, or the hook
/// would see its own output and recurse.
///
/// WHY THE HOLD IS A TIMER AND NOT A SLEEPING TASK. The first version did
/// <c>Task.Run(() =&gt; Thread.Sleep(holdMs))</c> on every press, so ordinary typing spun up a
/// thread-pool work item per keystroke that spent its whole life blocked. One reusable timer
/// replaces all of it, and - the part that actually matters - a timer can be CANCELLED, so releasing
/// the key stops the hold instead of leaving a sleeping thread to wake up and check a flag.
///
/// Only VK_CAPITAL is looked at. Every other key is ignored on sight and nothing is retained; see
/// docs/ANTIVIRUS.md.
/// </summary>
public class SmartCapsFeature : IDisposable
{
    private const string HookOwner = nameof(SmartCapsFeature);

    private const int VK_CAPITAL = 0x14;
    private const int VK_SHIFT = 0x10;

    private const ushort VK_ESCAPE = 0x1B;
    private const ushort VK_BACK = 0x08;
    private const ushort VK_DELETE = 0x2E;

    /// <summary>
    /// Fires once when the press has lasted long enough to be a hold. Volatile-free because it is
    /// only ever assigned under <see cref="_gate"/>.
    /// </summary>
    private Timer? _holdTimer;

    private readonly object _gate = new();

    // Written on the hook thread, read on the timer thread.
    private volatile bool _capsDown;
    private volatile bool _becameHold;

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

            CancelHold();
            _capsDown = false;
            _becameHold = false;
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        // Only Caps Lock is of any interest, and only from real hardware.
        if (e.VirtualKey != VK_CAPITAL || e.IsInjected) return false;

        if (e.IsKeyDown)
        {
            // Auto-repeat delivers a key-down every 32 ms while the key is held. Only the first one
            // starts a gesture; the rest are swallowed and otherwise ignored.
            if (!_capsDown)
            {
                _capsDown = true;
                _becameHold = false;

                // Captured once, so the whole gesture is judged against one value even if the slider
                // moves mid-press.
                int holdMs = TuningRegistry.Int(TuningRegistry.SmartCapsHoldMs);
                StartHold(holdMs);
            }

            return true; // Swallow the hardware press.
        }

        if (_capsDown)
        {
            _capsDown = false;
            CancelHold();

            // The hold already fired and turned this into a real Caps Lock. Nothing more to send.
            if (!_becameHold) SendTapKey();
        }

        return true; // Swallow the hardware release, whose press was swallowed too.
    }

    private void SendTapKey()
    {
        bool shift = (NativeMethods.GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

        string choice = shift
            ? TuningRegistry.Choice(TuningRegistry.SmartCapsShiftTapAction)
            : TuningRegistry.Choice(TuningRegistry.SmartCapsTapAction);

        ushort? key = choice.ToLowerInvariant() switch
        {
            "escape" => VK_ESCAPE,
            "backspace" => VK_BACK,
            "delete" => VK_DELETE,
            _ => null
        };

        if (key == null) return;

        // Shift is released first when it is the modifier that SELECTED this action, or the target
        // application receives Shift+Backspace - which is a different command in several editors.
        if (shift) SyntheticInput.ReleaseKey(VK_SHIFT);

        SyntheticInput.Tap(key.Value);
    }

    private void StartHold(int holdMs)
    {
        lock (_gate)
        {
            _holdTimer ??= new Timer(OnHoldElapsed, null, Timeout.Infinite, Timeout.Infinite);
            _holdTimer.Change(Math.Max(1, holdMs), Timeout.Infinite);
        }
    }

    private void CancelHold()
    {
        lock (_gate)
        {
            _holdTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        }
    }

    private void OnHoldElapsed(object? state)
    {
        try
        {
            // The release may have landed between the timer firing and this running.
            if (!_capsDown || _becameHold) return;

            _becameHold = true;

            // Held long enough: let it be a real Caps Lock after all. The lock state toggles on the
            // synthetic press, which is why the tap path must not also send anything.
            SyntheticInput.Tap(VK_CAPITAL);
        }
        catch
        {
            // A throw on a timer thread is an unhandled exception that takes the process down.
        }
    }

    public void Dispose()
    {
        SetEnabled(false);

        lock (_gate)
        {
            _holdTimer?.Dispose();
            _holdTimer = null;
        }
    }
}
