using System;
using System.Collections.Generic;
using System.Globalization;

namespace WindowTweaks.Core;

/// <summary>How a tuning value is edited, and therefore which control the settings window builds.</summary>
internal enum TuningKind
{
    /// <summary>A whole number with a unit, edited on a slider with a live readout.</summary>
    Integer,

    /// <summary>A whole number that means a percentage. Stored 0-100; features divide by 100.</summary>
    Percent,

    /// <summary>Free text, committed when the field loses focus.</summary>
    Text,

    /// <summary>One of a fixed set of values, edited in a drop-down.</summary>
    Choice
}

/// <summary>
/// One tunable number, string or choice: its key, its range, its default, and the words the settings
/// window shows for it.
/// </summary>
internal sealed class TuningDescriptor
{
    public required string Key { get; init; }
    public required string Title { get; init; }
    public required string Description { get; init; }
    public required string Page { get; init; }
    public required string Group { get; init; }

    public TuningKind Kind { get; init; } = TuningKind.Integer;

    public int Min { get; init; }
    public int Max { get; init; }
    public int Default { get; init; }
    public string Unit { get; init; } = string.Empty;

    public string DefaultText { get; init; } = string.Empty;

    /// <summary>Stored values for a Choice, paired index-for-index with <see cref="ChoiceLabels"/>.</summary>
    public string[] Choices { get; init; } = Array.Empty<string>();

    /// <summary>What the user sees for each choice.</summary>
    public string[] ChoiceLabels { get; init; } = Array.Empty<string>();
}

/// <summary>
/// Every tunable value in one place: the key, the range, the default and the copy.
///
/// This exists for the same reason FeatureKeys does. The tuning keys used to be private consts
/// scattered through the features that owned them, while the settings window addressed the same
/// values with duplicated string literals - so "parallax.fromSpeed" was written twice, in two files,
/// with nothing keeping them in step, and its range and default were a third copy inside the feature.
/// Now a setting is declared once and both sides read it from here.
///
/// THE KEYS ARE A STORED FORMAT. Renaming one silently discards that setting for existing users, so
/// treat them as data, not identifiers. The keys carried over from the earlier build keep their
/// original spelling for exactly that reason.
///
/// Reads are cheap but NOT free - each one takes the settings lock and parses a string. Read a value
/// once per operation into a local; never inside a per-window or per-frame loop. Where a value is
/// consumed on a hot path the feature caches it at the start of the gesture instead.
/// </summary>
internal static class TuningRegistry
{
    // --- Snapping -----------------------------------------------------------------------------
    public const string SnapDistance = "snap.distance";
    public const string SnapCornerBoost = "snap.cornerBoost";
    public const string SnapNeighbourProximity = "snap.neighbourProximity";
    public const string SnapHysteresis = "snap.hysteresis";

    // --- Transparency -------------------------------------------------------------------------
    public const string TransparencyStep = "transparency.step";

    // --- Breathing ----------------------------------------------------------------------------
    public const string BreathingIdleSeconds = "breathing.idleSeconds";
    public const string BreathingDimPercent = "breathing.dimPercent";
    public const string BreathingExemptAudio = "breathing.exemptAudio";
    public const string BreathingExcludeProcesses = "breathing.excludeProcesses";

    // --- Proximity ghost ----------------------------------------------------------------------
    public const string GhostMaxDistance = "ghost.maxDistance";
    public const string GhostMinOpacity = "ghost.minOpacity";
    public const string GhostClickDistance = "ghost.clickDistance";

    // --- Parallax (keys carried over from the earlier build) ----------------------------------
    public const string ParallaxFromSpeed = "parallax.fromSpeed";
    public const string ParallaxFullSpeed = "parallax.fullSpeed";
    public const string ParallaxMinOpacity = "parallax.minOpacity";

    // --- Ripple -------------------------------------------------------------------------------
    public const string RippleRadius = "ripple.radius";
    public const string RippleDurationMs = "ripple.durationMs";

    // --- Gestures -----------------------------------------------------------------------------
    public const string SmartCapsHoldMs = "smartcaps.holdMs";
    public const string DoubleTapTimeoutMs = "doubletap.timeoutMs";
    public const string StealthTimeoutMs = "stealth.timeoutMs";

    // --- Clock (keys carried over from the earlier build) -------------------------------------
    public const string ClockLocation = "clock.location";
    public const string ClockUnits = "clock.units";
    public const string ClockTimeFormat = "clock.timeFormat";
    public const string ClockDateFormat = "clock.dateFormat";
    public const string ClockGap = "clock.gap";
    public const string ClockAnchor = "clock.anchor";
    public const string ClockFontSizeTime = "clock.fontSizeTime";
    public const string ClockFontSizeDate = "clock.fontSizeDate";

    /// <summary>
    /// Keep the block inside the taskbar's height. Without this a large font size makes the two-row
    /// block taller than the bar it sits on, so it overhangs onto the screen and covers whatever is
    /// above it.
    /// </summary>
    public const string ClockFitToTaskbar = "clock.fitToTaskbar";

    // --- Sound --------------------------------------------------------------------------------
    // One profile for the whole app, so the keyboard clicks and the clipboard confirmations sound
    // like the same instrument. Volumes are per feature, because the useful level for a click you
    // hear a hundred times a minute is not the useful level for a confirmation you hear twice.
    public const string KeyboardSoundProfile = "sound.profile";
    public const string KeyboardSoundVolume = "sound.keyboardVolume";
    public const string ClipboardSoundVolume = "sound.clipboardVolume";
    public const string ClipboardShowOsd = "sound.clipboardOsd";
    public const string VolumeTickVolume = "sound.volumeTickVolume";

    // --- Taskbar volume wheel -----------------------------------------------------------------
    public const string VolumeWheelStep = "volume.wheelStep";
    public const string VolumeMiddleClickMute = "volume.middleClickMute";

    // --- Cursor locator -----------------------------------------------------------------------
    public const string LocatorShakeDistance = "locator.shakeDistance";
    public const string LocatorShakeRatio = "locator.shakeRatio";
    public const string LocatorRingSize = "locator.ringSize";

    // --- Text magnifier -----------------------------------------------------------------------
    public const string MagnifierZoom = "magnifier.zoom";
    public const string MagnifierLensSize = "magnifier.lensSize";
    public const string MagnifierDragThreshold = "magnifier.dragThreshold";

    // --- Middle click and grab & pan ----------------------------------------------------------
    public const string MiddleClickSkipBrowsers = "middleClick.skipBrowsers";
    public const string GrabPanHoldMs = "grabPan.holdMs";
    public const string GrabPanStep = "grabPan.step";

    // --- Smart Caps Lock ----------------------------------------------------------------------
    public const string SmartCapsTapAction = "smartcaps.tapAction";
    public const string SmartCapsShiftTapAction = "smartcaps.shiftTapAction";

    // --- Smart taskbar ------------------------------------------------------------------------
    public const string TaskbarHideScope = "taskbar.hideScope";

    private const string PageWindow = "Window Management";
    private const string PageOpacity = "Opacity & Effects";
    private const string PageAnimation = "Animation";
    private const string PagePower = "Power Features";
    private const string PageScreen = "Screen & Shell";

    private static readonly List<TuningDescriptor> AllItems = new()
    {
        // --- Snapping -------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = SnapDistance, Page = PageWindow, Group = "Snapping",
            Title = "Base snap reach", Unit = "px", Min = 5, Max = 200, Default = 30,
            Description = "How close an edge has to be before the window grabs it. The reach actually used scales up with how hard you throw the window."
        },
        new TuningDescriptor
        {
            Key = SnapCornerBoost, Page = PageWindow, Group = "Snapping", Kind = TuningKind.Percent,
            Title = "Corner boost", Unit = "%", Min = 100, Max = 400, Default = 220,
            Description = "Once one axis has snapped, the other is retried at this much of the normal reach. It is what makes corners feel sticky without making plain edges greedy."
        },
        new TuningDescriptor
        {
            Key = SnapNeighbourProximity, Page = PageWindow, Group = "Snapping",
            Title = "Neighbour range", Unit = "px", Min = 0, Max = 500, Default = 90,
            Description = "Another window offers its edges as snap targets only while it is within this distance on the other axis. Set it to 0 to snap to screen edges only."
        },
        new TuningDescriptor
        {
            Key = SnapHysteresis, Page = PageWindow, Group = "Snapping",
            Title = "Hysteresis", Unit = "px", Min = 0, Max = 50, Default = 5,
            Description = "A target this close wins over a slightly nearer rival, so a window already touching an edge does not flick between two of them."
        },

        // --- Transparency ---------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = TransparencyStep, Page = PageOpacity, Group = "Transparency wheel",
            Title = "Step per wheel notch", Unit = "alpha", Min = 5, Max = 64, Default = 25,
            Description = "How much one notch of Shift+Alt+Wheel changes opacity, out of 255. About 25 gives ten steps from solid to nearly invisible."
        },

        // --- Breathing ------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = BreathingIdleSeconds, Page = PageOpacity, Group = "Breathing windows",
            Title = "Idle before fading", Unit = "s", Min = 1, Max = 120, Default = 5,
            Description = "How long a window must go without focus or a cursor over it before it fades."
        },
        new TuningDescriptor
        {
            Key = BreathingDimPercent, Page = PageOpacity, Group = "Breathing windows", Kind = TuningKind.Percent,
            Title = "Faded opacity", Unit = "%", Min = 10, Max = 100, Default = 47,
            Description = "How solid an idle window stays. This multiplies with any opacity you set by hand, so a window already at 50% breathes between 50% and this fraction of it."
        },
        new TuningDescriptor
        {
            Key = BreathingExemptAudio, Page = PageOpacity, Group = "Breathing windows", Kind = TuningKind.Choice,
            Title = "Leave anything playing sound alone", DefaultText = "on",
            Choices = new[] { "on", "off" },
            ChoiceLabels = new[] { "Never fade an app that is playing sound", "Fade it like anything else" },
            Description = "This is what keeps a video in an ordinary window from fading while you watch it. It works per APPLICATION, not per window: while a browser is playing anything, none of its windows fade. A music player counts as playing sound too, so switch this off if you would rather Spotify faded while it plays. Picture-in-Picture and fullscreen video are never faded either way."
        },
        new TuningDescriptor
        {
            Key = BreathingExcludeProcesses, Page = PageOpacity, Group = "Breathing windows", Kind = TuningKind.Text,
            Title = "Never fade these apps",
            DefaultText = "vlc,mpv,mpc-hc64,mpc-hc,potplayermini64,wmplayer",
            Description = "Comma-separated process names without .exe - the names in Task Manager's Details tab. These never fade whether or not they are playing sound, which covers a video paused on a frame you are looking at. Takes effect when you click away from this box."
        },

        // --- Proximity ghost ------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = GhostMaxDistance, Page = PageOpacity, Group = "Proximity ghost",
            Title = "Fade distance", Unit = "px", Min = 100, Max = 2000, Default = 400,
            Description = "How far from the window the cursor has to be for it to reach its most transparent."
        },
        new TuningDescriptor
        {
            Key = GhostMinOpacity, Page = PageOpacity, Group = "Proximity ghost", Kind = TuningKind.Percent,
            Title = "Ghosted opacity", Unit = "%", Min = 5, Max = 100, Default = 20,
            Description = "How solid a ghosted window is while the cursor is far away."
        },
        new TuningDescriptor
        {
            Key = GhostClickDistance, Page = PageOpacity, Group = "Proximity ghost",
            Title = "Clickable within", Unit = "px", Min = 0, Max = 400, Default = 50,
            Description = "Inside this distance the ghost stops being click-through and takes the mouse again."
        },

        // --- Parallax -------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = ParallaxFromSpeed, Page = PageOpacity, Group = "Parallax dragging",
            Title = "Start fading at", Unit = "px/s", Min = 0, Max = 5000, Default = 250,
            Description = "Below this drag speed nothing fades at all, so a deliberate slow drag stays solid."
        },
        new TuningDescriptor
        {
            Key = ParallaxFullSpeed, Page = PageOpacity, Group = "Parallax dragging",
            Title = "Fully faded at", Unit = "px/s", Min = 100, Max = 20000, Default = 2200,
            Description = "The speed at which the window reaches the minimum opacity below. Both ends are named on purpose: a single gain reads correctly on paper and is indistinguishable from switched off in the hand."
        },
        new TuningDescriptor
        {
            Key = ParallaxMinOpacity, Page = PageOpacity, Group = "Parallax dragging", Kind = TuningKind.Percent,
            Title = "Minimum opacity", Unit = "%", Min = 10, Max = 100, Default = 55,
            Description = "How transparent a fast-moving window gets."
        },

        // --- Ripple ---------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = RippleRadius, Page = PageAnimation, Group = "Ripple click",
            Title = "Ring size", Unit = "px", Min = 10, Max = 200, Default = 22,
            Description = "How far the ring expands from the cursor before it finishes fading."
        },
        new TuningDescriptor
        {
            Key = RippleDurationMs, Page = PageAnimation, Group = "Ripple click",
            Title = "Duration", Unit = "ms", Min = 100, Max = 2000, Default = 420,
            Description = "How long one ripple takes. Longer values overlap more rings when clicking quickly."
        },

        // --- Gestures -------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = SmartCapsHoldMs, Page = PagePower, Group = "Gesture timing",
            Title = "Caps Lock hold", Unit = "ms", Min = 150, Max = 1500, Default = 400,
            Description = "Hold Caps Lock longer than this and it really toggles Caps Lock; a shorter tap sends Escape."
        },
        new TuningDescriptor
        {
            Key = DoubleTapTimeoutMs, Page = PagePower, Group = "Gesture timing",
            Title = "Double-tap window", Unit = "ms", Min = 150, Max = 1000, Default = 400,
            Description = "How close together the two taps of Alt or Ctrl have to be. Raise it if the gesture keeps missing; lower it if it fires while you are typing."
        },
        new TuningDescriptor
        {
            Key = StealthTimeoutMs, Page = PagePower, Group = "Gesture timing",
            Title = "Triple-Escape window", Unit = "ms", Min = 200, Max = 2000, Default = 600,
            Description = "How long the three taps of Escape may take in total."
        },

        // --- Clock ----------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = ClockLocation, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Text,
            Title = "Weather city", DefaultText = "",
            Description = "The city the clock's weather is for, e.g. Baku. Leave it empty and the app makes no network request at all - weather is the only feature that connects to the internet."
        },
        new TuningDescriptor
        {
            Key = ClockUnits, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Choice,
            Title = "Units", DefaultText = "metric",
            Choices = new[] { "metric", "imperial" },
            ChoiceLabels = new[] { "Metric (C, km/h)", "Imperial (F, mph)" },
            Description = "Which units the weather line uses."
        },
        new TuningDescriptor
        {
            Key = ClockTimeFormat, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Text,
            Title = "Time format", DefaultText = "HH:mm:ss",
            Description = "A standard .NET format string. HH is 24-hour, hh is 12-hour."
        },
        new TuningDescriptor
        {
            Key = ClockDateFormat, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Text,
            Title = "Date format", DefaultText = "dd.MM.yyyy",
            Description = "A standard .NET format string. Use dd:MM:yyyy if you want colons as separators."
        },
        new TuningDescriptor
        {
            Key = ClockAnchor, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Choice,
            Title = "Placement", DefaultText = "TaskbarLeft",
            Choices = new[] { "TaskbarLeft", "TrayEdge", "Clock" },
            ChoiceLabels = new[] { "Left edge of taskbar", "Right: whole tray (safe)", "Right: system clock (closer)" },
            Description = "Where the clock sits. Taskbar Left is best for Windows 11 with centered buttons. Right side sits to the left of the system tray."
        },
        new TuningDescriptor
        {
            Key = ClockGap, Page = PageScreen, Group = "Taskbar clock",
            Title = "Gap from anchor", Unit = "px", Min = 0, Max = 400, Default = 12,
            Description = "Distance between the block and whatever it sits to the left of."
        },
        new TuningDescriptor
        {
            Key = ClockFontSizeTime, Page = PageScreen, Group = "Taskbar clock",
            Title = "Time font size", Unit = "px", Min = 8, Max = 40, Default = 13,
            Description = "Font size for the time and weather glyph."
        },
        new TuningDescriptor
        {
            Key = ClockFontSizeDate, Page = PageScreen, Group = "Taskbar clock",
            Title = "Date font size", Unit = "px", Min = 8, Max = 40, Default = 11,
            Description = "Font size for the date and weather conditions."
        },
        new TuningDescriptor
        {
            Key = ClockFitToTaskbar, Page = PageScreen, Group = "Taskbar clock", Kind = TuningKind.Choice,
            Title = "Fit inside the taskbar", DefaultText = "on",
            Choices = new[] { "on", "off" },
            ChoiceLabels = new[] { "Shrink the text to fit the bar", "Use the exact sizes above" },
            Description = "The block has two rows, so a large font size can make it taller than the taskbar - at which point it overhangs onto the screen and covers whatever is above it. Leave this on unless you have deliberately made the taskbar tall."
        },

        // --- Sound ----------------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = KeyboardSoundProfile, Page = PagePower, Group = "Sound", Kind = TuningKind.Choice,
            Title = "Sound profile", DefaultText = "click",
            Choices = new[] { "click", "typewriter", "soft" },
            ChoiceLabels = new[] { "Click - short and dry", "Typewriter - heavier thock", "Soft - a quiet tone" },
            Description = "The instrument for every sound the app makes. Each sound is generated in memory, so there are no audio files and nothing is read from disk while you type."
        },
        new TuningDescriptor
        {
            Key = KeyboardSoundVolume, Page = PagePower, Group = "Sound", Kind = TuningKind.Percent,
            Title = "Keystroke volume", Unit = "%", Min = 0, Max = 100, Default = 35,
            Description = "How loud a keystroke is. This is a sound you hear hundreds of times a minute, so it wants to be quieter than you first think. Zero silences it without switching the feature off."
        },
        new TuningDescriptor
        {
            Key = ClipboardSoundVolume, Page = PagePower, Group = "Sound", Kind = TuningKind.Percent,
            Title = "Copy and paste volume", Unit = "%", Min = 0, Max = 100, Default = 55,
            Description = "How loud the copy, paste, cut and select-all confirmations are."
        },
        new TuningDescriptor
        {
            Key = ClipboardShowOsd, Page = PagePower, Group = "Sound", Kind = TuningKind.Choice,
            Title = "Show the clipboard label", DefaultText = "on",
            Choices = new[] { "on", "off" },
            ChoiceLabels = new[] { "Ring and label at the cursor", "Sound only" },
            Description = "Whether copy, paste, cut and select-all also draw a coloured ring and a word at the pointer, or only make their sound."
        },
        new TuningDescriptor
        {
            Key = VolumeTickVolume, Page = PagePower, Group = "Sound", Kind = TuningKind.Percent,
            Title = "Volume wheel tick", Unit = "%", Min = 0, Max = 100, Default = 25,
            Description = "How loud each notch of the taskbar volume wheel is."
        },

        // --- Taskbar volume wheel -------------------------------------------------------------
        new TuningDescriptor
        {
            Key = VolumeWheelStep, Page = PagePower, Group = "Taskbar volume",
            Title = "Step per notch", Unit = "%", Min = 1, Max = 20, Default = 3,
            Description = "How much one notch of the wheel moves the volume. Windows' own volume keys are fixed at two percent."
        },
        new TuningDescriptor
        {
            Key = VolumeMiddleClickMute, Page = PagePower, Group = "Taskbar volume", Kind = TuningKind.Choice,
            Title = "Middle-click to mute", DefaultText = "on",
            Choices = new[] { "on", "off" },
            ChoiceLabels = new[] { "Middle-click the taskbar mutes", "Leave middle-click alone" },
            Description = "Only applies over the taskbar itself. Switch it off if you use middle-click on the taskbar for something else."
        },

        // --- Cursor locator -------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = LocatorShakeDistance, Page = PagePower, Group = "Cursor locator",
            Title = "Shake effort", Unit = "px", Min = 200, Max = 3000, Default = 900,
            Description = "How far the pointer has to travel in half a second to count as a shake. Lower is easier to trigger, and easier to trigger by accident."
        },
        new TuningDescriptor
        {
            Key = LocatorShakeRatio, Page = PagePower, Group = "Cursor locator",
            Title = "Shake tightness", Unit = "/10", Min = 15, Max = 80, Default = 30,
            Description = "How much of that travel has to cancel itself out: 30 means the path was at least three times longer than the distance actually covered. This is what separates a shake from crossing the screen to click something."
        },
        new TuningDescriptor
        {
            Key = LocatorRingSize, Page = PagePower, Group = "Cursor locator",
            Title = "Ring size", Unit = "px", Min = 80, Max = 600, Default = 260,
            Description = "How large the rings start before they converge on the pointer."
        },

        // --- Text magnifier -------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = MagnifierZoom, Page = PagePower, Group = "Text magnifier",
            Title = "Magnification", Unit = "x", Min = 2, Max = 8, Default = 3,
            Description = "How much the lens enlarges. Takes effect the next time the feature is switched on, because the capture buffers are sized once rather than per frame."
        },
        new TuningDescriptor
        {
            Key = MagnifierLensSize, Page = PagePower, Group = "Text magnifier",
            Title = "Lens size", Unit = "px", Min = 80, Max = 320, Default = 130,
            Description = "The diameter of the round lens. Like magnification, it takes effect the next time the feature is switched on, because the capture buffers are sized once rather than per frame."
        },
        new TuningDescriptor
        {
            Key = MagnifierDragThreshold, Page = PagePower, Group = "Text magnifier",
            Title = "Appears after", Unit = "px", Min = 4, Max = 120, Default = 18,
            Description = "How far a left-drag has to move before the lens appears. It only appears for a drag that moves mostly sideways, so scrolling, dragging a file and moving a window are left alone."
        },

        // --- Middle click and grab & pan ------------------------------------------------------
        new TuningDescriptor
        {
            Key = MiddleClickSkipBrowsers, Page = PageWindow, Group = "Movement & Dragging", Kind = TuningKind.Choice,
            Title = "Middle-click close: browsers", DefaultText = "skip",
            Choices = new[] { "skip", "include" },
            ChoiceLabels = new[] { "Never close a browser window", "Treat browsers like anything else" },
            Description = "A browser's tab strip IS its title bar, so middle-clicking the empty space beside the tabs would close the whole window instead of a tab. Leave this on skip unless you never middle-click near a tab strip."
        },
        new TuningDescriptor
        {
            Key = GrabPanHoldMs, Page = PagePower, Group = "Grab & pan",
            Title = "Hold before panning", Unit = "ms", Min = 0, Max = 600, Default = 180,
            Description = "Hold the middle button this long and any movement then pans; move it further than a few pixels straight away and it pans immediately. A middle click that never moves is always passed straight through, however long you hold it - which is what keeps middle-click opening and closing browser tabs."
        },
        new TuningDescriptor
        {
            Key = GrabPanStep, Page = PagePower, Group = "Grab & pan",
            Title = "Pan sensitivity", Unit = "px", Min = 5, Max = 100, Default = 22,
            Description = "How far the pointer has to move for one notch of scrolling. Lower is faster."
        },

        // --- Smart Caps Lock ------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = SmartCapsTapAction, Page = PagePower, Group = "Smart Caps Lock", Kind = TuningKind.Choice,
            Title = "A tap sends", DefaultText = "escape",
            Choices = new[] { "escape", "backspace" },
            ChoiceLabels = new[] { "Escape", "Backspace" },
            Description = "What a short tap of Caps Lock does. Holding it always toggles Caps Lock for real."
        },
        new TuningDescriptor
        {
            Key = SmartCapsShiftTapAction, Page = PagePower, Group = "Smart Caps Lock", Kind = TuningKind.Choice,
            Title = "Shift and a tap send", DefaultText = "backspace",
            Choices = new[] { "backspace", "escape", "delete", "none" },
            ChoiceLabels = new[] { "Backspace", "Escape", "Delete", "Nothing" },
            Description = "The second key you can reach from Caps Lock, so it can be both Escape and Backspace without giving up either."
        },

        // --- Smart taskbar --------------------------------------------------------------------
        new TuningDescriptor
        {
            Key = TaskbarHideScope, Page = PageScreen, Group = "Taskbar", Kind = TuningKind.Choice,
            Title = "Auto-hide applies when", DefaultText = "all",
            Choices = new[] { "all", "primary" },
            ChoiceLabels = new[] { "Every taskbar is covered", "The primary one is covered" },
            Description = "Windows' auto-hide setting is a single switch for ALL taskbars, so a decision taken from the primary monitor alone also hid the second monitor's bar - with nothing on that monitor to explain why. On 'all' the bars hide only when every one of them is actually covered."
        }
    };

    private static readonly Dictionary<string, TuningDescriptor> ByKey = BuildIndex();

    private static Dictionary<string, TuningDescriptor> BuildIndex()
    {
        Dictionary<string, TuningDescriptor> map = new(StringComparer.OrdinalIgnoreCase);
        foreach (TuningDescriptor d in AllItems)
        {
            // A duplicated key would mean two controls fighting over one stored value. Fail loudly
            // at startup rather than shipping a setting that silently does not stick.
            if (map.ContainsKey(d.Key))
                throw new InvalidOperationException("Duplicate tuning key: " + d.Key);
            map[d.Key] = d;
        }
        return map;
    }

    public static IReadOnlyList<TuningDescriptor> Items => AllItems;

    public static TuningDescriptor? Find(string key)
    {
        return ByKey.TryGetValue(key, out TuningDescriptor? d) ? d : null;
    }

    public static IEnumerable<TuningDescriptor> ForPage(string page)
    {
        foreach (TuningDescriptor d in AllItems)
        {
            if (string.Equals(d.Page, page, StringComparison.OrdinalIgnoreCase)) yield return d;
        }
    }

    /// <summary>The stored value, clamped to the descriptor's range. Falls back to the default.</summary>
    public static int Int(string key)
    {
        TuningDescriptor? d = Find(key);
        if (d == null) return 0;
        return SettingsStore.GetInt(key, d.Default, d.Min, d.Max);
    }

    /// <summary>A Percent value as a 0.0-1.0 multiplier.</summary>
    public static double Fraction(string key)
    {
        return Int(key) / 100.0;
    }

    public static string Text(string key)
    {
        TuningDescriptor? d = Find(key);
        if (d == null) return string.Empty;
        return SettingsStore.GetString(key, d.DefaultText);
    }

    /// <summary>
    /// True when a Choice tuning currently holds <paramref name="option"/>.
    ///
    /// Most of the Choice settings in this app have exactly two options and are read as flags, and
    /// the comparison was open-coded at five call sites - each supplying its own literal and its own
    /// StringComparison, which is how one of them ends up case-sensitive by accident.
    /// </summary>
    public static bool Is(string key, string option)
    {
        return string.Equals(Choice(key), option, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>A Choice value, guaranteed to be one of the descriptor's options.</summary>
    public static string Choice(string key)
    {
        TuningDescriptor? d = Find(key);
        if (d == null) return string.Empty;

        string stored = SettingsStore.GetString(key, d.DefaultText);
        foreach (string option in d.Choices)
        {
            if (string.Equals(stored, option, StringComparison.OrdinalIgnoreCase)) return option;
        }
        return d.DefaultText;
    }

    public static void SetInt(string key, int value)
    {
        TuningDescriptor? d = Find(key);
        if (d == null) return;
        SettingsStore.SetInt(key, Math.Clamp(value, d.Min, d.Max));
    }

    public static void SetText(string key, string value)
    {
        SettingsStore.SetString(key, value ?? string.Empty);
    }

    /// <summary>Formats a value for the readout beside its slider.</summary>
    public static string Display(TuningDescriptor d, int value)
    {
        string number = value.ToString(CultureInfo.InvariantCulture);
        return d.Unit.Length == 0 ? number : number + " " + d.Unit;
    }
}
