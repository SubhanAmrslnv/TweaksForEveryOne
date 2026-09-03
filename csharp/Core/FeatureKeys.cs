namespace WindowTweaks.Core;

/// <summary>
/// Every settings key in one place. They are persisted strings, so renaming one silently discards
/// that setting for existing users - treat them as a stored format, not as identifiers.
/// </summary>
internal static class FeatureKeys
{
    // Window management
    public const string AltDrag = "window.altDrag";
    public const string MagneticGroups = "window.magneticGroups";
    public const string MagneticSnap = "window.magneticSnap";
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
    // THESE TWO CARRY A "hotkey." PREFIX AND EVERY OTHER POWER FEATURE CARRIES "power.". Leave them
    // alone. The prefix is wrong, they were shipped that way, and they are already in users'
    // settings.json - so renaming them to match would silently discard whatever the user had chosen
    // for both features. The prefixes are a stored format, not a taxonomy; the page a feature
    // appears on comes from its FeatureDescriptor, not from its key.
    public const string AcousticKeyboard = "hotkey.acousticKeyboard";
    public const string TaskbarVolume = "hotkey.taskbarVolume";

    public const string ClipboardOsd = "power.clipboardOsd";
    public const string ShortcutSounds = "power.shortcutSounds";
    public const string TextFormat = "power.textFormat";
    public const string CursorLocator = "power.cursorLocator";
    public const string TextMagnifier = "power.textMagnifier";
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

    public const string SmartActiveBorder = "new.smartactiveborder";
    public const string GlobalTextExpander = "new.globaltextexpander";
    public const string ZeroDelayMenus = "new.zerodelaymenus";
    public const string SnappyTaskbarPreviews = "new.snappytaskbarpreviews";
    public const string SmoothScrolling = "new.smoothscrolling";
    public const string FadeInEaseOut = "new.fadeineaseout";
    public const string CustomTextCaret = "new.customtextcaret";
    public const string BouncySnapping = "new.bouncysnapping";
    public const string FocusPulse = "new.focuspulse";
    public const string GhostSlideIn = "new.ghostslidein";
    public const string MagneticSeamFlash = "new.magneticseamflash";
    public const string TheaterSpotlight = "new.theaterspotlight";
    public const string FlyToMouseMinimize = "new.flytomouseminimize";
    public const string WindowUnrolling = "new.windowunrolling";
    public const string ContextMenuUnfold = "new.contextmenuunfold";
    public const string ElasticDrag = "new.elasticdrag";
    public const string CursorYawnBreathe = "new.cursoryawnbreathe";
    public const string MomentumTilt = "new.momentumtilt";
    public const string BlackHoleMinimize = "new.blackholeminimize";
    public const string ResistanceEdge = "new.resistanceedge";
    public const string FocusDepth = "new.focusdepth";
    public const string CarouselAltTab = "new.carouselalttab";
    public const string DynamicNotch = "new.dynamicnotch";
    public const string CurtainDrop = "new.curtaindrop";
    public const string MotionBlurScroll = "new.motionblurscroll";
    public const string OverscrollBounce = "new.overscrollbounce";
    public const string TaskbarIconWave = "new.taskbariconwave";
    public const string StartMenuBlur = "new.startmenublur";
    public const string WindowThrowCatch = "new.windowthrowcatch";
    public const string LightsaberSeamGlow = "new.lightsaberseamglow";
    public const string PrivacyBlur = "new.privacyblur";

    /// <summary>
    /// What Game Mode switches off. Anything that steals focus, dims a window, animates, makes a
    /// sound, draws an overlay, installs a low-level hook, or repositions a window while a game is
    /// running.
    ///
    /// KEEPING THIS LIST COMPLETE IS THE WHOLE POINT OF GAME MODE. A feature that is missing from it
    /// is a feature that keeps a global input hook installed and keeps drawing top-most windows over
    /// a full-screen game - and it will be blamed on the game, not on this app, because Game Mode
    /// reported that it had suspended everything. Six of the entries below were missing after the
    /// last round of features was added: every one of them holds a mouse or keyboard hook.
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
        PositionMemory,

        // Added with the features themselves. Each one holds a low-level hook, and the first three
        // also make a sound or draw an overlay.
        AcousticKeyboard,
        ClipboardOsd,
        ShortcutSounds,
        CursorLocator,
        TextMagnifier,
        TaskbarVolume,
        TextFormat,

        // Stubs added
        SmartActiveBorder,
        GlobalTextExpander,
        ZeroDelayMenus,
        SnappyTaskbarPreviews,
        SmoothScrolling,
        FadeInEaseOut,
        CustomTextCaret,
        BouncySnapping,
        FocusPulse,
        GhostSlideIn,
        MagneticSeamFlash,
        TheaterSpotlight,
        FlyToMouseMinimize,
        WindowUnrolling,
        ContextMenuUnfold,
        ElasticDrag,
        CursorYawnBreathe,
        MomentumTilt,
        BlackHoleMinimize,
        ResistanceEdge,
        FocusDepth,
        CarouselAltTab,
        DynamicNotch,
        CurtainDrop,
        MotionBlurScroll,
        OverscrollBounce,
        TaskbarIconWave,
        StartMenuBlur,
        WindowThrowCatch,
        LightsaberSeamGlow,
        PrivacyBlur
    };
}
