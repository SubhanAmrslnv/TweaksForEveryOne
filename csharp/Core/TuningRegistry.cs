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
            Title = "Ring size", Unit = "px", Min = 10, Max = 200, Default = 44,
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
            Title = "Sit left of", DefaultText = "TrayEdge",
            Choices = new[] { "TrayEdge", "Clock" },
            ChoiceLabels = new[] { "The whole tray (safe)", "The system clock (closer)" },
            Description = "A real trade-off. The tray edge never covers anything but sits further left, because the notification area's width moves with its icon count. The clock sits closer and covers whatever is in those last ~115 px."
        },
        new TuningDescriptor
        {
            Key = ClockGap, Page = PageScreen, Group = "Taskbar clock",
            Title = "Gap from anchor", Unit = "px", Min = 0, Max = 400, Default = 12,
            Description = "Distance between the block and whatever it sits to the left of."
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
