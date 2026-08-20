; Feature flags - the declared default of every non-numeric setting, and the
; enumerated lists those settings are validated against.
;
; Global initialisers only, no functions and no top-level statements. This is the
; first module in the manifest for one reason: hotkeys are live from load time
; and a #HotIf expression is evaluated against these globals from the first
; keypress, while a top-level "global X := ..." only runs when the auto-execute
; thread reaches that line. State declared thousands of lines away was therefore
; unassigned for the whole of startup - "#HotIf CarouselActive" threw "This
; global variable has not been assigned a value" on any Alt/Tab/Esc press.
;
; So FEATURE STATE LIVES NEXT TO ITS FLAG, never next to the function that uses
; it, and both live here.
;
; ENUMS ARE VALIDATED BY MEMBERSHIP, NOT BY RANGE. Every setting that feeds a
; DropDownList goes through IniPick(section, key, allowedList, default), and the
; control is built from the SAME list with IndexOf() for its Choose<n>. Two things
; break otherwise: DropDownList.Choose() on a value not in the list throws inside
; BuildWin, which leaves Shift+Alt+W permanently dead after one hand-edited
; settings.ini; and a value the dropdown cannot display leaves the GUI showing one
; thing while the engine uses another.
;
; Eight of these mirror a TUNE_SPEC row (SNAP_DISTANCE, CORNER_BOOST,
; NEIGHBOUR_PROX, GLIDE_THROW, GLIDE_MS, GLIDE_MAX, BREATHE_IDLE_MS,
; CursorYawnIdleTime). TuningRegistry.ahk owns the authoritative value and
; SyncTuningGlobals() writes it here, so every long-standing read site is
; untouched and pays no Map lookup. The registry copy is authoritative; this one
; is derived.

global SNAP_DISTANCE  := 30
global CORNER_BOOST   := 2.2
global NEIGHBOUR_PROX := 90
global MIN_DRAG       := 4
; Alt+F4 was intercepted unconditionally - the only behaviour change in the
; whole program with no flag and no settings entry.
global GravityCloseEnabled := true

; How long a window must go untouched before breathing dims it. MediaCore's hold
; window is derived from this (MC_SetHoldMs in SyncMediaCore) so the two can never
; be set into a dim/wake flicker - see MC_HoldMs() in MediaCore.ahk.
global BREATHE_IDLE_MS := 6000

global GlideEnabled  := true
global GLIDE_THROW   := 0.9
global GLIDE_MS      := 650
global GLIDE_MAX     := 500

; These declared defaults are documentation as much as code - they must agree
; with the default passed to IniStr() in LoadSettings, or a fresh install
; silently disagrees with what this file says it ships.
;
; The seven marked OFF-BY-DEFAULT below had never rendered a single pixel: five
; shared a malformed DWM_THUMBNAIL_PROPERTIES (wrong size, fVisible written into
; the struct padding) and two multiplied an already-millisecond QPC() by 1000
; again. Both bugs are fixed now, but that means these effects have never once
; run against snapping, glide, alpha or z-order. They ship unchecked so they are
; opted into one at a time rather than all arriving at once.
global SnapEnabled    := true
global MagneticGroupsEnabled := false
; OFF-BY-DEFAULT: physically moves whatever window is under the cursor on
; every wheel notch, through a direct WinMove outside the render pipeline, and
; costs ~6 cross-process queries per notch before it decides not to.
global ElasticScrollEnabled := false
global TextMagnifierEnabled := true
global SmartGridEnabled := true
global RippleClickEnabled := false        ; OFF-BY-DEFAULT: never rendered until now
; OFF-BY-DEFAULT: forces WS_EX_LAYERED onto every context menu in the OS.
global ContextMenuAnimEnabled := false
global ElasticDragEnabled := true
global BreatheCursorEnabled := true
global RestoreEnabled := true
global BlackHoleMinimizeEnabled := true
global MomentumTiltEnabled := true
; Feature state lives next to its flag, never next to the function that uses it.
; Hotkeys are live from load time and #HotIf expressions are evaluated against
; these globals from the first keypress, while a top-level "global X := ..."
; only runs when the auto-execute thread reaches that line. State declared
; thousands of lines down is therefore unassigned for the whole of startup:
; #HotIf CarouselActive threw "This global variable has not been assigned a
; value" on any Alt/Tab/Esc press, and ShellEvent's HSHELL_WINDOWDESTROYED
; cleanup threw the same on PushedBackWindows. See Boot() in
; ProcessLifecycle.ahk for the other half of this rule.
global FocusDepthEnabled := false
global LastActiveHwnd := 0
global PushedBackWindows := Map()
global CurtainDropEnabled := true
global CurtainDropped := false
global CurtainWindows := Map()
global SparkTypingEnabled := false        ; OFF-BY-DEFAULT: never rendered until now
global CarouselAltTabEnabled := false     ; OFF-BY-DEFAULT: never rendered until now
global CarouselActive := false
global CarouselGui := ""
global CarouselIndex := 1
global CarouselWindows := []
global Thumbnails := []
global CarouselAngleOffset := 0
global MotionBlurScrollEnabled := false   ; OFF-BY-DEFAULT: never rendered until now
global TaskbarWaveEnabled := false        ; OFF-BY-DEFAULT: never rendered until now
global CustomClockEnabled := true
global CustomClockWeather := ""
global CustomClockWind := ""               ; second line of the info column, e.g. "12 km/h"
global LastWeatherFetch := 0
global WeatherNextMs := 900000             ; ms until the next attempt; set by the outcome
global WeatherFailMs := 0                  ; current backoff, tripled per consecutive failure
global ClockLocation := ""                 ; required: open-meteo takes coordinates, not an IP
global ClockUnits := "Celsius"
global ClockAnchor := "TrayEdge"           ; which element the block sits beside
global ClockWeatherEnabled := true         ; the temperature column; a location gives it a value
global ClockWarnedNoCity := false          ; the "set a city" tip is said once per session
global WeatherWarnedFor := "-"             ; last location we complained about, so it is said once
global StartMenuBlurEnabled := true
global ToastBounceEnabled := true
global MonitorThrowEnabled := true
global BlackHoleDeleteEnabled := false    ; OFF-BY-DEFAULT: never rendered until now
global CursorYawnEnabled := true
global CursorYawnActive := false
global CursorYawnIdleTime := 900000
global ShatterEnabled := false            ; OFF-BY-DEFAULT: never rendered until now
global ActiveShatters := Map()
global LightsaberSeamEnabled := true
global PrivacyBlurEnabled := true
global PrivacyBlurWindows := Map()
global BreathingEnabled := true
global PulseEnabled := true
global OpenAnim := "Ghost Slide-In"
global ParallaxEnabled := true
global SeamFlashEnabled := true
global FlyMinimizeEnabled := true
; OFF-BY-DEFAULT, both of these: they are what puts the *MButton handler in
; front of EVERY middle click in the system - swallowed, probed with a 50 ms
; SendMessageTimeout to a foreign window, then re-synthesised. Shift+Alt+R still
; rolls a window up regardless; this flag only gates the middle-click gesture.
global RollUpEnabled := false
global TrayMinimizeEnabled := true
global BossKeyEnabled := true
global AltDragEnabled := true
global TaskbarScrollEnabled := true
global QuickFolderJumpEnabled := true
global PlainPasteEnabled := true
global MorphingPasteEnabled := true
global ClipboardAppendEnabled := true
global SmoothCaretEnabled := true
global TypingSoundsEnabled := true
global CopyFeedbackEnabled := true
global SmartCapsEnabled := true
global SmartCapsAction := "Escape"
global SmartTaskbarEnabled := false
global OriginalTaskbarState := -1
global QuickLookEnabled := true
global QuickLookGui := ""
global MultiMonitorDimmerEnabled := false
global DimmerGuis := Map()
global HotCornersEnabled := false
global HotCornerTL := "None", HotCornerTR := "Task View"
global HotCornerBL := "None", HotCornerBR := "Show Desktop"
global PremiumVolumeOSDEnabled := true
global OsdGui := "", OsdHiding := false
global LivePipEnabled := true
global PipGuis := Map()
global GrabPanEnabled := false
global MicKillSwitchEnabled := true
global MicOsdGui := "", MicOsdHiding := false
global InfiniteWrapEnabled := false
global SpotlightEnabled := true
global SpotlightGui := "", SpotlightInput := "", SpotlightResult := ""
global ActiveBorderEnabled := false
global ActiveBorderGui := ""
global ActiveBorderShown := false
global LastBorderHwnd := 0, LastBorderX := "", LastBorderY := "", LastBorderW := "", LastBorderH := ""
global AlwaysOnBottomEnabled := true
global BottomWindows := Map()
global TextExpanderEnabled := true
global MiddleClickCloseEnabled := false
global ProximityGhostEnabled := true
global ShakeFindEnabled := true
global GhostWindows := Map()
global MediaFallbackList := "youtube.exe; spotify.exe; vlc.exe; potplayermini64.exe; mpc-hc64.exe; netflix.exe"

; The single source of truth for every enumerated setting: LoadSettings validates
; against these lists and BuildWin populates its dropdowns from the same ones, so
; the stored value and the control's contents cannot drift apart.
global OPEN_ANIMS     := ["None", "Ghost Slide-In", "Portal Scale-In", "Window Unrolling"]
global CAPS_ACTIONS   := ["Escape", "Backspace"]
global CORNER_ACTIONS := ["None", "Task View", "Show Desktop", "Action Center", "Start Menu", "Lock Screen", "Mute Volume"]
global EP_STYLES      := ["Win10", "Win11"]
global EP_ICON_SIZES  := ["Small", "Large"]
global CLOCK_UNITS    := ["Celsius", "Fahrenheit"]
; Which taskbar element the clock block sits beside. Resolved by CLASS NAME at
; runtime, never by coordinate - see ResolveClockAnchor. It is a setting because
; the two options are a real trade-off the user has to make, not an internal
; detail. The block is about 115 px wide with the temperature column, so sitting it
; next to the clock covers everything in those 115 px - on this shell the Control
; Center button, the input indicator and part of the tray icons - which is the
; "corrupted tray" complaint all over again. So "TrayEdge", which covers nothing,
; is the default, and "Clock" is there for anyone who wants strict adjacency and
; accepts the cost.
global CLOCK_ANCHORS  := ["TrayEdge", "Clock", "TaskbarLeft"]

; Accent colour for the active-window border. Not in TUNE_SPEC because it is not
; a number; "auto" follows the Windows accent colour.
global BorderColor := "auto"

; A tray label string IS its own lookup key - SyncTray() passes the whole
; "Magnetic snap`tShift+Alt+S" to Check/Uncheck, and m.Default matches on it too.
; Written out by hand it appeared at three sites per item, so it drifted at two:
; every one of these still read Win+Ctrl+* long after commit 3dadac4 moved the
; bindings to Shift+Alt, and correcting only the m.Add call would have silently
; killed the tick marks. One constant per item, used at every site.
;
; They live in the flag block rather than next to BuildTray() so a label is
; assigned before anything can reach SyncTray(). Boot() removed the ordering
; hazard that originally forced this, but the grouping is still the right one:
; a label is a constant, not part of the menu build.
global TRAY_SETTINGS  := "Settings`tShift+Alt+W"

global TRAY_SNAP      := "Magnetic snap`tShift+Alt+S"

global TRAY_MEMORY    := "Position memory`tShift+Alt+M"

global TRAY_BREATHING := "Breathing windows`tShift+Alt+E"

global TRAY_STEALTH   := "Stealth Panic settings`tEsc Esc Esc"
