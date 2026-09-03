using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// A distinct sound for each of the Windows shortcuts that has no feedback of its own.
///
/// The problem this solves is that half of these chords do something invisible or slow. Win+Shift+S
/// dims the screen a beat later, Win+V opens a panel that may take a moment, Alt+Shift changes the
/// keyboard layout with no indication at all beyond a tray glyph nobody looks at - so the honest
/// answer to "did that register?" is usually to press it again. One sound at the moment the chord is
/// seen answers it immediately.
///
/// THE SOUNDS DIFFER BY SHAPE, NOT BY PITCH. A set of confirmations that are all short beeps a few
/// semitones apart is a set nobody ever learns. Here the window switcher rises, show-desktop falls,
/// the snip clacks like a camera, the clipboard ticks, and the layout toggle goes down and back up
/// because it is a toggle rather than a movement. See Core/SoundEngine.cs for the table.
///
/// THREE THINGS THAT ARE EASY TO GET WRONG HERE:
///
///   - IT NEVER SUPPRESSES A KEY. Every handler returns false. This feature comments on the user's
///     chords; it must be impossible for it to eat one. Win+L in particular has to keep working.
///
///   - MODIFIER STATE IS READ, NOT TRACKED, for the same reason as ClipboardOsdFeature: a key-up
///     missed during a lock-screen transition or while the hook was not installed would leave this
///     believing Win is held forever, and then every bare V would make a noise.
///
///   - THE LAYOUT SWITCH IS DECIDED ON RELEASE. It is the one gesture here with no third key, so
///     pressing Alt while Shift is down cannot be the trigger - that is also the first half of every
///     Shift+Alt hotkey this app owns, and of Shift+Alt+Tab. Ctrl+Shift, the other pair Windows can
///     be set to, is worse still: it opens a great many application shortcuts. Windows itself only
///     commits the layout change when the modifiers come back up with nothing pressed in between, so
///     this waits for the same thing. The state that costs is TWO BOOLEANS - "has anything else been
///     pressed since", once per pair. No key is stored, and that is not an accident; see
///     docs/ANTIVIRUS.md.
///
///     Which pair is live cannot be read out of Windows, so sound.layoutHotkey asks instead.
/// </summary>
public class ShortcutSoundsFeature : IDisposable
{
    private const string HookOwner = nameof(ShortcutSoundsFeature);

    /// <summary>
    /// The floor between two chord sounds. Holding Alt+Tab auto-repeats Tab about thirty times a
    /// second, and a swish thirty times a second is a fire alarm.
    /// </summary>
    private const double MinIntervalMs = 140.0;

    /// <summary>How long the cached profile and volume are trusted before being re-read.</summary>
    private const double ConfigTtlMs = 500.0;

    private const int VK_TAB = 0x09, VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12;
    private const int VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LMENU = 0xA4, VK_RMENU = 0xA5;
    private const int VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3;
    private const int VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    private const int VK_SNAPSHOT = 0x2C, VK_F4 = 0x73;
    private const int VK_LEFT = 0x25, VK_UP = 0x26, VK_RIGHT = 0x27, VK_DOWN = 0x28;
    private const int VK_A = 0x41, VK_D = 0x44, VK_E = 0x45, VK_I = 0x49, VK_K = 0x4B;
    private const int VK_L = 0x4C, VK_M = 0x4D, VK_N = 0x4E, VK_R = 0x52, VK_S = 0x53;
    private const int VK_T = 0x54, VK_V = 0x56;

    /// <summary>Semicolon and full stop: Win+; and Win+. both open the emoji panel.</summary>
    private const int VK_OEM_1 = 0xBA, VK_OEM_PERIOD = 0xBE;

    private long _lastPlayed;

    // Cached rather than read per keystroke: every read takes the settings lock and parses a string,
    // and this runs on the hook thread. See the same pattern in AcousticKeyboardFeature.
    private long _configReadAt;
    private string _profile = "click";
    private int _volume = 45;
    private string _layoutHotkey = "altShift";

    /// <summary>
    /// True while that pair of modifiers is down and nothing else has been pressed since. Between
    /// them these two are the whole state of the layout-switch gesture.
    /// </summary>
    private bool _altShiftArmed;
    private bool _ctrlShiftArmed;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            RefreshConfig(Stopwatch.GetTimestamp());

            // Built off the input path, so the first Alt+Tab of the session does not pay for
            // synthesising a sweep on the hook thread.
            SoundEngine.Prewarm(_profile, _volume,
                SoundId.SwitchWindow, SoundId.LanguageSwitch, SoundId.TaskView, SoundId.Shutter,
                SoundId.ClipboardHistory, SoundId.EmojiPicker, SoundId.ShowDesktop,
                SoundId.LockScreen, SoundId.Panel, SoundId.DesktopNext, SoundId.DesktopPrev,
                SoundId.Launch, SoundId.SnapWindow, SoundId.WindowGrow, SoundId.WindowShrink);

            KeyboardHook.Subscribe(HookOwner, OnKey);
        }
        else
        {
            KeyboardHook.Unsubscribe(HookOwner);
            _altShiftArmed = false;
            _ctrlShiftArmed = false;
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    /// <summary>
    /// Whether this feature owns the chord the given key is part of, given the modifiers held right
    /// now.
    ///
    /// This exists so the keyboard click and the chord sound do not both fire on one Win+V - the
    /// two-features-one-button problem, answered the way CLAUDE.md asks for: with an explicit
    /// arbitration rather than a second private opinion about who owns the button.
    ///
    /// It is a PURE QUERY over the live modifier state, deliberately, rather than a flag one handler
    /// sets for the other to read. Both features are subscribers on the same hook and their order in
    /// that list depends on which of them was switched on first, so anything order-dependent here
    /// would work or not work depending on the contents of settings.json.
    /// </summary>
    internal bool ClaimsKey(int virtualKey)
    {
        return IsEnabled && MatchChord(virtualKey).HasValue;
    }

    private void RefreshConfig(long now)
    {
        _profile = TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile);
        _volume = TuningRegistry.Int(TuningRegistry.ShortcutSoundVolume);
        _layoutHotkey = TuningRegistry.Choice(TuningRegistry.LayoutHotkey);
        _configReadAt = now;
    }

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        // Hardware only. Sounding on our own synthetic keys would make plain-text paste and the
        // camelCase formatter announce themselves as shortcuts.
        if (e.IsInjected) return false;

        int vk = e.VirtualKey;
        bool isAlt = vk is VK_MENU or VK_LMENU or VK_RMENU;
        bool isShift = vk is VK_SHIFT or VK_LSHIFT or VK_RSHIFT;
        bool isCtrl = vk is VK_CONTROL or VK_LCONTROL or VK_RCONTROL;

        if (!e.IsKeyDown)
        {
            // One of the pair coming back up with the gesture still armed IS the layout switch.
            // Both flags are cleared either way: whichever key was released, neither pair is whole
            // any more, and leaving the other armed would fire it on an unrelated release later.
            if (isAlt || isShift || isCtrl)
            {
                bool armed = _altShiftArmed || _ctrlShiftArmed;

                _altShiftArmed = false;
                _ctrlShiftArmed = false;

                if (armed) Play(SoundId.LanguageSwitch);
            }

            return false;
        }

        UpdateLayoutToggle(isAlt, isShift, isCtrl);

        SoundId? sound = MatchChord(vk);
        if (sound.HasValue) Play(sound.Value);

        // Never suppress. See the class comment.
        return false;
    }

    /// <summary>
    /// Arms the layout gesture when its pair of modifiers meets, and disarms it the moment anything
    /// else is pressed - which is what keeps Shift+Alt+W, Shift+Alt+Tab, Ctrl+Shift+T and every
    /// other chord that starts the same way from being heard as a layout switch when the modifiers
    /// are finally released.
    /// </summary>
    private void UpdateLayoutToggle(bool isAlt, bool isShift, bool isCtrl)
    {
        if (!isAlt && !isShift && !isCtrl)
        {
            _altShiftArmed = false;
            _ctrlShiftArmed = false;
            return;
        }

        // Win rules out both pairs, and each pair is ruled out by the third modifier: Windows'
        // layout hotkey is a BARE pair, so Ctrl+Shift+Alt is not one of them. The OTHER key of the
        // pair is what gets tested, never the one going down - the state of a key at the instant its
        // own low-level hook callback runs is not something to depend on.
        if (Down(VK_LWIN) || Down(VK_RWIN)) return;

        if (WantsAltShift && !Down(VK_CONTROL))
        {
            if (isAlt && Down(VK_SHIFT)) _altShiftArmed = true;
            else if (isShift && Down(VK_MENU)) _altShiftArmed = true;
        }

        if (WantsCtrlShift && !Down(VK_MENU))
        {
            if (isCtrl && Down(VK_SHIFT)) _ctrlShiftArmed = true;
            else if (isShift && Down(VK_CONTROL)) _ctrlShiftArmed = true;
        }
    }

    private bool WantsAltShift => _layoutHotkey is "altShift" or "both";

    private bool WantsCtrlShift => _layoutHotkey is "ctrlShift" or "both";

    /// <summary>
    /// The chord table. Returns the sound this key press belongs to, or null for the overwhelming
    /// majority of key presses, which are not chords at all.
    /// </summary>
    private static SoundId? MatchChord(int virtualKey)
    {
        bool win = Down(VK_LWIN) || Down(VK_RWIN);

        if (win)
        {
            // Win+Ctrl first, so its arrows are not read as bare Win chords.
            if (Down(VK_CONTROL))
            {
                return virtualKey switch
                {
                    VK_RIGHT => SoundId.DesktopNext,
                    VK_LEFT => SoundId.DesktopPrev,

                    // A new desktop, and closing this one. Same movement, so the same pair.
                    VK_D => SoundId.DesktopNext,
                    VK_F4 => SoundId.DesktopPrev,
                    _ => null
                };
            }

            if (Down(VK_SHIFT))
            {
                return virtualKey switch
                {
                    VK_S => SoundId.Shutter,
                    VK_T => SoundId.SwitchWindow,

                    // Move the window to the next monitor. It still lands, so it still knocks.
                    VK_LEFT or VK_RIGHT => SoundId.SnapWindow,
                    _ => null
                };
            }

            return virtualKey switch
            {
                VK_TAB => SoundId.TaskView,
                VK_V => SoundId.ClipboardHistory,
                VK_OEM_PERIOD or VK_OEM_1 => SoundId.EmojiPicker,
                VK_SNAPSHOT => SoundId.Shutter,
                VK_D or VK_M => SoundId.ShowDesktop,
                VK_L => SoundId.LockScreen,

                // Snapping. Left and right have arrived and go nowhere, so they get the bare knock;
                // up and down add the direction the window actually went.
                VK_LEFT or VK_RIGHT => SoundId.SnapWindow,
                VK_UP => SoundId.WindowGrow,
                VK_DOWN => SoundId.WindowShrink,

                // The panels: quick settings, settings, notifications, cast.
                VK_A or VK_I or VK_N or VK_K => SoundId.Panel,

                // Explorer, Run, Search.
                VK_E or VK_R or VK_S => SoundId.Launch,
                _ => null
            };
        }

        // Alt+Tab, and Alt+Shift+Tab going the other way round the switcher. Ctrl+Alt+Tab - the
        // variant that stays open - is the same gesture and gets the same sound.
        if (virtualKey == VK_TAB && Down(VK_MENU)) return SoundId.SwitchWindow;

        return null;
    }

    private void Play(SoundId sound)
    {
        long now = Stopwatch.GetTimestamp();
        double ticksPerMs = Stopwatch.Frequency / 1000.0;

        if (_lastPlayed != 0 && (now - _lastPlayed) / ticksPerMs < MinIntervalMs) return;
        _lastPlayed = now;

        if ((now - _configReadAt) / ticksPerMs > ConfigTtlMs) RefreshConfig(now);

        SoundEngine.Play(sound, _profile, _volume);
    }

    private static bool Down(int virtualKey)
    {
        return (NativeMethods.GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
