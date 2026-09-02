using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// A mechanical keyboard sound on every keystroke.
///
/// WHAT WAS WRONG WITH THE FIRST VERSION, since all three faults are easy to reintroduce:
///
///   1. It played <c>SystemSounds.Exclamation</c> - the Windows ERROR ding. Typing a sentence
///      sounded like a wall of alerts, and because it is a shared system sound the user could
///      neither retune it nor turn it down separately from real alerts.
///   2. It played through <c>Dispatcher.BeginInvoke</c>, so every key a person typed queued a work
///      item on the UI thread. Under fast typing that queue is what made the app feel wedged.
///   3. It made a sound for every event including key-UP and modifiers, so one keypress produced
///      two clicks and holding shift produced a stream of them.
///
/// Now: the click is synthesised once and cached (see Core/SoundEngine.cs) and started from the hook
/// thread with no dispatcher involvement at all. Different key groups get different sounds, because
/// a real keyboard does: space and enter are deeper, backspace is drier, modifiers are quieter.
///
/// NO KEYSTROKE IS RETAINED. The virtual key is used to choose a sound and then discarded within the
/// callback; nothing is stored, counted or ordered. The only state is one timestamp, for throttling.
/// That constraint is not stylistic - see docs/ANTIVIRUS.md.
/// </summary>
public class AcousticKeyboardFeature : IDisposable
{
    private const string HookOwner = nameof(AcousticKeyboardFeature);

    /// <summary>
    /// The floor between two sounds. Windows' auto-repeat runs at about 31 keys a second when a key
    /// is held down, which turns a click into a machine gun; this thins it out without needing to
    /// remember which keys are currently down.
    /// </summary>
    private const double MinIntervalMs = 45.0;

    /// <summary>How long a cached profile and volume are trusted before being re-read.</summary>
    private const double ConfigTtlMs = 500.0;

    private long _lastPlayed;

    // The profile and volume are CACHED, not read per keystroke. Each read takes the settings lock
    // and parses a string, and this runs on the hook thread for every key a person types - the rule
    // in CLAUDE.md is to read a tuning value once per operation and never on a hot path. Half a
    // second is well below what anyone notices after moving the slider.
    private long _configReadAt;
    private string _profile = "click";
    private int _volume = 35;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            RefreshConfig(Stopwatch.GetTimestamp());

            // Build the four key sounds off the input path, so the first keystroke of the session
            // does not pay for synthesising one on the hook thread.
            SoundEngine.Prewarm(_profile, _volume,
                SoundId.Key, SoundId.KeyDeep, SoundId.KeyErase, SoundId.KeySoft);

            KeyboardHook.Subscribe(HookOwner, OnKey);
        }
        else
        {
            KeyboardHook.Unsubscribe(HookOwner);
        }
    }

    private void RefreshConfig(long now)
    {
        _profile = TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile);
        _volume = TuningRegistry.Int(TuningRegistry.KeyboardSoundVolume);
        _configReadAt = now;
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        // Key-down only, and hardware only: a feature that sounded on its own synthetic keys would
        // click at every Smart Caps escape and every plain-text paste.
        if (!e.IsKeyDown || e.IsInjected) return false;

        long now = Stopwatch.GetTimestamp();
        double ticksPerMs = Stopwatch.Frequency / 1000.0;

        if (_lastPlayed != 0 && (now - _lastPlayed) / ticksPerMs < MinIntervalMs) return false;
        _lastPlayed = now;

        if ((now - _configReadAt) / ticksPerMs > ConfigTtlMs) RefreshConfig(now);

        SoundEngine.Play(SoundForKey(e.VirtualKey), _profile, _volume);

        // Never suppress. This feature is decoration; it must be impossible for it to eat a key.
        return false;
    }

    /// <summary>
    /// Picks the sound for one key. The virtual key does not leave this method.
    /// </summary>
    private static SoundId SoundForKey(int virtualKey)
    {
        const int VK_BACK = 0x08, VK_TAB = 0x09, VK_RETURN = 0x0D, VK_SPACE = 0x20, VK_DELETE = 0x2E;
        const int VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_CAPITAL = 0x14;
        const int VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_ESCAPE = 0x1B;

        // The contiguous navigation block: page up, page down, end, home and the four arrows.
        const int VK_PRIOR = 0x21, VK_DOWN = 0x28;

        switch (virtualKey)
        {
            // The wide keys. On a real board these are the two that thock.
            case VK_SPACE:
            case VK_RETURN:
                return SoundId.KeyDeep;

            case VK_BACK:
            case VK_DELETE:
                return SoundId.KeyErase;

            // Modifiers and navigation: present but out of the way, so holding shift or arrowing
            // through a document is not the loudest thing on the desk.
            case VK_SHIFT:
            case VK_CONTROL:
            case VK_MENU:
            case VK_CAPITAL:
            case VK_LWIN:
            case VK_RWIN:
            case VK_TAB:
            case VK_ESCAPE:
                return SoundId.KeySoft;

            default:
                // The navigation block by range, rather than eight more cases.
                if (virtualKey is >= VK_PRIOR and <= VK_DOWN) return SoundId.KeySoft;

                // Left and right shift, control and alt report as 0xA0-0xA5.
                if (virtualKey is >= 0xA0 and <= 0xA5) return SoundId.KeySoft;

                return SoundId.Key;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
