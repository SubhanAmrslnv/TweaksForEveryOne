using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Threading;
using WindowTweaks.Core;
using WindowTweaks.Features;

namespace WindowTweaks;

/// <summary>
/// The composition root. Every feature is constructed here, described to FeatureRegistry here, and
/// disposed here.
///
/// Two rules this file exists to enforce:
///
/// 1. NOTHING TOGGLES A FEATURE DIRECTLY. A hotkey, a tray item and a settings checkbox all go
///    through FeatureRegistry, which owns the state, applies it and persists it. That is what keeps
///    the settings window honest - it used to show hardcoded checkboxes wired to nothing.
///
/// 2. EVERY FEATURE IS DISPOSED. Five of them used to be missing from OnExit, which meant exiting
///    could leave foreign windows dimmed or transparent, and could leave a window hidden with no
///    tray icon left to restore it.
/// </summary>
public partial class App : System.Windows.Application
{
    private SystemTrayManager? _systemTrayManager;
    private HotkeyManager? _hotkeyManager;
    private MainWindow? _settingsWindow;
    private DispatcherTimer? _housekeeping;
    private ShutdownListener? _shutdownListener;

    // --- Global toggles ---
    private readonly MagneticSnappingFeature _magneticSnappingFeature = new();
    private readonly MagneticGroupsFeature _magneticGroupsFeature = new();
    private readonly PositionMemoryFeature _positionMemoryFeature = new();
    private readonly BreathingFeature _breathingFeature = new();
    private readonly MultiMonitorDimmerFeature _multiMonitorDimmerFeature = new();
    private readonly HotCornersFeature _hotCornersFeature = new();
    private readonly InfiniteWrapFeature _infiniteWrapFeature = new();
    private readonly SmartTaskbarFeature _smartTaskbarFeature = new();
    private readonly GrabPanFeature _grabPanFeature = new();
    private readonly CustomClockFeature _customClockFeature = new();
    private readonly SmartCapsFeature _smartCapsFeature = new();
    private readonly ChangeTransparencyFeature _changeTransparencyFeature = new();
    private readonly DragParallaxFeature _dragParallaxFeature = new();
    private readonly RippleClickFeature _rippleClickFeature = new();
    private readonly MiddleClickCloseFeature _middleClickCloseFeature = new();
    private readonly ShortcutSoundsFeature _shortcutSoundsFeature = new();
    private readonly TaskbarVolumeFeature _taskbarVolumeFeature = new();
    private readonly ClipboardOsdFeature _clipboardOsdFeature = new();

    // Built in the constructor, not in a field initialiser: they take one of the features above, and
    // C# forbids one instance field initialiser from referring to another (CS0236). Not in
    // OnStartup either - a readonly field assigned there would have to be nullable, and every use
    // site would then carry a null-forgiving operator for a field that is never null.
    private readonly TextFormatFeature _textFormatFeature;

    // Takes the shortcut sounds so it can stand aside for a chord that has a sound of its own -
    // otherwise Win+V is a clipboard-history sound with a letter click on top of it.
    private readonly AcousticKeyboardFeature _acousticKeyboardFeature;

    private readonly CursorLocatorFeature _cursorLocatorFeature = new();

    private readonly TextMagnifierFeature _textMagnifierFeature = new();

    // --- New Features ---
    private readonly SmartActiveBorderFeature _smartActiveBorderFeature = new();
    private readonly GlobalTextExpanderFeature _globalTextExpanderFeature = new();
    private readonly ZeroDelayMenusFeature _zeroDelayMenusFeature = new();
    private readonly SnappyTaskbarPreviewsFeature _snappyTaskbarPreviewsFeature = new();
    private readonly SmoothScrollingFeature _smoothScrollingFeature = new();
    private readonly FadeInEaseOutFeature _fadeInEaseOutFeature = new();
    private readonly CustomTextCaretFeature _customTextCaretFeature = new();
    private readonly BouncySnappingFeature _bouncySnappingFeature = new();
    private readonly FocusPulseFeature _focusPulseFeature = new();
    private readonly GhostSlideInFeature _ghostSlideInFeature = new();
    private readonly MagneticSeamFlashFeature _magneticSeamFlashFeature = new();
    private readonly TheaterSpotlightFeature _theaterSpotlightFeature = new();
    private readonly FlyToMouseMinimizeFeature _flyToMouseMinimizeFeature = new();
    private readonly WindowUnrollingFeature _windowUnrollingFeature = new();
    private readonly ContextMenuUnfoldFeature _contextMenuUnfoldFeature = new();
    private readonly ElasticDragFeature _elasticDragFeature = new();
    private readonly CursorYawnBreatheFeature _cursorYawnBreatheFeature = new();
    private readonly MomentumTiltFeature _momentumTiltFeature = new();
    private readonly BlackHoleMinimizeFeature _blackHoleMinimizeFeature = new();
    private readonly ResistanceEdgeFeature _resistanceEdgeFeature = new();
    private readonly FocusDepthFeature _focusDepthFeature = new();
    private readonly CarouselAltTabFeature _carouselAltTabFeature = new();
    private readonly DynamicNotchFeature _dynamicNotchFeature = new();
    private readonly CurtainDropFeature _curtainDropFeature = new();
    private readonly MotionBlurScrollFeature _motionBlurScrollFeature = new();
    private readonly OverscrollBounceFeature _overscrollBounceFeature = new();
    private readonly TaskbarIconWaveFeature _taskbarIconWaveFeature = new();
    private readonly StartMenuBlurFeature _startMenuBlurFeature = new();
    private readonly WindowThrowCatchFeature _windowThrowCatchFeature = new();
    private readonly LightsaberSeamGlowFeature _lightsaberSeamGlowFeature = new();
    private readonly PrivacyBlurFeature _privacyBlurFeature = new();

    // --- Hotkey commands ---
    private readonly FocusModeFeature _focusModeFeature = new();
    private readonly AlwaysOnTopFeature _alwaysOnTopFeature = new();
    private readonly AlwaysOnBottomFeature _alwaysOnBottomFeature = new();
    private readonly RollUpFeature _rollUpFeature = new();
    private readonly TrayMinimizeFeature _trayMinimizeFeature = new();
    private readonly BossKeyFeature _bossKeyFeature = new();
    private readonly CenterWindowFeature _centerWindowFeature = new();
    private readonly CycleWindowSizeFeature _cycleWindowSizeFeature = new();
    private readonly NextMonitorFeature _nextMonitorFeature = new();
    private readonly TileWindowFeature _tileWindowFeature = new();
    private readonly MaximizeRestoreFeature _maximizeRestoreFeature = new();
    private readonly UndoLayoutFeature _undoLayoutFeature = new();
    private readonly ResetTransparencyFeature _resetTransparencyFeature = new();
    private readonly ProximityGhostFeature _proximityGhostFeature = new();
    private readonly LivePipFeature _livePipFeature = new();
    private readonly SpotlightFeature _spotlightFeature = new();
    private readonly MicMuteFeature _micMuteFeature = new();
    private readonly QuickLookFeature _quickLookFeature = new();
    private readonly ShatterCloseFeature _shatterCloseFeature = new();
    private readonly GravityCloseFeature _gravityCloseFeature = new();
    private readonly PlainPasteFeature _plainPasteFeature = new();
    private readonly QuickFolderJumpFeature _quickFolderJumpFeature = new();
    private readonly GameModeFeature _gameModeFeature = new();

    // Constructed in OnStartup because they need collaborators or a callback.
    private AltDragFeature? _altDragFeature;
    private RestoreAllFeature? _restoreAllFeature;
    private StealthPanicTrigger? _stealthPanicTrigger;
    private DoubleAltTrigger? _doubleAltTrigger;
    private DoubleCtrlTrigger? _doubleCtrlTrigger;

    private const uint ModCtrl = 0x0002;

    private const uint VK_A = 0x41, VK_B = 0x42, VK_C = 0x43, VK_D = 0x44, VK_E = 0x45;
    private const uint VK_F = 0x46, VK_G = 0x47, VK_H = 0x48, VK_I = 0x49, VK_J = 0x4A;
    private const uint VK_K = 0x4B, VK_L = 0x4C, VK_M = 0x4D, VK_N = 0x4E, VK_O = 0x4F;
    private const uint VK_P = 0x50, VK_Q = 0x51, VK_R = 0x52, VK_S = 0x53, VK_T = 0x54;
    private const uint VK_U = 0x55, VK_V = 0x56, VK_W = 0x57, VK_X = 0x58, VK_Y = 0x59;
    private const uint VK_Z = 0x5A;

    private const uint VK_ESCAPE = 0x1B, VK_SPACE = 0x20, VK_UP = 0x26, VK_DOWN = 0x28;
    private const uint VK_F4 = 0x73, VK_F5 = 0x74, VK_F6 = 0x75, VK_F12 = 0x7B;
    private const uint VK_NUMPAD0 = 0x60;

    public App()
    {
        // The two features that take a collaborator. See the fields' comments for why they are here.
        _textFormatFeature = new TextFormatFeature(_clipboardOsdFeature);
        _acousticKeyboardFeature = new AcousticKeyboardFeature(_shortcutSoundsFeature);
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        SettingsStore.Load();

        // Anything that cannot reach this class - the taskbar clock's WM_CLOSE handler - asks for
        // shutdown through here. Set before any feature can exist, let alone show a window.
        AppLifetime.ShutdownRequested = RequestShutdown;

        _altDragFeature = new AltDragFeature();
        _restoreAllFeature = new RestoreAllFeature(_rollUpFeature, _trayMinimizeFeature);

        // The double-tap triggers marshal onto the dispatcher: the keyboard hook runs on whichever
        // thread is pumping, and both targets touch UI.
        _stealthPanicTrigger = new StealthPanicTrigger(() => Dispatcher.Invoke(() => _bossKeyFeature.Toggle()));
        _doubleAltTrigger = new DoubleAltTrigger(() => Dispatcher.Invoke(() => _micMuteFeature.Toggle()));
        _doubleCtrlTrigger = new DoubleCtrlTrigger(() => Dispatcher.Invoke(() => _spotlightFeature.Toggle()));

        // Must exist before anything else: it is the only way to ask this app to exit, since it
        // shows no window of its own.
        _shutdownListener = new ShutdownListener(RequestShutdown);

        _systemTrayManager = new SystemTrayManager(ShowSettingsWindow, ReloadApp, RequestShutdown);
        _hotkeyManager = new HotkeyManager();

        RegisterFeatures();
        RegisterHotkeys();

        // Start whatever the user had on last time. Must come after registration, and after the
        // hotkeys so that a feature's Apply cannot race a half-built hotkey table.
        FeatureRegistry.ApplyStoredState();

        // For this one feature the filesystem is the truth, not settings.json: the installer and
        // the uninstaller both write the shortcut, so the stored value can disagree with reality.
        // ApplyStoredState never calls Apply(false), so a stored "off" against an existing shortcut
        // would otherwise leave it in place while the settings window showed the switch as off.
        // Set() no-ops when the two already agree, which is the normal case.
        FeatureRegistry.Set(FeatureKeys.StartWithWindows, StartupManager.IsEnabled());

        EnsureDragFullWindowsIfNeeded();
        ReportFailedHotkeys();

        _gameModeFeature.StateChanged += OnGameModeChanged;

        // One slow sweep for records belonging to windows that have since closed, and a drop of the
        // process-name cache, whose entries go stale when Windows reuses a process id. A minute is
        // far slower than anything a user can notice and costs nothing.
        _housekeeping = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _housekeeping.Tick += (_, _) =>
        {
            AlphaCompositor.Sweep();
            ProcessNameCache.Trim();
        };
        _housekeeping.Start();
    }

    // -----------------------------------------------------------------------------------------
    // Feature registration
    // -----------------------------------------------------------------------------------------

    private void RegisterFeatures()
    {
        const string PageWindow = "Window Management";
        const string PageOpacity = "Opacity & Effects";
        const string PageAnimation = "Animation";
        const string PagePower = "Power Features";
        const string PageScreen = "Screen & Shell";
        const string PageGeneral = "General";

        // --- Window management -----------------------------------------------------------------
        Add(FeatureKeys.AltDrag, "Linux-style Alt-Drag", PageWindow, "Movement & Dragging",
            "Alt + left-click moves any window from anywhere in it; Alt + right-click resizes from the nearest edge.",
            "Alt+Drag", true, on => _altDragFeature!.SetEnabled(on));

        Add(FeatureKeys.MagneticSnap, "Magnetic window snapping", PageWindow, "Movement & Dragging",
            "On release each axis snaps independently to a screen edge, a work-area edge or another window's edge. Reach scales with how hard you throw it. Windows' own snap wins at the screen edges, by design - if Windows resizes the window, this leaves it alone.",
            "Shift+Alt+S", false, on => _magneticSnappingFeature.SetEnabled(on));

        Add(FeatureKeys.MagneticGroups, "Magnetic window groups", PageWindow, "Movement & Dragging",
            "Windows already touching each other move together.",
            "Shift+Alt+J", false, on => _magneticGroupsFeature.SetEnabled(on));

        Add(FeatureKeys.MiddleClickClose, "Middle-click title bar to close", PageWindow, "Movement & Dragging",
            "Middle-click a window's title bar to close it, the way a browser tab closes. Browsers are skipped by default, because their tab strip IS their title bar - see the Tuning page. Hung windows are detected and left alone.",
            null, false, on => _middleClickCloseFeature.SetEnabled(on));

        Add(FeatureKeys.PositionMemory, "Position memory", PageWindow, "Layout & States",
            "Apps reopen at the position you last left them, keyed on the executable and window class. Their size is never changed.",
            "Shift+Alt+M", false, on => _positionMemoryFeature.SetEnabled(on));

        Add(FeatureKeys.RollUp, "Window roll-up", PageWindow, "Layout & States",
            "Collapse a window to just its title bar, and roll it back down.",
            "Shift+Alt+R", true, null);

        Add(FeatureKeys.TrayMinimize, "Minimize to tray", PageWindow, "Layout & States",
            "Hide a window to its own tray icon instead of the taskbar.",
            "Shift+Alt+H", true, null);

        Add(FeatureKeys.AlwaysOnTop, "Always on top", PageWindow, "Layout & States",
            "Pin the active window above every other window.",
            "Shift+Alt+O", true, null);

        Add(FeatureKeys.AlwaysOnBottom, "Always on bottom", PageWindow, "Layout & States",
            "Pin a window to the desktop background as a widget. Released on exit - a window left parented to the shell cannot be alt-tabbed to.",
            "Shift+Alt+B", true, null);

        Add(FeatureKeys.LivePip, "Live picture-in-picture", PageWindow, "Layout & States",
            "A live, always-on-top thumbnail of a background window.",
            "Shift+Alt+P", true, null);

        // --- Opacity ---------------------------------------------------------------------------
        Add(FeatureKeys.TransparencyWheel, "Transparency wheel", PageOpacity, "Per-window opacity",
            "Shift+Alt and the mouse wheel sets the opacity of the window under the cursor. Composes with the ambient effects below instead of fighting them.",
            "Shift+Alt+Wheel", true, on => _changeTransparencyFeature.SetEnabled(on));

        Add(FeatureKeys.DragParallax, "Parallax dragging", PageOpacity, "Per-window opacity",
            "A window fades while you throw it around and returns to solid when it stops. Nothing happens below the start speed on the Tuning page.",
            null, false, on => _dragParallaxFeature.SetEnabled(on));

        Add(FeatureKeys.ProximityGhost, "Proximity ghost", PageOpacity, "Per-window opacity",
            "Makes a window mostly transparent and click-through; it fades in and becomes clickable as the cursor approaches.",
            "Shift+Alt+G", true, null);

        Add(FeatureKeys.Breathing, "Breathing windows", PageOpacity, "Ambient",
            "Background windows fade after a few seconds of inactivity and wake instantly on focus or hover.",
            "Shift+Alt+E", false, on => _breathingFeature.SetEnabled(on));

        Add(FeatureKeys.MonitorDimmer, "Multi-monitor focus dimmer", PageOpacity, "Ambient",
            "Dims the monitors you are not working on.",
            "Shift+Alt+D", false, on => _multiMonitorDimmerFeature.SetEnabled(on));

        Add(FeatureKeys.FocusMode, "Focus / cinema mode", PageOpacity, "Ambient",
            "Blacks out everything except the active window.",
            "Shift+Alt+F", true, null);

        // --- Animation -------------------------------------------------------------------------
        Add(FeatureKeys.RippleClick, "Ripple click", PageAnimation, "Pointer",
            "A soft ring expands from the cursor on every left click and fades out. Never intercepts the click.",
            null, false, on => _rippleClickFeature.SetEnabled(on));

        Add(FeatureKeys.GravityClose, "Gravity-drop close", PageAnimation, "Window closing",
            "Alt+F4 collapses the window into a bitmap that falls off the screen. Switch this off and Alt+F4 closes normally.",
            "Alt+F4", false, null);

        Add(FeatureKeys.ShatterClose, "Shatter to close", PageAnimation, "Window closing",
            "Smashes the window into glass shards that fall with gravity.",
            "Shift+Alt+F4", true, null);

        // --- Power features --------------------------------------------------------------------
        Add(FeatureKeys.PlainPaste, "Plain-text paste", PagePower, "Workflow",
            "Strips all formatting, colours and fonts from the clipboard and pastes as plain text.",
            "Ctrl+Alt+V", true, null);

        Add(FeatureKeys.QuickFolderJump, "Quick folder jump", PagePower, "Workflow",
            "In a file open/save dialog, jump to the folder of your most recent Explorer window. Takes effect on restart, because Ctrl+G belongs to other apps and is only claimed when this is on.",
            "Ctrl+G", false, null);

        Add(FeatureKeys.QuickLook, "Quick Look preview", PagePower, "Workflow",
            "Preview the selected file in Explorer without opening an application.",
            "Shift+Alt+Q", true, null);

        Add(FeatureKeys.Spotlight, "Spotlight launcher", PagePower, "Workflow",
            "A minimal search-and-launch bar.",
            "Shift+Alt+L", true, null);

        Add(FeatureKeys.DoubleCtrlSpotlight, "Double-tap Ctrl for Spotlight", PagePower, "Workflow",
            "Opens the launcher on a double-tap of Ctrl, without a chord.",
            "Ctrl, Ctrl", true, on => _doubleCtrlTrigger!.SetEnabled(on));

        Add(FeatureKeys.MicMute, "Microphone kill-switch", PagePower, "System",
            "Mutes and unmutes the default recording device system-wide.",
            "Shift+Alt+A", true, null);

        Add(FeatureKeys.DoubleAltMic, "Double-tap Alt to mute the mic", PagePower, "System",
            "Same kill-switch on a double-tap of Alt, without a chord.",
            "Alt, Alt", true, on => _doubleAltTrigger!.SetEnabled(on));

        Add(FeatureKeys.AcousticKeyboard, "Keyboard sounds", PagePower, "Sound",
            "A mechanical keyboard click on every keystroke. Space is a deep flat thock, Enter falls, Backspace falls fast and Delete rises, so the four are told apart by ear; modifiers are quieter than the rest. Pick the instrument and the volume on the Tuning page - every sound is generated in memory, so nothing is read from disk while you type.",
            null, false, on => _acousticKeyboardFeature.SetEnabled(on));

        Add(FeatureKeys.ClipboardOsd, "Copy, paste and undo feedback", PagePower, "Sound",
            "Ctrl+C, Ctrl+V, Ctrl+X, Ctrl+A, Ctrl+Z and Ctrl+Y each get their own sound and their own coloured ring at the pointer, so you can tell a copy from a cut - or an undo from a redo - without looking. Never intercepts the chord.",
            null, true, on => _clipboardOsdFeature.SetEnabled(on));

        Add(FeatureKeys.ShortcutSounds, "Windows shortcut sounds", PagePower, "Sound",
            "A sound for the Windows chords that confirm nothing on their own: Alt+Tab, Alt+Shift, Win+Tab, Win+Shift+S, Win+V, Win+., Win+D, Win+L and the rest. Each one has its own shape rather than its own pitch - the switcher rises, show-desktop falls, the snip clacks - so you learn them without trying. Never intercepts the chord.",
            null, true, on => _shortcutSoundsFeature.SetEnabled(on));

        Add(FeatureKeys.TaskbarVolume, "Taskbar volume wheel", PagePower, "Sound",
            "Scroll the wheel over the taskbar to change the volume, with a readout showing the new level - including on a second monitor, where Windows' own flyout appears on the primary. Middle-click the taskbar to mute.",
            null, true, on => _taskbarVolumeFeature.SetEnabled(on));

        Add(FeatureKeys.TextFormat, "camelCase the selection", PagePower, "Workflow",
            "Ctrl+Alt+C rewrites the selected text as camelCase in place. It works through the clipboard, because that is the only way to read a selection out of another application - and it puts your clipboard back afterwards.",
            "Ctrl+Alt+C", true, on => _textFormatFeature.SetEnabled(on));

        Add(FeatureKeys.CursorLocator, "Shake to find the cursor", PagePower, "Pointer",
            "Shake the mouse and two rings converge on the pointer. Judged on how much of the movement cancels itself out, so crossing the screen to click something does not trigger it.",
            null, true, on => _cursorLocatorFeature.SetEnabled(on));

        Add(FeatureKeys.TextMagnifier, "Magnifier while selecting text", PagePower, "Pointer",
            "A lens follows the pointer while you drag across text. Only for a drag that moves mostly sideways, so scrolling, dragging a file and moving a window are left alone.",
            null, true, on => _textMagnifierFeature.SetEnabled(on));

        Add(FeatureKeys.SmartCaps, "Smart Caps Lock", PagePower, "System",
            "A tap of Caps Lock sends another key and holding it toggles Caps Lock for real. Both the tap and the Shift+tap are configurable on the Tuning page, so it can be Escape and Backspace at once.",
            null, true, on => _smartCapsFeature.SetEnabled(on));

        Add(FeatureKeys.GrabPan, "Universal grab & pan", PagePower, "System",
            "Hold the middle button and drag to pan any scrollable window, like the hand tool in an image editor. A short middle click is passed straight through, so opening and closing browser tabs still works.",
            "Shift+Alt+Space", false, on => _grabPanFeature.SetEnabled(on));

        Add(FeatureKeys.StealthPanic, "Stealth panic (triple Escape)", PagePower, "System",
            "Three taps of Escape hides every window and mutes the system.",
            "Esc Esc Esc", true, on => _stealthPanicTrigger!.SetEnabled(on));

        // --- Screen & shell --------------------------------------------------------------------
        Add(FeatureKeys.HotCorners, "Hot corners", PageScreen, "Edges",
            "Throw the pointer into a screen corner to trigger an action. Gated on dwell time, so brushing a corner does nothing.",
            "Shift+Alt+C", false, on => _hotCornersFeature.SetEnabled(on));

        Add(FeatureKeys.InfiniteWrap, "Infinite cursor wrap", PageScreen, "Edges",
            "The pointer wraps across screen edges. Gated on approach speed and dwell, because the outer edge is somewhere the pointer lands constantly.",
            "Shift+Alt+I", false, on => _infiniteWrapFeature.SetEnabled(on));

        Add(FeatureKeys.SmartTaskbar, "Smart auto-hide taskbar", PageScreen, "Taskbar",
            "Hides the taskbar only when a window is maximised or touches the bottom edge.",
            "Shift+Alt+T", false, on => _smartTaskbarFeature.SetEnabled(on));

        Add(FeatureKeys.CustomClock, "Custom taskbar clock", PageScreen, "Taskbar",
            "Draws a two-row block on the taskbar: weather and time on the first line, conditions and date on the second. Positioned relative to the tray, never at a fixed coordinate.",
            null, false, on => _customClockFeature.SetEnabled(on));

        // The ONLY feature in the app that makes a network connection, which is why it is a separate
        // switch and why it defaults off. With no city set it still makes no request at all.
        Add(FeatureKeys.ClockWeather, "Clock weather (uses the internet)", PageScreen, "Taskbar",
            "Adds current conditions, temperature and wind to the clock, from open-meteo.com. This is the only part of the app that connects to the internet - it stays off until you switch it on, and makes no request until a city is set on the Tuning page. One request per 15 minutes.",
            null, false, on =>
            {
                CustomClockFeature.WeatherEnabled = on;
                if (on) WeatherService.InvalidateLocation();
            });

                // --- New Features ----------------------------------------------------------------------
        Add(FeatureKeys.SmartActiveBorder, "Smart Active Border", PageWindow, "Layout & States", "Draws a colorful, elegant border exclusively around the active window.", null, false, on => _smartActiveBorderFeature.SetEnabled(on));
        Add(FeatureKeys.GlobalTextExpander, "Global Text Expander", PagePower, "Workflow", "Automatically expands abbreviations like @@mail or @@date into full text snippets.", null, false, on => _globalTextExpanderFeature.SetEnabled(on));
        Add(FeatureKeys.ZeroDelayMenus, "Zero-delay Menus", PagePower, "Workflow", "Opens context menus instantly (0-50ms) mimicking macOS responsiveness.", null, false, on => _zeroDelayMenusFeature.SetEnabled(on));
        Add(FeatureKeys.SnappyTaskbarPreviews, "Snappy Taskbar Previews", PageScreen, "Taskbar", "Accelerates taskbar window previews from the default 400ms down to 100ms.", null, false, on => _snappyTaskbarPreviewsFeature.SetEnabled(on));
        Add(FeatureKeys.SmoothScrolling, "Smooth Scrolling", PagePower, "Pointer", "Applies interpolated, buttery-smooth scrolling globally across all applications.", null, false, on => _smoothScrollingFeature.SetEnabled(on));
        Add(FeatureKeys.FadeInEaseOut, "Fade In / Ease-Out", PageAnimation, "Ambient", "Replaces abrupt window disappearance with cinematic fade-in/out transitions.", null, false, on => _fadeInEaseOutFeature.SetEnabled(on));
        Add(FeatureKeys.CustomTextCaret, "Custom Text Caret", PagePower, "Pointer", "Overrides the default text cursor with a thicker, smoother, eye-friendly caret.", null, false, on => _customTextCaretFeature.SetEnabled(on));
        Add(FeatureKeys.BouncySnapping, "Bouncy Snapping", PageAnimation, "Movement & Dragging", "Adds a rubber-band bounce effect when snapping windows to screen edges.", null, false, on => _bouncySnappingFeature.SetEnabled(on));
        Add(FeatureKeys.FocusPulse, "Focus Pulse", PageAnimation, "Ambient", "Gently swells and shrinks a window when focused via Alt+Tab to draw attention.", null, false, on => _focusPulseFeature.SetEnabled(on));
        Add(FeatureKeys.GhostSlideIn, "Ghost Slide-In", PageAnimation, "Ambient", "Animates new application windows sliding up smoothly from the bottom.", null, false, on => _ghostSlideInFeature.SetEnabled(on));
        Add(FeatureKeys.MagneticSeamFlash, "Magnetic Seam Flash", PageAnimation, "Movement & Dragging", "Emits a brief neon flash effect where the borders of two windows magnetically snap together.", null, false, on => _magneticSeamFlashFeature.SetEnabled(on));
        Add(FeatureKeys.TheaterSpotlight, "Theater Spotlight", PageOpacity, "Ambient", "Darkens the background and creates a spotlight effect following the cursor.", null, false, on => _theaterSpotlightFeature.SetEnabled(on));
        Add(FeatureKeys.FlyToMouseMinimize, "Fly-to-Mouse Minimize", PageAnimation, "Window closing", "Sucks minimizing windows directly into the mouse cursor rather than the taskbar.", null, false, on => _flyToMouseMinimizeFeature.SetEnabled(on));
        Add(FeatureKeys.WindowUnrolling, "Window Unrolling", PageAnimation, "Ambient", "Unrolls new windows vertically from top to bottom like a window blind in 0.2 seconds.", null, false, on => _windowUnrollingFeature.SetEnabled(on));
        Add(FeatureKeys.ContextMenuUnfold, "Context Menu Unfold", PageAnimation, "Pointer", "Unfolds context menus downwards like origami instead of appearing instantly.", null, false, on => _contextMenuUnfoldFeature.SetEnabled(on));
        Add(FeatureKeys.ElasticDrag, "Elastic Drag", PageAnimation, "Movement & Dragging", "Creates a rubber-band stretching effect when dragging files and snaps back on release.", null, false, on => _elasticDragFeature.SetEnabled(on));
        Add(FeatureKeys.CursorYawnBreathe, "Cursor Yawn & Breathe", PageAnimation, "Pointer", "Makes an idle cursor subtly breathe and yawn when left untouched.", null, false, on => _cursorYawnBreatheFeature.SetEnabled(on));
        Add(FeatureKeys.MomentumTilt, "Momentum Tilt", PageAnimation, "Movement & Dragging", "Slightly tilts windows in the direction of movement while dragging and settles with inertia.", null, false, on => _momentumTiltFeature.SetEnabled(on));
        Add(FeatureKeys.BlackHoleMinimize, "Black Hole Minimize", PageAnimation, "Window closing", "Sucks minimizing windows and deleted files into a gravitational black hole effect.", null, false, on => _blackHoleMinimizeFeature.SetEnabled(on));
        Add(FeatureKeys.ResistanceEdge, "Resistance Edge", PageAnimation, "Movement & Dragging", "Simulates tactile rubber-like resistance when dragging a window against screen edges.", null, false, on => _resistanceEdgeFeature.SetEnabled(on));
        Add(FeatureKeys.FocusDepth, "Focus Depth", PageOpacity, "Ambient", "Pushes inactive windows into the background in 3D while scaling the active one forward.", null, false, on => _focusDepthFeature.SetEnabled(on));
        Add(FeatureKeys.CarouselAltTab, "Carousel Alt-Tab", PageAnimation, "Ambient", "Replaces the flat Alt-Tab switcher with a rotating 3D carousel of windows.", null, false, on => _carouselAltTabFeature.SetEnabled(on));
        Add(FeatureKeys.DynamicNotch, "Dynamic Notch (OSD)", PageScreen, "Taskbar", "Drops an iOS-style Dynamic Island from the top of the screen for volume and brightness.", null, false, on => _dynamicNotchFeature.SetEnabled(on));
        Add(FeatureKeys.CurtainDrop, "Curtain Drop", PageAnimation, "Ambient", "Drops all windows to the desktop using kinetic motion blur.", null, false, on => _curtainDropFeature.SetEnabled(on));
        Add(FeatureKeys.MotionBlurScroll, "Motion Blur Scroll", PageAnimation, "Pointer", "Applies a vertical motion blur effect while scrolling fast for extreme perceived smoothness.", null, false, on => _motionBlurScrollFeature.SetEnabled(on));
        Add(FeatureKeys.OverscrollBounce, "Overscroll Bounce", PageAnimation, "Pointer", "Adds an Apple-style rubber-band bounce effect when reaching the end of a scrolling page.", null, false, on => _overscrollBounceFeature.SetEnabled(on));
        Add(FeatureKeys.TaskbarIconWave, "Taskbar Icon Wave", PageAnimation, "Pointer", "Makes taskbar icons wave and notifications bounce elastically on mouse hover.", null, false, on => _taskbarIconWaveFeature.SetEnabled(on));
        Add(FeatureKeys.StartMenuBlur, "Start Menu Slide-Up Blur", PageOpacity, "Ambient", "Generates a deep background blur effect transitioning smoothly as the Start Menu opens.", null, false, on => _startMenuBlurFeature.SetEnabled(on));
        Add(FeatureKeys.WindowThrowCatch, "Window Throw & Catch", PageAnimation, "Movement & Dragging", "Allows throwing a window kinetically across monitors so it flies and lands on the other screen.", null, false, on => _windowThrowCatchFeature.SetEnabled(on));
        Add(FeatureKeys.LightsaberSeamGlow, "Lightsaber Seam Glow", PageAnimation, "Movement & Dragging", "Illuminates a glowing Jedi lightsaber edge when hovering over the seam of snapped windows.", null, false, on => _lightsaberSeamGlowFeature.SetEnabled(on));
        Add(FeatureKeys.PrivacyBlur, "Privacy Blur", PageOpacity, "Ambient", "Overlays an unreadable frosted glass blur over private windows when they lose focus.", null, false, on => _privacyBlurFeature.SetEnabled(on));

        // --- General ---------------------------------------------------------------------------
        // The default is read from the filesystem, not from settings.json: the shortcut is the
        // actual state, and the installer writes one too.
        Add(FeatureKeys.StartWithWindows, "Start with Windows", PageGeneral, "Startup",
            "Adds a shortcut to your own Startup folder. No admin rights and no registry keys.",
            null, StartupManager.IsEnabled(), on => StartupManager.SetEnabled(on));
    }

    private static void Add(string key, string title, string page, string? group, string description,
        string? hotkey, bool defaultEnabled, Action<bool>? apply)
    {
        FeatureRegistry.Register(new FeatureDescriptor
        {
            Key = key,
            Title = title,
            Page = page,
            Group = group,
            Description = description,
            Hotkey = hotkey,
            DefaultEnabled = defaultEnabled,
            Apply = apply
        });
    }

    // -----------------------------------------------------------------------------------------
    // Hotkeys
    // -----------------------------------------------------------------------------------------

    private void RegisterHotkeys()
    {
        if (_hotkeyManager == null) return;

        uint sa = NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT;

        // Always available - these are the app's own controls.
        Hk(sa, VK_W, "Shift+Alt+W", ShowSettingsWindow);
        Hk(sa, VK_F5, "Shift+Alt+F5", ReloadApp);
        Hk(sa, VK_F6, "Shift+Alt+F6", RequestShutdown);
        Hk(sa, VK_ESCAPE, "Shift+Alt+Esc", () => _bossKeyFeature.Toggle());
        Hk(sa, VK_Y, "Shift+Alt+Y", RestoreEverything);
        Hk(sa, VK_F12, "Shift+Alt+F12", () => _gameModeFeature.Toggle());

        // Layout commands. Deliberately never gated: they act only when pressed and cost nothing.
        Hk(sa, VK_K, "Shift+Alt+K", () => _centerWindowFeature.Toggle());
        Hk(sa, VK_U, "Shift+Alt+U", () => _cycleWindowSizeFeature.Toggle());
        Hk(sa, VK_N, "Shift+Alt+N", () => _nextMonitorFeature.Toggle());
        Hk(sa, VK_Z, "Shift+Alt+Z", () => _undoLayoutFeature.Toggle());
        Hk(sa, VK_X, "Shift+Alt+X", () => _resetTransparencyFeature.Toggle());
        Hk(sa, VK_NUMPAD0, "Shift+Alt+Numpad0", () => _maximizeRestoreFeature.Toggle());

        for (uint i = 1; i <= 9; i++)
        {
            int cell = (int)i;
            Hk(sa, VK_NUMPAD0 + i, "Shift+Alt+Numpad" + cell, () => _tileWindowFeature.TileWindow(cell));
        }

        // The only NumLock-independent layout keys: with NumLock off the keypad sends the
        // navigation names and every Numpad binding above is dead.
        Hk(sa, VK_UP, "Shift+Alt+Up", () => _tileWindowFeature.TileWindow(8));
        Hk(sa, VK_DOWN, "Shift+Alt+Down", () => _tileWindowFeature.TileWindow(2));

        // Feature toggles: the key flips the registry, which persists it and updates the settings
        // window if it happens to be open.
        Hk(sa, VK_S, "Shift+Alt+S", () => FeatureRegistry.Toggle(FeatureKeys.MagneticSnap));
        Hk(sa, VK_M, "Shift+Alt+M", () => FeatureRegistry.Toggle(FeatureKeys.PositionMemory));
        Hk(sa, VK_E, "Shift+Alt+E", () => FeatureRegistry.Toggle(FeatureKeys.Breathing));
        Hk(sa, VK_C, "Shift+Alt+C", () => FeatureRegistry.Toggle(FeatureKeys.HotCorners));
        Hk(sa, VK_I, "Shift+Alt+I", () => FeatureRegistry.Toggle(FeatureKeys.InfiniteWrap));
        Hk(sa, VK_D, "Shift+Alt+D", () => FeatureRegistry.Toggle(FeatureKeys.MonitorDimmer));
        Hk(sa, VK_T, "Shift+Alt+T", () => FeatureRegistry.Toggle(FeatureKeys.SmartTaskbar));
        Hk(sa, VK_J, "Shift+Alt+J", () => FeatureRegistry.Toggle(FeatureKeys.MagneticGroups));
        Hk(sa, VK_SPACE, "Shift+Alt+Space", () => FeatureRegistry.Toggle(FeatureKeys.GrabPan));

        // Gated commands: the hotkey stays registered, but does nothing while the feature is off.
        HkGated(sa, VK_O, "Shift+Alt+O", FeatureKeys.AlwaysOnTop, () => _alwaysOnTopFeature.Toggle());
        HkGated(sa, VK_B, "Shift+Alt+B", FeatureKeys.AlwaysOnBottom, () => _alwaysOnBottomFeature.Toggle());
        HkGated(sa, VK_F, "Shift+Alt+F", FeatureKeys.FocusMode, () => _focusModeFeature.Toggle());
        HkGated(sa, VK_R, "Shift+Alt+R", FeatureKeys.RollUp, () => _rollUpFeature.Toggle());
        HkGated(sa, VK_H, "Shift+Alt+H", FeatureKeys.TrayMinimize, () => _trayMinimizeFeature.Toggle());
        HkGated(sa, VK_G, "Shift+Alt+G", FeatureKeys.ProximityGhost, () => _proximityGhostFeature.Toggle());
        HkGated(sa, VK_P, "Shift+Alt+P", FeatureKeys.LivePip, () => _livePipFeature.Toggle());
        HkGated(sa, VK_L, "Shift+Alt+L", FeatureKeys.Spotlight, () => _spotlightFeature.Toggle());
        HkGated(sa, VK_A, "Shift+Alt+A", FeatureKeys.MicMute, () => _micMuteFeature.Toggle());
        HkGated(sa, VK_Q, "Shift+Alt+Q", FeatureKeys.QuickLook, () => _quickLookFeature.Toggle());
        HkGated(sa, VK_F4, "Shift+Alt+F4", FeatureKeys.ShatterClose, () => _shatterCloseFeature.Toggle());
        HkGated(NativeMethods.MOD_ALT | ModCtrl, VK_V, "Ctrl+Alt+V", FeatureKeys.PlainPaste,
            () => _plainPasteFeature.Toggle());

        // Alt+F4 is Windows' own close chord, so it cannot simply do nothing when the animation is
        // switched off - it has to still close the window.
        Hk(NativeMethods.MOD_ALT, VK_F4, "Alt+F4", () =>
        {
            if (FeatureRegistry.IsEnabled(FeatureKeys.GravityClose)) _gravityCloseFeature.Toggle();
            else CloseForegroundWindow();
        });

        // Ctrl+G belongs to other applications, so it is claimed only when the feature is actually
        // on. That is why its description says a restart is needed.
        if (SettingsStore.GetBool(FeatureKeys.QuickFolderJump, false))
            Hk(ModCtrl, VK_G, "Ctrl+G", () => _quickFolderJumpFeature.Toggle());
    }

    private void Hk(uint mods, uint vk, string description, Action action)
    {
        _hotkeyManager?.Register(mods, vk, action, description);
    }

    private void HkGated(uint mods, uint vk, string description, string featureKey, Action action)
    {
        bool ok = _hotkeyManager?.Register(mods, vk, () =>
        {
            if (FeatureRegistry.IsEnabled(featureKey)) action();
        }, description) ?? false;

        if (!ok)
        {
            FeatureDescriptor? d = FeatureRegistry.Find(featureKey);
            if (d != null) d.HotkeyUnavailable = true;
        }
    }

    /// <summary>Plain Alt+F4 behaviour, for when the gravity animation is switched off.</summary>
    private static void CloseForegroundWindow()
    {
        IntPtr hwnd = NativeMethods.GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return;
        NativeMethods.PostMessage(hwnd, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    /// <summary>
    /// Shift+Alt+Y - the recovery path for state a user cannot see: rolled-up, tray-hidden and
    /// ghosted windows, plus any opacity left on a window by an effect.
    /// </summary>
    private void RestoreEverything()
    {
        _restoreAllFeature?.Toggle();
        _proximityGhostFeature.RestoreAll();
        AlphaCompositor.ResetAll();
    }

    private void EnsureDragFullWindowsIfNeeded()
    {
        // Only touch a system-wide setting if a feature that genuinely depends on it is on.
        bool needed = FeatureRegistry.IsEnabled(FeatureKeys.MagneticSnap)
                      || FeatureRegistry.IsEnabled(FeatureKeys.DragParallax);
        if (!needed) return;

        if (!SystemTuning.EnsureDragFullWindows())
        {
            _systemTrayManager?.ShowBalloon("Window Tweaks",
                "Windows is set to drag window outlines instead of full windows, so snapping and " +
                "parallax cannot measure drag speed. Enable \"Show window contents while dragging\" " +
                "in Performance Options.");
        }
    }

    private void ReportFailedHotkeys()
    {
        IReadOnlyList<string>? failed = _hotkeyManager?.FailedRegistrations;
        if (failed == null || failed.Count == 0) return;

        _systemTrayManager?.ShowBalloon("Window Tweaks",
            "Another program already owns " + string.Join(", ", failed) +
            ". Those shortcuts will not work until it releases them.");
    }

    private void OnGameModeChanged(bool active)
    {
        _systemTrayManager?.ShowBalloon("Window Tweaks",
            active ? "Game Mode on - interfering features suspended." : "Game Mode off - features restored.");
        _settingsWindow?.SetGameModeNotice(active);
        _settingsWindow?.RefreshAll();
    }

    // -----------------------------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------------------------

    /// <summary>
    /// THE ONE WAY OUT. Every exit path goes through here - the tray menu, Shift+Alt+F6, a WM_CLOSE
    /// from the installer or from Windows shutting down - and it is what made "Full Exit" reliable.
    ///
    /// Three things it does that a bare Shutdown() did not:
    ///
    ///   1. IT IS IDEMPOTENT. Shutdown can be asked for twice - the installer posts WM_CLOSE to every
    ///      top-level window of the process, and this app owns several - and WPF throws on the second
    ///      call, from inside a message handler, leaving the first shutdown half finished.
    ///
    ///   2. IT STOPS THE HOOKS FEEDING THE DISPATCHER FIRST. Every feature that answers a hook
    ///      marshals its work onto the UI thread, so a hand resting on the mouse or a held key kept
    ///      queueing work onto the dispatcher that was trying to shut down. AppLifetime.BeginExit is
    ///      checked at the top of both shared hooks, so from this line on they add nothing.
    ///
    ///   3. IT ARMS A WATCHDOG. Teardown talks to audio endpoints over COM, un-parents foreign
    ///      windows and closes layered windows, none of which this app controls the timing of. There
    ///      is no correct timeout for any one of them, so there is one for all of them together.
    /// </summary>
    private void RequestShutdown()
    {
        if (!AppLifetime.BeginExit()) return;

        AppLifetime.StartWatchdog();

        // Not inside the caller's message handler: a WM_CLOSE sender is waiting on this message, and
        // OnExit does real work.
        Dispatcher.BeginInvoke(new Action(Shutdown));
    }

    private void ReloadApp()
    {
        SettingsStore.Flush();

        // Release the global hotkeys before the replacement starts, not in OnExit afterwards.
        // RegisterHotKey is exclusive per chord, so while this process still owned them the new
        // instance's registrations all failed - it came up with every hotkey dead and a balloon
        // blaming "another program". Dispose is idempotent, so OnExit calling it again is fine.
        _hotkeyManager?.Dispose();

        string? exePath = Environment.ProcessPath;
        if (exePath != null)
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = exePath,
                UseShellExecute = true
            });
        }

        RequestShutdown();
    }

    private void ShowSettingsWindow()
    {
        if (_settingsWindow == null)
        {
            _settingsWindow = new MainWindow();
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            _settingsWindow.Show();
        }
        else
        {
            if (_settingsWindow.WindowState == WindowState.Minimized)
                _settingsWindow.WindowState = WindowState.Normal;
            _settingsWindow.Activate();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        // OnExit can also be reached without RequestShutdown - Windows ending the session, or an
        // unhandled failure - so the flag and the watchdog are armed here too. Both are idempotent.
        if (AppLifetime.BeginExit()) AppLifetime.StartWatchdog();

        _housekeeping?.Stop();

        // Silence anything in flight before the audio device is released below.
        SoundEngine.Shutdown();

        // Leave Game Mode first, so the real configuration is what gets written.
        if (_gameModeFeature.IsActive) _gameModeFeature.Exit();

        // Stop every running feature before disposing, so each one gets the chance to undo what it
        // did to other people's windows.
        FeatureRegistry.StopAll();

        _hotkeyManager?.Dispose();

        // Every IDisposable feature, in one list. Five of these used to be missing.
        Dispose(_altDragFeature);
        Dispose(_magneticSnappingFeature);
        Dispose(_magneticGroupsFeature);
        Dispose(_positionMemoryFeature);
        Dispose(_breathingFeature);
        Dispose(_changeTransparencyFeature);
        Dispose(_dragParallaxFeature);
        Dispose(_rippleClickFeature);
        Dispose(_middleClickCloseFeature);
        Dispose(_multiMonitorDimmerFeature);
        Dispose(_hotCornersFeature);
        Dispose(_infiniteWrapFeature);
        Dispose(_smartTaskbarFeature);
        Dispose(_taskbarVolumeFeature);
        Dispose(_clipboardOsdFeature);
        Dispose(_acousticKeyboardFeature);
        Dispose(_shortcutSoundsFeature);
        Dispose(_textFormatFeature);
        Dispose(_cursorLocatorFeature);
        Dispose(_textMagnifierFeature);
        Dispose(_grabPanFeature);
        Dispose(_customClockFeature);
        Dispose(_smartCapsFeature);
        Dispose(_alwaysOnBottomFeature);
        Dispose(_proximityGhostFeature);
        Dispose(_livePipFeature);
        Dispose(_spotlightFeature);
        Dispose(_quickLookFeature);
        Dispose(_shatterCloseFeature);
        Dispose(_gravityCloseFeature);
        Dispose(_trayMinimizeFeature);
        Dispose(_stealthPanicTrigger);
        Dispose(_micMuteFeature);
        Dispose(_doubleAltTrigger);
        Dispose(_doubleCtrlTrigger);

        // New features
        Dispose(_smartActiveBorderFeature);
        Dispose(_globalTextExpanderFeature);
        Dispose(_zeroDelayMenusFeature);
        Dispose(_snappyTaskbarPreviewsFeature);
        Dispose(_smoothScrollingFeature);
        Dispose(_fadeInEaseOutFeature);
        Dispose(_customTextCaretFeature);
        Dispose(_bouncySnappingFeature);
        Dispose(_focusPulseFeature);
        Dispose(_ghostSlideInFeature);
        Dispose(_magneticSeamFlashFeature);
        Dispose(_theaterSpotlightFeature);
        Dispose(_flyToMouseMinimizeFeature);
        Dispose(_windowUnrollingFeature);
        Dispose(_contextMenuUnfoldFeature);
        Dispose(_elasticDragFeature);
        Dispose(_cursorYawnBreatheFeature);
        Dispose(_momentumTiltFeature);
        Dispose(_blackHoleMinimizeFeature);
        Dispose(_resistanceEdgeFeature);
        Dispose(_focusDepthFeature);
        Dispose(_carouselAltTabFeature);
        Dispose(_dynamicNotchFeature);
        Dispose(_curtainDropFeature);
        Dispose(_motionBlurScrollFeature);
        Dispose(_overscrollBounceFeature);
        Dispose(_taskbarIconWaveFeature);
        Dispose(_startMenuBlurFeature);
        Dispose(_windowThrowCatchFeature);
        Dispose(_lightsaberSeamGlowFeature);
        Dispose(_privacyBlurFeature);

        // Nothing should still be dimmed, but a crashed feature could have left a record behind.
        AlphaCompositor.ResetAll();

        // Release the shared low-level hooks explicitly. Subscribers drop them as they are disposed,
        // but the process must not exit still holding a global keyboard or mouse hook - a hook whose
        // owning process is gone stalls input delivery system-wide until Windows notices.
        //
        // THE MOUSE HOOK WAS MISSING FROM THIS LIST, and that is one of the reasons exiting appeared
        // to freeze: five features install it, and if any of them failed to unsubscribe the process
        // went away with a live WH_MOUSE_LL hook behind it.
        KeyboardHook.Shutdown();
        MouseHook.Shutdown();

        // Only after both hooks are gone. HookThread's message pump is what DELIVERS hook callbacks,
        // so stopping the pump while a hook is still installed would stall input, not free it.
        HookThread.Stop();

        // The cached audio endpoint is a COM object; release it rather than leaving it to a finalizer
        // that may run after the apartment has gone. The session manager behind the breathing
        // exemption is cached the same way and goes for the same reason.
        AudioManager.Shutdown();
        AudioSessionMonitor.Shutdown();

        _systemTrayManager?.Dispose();
        _shutdownListener?.Dispose();

        // There is no idle on the way out, so the debounced write has to be forced.
        SettingsStore.Flush();

        base.OnExit(e);

        // The process must actually end. WPF's shutdown does not wait for background threads, but a
        // hook thread, an audio thread or a COM apartment mid-teardown can still keep the process
        // alive with no window and no tray icon - which is the "it does not exit at all" report.
        // Everything above has already run, so there is nothing left to lose here.
        Environment.Exit(0);
    }

    private static void Dispose(IDisposable? d)
    {
        try
        {
            d?.Dispose();
        }
        catch (Exception ex)
        {
            // One feature throwing on teardown must not stop the others from being torn down.
            System.Diagnostics.Debug.WriteLine("Dispose failed: " + ex.Message);
        }
    }
}
