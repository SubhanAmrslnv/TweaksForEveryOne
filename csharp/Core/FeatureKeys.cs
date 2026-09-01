namespace WindowTweaks.Core;

/// <summary>
/// Every settings key in one place. They are persisted strings, so renaming one silently discards
/// that setting for existing users - treat them as a stored format, not as identifiers.
/// </summary>
internal static class FeatureKeys
{
    // Window management
    public const string AltDrag = "window.altDrag";
    public const string MagneticSnap = "window.magneticSnap";
    public const string MagneticGroups = "window.magneticGroups";
    public const string PositionMemory = "window.positionMemory";
    public const string MiddleClickClose = "window.middleClickClose";
    public const string RollUp = "window.rollUp";
    public const string TrayMinimize = "window.trayMinimize";
    public const string AlwaysOnTop = "window.alwaysOnTop";
    public const string AlwaysOnBottom = "window.alwaysOnBottom";
    public const string LivePip = "window.livePip";

    // Opacity and ambient effects
    public const string TransparencyWheel = "opacity.transparencyWheel";
    public const string DragParallax = "opacity.dragParallax";
    public const string Breathing = "opacity.breathing";
    public const string ProximityGhost = "opacity.proximityGhost";
    public const string MonitorDimmer = "opacity.monitorDimmer";
    public const string FocusMode = "opacity.focusMode";

    // Animation
    public const string RippleClick = "anim.rippleClick";
    public const string GravityClose = "anim.gravityClose";
    public const string ShatterClose = "anim.shatterClose";

    // Power features
    public const string PlainPaste = "power.plainPaste";
    public const string QuickFolderJump = "power.quickFolderJump";
    public const string QuickLook = "power.quickLook";
    public const string Spotlight = "power.spotlight";
    public const string MicMute = "power.micMute";
    public const string SmartCaps = "power.smartCaps";
    public const string StealthPanic = "power.stealthPanic";
    public const string GrabPan = "power.grabPan";

    // The double-tap triggers are separate from the hotkey that does the same thing: a user
    // may well want Shift+Alt+A but not have every double-tap of Alt mute their microphone.
    public const string DoubleAltMic = "power.doubleAltMic";
    public const string DoubleCtrlSpotlight = "power.doubleCtrlSpotlight";

    // Screen and shell
    public const string HotCorners = "screen.hotCorners";
    public const string InfiniteWrap = "screen.infiniteWrap";
    public const string SmartTaskbar = "screen.smartTaskbar";
    public const string CustomClock = "screen.customClock";

    // Weather is a SEPARATE key from the clock, and defaults off, because it is the only
    // feature in the app that makes a network connection. See docs/ANTIVIRUS.md.
    public const string ClockWeather = "screen.clockWeather";

    // General
    public const string StartWithWindows = "general.startWithWindows";

    /// <summary>
    /// What Game Mode switches off. Anything that steals focus, dims a window, animates, installs
    /// a low-level hook on the mouse, or repositions a window while a game is running.
    ///
    /// Deliberately NOT suspended: the pure hotkey commands (always-on-top, tray minimize, plain
    /// paste, the layout keys). They only act when explicitly pressed, so they cost a game nothing.
    /// </summary>
    public static readonly string[] GameModeSuspends =
    {
        AltDrag,
        MagneticSnap,
        MagneticGroups,
        MiddleClickClose,
        TransparencyWheel,
        DragParallax,
        Breathing,
        ProximityGhost,
        MonitorDimmer,
        FocusMode,
        RippleClick,
        SmartCaps,
        GrabPan,
        DoubleAltMic,
        DoubleCtrlSpotlight,
        HotCorners,
        InfiniteWrap,
        SmartTaskbar,
        CustomClock,
        ClockWeather,
        PositionMemory
    };
}
