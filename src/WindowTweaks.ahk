#Requires AutoHotkey v2.0
#SingleInstance Force
#Include SnapCore.ahk
#Include RenderCore.ahk
#Include AnimationScheduler.ahk
#Include MediaCore.ahk
Persistent
DetectHiddenWindows false
SetWinDelay -1
#MaxThreadsPerHotkey 2

; Every thread inherits this, and timer threads have no other way to get it.
; Without it the timers ran on the default coordinate mode while only a handful
; of hotkey bodies set Screen locally, so hot corners, the monitor dimmer and
; the fly-to-mouse minimize rect compared client-relative mouse coordinates
; against screen rectangles. Nothing here wants client coordinates.
CoordMode "Mouse", "Screen"

; Idle cost: no debug history buffers, no key history ring, below-normal
; priority so this never competes with the app you are actually using.
ListLines False
KeyHistory 0
ProcessSetPriority "BelowNormal"

; Window Tweaks - snapping, ice glide, always-on-top, position memory, taskbar.
; Win+Ctrl+W opens the settings window. See GUIDE.md.

global VERSION := "1.0"

global INI      := A_ScriptDir "\settings.ini"
global LOG_FILE := A_ScriptDir "\snap.log"
global POS_FILE := A_ScriptDir "\window-positions.ini"

; Single backslashes. AHK escapes with a backtick, so "HKCU\\Software\\..."
; is a literal double backslash naming a key that cannot exist.
global EP_KEY       := "HKCU\Software\ExplorerPatcher"
global ADVANCED_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

global SNAP_DISTANCE  := 30
global CORNER_BOOST   := 2.2
global NEIGHBOUR_PROX := 90
global MIN_DRAG       := 4
global MAX_LOG_BYTES  := 262144
global LOG_FLUSH_BYTES := 16384
global LogBuf         := ""
; Logging is buffered and written by an idle one-shot, but it is still disk
; I/O and a growing file for something most users never read. It now has a
; switch like everything else.
global DEBUG          := false
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
global FocusDepthEnabled := false
global CurtainDropEnabled := true
global SparkTypingEnabled := false        ; OFF-BY-DEFAULT: never rendered until now
global CarouselAltTabEnabled := false     ; OFF-BY-DEFAULT: never rendered until now
global MotionBlurScrollEnabled := false   ; OFF-BY-DEFAULT: never rendered until now
global TaskbarWaveEnabled := false        ; OFF-BY-DEFAULT: never rendered until now
global StartMenuBlurEnabled := true
global ToastBounceEnabled := true
global MonitorThrowEnabled := true
global BlackHoleDeleteEnabled := false    ; OFF-BY-DEFAULT: never rendered until now
global CursorYawnEnabled := true
global CursorYawnActive := false
global CursorYawnIdleTime := 900000
global ShatterEnabled := false            ; OFF-BY-DEFAULT: never rendered until now
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
; SendMessageTimeout to a foreign window, then re-synthesised. Win+Ctrl+R still
; rolls a window up regardless; this flag only gates the middle-click gesture.
global RollUpEnabled := false
global TrayMinimizeEnabled := true
global BossKeyEnabled := true
global AltDragEnabled := true
global TaskbarScrollEnabled := true
global QuickFolderJumpEnabled := true
global PlainPasteEnabled := true
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

; =========================================================== Tuning registry ===========================================================
; One row per user-tunable NUMBER. Loading, clamping, persistence, the settings
; control and its hint are all generated from this table.
;
; It exists because the original five numeric settings repeated their range in
; three places - the declared default, the clamp block at the end of LoadSettings
; and the Clamp() call in ApplyUi - so a range could (and did) drift between
; them. Every range now lives in exactly one row, which is also the only thing
; that has to be touched to add a setting.
;
;   key    TUNE_VAL key, and the C[] control key in the settings window
;          (the value map is TUNE_VAL, not TUNE: AHK identifiers are
;           case-insensitive, so a `TUNE` map and a `Tune()` accessor are the
;           same name and the script refuses to load)
;   sec    settings.ini section        ini   settings.ini key
;   def    default, always inside [lo, hi]
;   lo/hi  hard bounds. lo is the LOWEST USABLE value, not the lowest legal one:
;          a feature is switched off with its checkbox, not by typing 0 into its
;          duration. Where 0 does mean something ("stop where you let go", "screen
;          edges only", "gate disabled") the row says so in its hint.
;   step   the granularity the value is meaningful in. These are typed fields,
;          not spinners, so this is NOT used to quantise input - snapping 33 to
;          35 while someone is typing 330 is hostile. It is surfaced in the hint
;          so the useful resolution is visible.
;   dec    decimal places. 0 also makes the Edit control Number-only.
;   page   which settings page builds the row; "" = INI-only, no control.
;
; 'lo'/'hi' rather than 'min'/'max': the latter read as the built-in functions.
; Percentages are stored as 0-100 and converted with TuneAlpha(); every opacity
; in the program is exposed that way so the units never vary between features.
TS(key, sec, ini, def, lo, hi, step, dec, page, label, hint) =>
    {key: key, sec: sec, ini: ini, def: def, lo: lo, hi: hi
    , step: step, dec: dec, page: page, label: label, hint: hint}

global TUNE_SPEC := [
;      key             sec          ini             def     lo      hi     step dec page       label                      hint
  TS("snapDist"     , "snap"     , "distance"    ,     30,     4,    120,     1, 0, "win"    , "Snap distance"          , "px from an edge")
, TS("snapBoost"    , "snap"     , "cornerBoost" ,    2.2,     1,      5,   0.1, 1, "win"    , "Corner boost"           , "x stronger at corners")
, TS("snapProx"     , "snap"     , "neighbour"   ,     90,     0,    400,    10, 0, "win"    , "Neighbour reach"        , "px to nearby windows, 0 = edges only")
, TS("glideThrow"   , "glide"    , "throw"       ,    0.9,     0,      3,   0.1, 1, "win"    , "Throw strength"         , "0 = stop where you let go")
, TS("glideMs"      , "glide"    , "ms"          ,    650,   120,   1500,    10, 0, "win"    , "Slide time"             , "ms maximum")
, TS("glideMax"     , "glide"    , "max"         ,    500,   100,   2000,    50, 0, "win"    , "Throw distance"         , "px a flick can carry a window")
, TS("parallaxMin"  , "memory"   , "parallaxmin" ,     24,    10,    100,     5, 0, "win"    , "Drag opacity floor"     , "% at full drag speed")
, TS("gridGap"      , "snap"     , "smartgap"    ,      8,     0,     40,     2, 0, "win"    , "Tiling grid gap"        , "px between tiled windows")
, TS("elasticAmt"   , "snap"     , "elasticamt"  ,     18,     4,     60,     2, 0, "win"    , "Rubber-band travel"     , "px the window leans")
, TS("ghostAlpha"   , "ghost"    , "alpha"       ,     16,     5,     60,     1, 0, "power"  , "Ghost opacity"          , "% when the mouse is far away")
, TS("ghostRange"   , "ghost"    , "range"       ,    350,    50,   1500,    25, 0, "power"  , "Ghost fade range"       , "px at which it starts fading in")
, TS("ghostClick"   , "ghost"    , "clickrange"  ,     80,    20,    400,    10, 0, "power"  , "Ghost click range"      , "px at which it becomes clickable")
, TS("osdStep"      , "osd"      , "volumestep"  ,      2,     1,     20,     1, 0, "media"  , "Volume step"            , "% per wheel notch")
, TS("osdHide"      , "osd"      , "hidems"      ,   1500,   500,  10000,   250, 0, "media"  , "OSD hold time"          , "ms on screen after the last change")
, TS("osdAlpha"     , "osd"      , "alpha"       ,     86,    40,    100,     5, 0, "media"  , "OSD opacity"            , "%")
, TS("wrapTol"      , "wrap"     , "tolerance"   ,      2,     0,     20,     1, 0, "multi"  , "Edge tolerance"         , "px band that counts as the edge")
, TS("wrapDelay"    , "wrap"     , "delay"       ,    250,     0,   2000,    25, 0, "multi"  , "Hold time"              , "ms against the edge, 0 = no wait")
, TS("wrapSpeed"    , "wrap"     , "speed"       ,    250,     0,   3000,    50, 0, "multi"  , "Approach speed"         , "px/s minimum, 0 = any speed")
, TS("wrapCool"     , "wrap"     , "cooldown"    ,    700,   100,   5000,    50, 0, "multi"  , "Cooldown"               , "ms before it can wrap again")
, TS("dimmerAlpha"  , "dimmer"   , "alpha"       ,     47,    10,     90,     5, 0, "multi"  , "Dim strength"           , "% on inactive monitors")
, TS("borderThick"  , "border"   , "thickness"   ,      2,     1,      8,     1, 0, "multi"  , "Border thickness"       , "px")
, TS("borderAlpha"  , "border"   , "alpha"       ,    100,    20,    100,     5, 0, "multi"  , "Border opacity"         , "%")
, TS("breatheIdle"  , "breathing", "idle"        ,   6000,  1000,  60000,   500, 0, "multi"  , "Breathe after"          , "ms of inactivity")
, TS("breatheAlpha" , "breathing", "alpha"       ,     70,    20,     95,     5, 0, "multi"  , "Breathe opacity"        , "% once dimmed")
, TS("yawnIdle"     , "mouse"    , "cursoryawntime", 900000, 60000, 7200000, 60000, 0, "multi", "Cursor yawn after"    , "ms idle (900000 = 15 min)")
, TS("shakeCount"   , "mouse"    , "shakecount"  ,      6,     3,     15,     1, 0, "multi"  , "Shake sensitivity"      , "direction changes to trigger")
, TS("shakeSize"    , "mouse"    , "shakesize"   ,    150,    50,    400,    10, 0, "multi"  , "Shake highlight size"   , "px across")
, TS("cornerSize"   , "corners"  , "size"        ,      5,     1,     40,     1, 0, "corners", "Corner size"            , "px square that arms the corner")
, TS("cornerDelay"  , "corners"  , "delay"       ,    150,     0,   2000,    25, 0, "corners", "Hold time"              , "ms in the corner, 0 = instant")
, TS("animOpenMs"   , "anim"     , "openms"      ,    240,    60,   1000,    10, 0, "anim"   , "New window"             , "ms for the open animation")
, TS("animOpenSlide", "anim"     , "openslide"   ,     30,     5,    200,     5, 0, "anim"   , "Slide-in distance"      , "px Ghost Slide-In rises")
, TS("animPulseMs"  , "anim"     , "pulsems"     ,    190,    60,    600,    10, 0, "anim"   , "Focus pulse"            , "ms")
, TS("animPulse"    , "anim"     , "pulse"       ,    1.5,   0.2,      5,   0.1, 1, "anim"   , "Focus pulse size"       , "% the window grows")
, TS("animBounceMs" , "anim"     , "bouncems"    ,    150,    60,    600,    10, 0, "anim"   , "Snap bounce"            , "ms")
, TS("animBounce"   , "anim"     , "bounce"      ,     15,     1,     40,     1, 0, "anim"   , "Snap bounce depth"      , "px of squash on impact")
, TS("animRollMs"   , "anim"     , "rollupms"    ,    190,    60,    800,    10, 0, "anim"   , "Roll-up"                , "ms")
, TS("animSeamMs"   , "anim"     , "seamms"      ,    190,    60,    800,    10, 0, "anim"   , "Seam flash"             , "ms")
, TS("animGravityMs", "anim"     , "gravityms"   ,    320,   100,   1500,    20, 0, "anim"   , "Gravity close"          , "ms for the Alt+F4 drop")
, TS("animFadeMs"   , "anim"     , "fadems"      ,    110,    30,    500,    10, 0, "anim"   , "Overlay fade"           , "ms for dimmers and previews")
, TS("animNotchMs"  , "anim"     , "notchms"     ,    150,    50,    600,    10, 0, "anim"   , "OSD slide"              , "ms for the notch drop")
, TS("focusAlpha"   , "focus"    , "alpha"       ,     94,    30,    100,     5, 0, "anim"   , "Focus mode dim"         , "% outside the active window")
, TS("focusFeather" , "focus"    , "feather"     ,     70,     0,    200,    10, 0, "anim"   , "Focus mode softness"    , "px of falloff per layer")
, TS("focusRadius"  , "focus"    , "radius"      ,     40,     0,    200,     5, 0, "anim"   , "Focus mode corners"     , "px corner radius")
, TS("transStep"    , "trans"    , "step"        ,     25,     5,     64,     1, 0, "anim"   , "Transparency step"      , "alpha per Win+Ctrl+wheel notch")
, TS("transMin"     , "trans"    , "min"         ,     20,     5,     90,     5, 0, "anim"   , "Transparency floor"     , "% the wheel will not go below")
]

global TUNE_VAL       := Map()      ; key -> validated value
global TUNE_INDEX := Map()      ; key -> spec row, built once by TuneInit()

; Accent colour for the active-window border. Not in TUNE_SPEC because it is not
; a number; "auto" follows the Windows accent colour.
global BorderColor := "auto"

global Win := "", Pages := Map(), NavItems := Map(), CurPage := ""
global C := Map()
global IniCache := Map()

LoadSettings()
RotateLog()
SyncTray()
BuildTray()

; InitShakeFind() and InitLightsaber() are NOT called here. Top-level
; "global X := ..." initialisers run in file order, and both functions' globals
; are declared thousands of lines below this point - calling them here created
; the overlay GUIs and then had SF_Hwnd/LS_Gui/LS_Hwnd reset to 0 underneath
; them, and armed ShakeDetector's 40 ms timer before the variables it reads
; existed. They are called at the very bottom of the file instead.


WriteLog("=== Window Tweaks " VERSION " started ===")

; =========================================================== Settings ===========================================================
; Kept for any caller that wants a bare number; the tuning registry has its own
; reader. Seeds the write cache like IniStr does, so a value that is already
; correct on disk is not rewritten by the next save.
IniNum(section, key, defaultVal) {
    global INI, IniCache
    try {
        raw := IniRead(INI, section, key, defaultVal)
        if (String(raw) == String(defaultVal))
            IniCache[section "`n" key] := String(raw)
        return Number(raw)
    }
    return defaultVal
}

; Reads a string setting AND seeds the write cache with what was on disk, so the
; first save does not pointlessly rewrite the 38 keys that already hold the right
; value. The sentinel distinguishes "key absent" from "key present but empty" -
; an empty value is legitimate (a cleared media_fallback list), and treating it
; as absent would make that setting impossible to clear.
IniStr(section, key, defaultVal) {
    global INI, IniCache
    v := Chr(1)
    try v := IniRead(INI, section, key, Chr(1))
    if (v == Chr(1))
        return defaultVal              ; absent: leave it uncached so it gets written
    IniCache[section "`n" key] := v
    return v
}

; Settings that feed a DropDownList must be validated by MEMBERSHIP, not range.
; A value that is merely "not silly" still breaks two things: Choose() throws on
; a string that is not in the list, which happens inside BuildWin and leaves
; Win+Ctrl+W permanently dead, and a value the dropdown cannot show leaves the
; GUI displaying one thing while the engine uses another.
IniPick(section, key, allowed, defaultVal) {
    v := IniStr(section, key, defaultVal)
    for a in allowed {
        if (v == a)
            return v
    }
    return defaultVal
}

; 1-based position of `needle` in `list`, or 1. Used to build "Choose<n>" options
; so a dropdown can never be handed a value it does not contain.
IndexOf(list, needle) {
    for i, v in list {
        if (v == needle)
            return i
    }
    return 1
}

; ----- Tuning registry: load / validate / persist / build -------------------
; See the TUNE_SPEC table near the top of the file for what a row means.

TuneInit() {
    global TUNE_SPEC, TUNE_INDEX
    if TUNE_INDEX.Count
        return
    for s in TUNE_SPEC
        TUNE_INDEX[s.key] := s
}

TuneSpec(key) {
    global TUNE_INDEX
    TuneInit()
    return TUNE_INDEX.Has(key) ? TUNE_INDEX[key] : ""
}

; The validated value. Named Tune(), not T(): AHK identifiers are
; case-insensitive and T is a rectangle-top variable in half this file.
Tune(key) {
    global TUNE_VAL
    return TUNE_VAL.Has(key) ? TUNE_VAL[key] : 0
}

; A percentage row as a 0-255 alpha. Every opacity in the program is stored as a
; percentage so the unit never changes between features; this is the one place
; that converts.
TuneAlpha(key) {
    v := Round(Tune(key) * 2.55)
    return (v < 0) ? 0 : (v > 255) ? 255 : v
}

; Clamp into range and round to the row's precision. Note this does NOT snap to
; s.step - see the note on the spec table.
TuneClean(s, v) {
    if !IsNumber(v)
        return s.def
    v := Clamp(Number(v), s.lo, s.hi)
    return (s.dec > 0) ? Round(v, s.dec) : Integer(Round(v))
}

; How a value is written to disk and shown in its control - one function, so the
; on-disk text and the control text can never disagree and cause a pointless
; rewrite on every save.
TuneFormat(s, v) => (s.dec > 0) ? String(Round(v, s.dec)) : String(Integer(v))

TuneText(key) {
    s := TuneSpec(key)
    return s ? TuneFormat(s, Tune(key)) : ""
}

TuneLoad() {
    global TUNE_VAL, TUNE_SPEC, INI, IniCache
    TuneInit()
    for s in TUNE_SPEC {
        raw := ""
        try raw := IniRead(INI, s.sec, s.ini, "")
        v := TuneClean(s, raw)
        TUNE_VAL[s.key] := v
        ; Seed the write cache ONLY when the file already holds exactly what we
        ; would write. A missing, malformed or out-of-range value is left
        ; uncached so the next save corrects it on disk instead of remembering
        ; it as already-written. (IniStr does the same for string settings;
        ; IniNum never did, which is why numeric keys were rewritten every time.)
        if (raw == TuneFormat(s, v))
            IniCache[s.sec "`n" s.ini] := raw
    }
    SyncTuningGlobals()
}

TuneSave() {
    global TUNE_SPEC
    for s in TUNE_SPEC
        PutIni(TuneFormat(s, Tune(s.key)), s.sec, s.ini)
}

; Read every generated control back. writeBack corrects the control text to the
; clamped value; ApplyUi only asks for that on LoseFocus and on close, never on
; the debounced Change, because rewriting a field mid-keystroke turns a typed
; "330" into "35" the moment the debounce fires on "3".
TuneApplyUi(writeBack := false) {
    global TUNE_VAL, TUNE_SPEC, C
    corrected := false
    for s in TUNE_SPEC {
        if (s.page == "" || !C.Has(s.key))
            continue
        raw := ""
        try raw := C[s.key].Value
        catch
            continue
        TUNE_VAL[s.key] := TuneClean(s, IsNumber(raw) ? raw : Tune(s.key))
        if (writeBack) {
            shown := TuneFormat(s, Tune(s.key))
            if (String(raw) != shown) {
                try C[s.key].Value := shown
                corrected := true
            }
        }
    }
    ; Writing a control fires its own Change event, which arms the debounced
    ; ApplyUi. Cancel it: the values are already applied, and letting it run
    ; would re-enter this function for nothing.
    if corrected
        SetTimer(ApplyUi, 0)
    SyncTuningGlobals()
}

; Mirror the rows that back a long-standing global into that global, so every
; existing read site (SnapWindow, Glide, BreathingMonitorStep, ShakeDetector...)
; is untouched by the registry and keeps its zero-lookup access.
SyncTuningGlobals() {
    global SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX, GLIDE_THROW, GLIDE_MS
    global GLIDE_MAX, BREATHE_IDLE_MS, CursorYawnIdleTime
    SNAP_DISTANCE      := Integer(Tune("snapDist"))
    CORNER_BOOST       := Tune("snapBoost")
    NEIGHBOUR_PROX     := Integer(Tune("snapProx"))
    GLIDE_THROW        := Tune("glideThrow")
    GLIDE_MS           := Integer(Tune("glideMs"))
    GLIDE_MAX          := Integer(Tune("glideMax"))
    BREATHE_IDLE_MS    := Integer(Tune("breatheIdle"))
    CursorYawnIdleTime := Integer(Tune("yawnIdle"))
}

; One "Label [value] hint" row, laid out like every hand-written settings row.
; Called inline from BuildWin at the point the value belongs, so a number sits
; under the checkbox it belongs to rather than in a distant list of numbers.
TuneRow(pg, key, col, subCol, pos := "xm y+12") {
    global C
    s := TuneSpec(key)
    if !s
        return
    Lbl(pg, col, s.label, pos, 190)
    C[key] := pg.AddEdit("x196 yp-3 w70" (s.dec > 0 ? "" : " Number"), TuneText(key))
    Sub(pg, 250, subCol, s.hint " (" TuneFormat(s, s.lo) "-" TuneFormat(s, s.hi)
        . (s.step != 1 ? ", step " s.step : "") ")", "x+12 yp+3")
}

LoadSettings() {
    global
    SnapEnabled    := IniStr("snap", "enabled", "1") = "1"
    MagneticGroupsEnabled := IniStr("snap", "magnetic", "0") = "1"
    ElasticScrollEnabled := IniStr("snap", "elastic", "0") = "1"
    TextMagnifierEnabled := IniStr("mouse", "textmag", "1") = "1"
    SmartGridEnabled := IniStr("snap", "smartgrid", "1") = "1"
    RippleClickEnabled := IniStr("mouse", "ripple", "0") = "1"
    ContextMenuAnimEnabled := IniStr("mouse", "contextanim", "0") = "1"
    ElasticDragEnabled := IniStr("mouse", "elasticdrag", "1") = "1"
    BreatheCursorEnabled := IniStr("mouse", "breathe", "1") = "1"
    SeamFlashEnabled := IniStr("snap", "flash", "1") = "1"
    BlackHoleMinimizeEnabled := IniStr("memory", "blackhole", "1") = "1"
    MomentumTiltEnabled := IniStr("mouse", "momentum", "1") = "1"
    FocusDepthEnabled := IniStr("memory", "focusdepth", "0") = "1"
    CurtainDropEnabled := IniStr("memory", "curtain", "1") = "1"
    SparkTypingEnabled := IniStr("mouse", "spark", "0") = "1"
    CarouselAltTabEnabled := IniStr("memory", "carousel", "0") = "1"
    MotionBlurScrollEnabled := IniStr("mouse", "motionblur", "0") = "1"
    TaskbarWaveEnabled := IniStr("taskbar", "wave", "0") = "1"
    StartMenuBlurEnabled := IniStr("taskbar", "startblur", "1") = "1"
    ToastBounceEnabled := IniStr("taskbar", "toastbounce", "1") = "1"
    MonitorThrowEnabled := IniStr("mouse", "monthrow", "1") = "1"
    BlackHoleDeleteEnabled := IniStr("mouse", "blackhole", "0") = "1"
    CursorYawnEnabled := IniStr("mouse", "cursoryawn", "1") = "1"
    ShatterEnabled := IniStr("mouse", "shatter", "0") = "1"
    LightsaberSeamEnabled := IniStr("mouse", "lightsaber", "1") = "1"
    PrivacyBlurEnabled := IniStr("window", "privacyblur", "1") = "1"
    ; SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX, GLIDE_THROW, GLIDE_MS,
    ; GLIDE_MAX, BREATHE_IDLE_MS and CursorYawnIdleTime are all loaded, clamped
    ; and mirrored back into their globals by TuneLoad() at the end of this
    ; function, along with every other tunable number.
    GlideEnabled   := IniStr("glide", "enabled", "1") = "1"
    RestoreEnabled := IniStr("memory", "enabled", "1") = "1"
    GravityCloseEnabled := IniStr("memory", "gravityclose", "1") = "1"
    DEBUG := IniStr("memory", "debuglog", "0") = "1"
    BreathingEnabled := IniStr("memory", "breathing", "1") = "1"
    PulseEnabled := IniStr("memory", "pulse", "1") = "1"
    OpenAnim := IniPick("memory", "openanim", OPEN_ANIMS, "Ghost Slide-In")
    FlyMinimizeEnabled := IniStr("memory", "fly", "1") = "1"
    RollUpEnabled := IniStr("memory", "rollup", "0") = "1"
    TrayMinimizeEnabled := IniStr("memory", "traymin", "1") = "1"
    BossKeyEnabled := IniStr("memory", "bosskey", "1") = "1"
    AltDragEnabled := IniStr("memory", "altdrag", "1") = "1"
    TaskbarScrollEnabled := IniStr("memory", "taskbarscroll", "1") = "1"
    QuickFolderJumpEnabled := IniStr("memory", "quickfolder", "1") = "1"
    PlainPasteEnabled := IniStr("memory", "plainpaste", "1") = "1"
    SmartCapsEnabled := IniStr("memory", "smartcaps", "1") = "1"
    SmartCapsAction := IniPick("memory", "smartcaps_act", CAPS_ACTIONS, "Escape")
    ParallaxEnabled := IniStr("memory", "parallax", "1") = "1"
    QuickLookEnabled := IniStr("memory", "quicklook", "1") = "1"
    MultiMonitorDimmerEnabled := IniStr("memory", "multidimmer", "0") = "1"
    HotCornersEnabled := IniStr("corners", "enabled", "0") = "1"
    HotCornerTL := IniPick("corners", "tl", CORNER_ACTIONS, "None")
    HotCornerTR := IniPick("corners", "tr", CORNER_ACTIONS, "Task View")
    HotCornerBL := IniPick("corners", "bl", CORNER_ACTIONS, "None")
    HotCornerBR := IniPick("corners", "br", CORNER_ACTIONS, "Show Desktop")
    PremiumVolumeOSDEnabled := IniStr("memory", "osd", "1") = "1"
    LivePipEnabled := IniStr("memory", "pip", "1") = "1"
    GrabPanEnabled := IniStr("memory", "grabpan", "0") = "1"
    MicKillSwitchEnabled := IniStr("memory", "mickill", "1") = "1"
    InfiniteWrapEnabled := IniStr("memory", "wrap", "0") = "1"
    SpotlightEnabled := IniStr("memory", "spotlight", "1") = "1"
    ActiveBorderEnabled := IniStr("memory", "border", "0") = "1"
    AlwaysOnBottomEnabled := IniStr("memory", "bottom", "1") = "1"
    TextExpanderEnabled := IniStr("memory", "expander", "1") = "1"
    MiddleClickCloseEnabled := IniStr("memory", "midclose", "0") = "1"
    ProximityGhostEnabled := IniStr("memory", "ghost", "1") = "1"
    ShakeFindEnabled := IniStr("mouse", "shakefind", "1") = "1"
    SmartTaskbarEnabled := IniStr("taskbar", "smart", "0") = "1"
    MediaFallbackList := IniStr("memory", "media_fallback", "youtube.exe; spotify.exe; vlc.exe; potplayermini64.exe; mpc-hc64.exe; netflix.exe")
    
    OriginalTaskbarState := GetTaskbarState()
    
    ; Backslash is NOT an escape character in AHK (backtick is), so "HKCU\\..."
    ; is a literal double backslash and the key can never be found. These reads
    ; are wrapped in try, so getting it wrong fails completely silently.
    ; Value names are ExplorerPatcher's own - see PatcherSettings\*.reg.
    EP_Style := "Win11"
    try EP_Style := RegRead(EP_KEY, "OldTaskbar", 0) != 0 ? "Win10" : "Win11"
    EP_IconSize := "Large"
    try EP_IconSize := RegRead(ADVANCED_KEY, "TaskbarSmallIcons", 0) != 0 ? "Small" : "Large"

    ; "auto" follows the Windows accent colour. Validated by shape, like the
    ; enumerated settings are validated by membership: a value the GUI cannot
    ; round-trip must never reach Gui.BackColor.
    BorderColor := IniStr("border", "color", "auto")
    if !(BorderColor = "auto" || BorderColor ~= "^[0-9A-Fa-f]{6}$")
        BorderColor := "auto"

    ; Every tunable number, clamped against the one table that owns its range.
    ; A corrupt INI must not stop the program from starting, so TuneClean falls
    ; back to the declared default for anything non-numeric.
    TuneLoad()
}

; Written values, so an unchanged key is never written again.
;
; Measured: one IniWrite costs 771 us, and SaveSettings writes 45 keys - 34.6 ms
; of blocking disk I/O. It runs on every checkbox click, every debounced keystroke
; in the settings window, and every toggle hotkey, so Win+Ctrl+S used to stall the
; whole process for 35 ms. A toggle changes exactly one key; writing only that one
; costs 0.8 ms, and SaveSettings() no longer writes at all - it queues.

PutIni(value, section, key) {
    global INI, IniCache
    v := String(value)
    ck := section "`n" key
    if (IniCache.Has(ck) && IniCache[ck] == v)
        return
    try {
        IniWrite(v, INI, section, key)
        IniCache[ck] := v
    }
}

; Public entry point: mark the settings dirty. The actual disk write happens on a
; one-shot idle timer, so nothing the user does waits for it. Bye() forces it.
SaveSettings() {
    SetTimer(WriteSettings, -700)
}

WriteSettings() {
    global
    SetTimer(WriteSettings, 0)
    PutIni(SnapEnabled ? 1 : 0,      "snap", "enabled")
    PutIni(MagneticGroupsEnabled ? 1 : 0, "snap", "magnetic")
    PutIni(ElasticScrollEnabled ? 1 : 0,  "snap", "elastic")
    PutIni(TextMagnifierEnabled ? 1 : 0,  "mouse", "textmag")
    PutIni(SmartGridEnabled ? 1 : 0, "snap", "smartgrid")
    PutIni(RippleClickEnabled ? 1 : 0,  "mouse", "ripple")
    PutIni(ContextMenuAnimEnabled ? 1 : 0,  "mouse", "contextanim")
    PutIni(ElasticDragEnabled ? 1 : 0,  "mouse", "elasticdrag")
    PutIni(BreatheCursorEnabled ? 1 : 0,  "mouse", "breathe")
    PutIni(SeamFlashEnabled ? 1 : 0, "snap", "flash")
    PutIni(BlackHoleMinimizeEnabled ? 1 : 0, "memory", "blackhole")
    PutIni(MomentumTiltEnabled ? 1 : 0, "mouse", "momentum")
    PutIni(FocusDepthEnabled ? 1 : 0, "memory", "focusdepth")
    PutIni(CurtainDropEnabled ? 1 : 0, "memory", "curtain")
    PutIni(SparkTypingEnabled ? 1 : 0, "mouse", "spark")
    PutIni(CarouselAltTabEnabled ? 1 : 0, "memory", "carousel")
    PutIni(MotionBlurScrollEnabled ? 1 : 0, "mouse", "motionblur")
    PutIni(TaskbarWaveEnabled ? 1 : 0, "taskbar", "wave")
    PutIni(StartMenuBlurEnabled ? 1 : 0, "taskbar", "startblur")
    PutIni(ToastBounceEnabled ? 1 : 0, "taskbar", "toastbounce")
    PutIni(MonitorThrowEnabled ? 1 : 0, "mouse", "monthrow")
    PutIni(BlackHoleDeleteEnabled ? 1 : 0, "mouse", "blackhole")
    PutIni(CursorYawnEnabled ? 1 : 0, "mouse", "cursoryawn")
    PutIni(ShatterEnabled ? 1 : 0, "mouse", "shatter")
    PutIni(LightsaberSeamEnabled ? 1 : 0, "mouse", "lightsaber")
    PutIni(PrivacyBlurEnabled ? 1 : 0, "window", "privacyblur")
    PutIni(GlideEnabled ? 1 : 0,     "glide", "enabled")
    PutIni(RestoreEnabled ? 1 : 0,   "memory", "enabled")
    PutIni(GravityCloseEnabled ? 1 : 0, "memory", "gravityclose")
    PutIni(DEBUG ? 1 : 0,            "memory", "debuglog")
    PutIni(BorderColor,              "border", "color")
    TuneSave()                       ; every tunable number, in one pass
    PutIni(BreathingEnabled ? 1 : 0, "memory", "breathing")
    PutIni(PulseEnabled ? 1 : 0, "memory", "pulse")
    PutIni(OpenAnim, "memory", "openanim")
    PutIni(FlyMinimizeEnabled ? 1 : 0, "memory", "fly")
    PutIni(RollUpEnabled ? 1 : 0, "memory", "rollup")
    PutIni(TrayMinimizeEnabled ? 1 : 0, "memory", "traymin")
    PutIni(BossKeyEnabled ? 1 : 0, "memory", "bosskey")
    PutIni(AltDragEnabled ? 1 : 0, "memory", "altdrag")
    PutIni(TaskbarScrollEnabled ? 1 : 0, "memory", "taskbarscroll")
    PutIni(QuickFolderJumpEnabled ? 1 : 0, "memory", "quickfolder")
    PutIni(PlainPasteEnabled ? 1 : 0, "memory", "plainpaste")
    PutIni(SmartCapsEnabled ? 1 : 0, "memory", "smartcaps")
    PutIni(SmartCapsAction, "memory", "smartcaps_act")
    PutIni(ParallaxEnabled ? 1 : 0, "memory", "parallax")
    PutIni(QuickLookEnabled ? 1 : 0, "memory", "quicklook")
    PutIni(MultiMonitorDimmerEnabled ? 1 : 0, "memory", "multidimmer")
    PutIni(HotCornersEnabled ? 1 : 0, "corners", "enabled")
    PutIni(HotCornerTL, "corners", "tl")
    PutIni(HotCornerTR, "corners", "tr")
    PutIni(HotCornerBL, "corners", "bl")
    PutIni(HotCornerBR, "corners", "br")
    PutIni(PremiumVolumeOSDEnabled ? 1 : 0, "memory", "osd")
    PutIni(LivePipEnabled ? 1 : 0, "memory", "pip")
    PutIni(GrabPanEnabled ? 1 : 0, "memory", "grabpan")
    PutIni(MicKillSwitchEnabled ? 1 : 0, "memory", "mickill")
    PutIni(InfiniteWrapEnabled ? 1 : 0, "memory", "wrap")
    PutIni(SpotlightEnabled ? 1 : 0, "memory", "spotlight")
    PutIni(ActiveBorderEnabled ? 1 : 0, "memory", "border")
    PutIni(AlwaysOnBottomEnabled ? 1 : 0, "memory", "bottom")
    PutIni(TextExpanderEnabled ? 1 : 0, "memory", "expander")
    PutIni(MiddleClickCloseEnabled ? 1 : 0, "memory", "midclose")
    PutIni(ProximityGhostEnabled ? 1 : 0, "memory", "ghost")
    PutIni(ShakeFindEnabled ? 1 : 0, "mouse", "shakefind")
    PutIni(SmartTaskbarEnabled ? 1 : 0, "taskbar", "smart")
    PutIni(MediaFallbackList, "memory", "media_fallback")
    ; ExplorerPatcher treats any non-zero OldTaskbar as "Win10 taskbar", and the
    ; shipped .reg uses 2. Only write when the on/off state actually changes, so
    ; selecting Win10 does not quietly rewrite a working 2 down to a 1.
    ; WriteSettings is assume-global, so every name assigned here becomes a
    ; global - keep these prefixed so they cannot collide with a local elsewhere.
    try {
        epCur := 0
        try epCur := RegRead(EP_KEY, "OldTaskbar", 0)
        epWant := (EP_Style == "Win10")
        if (epWant != (epCur != 0))
            RegWrite(epWant ? 1 : 0, "REG_DWORD", EP_KEY, "OldTaskbar")
    }
    ; Registry writes are cheap, but not free, and this one runs every save.
    epIcon := (EP_IconSize == "Small") ? 1 : 0
    if (!IniCache.Has("epIcon") || IniCache["epIcon"] != epIcon) {
        try {
            RegWrite(epIcon, "REG_DWORD", ADVANCED_KEY, "TaskbarSmallIcons")
            IniCache["epIcon"] := epIcon
        }
    }
}

RotateLog() {
    global LOG_FILE, MAX_LOG_BYTES
    try {
        if (FileExist(LOG_FILE) && FileGetSize(LOG_FILE) > MAX_LOG_BYTES) {
            if FileExist(LOG_FILE ".old")
                FileDelete(LOG_FILE ".old")
            FileMove(LOG_FILE, LOG_FILE ".old")
        }
    }
}

; Log lines are buffered in memory and written by an idle one-shot timer.
;
; Measured on this machine: one FileAppend of a single line costs 1.9 ms in the
; program folder and 9.3 ms under %TEMP% (open + write + close, times whatever
; the AV filter driver adds). WriteLog is called three times per drag, from the
; FinishDrag timer thread - so logging alone was spending 6-28 ms of blocking
; disk I/O inside every single drag, stalling the frame loop and every other
; timer with it. Appending to a string costs 0.3 us.
;
; A held file handle would be faster still, but it keeps the file locked and
; leaves the tail unflushed for "Open log"; buffering keeps both, and adds no
; permanent handle.
WriteLog(s) {
    global DEBUG, LogBuf, LOG_FLUSH_BYTES
    if !DEBUG
        return
    LogBuf .= A_Now "  " s "`n"
    if (StrLen(LogBuf) >= LOG_FLUSH_BYTES) {
        FlushLog()
        return
    }
    ; One-shot, re-armed on each line: nothing is scheduled while idle, and the
    ; write lands ~1.5 s after logging stops rather than inside the drag.
    SetTimer(FlushLog, -1500)
}

FlushLog() {
    global LogBuf, LOG_FILE
    static sinceCheck := 0
    if (LogBuf == "")
        return
    text := LogBuf
    LogBuf := ""                        ; clear first: a failed write must not
    SetTimer(FlushLog, 0)               ; re-queue the same text forever
    try FileAppend(text, LOG_FILE)
    ; RotateLog only ran at startup, so the 256 KB cap did nothing within a long
    ; session - the file just grew. Check every few flushes (FileGetSize is a
    ; disk call, measured at 14 us).
    if (++sinceCheck >= 20) {
        sinceCheck := 0
        RotateLog()
    }
}

Notify(msg) => TrayTip(msg, "Window Tweaks")

; =========================================================== Start with Windows ===========================================================
StartupLink() => A_Startup "\Window Tweaks.lnk"
IsAutoStart()  => FileExist(StartupLink()) ? true : false

SetAutoStart(on) {
    try {
        if on
            FileCreateShortcut(A_AhkPath, StartupLink(), A_ScriptDir,
                               '"' A_ScriptFullPath '"', "Window Tweaks", A_ScriptDir "\WindowTweaks.ico", "", 0)
        else if FileExist(StartupLink())
            FileDelete(StartupLink())
    }
}

; =========================================================== Tray ===========================================================
BuildTray() {
    try TraySetIcon(A_ScriptDir "\WindowTweaks.ico")
    A_IconTip := "Window Tweaks " VERSION
    m := A_TrayMenu
    m.Delete()
    m.Add("Settings`tWin+Ctrl+W", (*) => ShowWin())
    m.Add()
    m.Add("Magnetic snap`tWin+Ctrl+S", (*) => ToggleSnap())
    m.Add("Position memory`tWin+Ctrl+M", (*) => ToggleMemory())
    m.Add("Breathing windows`tWin+Ctrl+E", (*) => ToggleBreathing())
    m.Add()
    m.Add("Restart", (*) => Reload())
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Settings`tWin+Ctrl+W"
    SyncTray()
}

SyncTray() {
    global SnapEnabled, RestoreEnabled, BreathingEnabled
    try SnapEnabled ? A_TrayMenu.Check("Magnetic snap`tWin+Ctrl+S")
                    : A_TrayMenu.Uncheck("Magnetic snap`tWin+Ctrl+S")
    try RestoreEnabled ? A_TrayMenu.Check("Position memory`tWin+Ctrl+M")
                       : A_TrayMenu.Uncheck("Position memory`tWin+Ctrl+M")
    try BreathingEnabled ? A_TrayMenu.Check("Breathing windows`tWin+Ctrl+E")
                         : A_TrayMenu.Uncheck("Breathing windows`tWin+Ctrl+E")
}

; =========================================================== Settings window ===========================================================
IsDark() {
    try return (RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                        "AppsUseLightTheme") = 0)
    return true
}

ShowWin() {
    global Win
    if (Win) {                       ; Win holds a Gui object, not a string
        try {
            WinActivate("ahk_id " Win.Hwnd)
            return
        }
        Win := ""                    ; stale handle - fall through and rebuild
    }
    BuildWin()
}

BuildWin() {
    global Win, Pages, NavItems, C, CurPage, VERSION
    global SnapEnabled, MagneticGroupsEnabled, ElasticScrollEnabled, SeamFlashEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global TextMagnifierEnabled, SmartGridEnabled
    global RippleClickEnabled, ContextMenuAnimEnabled, ElasticDragEnabled, BreatheCursorEnabled
    global GlideEnabled, GLIDE_THROW, GLIDE_MS
    global BlackHoleMinimizeEnabled, MomentumTiltEnabled, FocusDepthEnabled
    global CurtainDropEnabled, SparkTypingEnabled, CarouselAltTabEnabled, MotionBlurScrollEnabled
    global TaskbarWaveEnabled, StartMenuBlurEnabled, ToastBounceEnabled, MonitorThrowEnabled, BlackHoleDeleteEnabled, CursorYawnEnabled, ShatterEnabled, LightsaberSeamEnabled
    global RestoreEnabled, BreathingEnabled, PulseEnabled, OpenAnim, FlyMinimizeEnabled, RollUpEnabled, TrayMinimizeEnabled, BossKeyEnabled, AltDragEnabled, TaskbarScrollEnabled, QuickFolderJumpEnabled, PlainPasteEnabled, SmartCapsEnabled, SmartCapsAction, ParallaxEnabled, EP_Style, EP_IconSize, PrivacyBlurEnabled
    global NAV, SEL, SELF, FG

    dark := IsDark()
    BG   := dark ? "1F1F1F" : "F5F5F5"      ; content background
    NAV  := dark ? "171717" : "E6E6E6"      ; sidebar
    FG   := dark ? "FFFFFF" : "141414"      ; primary text
    cSub  := dark ? "9A9A9A" : "5A5A5A"      ; secondary text
    SEL  := dark ? "0F5FA6" : "CCE4F7"      ; selected nav
    SELF := dark ? "FFFFFF" : "0A0A0A"      ; selected nav text

    W := 780, H := 560, SW := 196

    g := Gui("+Resize +OwnDialogs", "Window Tweaks")
    g.OnEvent("Size", Gui_Size)
    OnMessage(0x020A, OnMouseWheel)
    g.BackColor := BG
    g.MarginX := 0, g.MarginY := 0
    Win := g
    Pages := Map(), NavItems := Map(), C := Map()

    ; --- sidebar ---
    g.SidebarBg := g.AddText("x0 y0 w" SW " h" H " Background" NAV)
    g.SetFont("s13 bold", "Segoe UI")
    g.AddText("x20 y22 w160 c" FG " Background" NAV, "Window Tweaks")
    g.SetFont("s8 norm", "Segoe UI")
    g.AddText("x21 y50 w160 c" cSub " Background" NAV, "version " VERSION)

    g.SetFont("s10 norm", "Segoe UI")
    ny := 88
    for name in ["🪟 Window Management", "⚡ Power Features", "🔊 System & Media", "🖥️ Multi-Monitor", "✨ Animation", "📐 Hot Corners", "⚙️ General"] {
        t := g.AddText("x0 y" ny " w" SW " h42 +0x200 c" FG " Background" NAV, "    " name)
        t.OnEvent("Click", NavClick.Bind(name))
        NavItems[name] := t
        ny += 42
    }

    g.SetFont("s8", "Segoe UI")
    g.HintLbl := g.AddText("x20 y" (H - 40) " w160 c" cSub " Background" NAV, "Win+Ctrl+W  opens this")

    ; --- content ---
    CX := SW + 28, CW := W - SW - 56

    ; Registers under 'name' as well as building the page, so the nav key is
    ; written once. It used to be repeated in a trailing Pages[...] := pg, and
    ; the two names had to agree or the page silently never showed.
    CreatePage(name) {
        pg := Gui("+Parent" Win.Hwnd " -Caption")
        pg.BackColor := BG
        pg.MarginX := 0, pg.MarginY := 26
        Pages[name] := pg
        return pg
    }

    ; ---- Window Management
    pg := CreatePage("🪟 Window Management")
    Head(pg, CW, FG, "Window Management")
    Sub(pg, CW, cSub, "Fluid, physics-based movement and snapping.", "xm y+10")
    
    C["snap"] := Box(pg, CW, FG, "Enable magnetic snapping", SnapEnabled, "xm y+16")
    C["magnetic"] := Box(pg, CW, FG, "Magnetic Window Groups (Win+Ctrl+Shift+G)", MagneticGroupsEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Groups windows together when snapped. Dragging one will pull the other.", "xm y+8")
    
    C["shatter"] := Box(pg, CW, FG, "Shatter to Close (Shift+Alt+F4)", ShatterEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Aggressively close the active window by smashing it into dozens of 3D glass shards.", "xm y+8")
    
    C["lightsaber"] := Box(pg, CW, FG, "Lightsaber Seam Glow", LightsaberSeamEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Hovering between two snapped windows creates a neon glow that shoots down the seam.", "xm y+8")
    
    C["privacyblur"] := Box(pg, CW, FG, "Privacy Blur on Unfocus (Win+Alt+B)", PrivacyBlurEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Mark a window as private. When inactive, it gets a heavy frosted glass overlay.", "xm y+8")
    
    C["smartgrid"] := Box(pg, CW, FG, "Smart Tiling Grid (Hold Shift while dragging)", SmartGridEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shows a visual 3-zone layout grid. Drop the window into a zone to snap it.", "xm y+8")
    TuneRow(pg, "gridGap", FG, cSub)

    C["elastic"] := Box(pg, CW, FG, "Rubber-Band Scroll (Kinetic lean)", ElasticScrollEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Scrolling forcefully pulls the entire window elastically, springing back when stopped.", "xm y+8")
    TuneRow(pg, "elasticAmt", FG, cSub)

    TuneRow(pg, "snapDist",  FG, cSub)
    TuneRow(pg, "snapBoost", FG, cSub)
    TuneRow(pg, "snapProx",  FG, cSub)
    C["flash"] := Box(pg, CW, FG, "Magnetic Seam Flash (neon spark on snap)", SeamFlashEnabled, "xm y+16")

    C["glide"] := Box(pg, CW, FG, "Enable ice glide (Physics-based throwing)", GlideEnabled, "xm y+16")
    TuneRow(pg, "glideThrow", FG, cSub)
    TuneRow(pg, "glideMs",    FG, cSub)
    TuneRow(pg, "glideMax",   FG, cSub)

    C["parallax"] := Box(pg, CW, FG, "Parallax Dragging (Velocity Transparency)", ParallaxEnabled, "xm y+16")
    TuneRow(pg, "parallaxMin", FG, cSub)
    C["altdrag"] := Box(pg, CW, FG, "Linux-Style Alt-Drag (Move & Resize)", AltDragEnabled, "xm y+12")
    
    C["fly"] := Box(pg, CW, FG, "Fly-to-Mouse Minimize (vacuum effect)", FlyMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Minimizes windows to your cursor rather than the taskbar.", "xm y+8")
    
    C["blackhole"] := Box(pg, CW, FG, "Black Hole Minimize (Taskbar suck effect)", BlackHoleMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Minimizes windows directly into the bottom center like a funnel.", "xm y+8")
    
    C["focusdepth"] := Box(pg, CW, FG, "Focus Depth of Field (3D background scale)", FocusDepthEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Pushes inactive windows back slightly and dims them.", "xm y+8")
    
    C["curtain"] := Box(pg, CW, FG, "Curtain Drop (Win+D)", CurtainDropEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Smoothly drops windows down off-screen instead of instantly vanishing.", "xm y+8")
    
    C["carousel"] := Box(pg, CW, FG, "3D Carousel Alt-Tab", CarouselAltTabEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Replaces standard Alt-Tab with a spinning 3D ring of live windows.", "xm y+8")
    
    C["grabpan"] := Box(pg, CW, FG, "Universal Grab && Pan (Win+Ctrl+Shift+P)", GrabPanEnabled, "xm y+12")
    C["rollup"] := Box(pg, CW, FG, "Middle-click title bar to roll up", RollUpEnabled, "xm y+12")
    Sub(pg, CW, cSub, "Win+Ctrl+R rolls a window up whether this is on or off - this is the mouse gesture.", "xm y+8")
    
    C["mem"] := Box(pg, CW, FG, "Remember window positions", RestoreEnabled, "xm y+16")
    b := pg.AddButton("xm y+12 w190 h30", "Forget saved positions")
    b.OnEvent("Click", (*) => ForgetPositions())

    ; ---- Power Features
    pg := CreatePage("⚡ Power Features")
    Head(pg, CW, FG, "Power Features")
    Sub(pg, CW, cSub, "Advanced overlays, widgets, and shortcuts.", "xm y+10")
    
    C["spotlight"] := Box(pg, CW, FG, "Quick Spotlight Launcher (Double-tap Ctrl)", SpotlightEnabled, "xm y+16")
    Sub(pg, CW, cSub, "A fast, minimalist search bar for calculations, folders, and apps.", "xm y+8")
    
    C["pip"] := Box(pg, CW, FG, "Live Window PiP (Win+Ctrl+P)", LivePipEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Win+Ctrl+P on any window to create a live, always-on-top thumbnail.", "xm y+8")
    
    C["ghost"] := Box(pg, CW, FG, "Proximity Ghost Window (Win+Ctrl+G)", ProximityGhostEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Turns active window into an interactive ghost overlay that fades in as your mouse approaches.", "xm y+8")
    TuneRow(pg, "ghostAlpha", FG, cSub)
    TuneRow(pg, "ghostRange", FG, cSub)
    TuneRow(pg, "ghostClick", FG, cSub)

    C["bottom"] := Box(pg, CW, FG, "Always on Bottom / Widget (Win+Ctrl+B)", AlwaysOnBottomEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Pins any window permanently to your desktop background, transforming it into a widget.", "xm y+8")
    
    C["midclose"] := Box(pg, CW, FG, "Middle-Click Titlebar to Close", MiddleClickCloseEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Overrides Roll-Up. Middle-click any window's title bar to close it.", "xm y+8")
    
    C["traymin"] := Box(pg, CW, FG, "Minimize to Tray (Win+Ctrl+H)", TrayMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Hides the active window completely and creates a custom System Tray icon.", "xm y+8")
    
    C["quickfolder"] := Box(pg, CW, FG, "Quick Folder Jump (Ctrl+G in dialogs)", QuickFolderJumpEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Ctrl+G in any File Dialog to jump to the last active Explorer folder.", "xm y+8")
    
    C["quicklook"] := Box(pg, CW, FG, "macOS Quick Look (Spacebar Preview)", QuickLookEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Space on any file in Explorer to preview files instantly.", "xm y+8")

    ; ---- System & Media
    pg := CreatePage("🔊 System & Media")
    Head(pg, CW, FG, "System & Media")
    Sub(pg, CW, cSub, "Audio, typing, and system-wide controls.", "xm y+10")
    
    C["taskbarscroll"] := Box(pg, CW, FG, "Taskbar Volume Scroll", TaskbarScrollEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Scroll over the taskbar to adjust volume. Middle-click to mute.", "xm y+8")
    
    C["osd"] := Box(pg, CW, FG, "Premium Volume OSD", PremiumVolumeOSDEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Show a sleek, macOS-style volume indicator when scrolling the taskbar.", "xm y+8")
    TuneRow(pg, "osdStep",  FG, cSub)
    TuneRow(pg, "osdHide",  FG, cSub)
    TuneRow(pg, "osdAlpha", FG, cSub)

    C["mickill"] := Box(pg, CW, FG, "Global Mic Kill-Switch (Double-tap Alt)", MicKillSwitchEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Quickly double-tap the Alt key to instantly mute or unmute your microphone system-wide.", "xm y+8")
    
    C["bosskey"] := Box(pg, CW, FG, "Boss Key (Win+Ctrl+Esc)", BossKeyEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Instantly hides all windows and mutes system volume. Press again to restore.", "xm y+8")
    
    C["expander"] := Box(pg, CW, FG, "Global Text Expander (Snippets)", TextExpanderEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Type @@mail, @@tel, @@date to auto-expand. Edit snippets in WindowTweaks.ini", "xm y+8")
    
    C["smartcaps"] := Box(pg, CW, FG, "Smart Caps Lock (Hold for Caps, Tap for action)", SmartCapsEnabled, "xm y+16")
    C["smartcaps_act"] := pg.AddDropDownList("x320 yp-3 w90 Choose" IndexOf(CAPS_ACTIONS, SmartCapsAction), CAPS_ACTIONS)
    Sub(pg, CW, cSub, "Holding CapsLock for 0.4s toggles CapsLock. Tapping it sends Esc or Backspace.", "xm y+8")
    
    C["plainpaste"] := Box(pg, CW, FG, "Plain-Text Paste (Ctrl+Win+V)", PlainPasteEnabled, "xm y+16")

    ; Editable at last: this drives MediaCore's fallback list, which decides
    ; which programs are never dimmed by breathing or the monitor dimmer, and
    ; until now it could only be changed by hand-editing settings.ini.
    Lbl(pg, FG, "Never dim these apps", "xm y+20", 190)
    C["mediafallback"] := pg.AddEdit("xm y+6 w" CW, MediaFallbackList)
    ; No " ;" in this string: a space followed by a semicolon starts a comment
    ; even INSIDE a quoted string, so the literal would truncate mid-argument and
    ; the file would fail to load with "Missing """. Same reason the shipped
    ; media_fallback default writes "a.exe; b.exe" and never "a.exe ; b.exe".
    Sub(pg, CW, cSub, "Executable names, comma or semicolon separated - used when no audio API reports playback.", "xm y+6")

    ; ---- Multi-Monitor
    pg := CreatePage("🖥️ Multi-Monitor")
    Head(pg, CW, FG, "Multi-Monitor & Visuals")
    Sub(pg, CW, cSub, "Dual/Triple monitor optimizations and focus effects.", "xm y+10")
    
    C["shakefind"] := Box(pg, CW, FG, "Shake to Find Cursor (macOS style)", ShakeFindEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shake your mouse left and right rapidly to make the cursor temporarily grow.", "xm y+8")
    TuneRow(pg, "shakeCount", FG, cSub)
    TuneRow(pg, "shakeSize",  FG, cSub)

    C["cursoryawn"] := Box(pg, CW, FG, "Cursor Yawn (Wakes up after idle)", CursorYawnEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Cursor stretches and 'yawns' the first time you touch it after a long idle.", "xm y+8")
    TuneRow(pg, "yawnIdle", FG, cSub)

    C["monthrow"] := Box(pg, CW, FG, "Window Throw & Catch (Monitor to Monitor)", MonitorThrowEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Throw a window forcefully towards another monitor to make it fly and land in the center.", "xm y+8")
    
    C["ripple"] := Box(pg, CW, FG, "Ripple Click (Tactile water ripple on click)", RippleClickEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Draws a fast fading ripple when you left click.", "xm y+8")
    
    C["contextanim"] := Box(pg, CW, FG, "Context Menu Unfold (Origami open animation)", ContextMenuAnimEnabled, "xm y+16")
    C["elasticdrag"] := Box(pg, CW, FG, "Elastic Drag (Rubber band trail when dragging)", ElasticDragEnabled, "xm y+16")
    C["breathe"] := Box(pg, CW, FG, "Breathe Cursor (Idle glow effect)", BreatheCursorEnabled, "xm y+16")
    
    C["momentum"] := Box(pg, CW, FG, "Momentum Tilt (Jello bounce on drag stop)", MomentumTiltEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Window jiggles elastically when you suddenly stop moving it.", "xm y+8")
    
    C["spark"] := Box(pg, CW, FG, "Spark Typing (Neon caret trail)", SparkTypingEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Spawns neon sparks behind the text caret while typing.", "xm y+8")

    C["motionblur"] := Box(pg, CW, FG, "Motion Blur Scroll (Vertical speed blur)", MotionBlurScrollEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Applies a cinematic vertical motion blur to text when scrolling fast.", "xm y+8")
    
    C["textmag"] := Box(pg, CW, FG, "Text Selection Magnifier (iOS style)", TextMagnifierEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shows a 2x zoom loupe when selecting text.", "xm y+8")
    
    C["wrap"] := Box(pg, CW, FG, "Infinite Cursor Wrap (Win+Ctrl+Shift+W)", InfiniteWrapEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Push the cursor into the left/right edge of the desktop and hold to teleport to the other side.", "xm y+8")
    TuneRow(pg, "wrapTol",   FG, cSub)
    TuneRow(pg, "wrapDelay", FG, cSub)
    TuneRow(pg, "wrapSpeed", FG, cSub)
    TuneRow(pg, "wrapCool",  FG, cSub)

    C["multidimmer"] := Box(pg, CW, FG, "Multi-Monitor Focus Dimmer (Win+Ctrl+Shift+D)", MultiMonitorDimmerEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Automatically dims every monitor except the one your mouse is currently on.", "xm y+8")
    TuneRow(pg, "dimmerAlpha", FG, cSub)

    C["border"] := Box(pg, CW, FG, "Smart Active Border (Win+Ctrl+Shift+A)", ActiveBorderEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Draws a sleek, accent-colored border around the currently active window.", "xm y+8")
    TuneRow(pg, "borderThick", FG, cSub)
    TuneRow(pg, "borderAlpha", FG, cSub)
    Lbl(pg, FG, "Border colour", "xm y+12", 190)
    C["bordercolor"] := pg.AddEdit("x196 yp-3 w70", BorderColor)
    Sub(pg, 250, cSub, "auto = Windows accent, or a hex RRGGBB", "x+12 yp+3")

    C["breath"] := Box(pg, CW, FG, "Breathing (dim inactive windows)", BreathingEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Windows fade out once you have not touched them for a while.", "xm y+8")
    TuneRow(pg, "breatheIdle",  FG, cSub)
    TuneRow(pg, "breatheAlpha", FG, cSub)

    C["pulse"] := Box(pg, CW, FG, "Focus Pulse (Heartbeat on active)", PulseEnabled, "xm y+16")

    Lbl(pg, FG, "New window animation", "xm y+16")
    C["openanim"] := pg.AddDropDownList("x160 yp-3 w160 Choose" IndexOf(OPEN_ANIMS, OpenAnim), OPEN_ANIMS)

    ; ---- Animation & Timing
    ; The cross-cutting motion values. Everything on this page affects more than
    ; one feature, so it does not belong under any single checkbox.
    pg := CreatePage("✨ Animation")
    Head(pg, CW, FG, "Animation & Timing")
    Sub(pg, CW, cSub, "How long things take and how far they move. Lower is snappier.", "xm y+10")

    Lbl(pg, FG, "Window animations", "xm y+16")
    TuneRow(pg, "animOpenMs",    FG, cSub)
    TuneRow(pg, "animOpenSlide", FG, cSub)
    TuneRow(pg, "animPulseMs",   FG, cSub)
    TuneRow(pg, "animPulse",     FG, cSub)
    TuneRow(pg, "animBounceMs",  FG, cSub)
    TuneRow(pg, "animBounce",    FG, cSub)
    TuneRow(pg, "animRollMs",    FG, cSub)
    TuneRow(pg, "animSeamMs",    FG, cSub)
    TuneRow(pg, "animGravityMs", FG, cSub)

    Lbl(pg, FG, "Overlays", "xm y+20")
    TuneRow(pg, "animFadeMs",   FG, cSub)
    TuneRow(pg, "animNotchMs",  FG, cSub)

    Lbl(pg, FG, "Focus mode (Win+Ctrl+F)", "xm y+20")
    TuneRow(pg, "focusAlpha",   FG, cSub)
    TuneRow(pg, "focusFeather", FG, cSub)
    TuneRow(pg, "focusRadius",  FG, cSub)

    Lbl(pg, FG, "Transparency wheel (Win+Ctrl+wheel)", "xm y+20", 300)
    TuneRow(pg, "transStep", FG, cSub)
    TuneRow(pg, "transMin",  FG, cSub)

    ; ---- Hot Corners
    pg := CreatePage("📐 Hot Corners")
    Head(pg, CW, FG, "macOS Hot Corners")
    Sub(pg, CW, cSub, "Throw your mouse into the corners of the screen to trigger actions.", "xm y+10")
    
    C["corners_en"] := Box(pg, CW, FG, "Enable Hot Corners (Win+Ctrl+Shift+C)", HotCornersEnabled, "xm y+16")
    TuneRow(pg, "cornerSize",  FG, cSub)
    TuneRow(pg, "cornerDelay", FG, cSub)

    ; Choose by index, not by text: Choose("something not in the list") throws,
    ; and it would throw here - inside BuildWin, with no catch - which used to
    ; leave Win+Ctrl+W permanently broken after a hand-edited settings.ini.
    ; LoadSettings validates these now; IndexOf is the second line of defence.
    Lbl(pg, FG, "Top Left:", "xm y+20")
    C["corner_tl"] := pg.AddDropDownList("x140 yp-3 w130 Choose" IndexOf(CORNER_ACTIONS, HotCornerTL), CORNER_ACTIONS)

    Lbl(pg, FG, "Top Right:", "x+30 yp+3")
    C["corner_tr"] := pg.AddDropDownList("x+10 yp-3 w130 Choose" IndexOf(CORNER_ACTIONS, HotCornerTR), CORNER_ACTIONS)

    Lbl(pg, FG, "Bottom Left:", "xm y+20")
    C["corner_bl"] := pg.AddDropDownList("x140 yp-3 w130 Choose" IndexOf(CORNER_ACTIONS, HotCornerBL), CORNER_ACTIONS)

    Lbl(pg, FG, "Bottom Right:", "x+30 yp+3")
    C["corner_br"] := pg.AddDropDownList("x+10 yp-3 w130 Choose" IndexOf(CORNER_ACTIONS, HotCornerBR), CORNER_ACTIONS)
    ; ---- General
    pg := CreatePage("⚙️ General")
    Head(pg, CW, FG, "General Settings")
    
    C["auto"] := Box(pg, CW, FG, "Start with Windows", IsAutoStart(), "xm y+16")

    C["gravityclose"] := Box(pg, CW, FG, "Gravity Drop on Close (Alt+F4)", GravityCloseEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Closing a window drops it off the screen. Off leaves Alt+F4 entirely to Windows.", "xm y+8")

    C["debuglog"] := Box(pg, CW, FG, "Write a debug log (snap.log)", DEBUG, "xm y+16")
    Sub(pg, CW, cSub, "Only needed when reporting a problem. Buffered in memory, written when idle.", "xm y+8")
    
    C["smart_tb"] := Box(pg, CW, FG, "Smart Auto-Hide Taskbar (Win+Ctrl+Shift+T)", SmartTaskbarEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Only hides taskbar when windows maximize or touch the bottom edge.", "xm y+8")
    
    C["deletehole"] := Box(pg, CW, FG, "Recycle Bin Black Hole (Delete Animation)", BlackHoleDeleteEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Deleting a file visually sucks it into a top-left singularity (spaghettification).", "xm y+8")
    
    C["twave"] := Box(pg, CW, FG, "Taskbar Icon Wave", TaskbarWaveEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Hovering over the taskbar creates a magnifying glass bubble that tracks your mouse.", "xm y+8")
    
    C["startblur"] := Box(pg, CW, FG, "Start Menu Blur (Cinematic Focus)", StartMenuBlurEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Heavily blurs the background when the Start Menu is open.", "xm y+8")
    
    C["toast"] := Box(pg, CW, FG, "Elastic Toast Notifications", ToastBounceEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Notifications slide in elastically with an overshoot bounce.", "xm y+8")

    Lbl(pg, FG, "Taskbar Style", "xm y+16")
    C["epStyle"] := pg.AddDropDownList("x170 yp-3 w100 Choose" IndexOf(EP_STYLES, EP_Style), EP_STYLES)
    Sub(pg, 220, cSub, "Win10 supports small icons", "x+16 yp+3")

    Lbl(pg, FG, "Icon Size", "xm y+16")
    C["epIconSize"] := pg.AddDropDownList("x170 yp-3 w100 Choose" IndexOf(EP_ICON_SIZES, EP_IconSize), EP_ICON_SIZES)
    
    b2 := pg.AddButton("xm y+24 w150 h30", "Restart Explorer")
    b2.OnEvent("Click", (*) => RestartExplorer())
    
    b := pg.AddButton("xm y+24 w150 h30", "Open log")
    b.OnEvent("Click", (*) => OpenLog())
    b3 := pg.AddButton("x+12 yp w150 h30", "Open folder")
    b3.OnEvent("Click", (*) => Run(A_ScriptDir))
    b4 := pg.AddButton("xm y+12 w150 h30", "Hotkeys")
    b4.OnEvent("Click", (*) => ShowHotkeys())
    b5 := pg.AddButton("x+12 yp w150 h30", "Guide")
    b5.OnEvent("Click", (*) => OpenDoc("GUIDE.md"))

    g.OnEvent("Close", (*) => CloseWin(g))
    g.OnEvent("Escape", (*) => CloseWin(g))

    for key, ctl in C {
        if (key == "epStyle" || key == "epIconSize")
            ctl.OnEvent("Change", (*) => ApplyUi(true))
        else if InStr(ctl.Type, "CheckBox")
            ctl.OnEvent("Click", (*) => ApplyUi(true))
        else {
            ; Typed fields apply on their own, debounced, so a value takes
            ; effect without needing to click something else afterwards.
            ;
            ; The debounced path deliberately passes writeBack = false. Correcting
            ; an out-of-range number back into the control 600 ms after the last
            ; keystroke would rewrite the field while the user is still typing it -
            ; "3" on the way to "330" becomes the clamped minimum. The correction
            ; happens when focus leaves instead, which is when the user is done.
            ctl.OnEvent("Change", (*) => SetTimer(ApplyUi, -600))
            ctl.OnEvent("LoseFocus", (*) => ApplyUi(true))
        }
    }

    if dark {
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 20, "int*", 1, "uint", 4)
        for ctl in g {
            if (ctl.Type = "Edit" || ctl.Type = "ComboBox" || ctl.Type = "Button")
                DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
        }
        for pname, cpg in Pages {
            for ctl in cpg {
                if (ctl.Type = "Edit" || ctl.Type = "ComboBox" || ctl.Type = "Button")
                    DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
            }
        }
    }

    g.Show("w" W " h" H)
    SelectPage("🪟 Window Management")
}

Head(pg, w, col, txt, pos := "xm") {
    pg.SetFont("s14 bold", "Segoe UI")
    t := pg.AddText(pos " w" w " c" col, txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return t
}
Sub(pg, w, col, txt, pos := "xm y+8") {
    pg.SetFont("s9 norm", "Segoe UI")
    return pg.AddText(pos " w" w " c" col, txt)
}
; `w` defaults to the original 160 so every existing call is unchanged; the
; generated tuning rows pass a wider label because their names are longer.
Lbl(pg, col, txt, pos := "xm y+16", w := 160) {
    pg.SetFont("s10 norm", "Segoe UI")
    t := pg.AddText(pos " w" w " c" col, txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return t
}
Box(pg, w, col, txt, checked, pos := "xm y+16") {
    pg.SetFont("s10 norm", "Segoe UI")
    ; 'ctl', not 'c' - AHK identifiers are case-insensitive, so 'c' is the
    ; global control Map C.
    ctl := pg.AddCheckbox(pos " w" w " c" col (checked ? " Checked" : ""), txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return ctl
}

NavClick(name, *) => SelectPage(name)

SelectPage(name) {
    global Pages, NavItems, CurPage, Win, NAV, SEL, SELF, FG
    if !Pages.Has(name)
        return

    for pname, pg in Pages {
        if (pname = name) {
            y_off := pg.HasOwnProp("Y_Offset") ? pg.Y_Offset : 0
            pg.Show("x224 y" y_off " w528 NoActivate")
        } else {
            pg.Hide()
        }
    }
    
    for pname, item in NavItems {
        item.Opt((pname = name) ? "Background" SEL " c" SELF : "Background" NAV " c" FG)
        item.Redraw()
    }
    CurPage := name
}

Gui_Size(thisGui, minMax, width, height) {
    if (minMax = -1)
        return
    try thisGui.SidebarBg.Move(,,, height)
    try thisGui.HintLbl.Move(, height - 40)
    
    global CurPage, Pages
    if CurPage && Pages.Has(CurPage) {
        pg := Pages[CurPage]
        if !pg.HasOwnProp("Y_Offset")
            pg.Y_Offset := 0
        pg.GetPos(,,, &h)
        minY := height - h
        if (minY > 0)
            minY := 0
        if (pg.Y_Offset < minY) {
            pg.Y_Offset := minY
            pg.Move(, minY)
        }
    }
}

OnMouseWheel(wParam, lParam, msg, hwnd) {
    global CurPage, Pages, Win
    if !Win || !CurPage || !Pages.Has(CurPage)
        return
    if !WinActive("ahk_id " Win.Hwnd)
        return
        
    pg := Pages[CurPage]
    delta := (wParam << 32 >> 48)
    
    if !pg.HasOwnProp("Y_Offset")
        pg.Y_Offset := 0
        
    newY := pg.Y_Offset + (delta > 0 ? 40 : -40)
    
    pg.GetPos(,,, &h)
    Win.GetClientPos(,,, &ph)
    
    minY := ph - h
    if (minY > 0)
        minY := 0
        
    if (newY > 0)
        newY := 0
    if (newY < minY)
        newY := minY
        
    pg.Y_Offset := newY
    pg.Move(, newY)
}

; Closing the window used to run SaveSettings() and only THEN cancel the pending
; debounced ApplyUi, so a value typed within 600 ms of closing was thrown away.
; Apply first, then save, then tear down.
CloseWin(g) {
    global Win
    SetTimer(ApplyUi, 0)
    ApplyUi(true)
    SaveSettings()
    try g.Destroy()
    Win := ""
}

; writeBack corrects an out-of-range number back into its control. Only the
; LoseFocus and close paths ask for it - the debounced Change path must not,
; because rewriting a field between keystrokes turns a half-typed "3" into the
; clamped minimum and the user can never finish typing "330".
ApplyUi(writeBack := false) {
    ; Bare 'global', like LoadSettings/SaveSettings. A partial list is a trap
    ; here: AHK v2 makes a silent local out of any name assigned but not
    ; declared, so a missing entry means that control quietly does nothing.
    global
    if !Win
        return

    ; Reading the controls and acting on them are separated on purpose. It used
    ; to be one long try with no catch, so a single failing control skipped every
    ; assignment after it AND the SaveSettings() at the end - silently.
    ;
    ; ApplyUi is assume-global, so every name assigned here becomes a global -
    ; the ui* prefix keeps these from colliding with anything else.
    uiAutoStart := "", uiOldSmartTb := ""
    ; Turning a feature off has to undo what it already did. Ghost, always-on-
    ; bottom and PiP are each driven by a hotkey inside `#HotIf <flag>`, so once
    ; the flag is false the hotkey no longer exists and the user cannot undo the
    ; state by hand: ghosted windows stay click-through and topmost, pinned windows
    ; stay children of the desktop, thumbnails stay on screen.
    ; Same reasoning for Focus Depth: it is driven from the shell hook rather than
    ; a hotkey, so once the flag is false nothing ever calls BringForwardWindow
    ; again and every pushed-back window stays 98% size at alpha 210 forever.
    uiOldGhost := ProximityGhostEnabled
    uiOldBottom := AlwaysOnBottomEnabled
    uiOldPip := LivePipEnabled
    uiOldFocusDepth := FocusDepthEnabled
    try {
        SnapEnabled    := C["snap"].Value
        MagneticGroupsEnabled := C["magnetic"].Value
        SmartGridEnabled := C["smartgrid"].Value
        ElasticScrollEnabled := C["elastic"].Value

        SeamFlashEnabled := C["flash"].Value
        GlideEnabled   := C["glide"].Value
        RestoreEnabled := C["mem"].Value
        BreathingEnabled := C["breath"].Value
        PulseEnabled   := C["pulse"].Value
        OpenAnim       := C["openanim"].Text
        FlyMinimizeEnabled := C["fly"].Value
        RollUpEnabled  := C["rollup"].Value
        MiddleClickCloseEnabled := C["midclose"].Value
        ProximityGhostEnabled := C["ghost"].Value
        SpotlightEnabled := C["spotlight"].Value
        TrayMinimizeEnabled := C["traymin"].Value
        BossKeyEnabled := C["bosskey"].Value
        AltDragEnabled := C["altdrag"].Value
        GrabPanEnabled := C["grabpan"].Value
        LivePipEnabled := C["pip"].Value
        MicKillSwitchEnabled := C["mickill"].Value
        ShakeFindEnabled := C["shakefind"].Value
        TextMagnifierEnabled := C["textmag"].Value
        RippleClickEnabled := C["ripple"].Value
        ContextMenuAnimEnabled := C["contextanim"].Value
        ElasticDragEnabled := C["elasticdrag"].Value
        BreatheCursorEnabled := C["breathe"].Value
        InfiniteWrapEnabled := C["wrap"].Value
        BlackHoleMinimizeEnabled := C["blackhole"].Value
        MomentumTiltEnabled := C["momentum"].Value
        FocusDepthEnabled := C["focusdepth"].Value
        CurtainDropEnabled := C["curtain"].Value
        SparkTypingEnabled := C["spark"].Value
        CarouselAltTabEnabled := C["carousel"].Value
        MotionBlurScrollEnabled := C["motionblur"].Value
        TaskbarWaveEnabled := C["twave"].Value
        StartMenuBlurEnabled := C["startblur"].Value
        ToastBounceEnabled := C["toast"].Value
        MonitorThrowEnabled := C["monthrow"].Value
        BlackHoleDeleteEnabled := C["deletehole"].Value
        CursorYawnEnabled := C["cursoryawn"].Value
        ShatterEnabled := C["shatter"].Value
        LightsaberSeamEnabled := C["lightsaber"].Value
        PrivacyBlurEnabled := C["privacyblur"].Value
        TaskbarScrollEnabled := C["taskbarscroll"].Value
        PremiumVolumeOSDEnabled := C["osd"].Value
        QuickFolderJumpEnabled := C["quickfolder"].Value
        QuickLookEnabled := C["quicklook"].Value
        MultiMonitorDimmerEnabled := C["multidimmer"].Value
        
        HotCornersEnabled := C["corners_en"].Value
        HotCornerTL := C["corner_tl"].Text
        HotCornerTR := C["corner_tr"].Text
        HotCornerBL := C["corner_bl"].Text
        HotCornerBR := C["corner_br"].Text

        ActiveBorderEnabled := C["border"].Value
        AlwaysOnBottomEnabled := C["bottom"].Value
        TextExpanderEnabled := C["expander"].Value
        PlainPasteEnabled := C["plainpaste"].Value
        SmartCapsEnabled := C["smartcaps"].Value
        SmartCapsAction := C["smartcaps_act"].Text
        ParallaxEnabled := C["parallax"].Value

        uiOldSmartTb := SmartTaskbarEnabled
        SmartTaskbarEnabled := C["smart_tb"].Value

        EP_Style       := C["epStyle"].Text
        EP_IconSize    := C["epIconSize"].Text

        BorderColor := Trim(C["bordercolor"].Value)
        if !(BorderColor = "auto" || BorderColor ~= "^[0-9A-Fa-f]{6}$")
            BorderColor := "auto"

        ; No validation beyond trimming: MC_ParseExeList already rejects paths
        ; and normalises separators, and an empty list is a legitimate value
        ; (it means "trust the audio API alone").
        MediaFallbackList := Trim(C["mediafallback"].Value)

        GravityCloseEnabled := C["gravityclose"].Value
        DEBUG := C["debuglog"].Value

        uiAutoStart := C["auto"].Value
    } catch as e {
        WriteLog("ApplyUi: could not read a control - " e.Message)
    }

    ; Separate try of its own, for the same reason the block above is separated
    ; from the block below: one unreadable Edit must not cost every OTHER number
    ; its value. TuneApplyUi already skips a control it cannot read.
    try TuneApplyUi(writeBack)

    ; Everything below is applying state, not reading controls, and each step is
    ; independent - so one failure cannot silently skip the rest or the save.
    if (uiAutoStart != "" && uiAutoStart != IsAutoStart())
        try SetAutoStart(uiAutoStart)

    ; Switched off: hand the taskbar back the auto-hide state it had at startup.
    if (uiOldSmartTb != "" && uiOldSmartTb && !SmartTaskbarEnabled && OriginalTaskbarState != -1)
        try SetTaskbarAutoHide(OriginalTaskbarState & 1)

    ; Switched off: release whatever the feature is still holding, through the same
    ; functions the hotkeys and Bye() use.
    if (uiOldGhost && !ProximityGhostEnabled) {
        for hwnd, info in GhostWindows.Clone()
            try UnGhostWindow(hwnd)
        SetTimer(GhostMonitorStep, 0)
        SyncMediaCore()
    }
    if (uiOldBottom && !AlwaysOnBottomEnabled) {
        for hwnd, info in BottomWindows.Clone()
            try RestoreFromBottom(hwnd)
    }
    if (uiOldPip && !LivePipEnabled) {
        for src, pip in PipGuis.Clone()
            try ClosePiP(src)
    }
    if (uiOldFocusDepth && !FocusDepthEnabled)
        try RestoreFocusDepth()

    try UpdateKeyboardHook()         ; start/stop the keyboard hook to match the boxes
    try SyncTray()
    try SyncBreathingTimers()        ; start/stop the polling to match the checkbox
    try SyncSmartTaskbar()
    try SyncDimmerTimer()
    try SyncHotCornersTimer()
    try SyncCursorWrapTimer()
    try SyncActiveBorderTimer()
    try SyncTextExpander()
    try SyncShakeDetector()
    try SyncCursorFxTimer()
    try SyncTaskbarUiTimer()
    try SyncMediaCore()
    try SaveSettings()
}

NumOr(text, fallback) => IsNumber(text) ? Number(text) : fallback

RestartExplorer() {
    RunWait('taskkill /f /im explorer.exe', , "Hide")
    Run "explorer.exe"
}

ShowHotkeys() {
    MsgBox(
    "GLOBAL WINDOWS:`n"
  . "Win+Ctrl+W`tSettings menu`n"
  . "Win+Ctrl+T`tAlways on top (active window)`n"
  . "Win+Ctrl+B`tAlways on bottom (Desktop Widget)`n"
  . "Win+Ctrl+G`tProximity Ghost Window mode`n"
  . "Win+Ctrl+P`tLive Window Picture-in-Picture`n"
  . "Win+Ctrl+R`tRoll up / unroll the active window`n"
  . "Win+Ctrl+H`tMinimize the active window to the tray`n"
  . "Win+Ctrl+E`tBreathing windows on / off`n"
  . "Win+Ctrl+F`tFocus mode (cinema) on / off`n"
  . "Win+Ctrl+S`tMagnetic snapping on / off`n"
  . "Win+Ctrl+M`tPosition memory on / off`n"
  . "Win+Ctrl+Esc`tBoss key - hide everything and mute`n"
  . "Win+Ctrl+Wheel`tTransparency of the active window`n"
  . "Alt+F4`t`tClose with the gravity-drop animation`n`n"
  . "SYSTEM & MEDIA:`n"
  . "Ctrl+Win+V`tPaste as plain text`n"
  . "Double-tap Alt`tGlobal Mic Kill-Switch`n"
  . "Double-tap Ctrl`tQuick Spotlight Launcher`n`n"
  . "WHEN A FEATURE IS ENABLED:`n"
  . "Alt+LeftDrag`tMove a window from anywhere`n"
  . "Alt+RightDrag`tResize a window from the nearest edge`n"
  . "Middle-click`tTitle bar: Close or Roll-up`n"
  . "Middle-click`tHold to Universal Grab & Pan`n"
  . "Ctrl+G`t`tIn a Save/Open dialog: jump to the last Explorer folder`n"
  . "Spacebar`t`tIn Explorer: Quick Look preview`n"
  . "@@date / @@time`tText Expander snippets`n"
  . "CapsLock`ttap = Escape or Backspace, hold = Caps`n`n"
  . "OVER THE TASKBAR:`n"
  . "Wheel`t`tVolume up / down`n"
  . "Middle-click`tMute`n`n"
  . "HOTKEYS.md explains conflicts and how to change these.",
    "Window Tweaks - Hotkeys", "Iconi")
}

OpenLog() {
    global LOG_FILE
    FlushLog()                    ; the tail is in RAM until something flushes it
    if FileExist(LOG_FILE)
        Run 'notepad.exe "' LOG_FILE '"'
    else
        Notify("No log yet")
}

OpenDoc(name) {
    p := A_ScriptDir "\" name
    if FileExist(p)
        Run 'notepad.exe "' p '"'
    else
        Notify(name " not found")
}

ForgetPositions() {
    global POS_FILE, PendingPositions
    try {
        SetTimer(WritePositions, 0)
        PendingPositions.Clear()     ; or the buffered ones rewrite the file
        if FileExist(POS_FILE)
            FileDelete(POS_FILE)
        Notify("Saved window positions cleared")
    }
}

; =========================================================== Hotkeys ===========================================================
#^w::ShowWin()
#^s::ToggleSnap()
#^m::ToggleMemory()
#^f::ToggleFocusMode()
#^h::HideToTray()
#^r::ToggleRollUp()
#^e::ToggleBreathing()
#^Esc::ToggleBossKey()

#HotIf AlwaysOnBottomEnabled
#^b::ToggleAlwaysOnBottom()
#HotIf

#HotIf ProximityGhostEnabled
#^g::ToggleGhostMode()
#HotIf
#^WheelUp::ChangeTransparency(1)
#^WheelDown::ChangeTransparency(-1)

#HotIf LivePipEnabled
#^p::TogglePiP()
#HotIf

; ----- Window layout ---------------------------------------------------------
; Win+Ctrl+<key> acts on the active window. Win+Ctrl+Shift+<key> toggles a
; feature on or off - see the second-tier block below.
;
; Deliberately unbound: Win+Ctrl+Left/Right (Windows virtual-desktop switching)
; and Win+Left/Right, which already tile to the left and right halves. Also
; avoided across both tiers: Win+Ctrl+D/Q/C/N/O/Enter/Space and Win+Ctrl+Shift+B,
; all of which Windows 11 claims for the desktop switcher, Quick Assist, colour
; filters, Narrator, the on-screen keyboard and the graphics-driver reset.
#^k::CenterWindow()
#^u::CycleWindowSize()
#^j::MoveToNextMonitor()
#^z::UndoLayout()

; 3x3 grid tiling, laid out like the numeric keypad: corners are quarters, 8/2
; are the top and bottom halves, 4/6 the left and right halves, 5 a centred half.
; Both names of every keypad key are bound, because with NumLock OFF the keypad
; sends NumpadHome/NumpadUp/... instead of Numpad7/Numpad8/... - binding only the
; digit names would leave the whole gesture dead for anyone who keeps NumLock off.
#^Numpad7::TileWindow(7)
#^NumpadHome::TileWindow(7)
#^Numpad8::TileWindow(8)
#^NumpadUp::TileWindow(8)
#^Numpad9::TileWindow(9)
#^NumpadPgUp::TileWindow(9)
#^Numpad4::TileWindow(4)
#^NumpadLeft::TileWindow(4)
#^Numpad5::TileWindow(5)
#^NumpadClear::TileWindow(5)
#^Numpad6::TileWindow(6)
#^NumpadRight::TileWindow(6)
#^Numpad1::TileWindow(1)
#^NumpadEnd::TileWindow(1)
#^Numpad2::TileWindow(2)
#^NumpadDown::TileWindow(2)
#^Numpad3::TileWindow(3)
#^NumpadPgDn::TileWindow(3)
#^Numpad0::ToggleMaximize()
#^NumpadIns::ToggleMaximize()

; Laptop aliases for the two halves that have no Windows equivalent. The arrow
; keys are only free vertically - Win+Ctrl+Left/Right switch virtual desktops.
#^Up::TileWindow(8)
#^Down::TileWindow(2)

; ----- Utility ---------------------------------------------------------------
#^x::ResetTransparency()
#^y::RestoreAllWindows()
#^+r::Reload()
#^+q::ExitApp()

; ----- Keyboard access to gesture-only features ------------------------------
; Each of these already has a gesture; the gesture stays. A double-tap has to be
; disambiguated from two ordinary shortcuts (see IsDoublePress below), so an
; unambiguous key for the same action is worth having.
#HotIf SpotlightEnabled
#^l::ToggleSpotlight()
#HotIf

#HotIf MicKillSwitchEnabled
#^a:: {
    state := ToggleDefaultMic()
    if (state != -1)
        ShowMicOSD(state)
}
#HotIf

#HotIf QuickLookEnabled && WinActive("ahk_class CabinetWClass")
#^i::ToggleQuickLook()
#HotIf

; ----- Feature toggles: Win+Ctrl+Shift+<key> ---------------------------------
; These seven flags already persist to settings.ini; before this the only way to
; change one was to open the settings window.
#^+c::ToggleHotCorners()
#^+a::ToggleActiveBorder()
#^+w::ToggleCursorWrap()
#^+d::ToggleDimmer()
#^+t::ToggleSmartTaskbar()
#^+g::ToggleMagneticGroups()
#^+p::ToggleGrabPan()

; Helper function for modifier key double presses (ignores auto-repeat)
IsDoublePress(Timeout := 400) {
    global LastNonModifierKeyTime
    static lastTriggers := Map()

    if !(A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < Timeout)
        return false

    ; "Was the previous hotkey this same one, recently" is NOT enough on its own.
    ; ~LCtrl up and ~LAlt up fire on every release of those keys, and an ordinary
    ; shortcut like ^c is not a hotkey here - so it never becomes A_PriorHotkey.
    ; Ctrl+C followed by Ctrl+V inside the timeout therefore produced two
    ; consecutive ~LCtrl up firings and looked exactly like a deliberate
    ; double-tap: copy-then-paste opened the Spotlight launcher, and two Alt
    ; shortcuts in a row muted the microphone system-wide.
    ;
    ; A real double-tap has nothing pressed between the two releases. If a
    ; non-modifier key was pressed more recently than the previous release, this
    ; was two shortcuts, not a gesture.
    if (A_TickCount - LastNonModifierKeyTime < A_TimeSincePriorHotkey)
        return false

    last := lastTriggers.Has(A_ThisHotkey) ? lastTriggers[A_ThisHotkey] : 0
    if (A_TickCount - last < Timeout) {
        ; Prevent triple-press from triggering twice
        lastTriggers.Delete(A_ThisHotkey)
        return false
    }
    lastTriggers[A_ThisHotkey] := A_TickCount
    return true
}

#HotIf MicKillSwitchEnabled
~LAlt up:: {
    if IsDoublePress() {
        state := ToggleDefaultMic()
        if (state != -1)
            ShowMicOSD(state)
    }
}
#HotIf

#HotIf SpotlightEnabled
~LCtrl up:: {
    if IsDoublePress()
        ToggleSpotlight()
}
~RCtrl up:: {
    if IsDoublePress()
        ToggleSpotlight()
}
#HotIf

IsSpotlightActive() {
    global SpotlightGui
    return SpotlightGui && WinActive("ahk_id " SpotlightGui.Hwnd)
}

#HotIf IsSpotlightActive()
Enter::SpotlightExecute()
Escape::ToggleSpotlight()
#HotIf

#HotIf QuickLookEnabled && WinActive("ahk_class CabinetWClass") && !IsTypingInExplorer()
Space:: {
    if !ToggleQuickLook()
        Send "{Space}"
}
#HotIf

#HotIf QuickLookEnabled && QuickLookGui && WinActive("ahk_id " QuickLookGui.Hwnd)
Space::CloseQuickLook()
Escape::CloseQuickLook()
#HotIf

IsMouseOverTaskbar() {
    MouseGetPos(,, &hwnd)
    if !hwnd
        return false
    ; Runs inside a #HotIf, so it is evaluated on every wheel and middle-click.
    ; A window destroyed between MouseGetPos and here would otherwise throw
    ; from inside hotkey-criteria evaluation. 'cls' avoids the built-in Class.
    cls := ""
    try cls := WinGetClass(hwnd)
    return (cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
}

#HotIf TaskbarScrollEnabled && IsMouseOverTaskbar()
WheelUp:: {
    if PremiumVolumeOSDEnabled
        ChangeVolumeOSD(1)
    else
        Send("{Volume_Up}")
}
WheelDown:: {
    if PremiumVolumeOSDEnabled
        ChangeVolumeOSD(-1)
    else
        Send("{Volume_Down}")
}
MButton:: {
    if PremiumVolumeOSDEnabled
        ToggleMuteOSD()
    else
        Send("{Volume_Mute}")
}
#HotIf

#HotIf (ElasticScrollEnabled || MotionBlurScrollEnabled) && !IsMouseOverTaskbar()
~WheelUp::
~WheelDown:: {
    MouseGetPos(,, &hwnd)
    global DragHwnd
    if (DragHwnd == hwnd)
        return
        
    dir := A_ThisHotkey = "~WheelUp" ? 1 : -1
    
    ; Order matters: this runs on EVERY wheel notch anywhere in the system.
    ; IsRestorable is ~6 cross-process queries plus a DWM call; WinGetMinMax is
    ; 0.28 us. Ask the cheap question first and most notches never reach the
    ; expensive one. Both features want the same two facts, so they are gathered
    ; once instead of IsRestorable being paid twice.
    if (!DllCall("IsWindow", "ptr", hwnd))
        return
    try {
        if (WinGetMinMax(hwnd) != 0)
            return
        WinGetPos(&bx, &by, &bw, &bh, hwnd)
    } catch
        return
    if (!IsRestorable(hwnd))
        return

    if (MotionBlurScrollEnabled)
        TriggerMotionBlur(hwnd, dir)

    if (!ElasticScrollEnabled)
        return
    ; A full-screen window has nowhere to lean to, and leaning it would expose
    ; the desktop behind it.
    if (bw >= A_ScreenWidth && bh >= A_ScreenHeight)
        return
    ElasticScroll(hwnd, dir, bx, by)
}
#HotIf

#HotIf !IsMouseOverTaskbar()
~LButton:: {
    global TextMagnifierEnabled, RippleClickEnabled, ElasticDragEnabled
    
    MouseGetPos(&startX, &startY)

    if (RippleClickEnabled) {
        SpawnRipple(startX, startY)
    }

    if (TextMagnifierEnabled) {
        global MagActive, MagStartX, MagStartY
        if (A_Cursor == "IBeam") {
            MagStartX := startX, MagStartY := startY
            MagActive := false
            SetTimer(CheckMagDrag, 16)
        }
    }
    
    if (ElasticDragEnabled) {
        global DragTrailStartX := startX, DragTrailStartY := startY
        global DragTrailActive := false
        SetTimer(CheckElasticDrag, 16)
    }
}
#HotIf

IsFileDialog(hwnd) {
    if !hwnd
        return false
    ; Evaluated inside a #HotIf, so this runs on the hotkey-criteria thread for
    ; every Ctrl+G press. A window that closed a moment ago must not throw from
    ; in there - same reasoning as IsMouseOverTaskbar.
    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls != "#32770")
        return false
    try {
        ControlGetHwnd("Edit1", hwnd)
        return true
    }
    return false
}

GetActiveExplorerPath() {
    try {
        shell := ComObject("Shell.Application")
        hwnd := WinExist("ahk_class CabinetWClass")
        if !hwnd
            return ""
            
        for window in shell.Windows {
            if (window.HWND == hwnd)
                return window.Document.Folder.Self.Path
        }
    }
    return ""
}

#HotIf QuickFolderJumpEnabled && IsFileDialog(WinExist("A"))
^g:: {
    hwnd := WinExist("A")
    path := GetActiveExplorerPath()
    if (path == "") {
        Notify("No open Explorer folder found.")
        return
    }
    
    try {
        oldText := ControlGetText("Edit1", hwnd)
        ControlFocus("Edit1", hwnd)
        ControlSetText(path, "Edit1", hwnd)
        Sleep(50)
        ControlSend("{Enter}", "Edit1", hwnd)
        Sleep(150)
        if (oldText != "")
            ControlSetText(oldText, "Edit1", hwnd)
    }
}
#HotIf

#HotIf PlainPasteEnabled
^#v:: {
    if (A_Clipboard == "")
        return
    ClipSaved := ClipboardAll()
    A_Clipboard := A_Clipboard
    ; ClipWait, not a fixed spin: the round-trip through the clipboard is not
    ; instant, and a busy-wait would block every timer in the process meanwhile.
    ClipWait(1, false)
    Send("^v")
    Sleep(120)
    A_Clipboard := ClipSaved
    ClipSaved := ""
}
#HotIf

#HotIf SmartCapsEnabled
*CapsLock:: {
    global SmartCapsAction
    if !KeyWait("CapsLock", "T0.4") {
        SetCapsLockState(!GetKeyState("CapsLock", "T"))
        KeyWait("CapsLock")
    } else {
        if (SmartCapsAction == "Backspace")
            Send("{Blind}{Backspace}")
        else
            Send("{Blind}{Esc}")
    }
}
#HotIf

#HotIf AltDragEnabled
!LButton::AltDragMove()
!RButton::AltDragResize()
#HotIf

#HotIf (GrabPanEnabled || RollUpEnabled || MiddleClickCloseEnabled) && !IsMouseOverTaskbar()
*MButton:: {
    ; Guard against a second thread starting another pan loop over the same
    ; window: both would Send wheel events and fight over StartX/StartY.
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&sX, &sY, &hwnd, &ctrl, 2)
    if !hwnd
        return


    ; The title-bar probe costs a cross-process SendMessageTimeout with a 50 ms
    ; ceiling, and it is only ever used to decide between Close and Roll-Up. With
    ; neither of those on - grab & pan alone - it answered a question nobody
    ; asked, on every middle click in the system.
    res := 0
    if (RollUpEnabled || MiddleClickCloseEnabled) {
        lp := ((sY & 0xFFFF) << 16) | (sX & 0xFFFF)
        DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x84, "ptr", 0, "ptr", lp, "uint", 2, "uint", 50, "ptr*", &res)
    }
    
    if (!GrabPanEnabled) {
        if (res == 2) {
            KeyWait("MButton")
            if (MiddleClickCloseEnabled) {
                try WinClose("ahk_id " hwnd)
                return
            }
            if (RollUpEnabled) {
                ToggleRollUp(hwnd)
                return
            }
        }
        Send("{Blind}{MButton Down}")
        KeyWait("MButton")
        Send("{Blind}{MButton Up}")
        return
    }
    
    StartX := sX
    StartY := sY
    dragged := false
    threshold := 3
    step := 25

    busy := true
    try {
        Loop {
            if !GetKeyState("MButton", "P")
                break

            MouseGetPos(&CurX, &CurY)
            dx := CurX - StartX
            dy := CurY - StartY

            if (!dragged && (Abs(dx) > threshold || Abs(dy) > threshold))
                dragged := true

            if (dragged) {
                if (Abs(dy) >= step) {
                    count := Abs(dy) // step
                    if (dy < 0)
                        Send("{WheelDown " count "}")
                    else
                        Send("{WheelUp " count "}")
                    StartY := StartY + (dy < 0 ? -count * step : count * step)
                }

                if (Abs(dx) >= step) {
                    count := Abs(dx) // step
                    if (dx < 0)
                        Send("{WheelRight " count "}")
                    else
                        Send("{WheelLeft " count "}")
                    StartX := StartX + (dx < 0 ? -count * step : count * step)
                }
            }
            Sleep(10)
        }
    }
    busy := false

    if (!dragged) {
        if (res == 2) {
            if (MiddleClickCloseEnabled) {
                try WinClose("ahk_id " hwnd)
                return
            }
            if (RollUpEnabled) {
                ToggleRollUp(hwnd)
                return
            }
        }
        Send("{Blind}{MButton}")
    }
}
#HotIf

; =========================================================== Window layout ===========================================================
; Keyboard positioning. Every function in this section is a ONE-SHOT producer:
; it queues through RS_SetPos and returns. The animation scheduler stops its
; timer as soon as nothing is animating, so each of these MUST call RS_Commit()
; itself or the queued move is simply never applied and the window does not budge.

global LayoutUndo   := Map()      ; hwnd -> {x, y, w, h}, WinGetPos space
global SizeCycleIdx := Map()      ; hwnd -> {idx, l, t, r, b} last applied by CycleWindowSize

global SIZE_CYCLE := [0.50, 0.75, 0.90]

; Which cached monitor contains (px, py)? A 1-based index into
; ScreenMetrics().mons, falling back to 1 for a point off every screen.
MonitorIndexAt(px, py) {
    g := ScreenMetrics()
    for i, m in g.mons {
        if (px >= m.l && px < m.r && py >= m.t && py < m.b)
            return i
    }
    ; Monitor 1 is NOT the primary - the enumeration order is whatever the OS
    ; hands back, and on plenty of setups the primary is 2 or 3. For a point that
    ; is off every screen the primary is the only defensible answer.
    try return MonitorGetPrimary()
    return 1
}

; Which monitor should a transient overlay appear on? The one holding the
; pointer, because that is where the user is looking, and the primary when the
; pointer is nowhere. Shared by both OSDs so they cannot disagree.
CursorMonitorIndex() {
    MouseGetPos(&mx, &my)
    return MonitorIndexAt(mx, my)
}

; Work area (monitor minus taskbar) of monitor `idx`.
; The monitor RECTS come from the ScreenMetrics cache, but the work area is read
; live every time on purpose: it changes whenever the taskbar auto-hides, and
; that raises no WM_DISPLAYCHANGE - so a cached copy would be stale exactly when
; Smart Auto-Hide is on. This is a hotkey path, not a per-frame one, and
; MonitorGetWorkArea costs ~3 us.
WorkAreaOf(idx, &wl, &wt, &wr, &wb) {
    try {
        MonitorGetWorkArea(idx, &wl, &wt, &wr, &wb)
        return true
    }
    try {
        MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
        return true
    }
    return false
}

WorkAreaAt(px, py, &wl, &wt, &wr, &wb) {
    return WorkAreaOf(MonitorIndexAt(px, py), &wl, &wt, &wr, &wb)
}

; Un-maximize before laying a window out, and do it BEFORE IsRestorable is
; consulted: that predicate goes through IsSnappable, which rejects maximized
; windows outright, so without this every layout key would be silently dead on
; exactly the windows most likely to need one. Windows' own maximize also wins
; over an explicit rect, so tiling one without restoring it first does nothing.
UnmaximizeFirst(hwnd) {
    try {
        if (WinGetMinMax(hwnd) != 1)        ; 1 = maximized
            return
        WinRestore(hwnd)
        ; Sleep, not a spin: the restore is carried out by the target window's
        ; own thread and everything downstream measures the rect it settles into.
        ; A busy wait would block every timer in this process, frame loop
        ; included - the same mistake that used to freeze SnapWindow.
        Sleep(60)
    }
}

; Move a window so its VISIBLE frame occupies (tx, ty, tw, th). Pass -1 for
; tw/th to keep the current size. Returns false if the window went away.
;
; Three things make this correct, and every one of them has cost debugging time
; somewhere else in this file:
;   - the DWM frame rect and the WinMove rect differ by the invisible resize
;     border, so the target has to be converted back the way SnapWindow does;
;   - a Glide or Bounce still registered on this window writes RS_SetPos at the
;     same priority every frame and would overwrite this one silently;
;   - a rolled-up window is clipped by a region measured against its old width,
;     so resizing it without clearing that region leaves a torn-looking window.
ApplyLayout(hwnd, tx, ty, tw := -1, th := -1) {
    global RolledUpWindows
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return false
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY)
        return false
    try WinGetPos(, , &winW, &winH, hwnd)
    catch
        return false
    if (winW = "" || winH = "")
        return false

    CancelAnimation("Glide_" hwnd)
    CancelAnimation("Bounce_" hwnd)
    CancelAnimation("RollUp_" hwnd)

    if RolledUpWindows.Has(hwnd) {
        RolledUpWindows.Delete(hwnd)
        RS_SetRegion(hwnd, "", RS_PRI_USER)
    }

    RememberLayout(hwnd, winX, winY, winW, winH)

    ; Frame space -> WinMove space.
    destX := winX + (tx - fL)
    destY := winY + (ty - fT)
    destW := (tw < 0) ? -1 : tw + (winW - (fR - fL))
    destH := (th < 0) ? -1 : th + (winH - (fB - fT))

    RS_SetPos(hwnd, destX, destY, destW, destH, RS_PRI_USER)
    RS_Commit()                    ; one-shot producer: nothing else will flush
    return true
}

RememberLayout(hwnd, x, y, w, h) {
    global LayoutUndo
    LayoutUndo[hwnd] := {x: x, y: y, w: w, h: h}
}

; One level of undo per window - enough to take back a mis-aimed tile, which is
; the only thing this is for. A stack would need pruning rules of its own.
UndoLayout() {
    global LayoutUndo, SizeCycleIdx
    hwnd := WinExist("A")
    if !hwnd || !LayoutUndo.Has(hwnd) {
        Notify("Nothing to undo")
        return
    }
    r := LayoutUndo[hwnd]
    LayoutUndo.Delete(hwnd)
    if SizeCycleIdx.Has(hwnd)
        SizeCycleIdx.Delete(hwnd)
    if !DllCall("IsWindow", "ptr", hwnd)
        return

    CancelAnimation("Glide_" hwnd)
    CancelAnimation("Bounce_" hwnd)
    ; Already in WinMove space - this is what WinGetPos reported before the move,
    ; so it must NOT go through the frame conversion a second time.
    RS_SetPos(hwnd, r.x, r.y, r.w, r.h, RS_PRI_USER)
    RS_Commit()
    Notify("Layout undone")
}

CenterWindow() {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return
    fw := fR - fL, fh := fB - fT
    if !WorkAreaAt(fL + fw // 2, fT + fh // 2, &wl, &wt, &wr, &wb)
        return
    ApplyLayout(hwnd, wl + ((wr - wl) - fw) // 2, wt + ((wb - wt) - fh) // 2)
}

; 50% -> 75% -> 90% of the work area, centred, then back to 50%.
CycleWindowSize() {
    global SizeCycleIdx, SIZE_CYCLE
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return

    ; Restart the cycle whenever the window is not where this function last put
    ; it. Without the check, dragging a window between two presses made the next
    ; press jump to a size with no relationship to what was on screen.
    idx := 0
    if SizeCycleIdx.Has(hwnd) {
        st := SizeCycleIdx[hwnd]
        if (Abs(st.l - fL) <= 2 && Abs(st.t - fT) <= 2
         && Abs(st.r - fR) <= 2 && Abs(st.b - fB) <= 2)
            idx := st.idx
    }
    idx := Mod(idx, SIZE_CYCLE.Length) + 1

    if !WorkAreaAt((fL + fR) // 2, (fT + fB) // 2, &wl, &wt, &wr, &wb)
        return
    frac := SIZE_CYCLE[idx]
    tw := Round((wr - wl) * frac), th := Round((wb - wt) * frac)
    tx := wl + ((wr - wl) - tw) // 2, ty := wt + ((wb - wt) - th) // 2

    if !ApplyLayout(hwnd, tx, ty, tw, th)
        return
    SizeCycleIdx[hwnd] := {idx: idx, l: tx, t: ty, r: tx + tw, b: ty + th}
    Notify("Window size: " Round(frac * 100) "%")
}

; The digit is the position of the key on the numeric keypad, which is the whole
; point of the gesture: 7 is the top-left quarter, 2 the bottom half, and so on.
TileWindow(cell) {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return
    if !WorkAreaAt((fL + fR) // 2, (fT + fB) // 2, &wl, &wt, &wr, &wb)
        return

    aw := wr - wl, ah := wb - wt
    hw := aw // 2, hh := ah // 2
    ; The far half takes the remainder, so an odd work-area width leaves no
    ; one-pixel seam between two tiled windows.
    rw := aw - hw, rh := ah - hh

    switch cell {
        case 7: tx := wl,      ty := wt,      tw := hw, th := hh
        case 8: tx := wl,      ty := wt,      tw := aw, th := hh
        case 9: tx := wl + hw, ty := wt,      tw := rw, th := hh
        case 4: tx := wl,      ty := wt,      tw := hw, th := ah
        case 5: tx := wl + rw // 2, ty := wt + rh // 2, tw := hw, th := hh
        case 6: tx := wl + hw, ty := wt,      tw := rw, th := ah
        case 1: tx := wl,      ty := wt + hh, tw := hw, th := rh
        case 2: tx := wl,      ty := wt + hh, tw := aw, th := rh
        case 3: tx := wl + hw, ty := wt + hh, tw := rw, th := rh
        default: return
    }
    ApplyLayout(hwnd, tx, ty, tw, th)
}

; Push the window to the next monitor, keeping its position and size relative to
; the work area - a half-width window stays half-width on a display of a
; different resolution instead of keeping its pixel count.
MoveToNextMonitor() {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    g := ScreenMetrics()
    if (g.mons.Length < 2) {
        Notify("Only one monitor")
        return
    }
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return

    fw := fR - fL, fh := fB - fT
    cur := MonitorIndexAt(fL + fw // 2, fT + fh // 2)
    nxt := Mod(cur, g.mons.Length) + 1

    if !WorkAreaOf(cur, &sl, &st, &sr, &sb)
        return
    if !WorkAreaOf(nxt, &dl, &dt, &dr, &db)
        return
    sw := sr - sl, sh := sb - st
    dw := dr - dl, dh := db - dt
    if (sw <= 0 || sh <= 0)
        return

    tw := Round(fw * dw / sw), th := Round(fh * dh / sh)
    tx := dl + Round((fL - sl) * dw / sw)
    ty := dt + Round((fT - st) * dh / sh)

    ; Clamp last, so rounding can never push it off the destination work area.
    if (tw > dw)
        tw := dw
    if (th > dh)
        th := dh
    if (tx + tw > dr)
        tx := dr - tw
    if (ty + th > db)
        ty := db - th
    if (tx < dl)
        tx := dl
    if (ty < dt)
        ty := dt

    if ApplyLayout(hwnd, tx, ty, tw, th)
        Notify("Moved to monitor " nxt)
}

; IsRestorable is deliberately NOT the gate here: it goes through IsSnappable,
; which rejects maximized windows outright, so it can never see the one window
; this is meant to un-maximize. WinMaximize/WinRestore also stay outside the
; render pipeline because RS_* has no concept of a maximize state - it queues
; explicit rects, and the two would fight over the same window.
ToggleMaximize() {
    hwnd := WinExist("A")
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return
        if !(WinGetStyle(hwnd) & 0x10000)          ; WS_MAXIMIZEBOX
            return
        CancelAnimation("Glide_" hwnd)
        CancelAnimation("Bounce_" hwnd)
        if (WinGetMinMax(hwnd) = 1)
            WinRestore(hwnd)
        else
            WinMaximize(hwnd)
    }
}

global CustomTrans := Map()

global PendingTransMsg := ""

ChangeTransparency(dir) {
    global CustomTrans, PendingTransMsg
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return

    current := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

    step := Tune("transStep")
    if (dir > 0)
        current += step
    else
        current -= step

    ; The floor is a real one: a window at alpha 0 is invisible, focused and
    ; still clickable, and the only way back is Win+Ctrl+X on a window you can
    ; no longer see.
    floor := TuneAlpha("transMin")
    if (current > 255)
        current := 255
    if (current < floor)
        current := floor

    CustomTrans[hwnd] := current

    global BreathingEnabled, WinCurrentAlpha, WinTargetAlpha
    if BreathingEnabled {
        WinTargetAlpha[hwnd] := current
        WinCurrentAlpha[hwnd] := current
    }

    if (current == 255) {
        RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
        CustomTrans.Delete(hwnd)
        PendingTransMsg := "Transparency: OFF"
    } else {
        RS_SetAlpha(hwnd, current, RS_PRI_USER)
        PendingTransMsg := "Opacity: " Round((current / 255) * 100) "%"
    }
    ; One-shot producer: nothing else is animating, so nothing else will flush.
    RS_Commit()
    ; One tray tip per gesture, not one per wheel notch - a single scroll used to
    ; queue a dozen notifications into the Action Center.
    SetTimer(FlushTransNotify, -400)
}

FlushTransNotify() {
    global PendingTransMsg
    if (PendingTransMsg != "") {
        Notify(PendingTransMsg)
        PendingTransMsg := ""
    }
}

; Back to fully opaque in one press. Mirrors the current == 255 branch of
; ChangeTransparency, including handing the window back to breathing at full
; alpha - leaving WinTargetAlpha at the old value made breathing fade it
; straight back down again.
ResetTransparency() {
    global CustomTrans, BreathingEnabled, WinCurrentAlpha, WinTargetAlpha
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
    if CustomTrans.Has(hwnd)
        CustomTrans.Delete(hwnd)
    if BreathingEnabled {
        WinCurrentAlpha[hwnd] := 255
        WinTargetAlpha[hwnd] := 255
    }
    RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
    RS_Commit()                    ; one-shot producer: nothing else will flush
    Notify("Transparency: OFF")
}

; The panic key. Every state this app can put a window into that is not obvious
; from looking at the screen - rolled up to a title bar, ghosted click-through,
; hidden into the tray - is undone here in one press.
RestoreAllWindows() {
    global RolledUpWindows, GhostWindows, TrayIcons
    n := 0

    ; Iterate clones throughout: ToggleRollUp, UnGhostWindow and RestoreFromTray
    ; each delete from the very Map being walked, which shifts the remainder
    ; under the enumerator and silently skips the next entry.
    for hwnd in RolledUpWindows.Clone() {
        if DllCall("IsWindow", "ptr", hwnd) {
            ToggleRollUp(hwnd)
            n += 1
        } else {
            RolledUpWindows.Delete(hwnd)
        }
    }

    for hwnd in GhostWindows.Clone() {
        UnGhostWindow(hwnd)
        n += 1
    }
    if (GhostWindows.Count == 0)
        SetTimer(GhostMonitorStep, 0)

    for hwnd in TrayIcons.Clone() {
        RestoreFromTray(hwnd)
        n += 1
    }

    ; Everything else this program can do to a window that the user cannot undo
    ; by hand. Each of these is reachable only through a hotkey that lives behind
    ; its feature flag, so switching the feature off strands the state with no way
    ; back - which is exactly what a panic key is for. Bye() already reverses all
    ; of them on exit; there was no reason for Win+Ctrl+Y not to.
    global BottomWindows, CustomTrans, PushedBackWindows, CurtainWindows, PrivacyBlurWindows
    for hwnd, info in BottomWindows.Clone() {
        try RestoreFromBottom(hwnd)
        n += 1
    }
    for hwnd, alpha in CustomTrans.Clone() {
        if DllCall("IsWindow", "ptr", hwnd) {
            try RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
            n += 1
        }
        CustomTrans.Delete(hwnd)
    }
    if PushedBackWindows.Count {
        n += PushedBackWindows.Count
        try RestoreFocusDepth()
    }
    if CurtainWindows.Count {
        n += CurtainWindows.Count
        try RestoreCurtain()
    }
    for hwnd, obj in PrivacyBlurWindows.Clone() {
        try RemovePrivacyBlur(hwnd)
        n += 1
    }
    try RestoreShatters()
    RS_Commit()                     ; one-shot producer: nothing else will flush

    SyncMediaCore()
    Notify(n ? "Restored " n " window(s)" : "Nothing to restore")
}

global RolledUpWindows := Map()

; Title-bar height: the difference between the window rect and the client rect.
; Falls back to 35 when the window reports something implausible (a custom-drawn
; frame, or a window that has already been clipped by a previous roll-up).
CaptionHeight(hwnd) {
    rc := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        return 35
    wh := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    if !DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        return 35
    caption := wh - NumGet(rc, 12, "int")
    return (caption < 30) ? 35 : caption
}

ToggleRollUp(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    animKey := "RollUp_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animRollMs")   ; duration in ms, not a frame count

    ; Measure once, guarded. The window can close between IsRestorable and here,
    ; and an uncaught WinGetPos in a hotkey thread is an error dialog.
    try
        WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    caption := CaptionHeight(hwnd)

    if RolledUpWindows.Has(hwnd) {
        origH := RolledUpWindows[hwnd]
        RolledUpWindows.Delete(hwnd)

        RollDownStep(dt, now) {
            if !DllCall("IsWindow", "ptr", hwnd)
                return false
            t := (now - start) / ms
            if (t >= 1) {
                RS_SetRegion(hwnd, "", RS_PRI_ANIM)
                return false
            }
            ease := 1 - (1 - t) * (1 - t)
            curH := caption + Round((origH - caption) * ease)
            RS_SetRegion(hwnd, "0-0 W" w " H" curH, RS_PRI_ANIM)
            return true
        }
        RegisterAnimation(animKey, RollDownStep)
    } else {
        RolledUpWindows[hwnd] := h

        RollUpStep(dt, now) {
            if !DllCall("IsWindow", "ptr", hwnd)
                return false
            t := (now - start) / ms
            if (t >= 1) {
                RS_SetRegion(hwnd, "0-0 W" w " H" caption, RS_PRI_ANIM)
                return false
            }
            ease := 1 - (1 - t) * (1 - t)
            curH := h - Round((h - caption) * ease)
            RS_SetRegion(hwnd, "0-0 W" w " H" curH, RS_PRI_ANIM)
            return true
        }
        RegisterAnimation(animKey, RollUpStep)
    }
}

AltDragMove() {
    ; #MaxThreadsPerHotkey 2 lets a second Alt+LButton interrupt this one. Two
    ; loops driving the same window from different origin snapshots fight each
    ; other, so only one may run at a time.
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return

    CancelAnimation("Glide_" hwnd)
    CancelAnimation("Bounce_" hwnd)
    CancelAnimation("GhostSlideIn_" hwnd)
    CancelAnimation("PortalScaleIn_" hwnd)
    CancelAnimation("Unroll_" hwnd)

    try {
        if WinGetMinMax(hwnd) != 0
            return
    } catch
        return

    if !WinActive(hwnd)
        try WinActivate(hwnd)

    global ParallaxEnabled, GlideEnabled, SnapEnabled
    global VelX, VelY, GLIDE_THROW, GLIDE_MAX
    vX := 0, vY := 0

    busy := true
    try {
        Loop {
            if !GetKeyState("LButton", "P") || !GetKeyState("Alt", "P")
                break
            if !DllCall("IsWindow", "ptr", hwnd)
                break
            MouseGetPos(&nX, &nY)
            if (nX != mX || nY != mY) {
                vX := nX - mX
                vY := nY - mY

                global GhostWindows
                if (ParallaxEnabled && !GhostWindows.Has(hwnd)) {
                    ; Same floor as the title-bar drag path in
                    ; SampleVelocityStep. It used to be a separate hard-coded
                    ; 100 here against 60 there, so an alt-drag and a title-bar
                    ; drag of the same window at the same speed did not match.
                    vel := Sqrt(vX**2 + vY**2)
                    RS_SetAlpha(hwnd, Clamp(255 - Round(vel * 3), TuneAlpha("parallaxMin"), 255), RS_PRI_DRAG)
                }

                try WinGetPos(&wX, &wY,,, hwnd)
                catch
                    break
                wX += vX
                wY += vY
                mX := nX
                mY := nY
                RS_SetPos(hwnd, wX, wY, -1, -1, RS_PRI_DRAG)
                RS_Commit()
            } else {
                vX := 0, vY := 0
                if (ParallaxEnabled && !GhostWindows.Has(hwnd))
                    RS_SetAlpha(hwnd, 255, RS_PRI_DRAG)
            }
            ; Sleep, not PreciseSleep: this yields, so the frame loop keeps
            ; running other animations instead of being starved by a spin.
            Sleep(10)
        }
    }
    busy := false

    if (ParallaxEnabled && !GhostWindows.Has(hwnd)) {
        RS_SetAlpha(hwnd, "Off", RS_PRI_DRAG)
        RS_Commit()
    }

    ; Hand off to the same release pipeline a title-bar drag uses. SnapWindow
    ; reads VelX/VelY to carry the throw forward and calls Glide itself, so
    ; there is nothing to schedule separately.
    VelX := vX, VelY := vY
    if (SnapEnabled) {
        if GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
            SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    } else if (GlideEnabled && (Abs(vX) > 5 || Abs(vY) > 5)) {
        ; Snap off, glide on: throw it by hand, then keep it on screen.
        try {
            WinGetPos(&gx, &gy, &gw, &gh, hwnd)
            tx := gx + Clamp(Round(vX * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
            ty := gy + Clamp(Round(vY * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
            gR := tx + gw, gB := ty + gh
            KeepOnScreen(hwnd, &tx, &ty, &gR, &gB, vX, vY)
            Glide(hwnd, gx, gy, tx, ty)
        }
    }
    RememberPosition(hwnd)
}

AltDragResize() {
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return

    try {
        WinGetPos(&wX, &wY, &wW, &wH, hwnd)
        if WinGetMinMax(hwnd) != 0
            return
    } catch
        return


    if !WinActive(hwnd)
        try WinActivate(hwnd)
        
    leftDist := mX - wX
    rightDist := (wX + wW) - mX
    topDist := mY - wY
    bottomDist := (wY + wH) - mY
    
    resizeMask := 0
    if (leftDist < wW / 3)
        resizeMask |= 1
    else if (rightDist < wW / 3)
        resizeMask |= 2
        
    if (topDist < wH / 3)
        resizeMask |= 4
    else if (bottomDist < wH / 3)
        resizeMask |= 8
        
    if (resizeMask == 0)
        resizeMask := 10
        
    busy := true
    try {
        Loop {
            if !GetKeyState("RButton", "P") || !GetKeyState("Alt", "P")
                break
            if !DllCall("IsWindow", "ptr", hwnd)
                break
            MouseGetPos(&nX, &nY)
            dX := nX - mX
            dY := nY - mY
            if (dX != 0 || dY != 0) {
                newX := wX, newY := wY, newW := wW, newH := wH
                if (resizeMask & 1) {
                    newX += dX, newW -= dX
                } else if (resizeMask & 2) {
                    newW += dX
                }
                if (resizeMask & 4) {
                    newY += dY, newH -= dY
                } else if (resizeMask & 8) {
                    newH += dY
                }
                if (newW < 100) {
                    if (resizeMask & 1)
                        newX -= (100 - newW)
                    newW := 100
                }
                if (newH < 100) {
                    if (resizeMask & 4)
                        newY -= (100 - newH)
                    newH := 100
                }
                wX := newX, wY := newY, wW := newW, wH := newH
                mX := nX, mY := nY
                RS_SetPos(hwnd, wX, wY, wW, wH, RS_PRI_DRAG)
                RS_Commit()
            }
            Sleep(10)
        }
    }
    busy := false
}

global TrayIcons := Map()
OnMessage(0x1000, TrayIconClick)

TrayIconClick(wParam, lParam, msg, hwnd) {
    if (lParam == 0x0202) {
        if TrayIcons.Has(wParam)
            RestoreFromTray(wParam)
    }
}

; WM_GETICON, asked politely. A plain SendMessage to a foreign window blocks
; until that window's thread pumps messages - so a hung ("Not Responding") app
; froze this whole process, every timer and every hotkey with it, forever.
; SMTO_ABORTIFHUNG plus a short timeout costs us a default icon at worst.
AskWindowIcon(hwnd) {
    static ICON_SMALL2 := 2, ICON_BIG := 1, GCLP_HICON := -14
    for which in [ICON_SMALL2, ICON_BIG] {
        res := 0
        ok := DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x7F
            , "ptr", which, "ptr", 0, "uint", 2, "uint", 100, "ptr*", &res)
        if (ok && res)
            return res
    }
    ; Class icon needs no cooperation from the target thread at all.
    try {
        if (A_PtrSize == 8)
            return DllCall("GetClassLongPtrW", "ptr", hwnd, "int", GCLP_HICON, "ptr")
        return DllCall("GetClassLongW", "ptr", hwnd, "int", GCLP_HICON, "uint")
    }
    return 0
}

HideToTray(hwnd := 0) {
    global TrayMinimizeEnabled
    if (!TrayMinimizeEnabled)
        return
        
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    title := "Hidden Window"
    try title := WinGetTitle(hwnd)
    if (title == "")
        title := "Hidden Window"

    hIcon := AskWindowIcon(hwnd)
    if !hIcon
        hIcon := DllCall("LoadIcon", "ptr", 0, "ptr", 32512, "ptr")


    cbSize := A_PtrSize == 8 ? 976 : 956
    nid := Buffer(cbSize, 0)
    NumPut("uint", cbSize, nid, 0)
    NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
    NumPut("uint", hwnd, nid, A_PtrSize == 8 ? 16 : 8)
    NumPut("uint", 0x7, nid, A_PtrSize == 8 ? 20 : 12)
    NumPut("uint", 0x1000, nid, A_PtrSize == 8 ? 24 : 16)
    NumPut("ptr", hIcon, nid, A_PtrSize == 8 ? 32 : 20)
    StrPut(SubStr(title, 1, 63), nid.Ptr + (A_PtrSize == 8 ? 40 : 24), "UTF-16")
    
    DllCall("shell32\Shell_NotifyIconW", "uint", 0, "ptr", nid)
    
    TrayIcons[hwnd] := true
    try WinHide(hwnd)
}

RestoreFromTray(hwnd) {
    if TrayIcons.Has(hwnd) {
        cbSize := A_PtrSize == 8 ? 976 : 956
        nid := Buffer(cbSize, 0)
        NumPut("uint", cbSize, nid, 0)
        NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
        NumPut("uint", hwnd, nid, A_PtrSize == 8 ? 16 : 8)
        
        DllCall("shell32\Shell_NotifyIconW", "uint", 2, "ptr", nid)
        TrayIcons.Delete(hwnd)
        
        try WinShow(hwnd)
        try WinActivate(hwnd)
    }
}

global BossKeyActive := false
global BossKeyWindows := []
global BossKeyMuteState := false

ToggleBossKey() {
    global BossKeyActive, BossKeyWindows, BossKeyMuteState, BossKeyEnabled
    ; Re-entry here is the most damaging of any toggle in the file: a second
    ; press during the WinGetList/WinHide loop would start a fresh BossKeyWindows
    ; array and the first pass's hidden windows would have no record left at all.
    static busy := false
    if busy
        return
    ; Only the HIDE direction is gated. Gating both meant that turning the feature
    ; off while it was active left every window on the desktop hidden with no way
    ; to get them back short of quitting - the one path that must always work is
    ; the one that undoes what we already did.
    if (!BossKeyEnabled && !BossKeyActive)
        return
    busy := true
    try {

    ; The privacy-blur overlays are owned by THIS process, so the ownPid filter
    ; below deliberately skips them - and WinHide on an owner does not hide owned
    ; windows either. They have to be hidden explicitly, or CheckPrivacyBlur sees
    ; "nothing is active", takes the inactive branch for every private window and
    ; paints an opaque rectangle onto the bare desktop at exactly the position and
    ; size of the window the user just hid.
    global PrivacyBlurWindows

    if (BossKeyActive) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        BossKeyWindows := []
        try SoundSetMute(BossKeyMuteState)
        BossKeyActive := false
    } else {
        for hwnd, obj in PrivacyBlurWindows {
            try DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)   ; SW_HIDE
            obj.active := false
        }
        try BossKeyMuteState := SoundGetMute()
        catch
            BossKeyMuteState := false
            
        try SoundSetMute(true)
        
        hwnds := WinGetList()
        BossKeyWindows := []
        ownPid := DllCall("GetCurrentProcessId", "uint")

        for hwnd in hwnds {
            cls := ""
            try cls := WinGetClass(hwnd)
            ; Shell_SecondaryTrayWnd is the taskbar on every non-primary monitor.
            ; Hiding it left those taskbars gone for good if this process died
            ; while Boss Key was active.
            if (cls == "Progman" || cls == "WorkerW"
                || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
                continue

            ; Our own overlays (active border, monitor dimmers, the OSDs, the
            ; focus vignette) are visible top-level windows too. Hiding them and
            ; showing them back later resurrects overlays whose feature may have
            ; been switched off in between.
            pid := 0
            try pid := WinGetPID(hwnd)
            if (pid == ownPid)
                continue

            BossKeyWindows.Push(hwnd)
            try WinHide(hwnd)
        }

        BossKeyActive := true
    }
    }
    busy := false
}

ToggleBreathing() {
    global BreathingEnabled, Win, C
    BreathingEnabled := !BreathingEnabled
    SyncTray(), SaveSettings()
    if (Win && WinExist("ahk_id " Win.Hwnd))
        try C["breath"].Value := BreathingEnabled
    Notify("Breathing windows " (BreathingEnabled ? "ON" : "OFF"))
    SyncBreathingTimers()
}

global WinTargetAlpha := Map()
global WinCurrentAlpha := Map()
global WinLastActive := Map()

; These used to be installed unconditionally and merely return early when the
; feature is off - but BreathingMonitor runs WinGetList() plus IsRestorable()
; (up to six window queries and a DWM call each) over every top-level window
; five times a second. That is exactly the polling the drag pipeline was
; designed to avoid, and it ran even for users who never turn breathing on.
SyncBreathingTimers() {
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive, CustomTrans
    if (BreathingEnabled) {
        now := QPC()
        hwnds := WinGetList()
        for hwnd in hwnds {
            if IsRestorable(hwnd) {
                baseAlpha := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255
                WinLastActive[hwnd] := now
                WinCurrentAlpha[hwnd] := baseAlpha
                WinTargetAlpha[hwnd] := baseAlpha
            }
        }
        SetTimer(BreathingMonitorStep, 200)
        SyncMediaCore()
        return
    }
    SetTimer(BreathingMonitorStep, 0)
    CancelAnimation("BreathingAnimator")
    ; Hand every window its opacity back before we stop animating it, or a
    ; window dimmed at the moment of the toggle stays dim for good. The commit
    ; is the point: cancelling the animator was the last thing that would ever
    ; have flushed these writes, so without it they were never applied.
    for hwnd, alpha in WinCurrentAlpha {
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_SetAlpha(hwnd, CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : "Off", RS_PRI_AMBIENT)
    }
    RS_Commit()
    WinTargetAlpha.Clear(), WinCurrentAlpha.Clear(), WinLastActive.Clear()
    ; Breathing is a MediaCore consumer, so its state has to be re-published here
    ; and not by each caller.
    ;
    ; SyncBreathingTimers is on every path that changes breathing - startup,
    ; ApplyUi and ToggleBreathing - whereas SyncMediaCore was only reached from
    ; ApplyUi and, at startup, as a side effect of SyncDimmerTimer. So toggling
    ; breathing with Win+Ctrl+E never told MediaCore: turning it ON while nothing
    ; else wanted MediaCore left the sweep stopped, and breathing then dimmed
    ; windows that were playing video - the exact thing MediaCore exists to
    ; prevent. Turning it OFF left the sweep running for nothing. Same pattern as
    ; SyncDimmerTimer, which already ends with this call.
    SyncMediaCore()
}
SyncBreathingTimers()



; Runs on a 200 ms timer, so a throw in here is not a dropped frame - AHK kills
; a timer whose callback throws, and breathing would then be dead for the rest of
; the session with the checkbox still saying it is on.
;
; Two hazards, both from the same source: ShellEvent's HSHELL_WINDOWDESTROYED
; branch deletes the closing window from WinLastActive, WinTargetAlpha and
; WinCurrentAlpha, and it runs on the message thread, which can interrupt this
; timer between any two lines.
;
;   - Enumerating WinLastActive directly meant that delete shifted the remainder
;     under the live enumerator and silently skipped a window. Iterate a snapshot
;     of the keys instead, the same shape RenderFrame uses.
;   - WinTargetAlpha[hwnd] and WinCurrentAlpha[hwnd] were indexed unguarded. The
;     window can vanish between the IsWindow check and either read, and a missing
;     key throws. Note the target is NOT necessarily written earlier in the same
;     iteration: the else branch only assigns once the idle threshold is passed.
BreathingMonitorStep() {
    global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha, CustomTrans
    if !BreathingEnabled
        return

    try {
        MouseGetPos(,, &mHwnd)
        aHwnd := WinExist("A")
        now := QPC()

        needsAnimation := false
        ; One O(1) check instead of a 1.7 us MC_IsMediaHwnd per tracked window. When
        ; nothing is playing - the usual case - MC_IsMediaHwnd would return false for
        ; every window anyway, so short-circuiting is behaviour-identical.
        anyMedia := MC_AnyMedia()
        dimAlpha := TuneAlpha("breatheAlpha")

        keys := []
        for hwnd, unused in WinLastActive
            keys.Push(hwnd)

        for hwnd in keys {
            if !WinLastActive.Has(hwnd)              ; closed since the snapshot
                continue
            if !DllCall("IsWindow", "ptr", hwnd)
                continue

            lastActive := WinLastActive[hwnd]
            baseAlpha := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

            if (hwnd == aHwnd || hwnd == mHwnd || (anyMedia && MC_IsMediaHwnd(hwnd))) {
                WinLastActive[hwnd] := now
                WinTargetAlpha[hwnd] := baseAlpha
            } else if (now - lastActive > BREATHE_IDLE_MS) {
                WinTargetAlpha[hwnd] := Min(baseAlpha, dimAlpha)
            }

            if (!WinTargetAlpha.Has(hwnd) || !WinCurrentAlpha.Has(hwnd))
                continue
            if (WinTargetAlpha[hwnd] != WinCurrentAlpha[hwnd])
                needsAnimation := true
        }

        if (needsAnimation)
            RegisterAnimation("BreathingAnimator", BreathingAnimatorStep)
    }
}

BreathingAnimatorStep(dt:=0, now:=0) {
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive, CustomTrans, FRAME_MS
    global GhostWindows
    if !BreathingEnabled
        return false
    if (dt <= 0)
        dt := FRAME_MS
        
    activeFades := false
    dead := []
    ; Hoisted out of the loop: this runs every frame for every tracked window.
    anyMedia := MC_AnyMedia()
    For hwnd, target in WinTargetAlpha {
        ; Collect, do not delete: removing the current item shifts the rest down
        ; under the live enumerator index, which silently skips the next window.
        if !DllCall("IsWindow", "ptr", hwnd) {
            dead.Push(hwnd)
            continue
        }
        ; Same shell-hook race as BreathingMonitorStep: the destroy branch can
        ; delete this hwnd from WinCurrentAlpha between the IsWindow check above
        ; and the read below. That throw was caught by the scheduler, which then
        ; retired the whole animator mid-fade and left every dimmed window frozen
        ; part-way until the 200 ms monitor re-registered it.
        if !WinCurrentAlpha.Has(hwnd) {
            dead.Push(hwnd)
            continue
        }

        ; A ghosted window's opacity belongs to GhostMonitorStep. Both write at
        ; RS_PRI_AMBIENT but from different timers with their own commits, so
        ; neither priority nor per-flush arbitration separates them - the window
        ; visibly oscillated between the proximity alpha and the breathing alpha.
        ; One owner per window.
        if GhostWindows.Has(hwnd)
            continue

        if (anyMedia && MC_IsMediaHwnd(hwnd)) {
            ; Track it as awake so we stop re-queueing "Off" on every frame for
            ; the whole time something is playing.
            WinCurrentAlpha[hwnd] := 255
            RS_SetAlpha(hwnd, "Off", RS_PRI_AMBIENT)
            continue
        }

        current := WinCurrentAlpha[hwnd]
        if (current == target)
            continue

        activeFades := true

        ; Rates in alpha units per millisecond, not per frame. These are the old
        ; per-frame steps (25 waking, 2 sleeping) divided by the nominal frame, so
        ; the fade looks the same at 63 fps but now holds its wall-clock duration
        ; when frames get heavy instead of turning into slow motion.
        rate := (target == 255) ? (25 / FRAME_MS) : (2 / FRAME_MS)
        step := rate * dt
        if (step < 0.5)                ; never stall on a very short frame
            step := 0.5

        if (current < target)
            current := Min(current + step, target)
        else
            current := Max(current - step, target)

        WinCurrentAlpha[hwnd] := current

        try {
            ; Integer() before the compare: alpha is applied as an integer, so a
            ; fractional current must not re-queue the same visible value.
            iv := Integer(current + 0.5)
            if (iv >= 255)
                RS_SetAlpha(hwnd, "Off", RS_PRI_AMBIENT)
            else
                RS_SetAlpha(hwnd, iv, RS_PRI_AMBIENT)
        }
    }

    for hwnd in dead {
        WinTargetAlpha.Delete(hwnd)
        if WinCurrentAlpha.Has(hwnd)
            WinCurrentAlpha.Delete(hwnd)
        if WinLastActive.Has(hwnd)
            WinLastActive.Delete(hwnd)
        ; CustomTrans is cleaned up by the shell hook's destroy branch, which is
        ; also where RS_RemoveHwnd / MC_RemoveHwnd happen. Doing it here as well
        ; only duplicated that, so it is left to the one owner.
    }
    return activeFades
}
; Behind its flag rather than re-sending Alt+F4 from the body: with the
; feature off the key is simply not claimed, so Windows' own close runs and
; nothing sits in front of Alt+F4 at all.
#HotIf GravityCloseEnabled
$!F4::GravityClose()
#HotIf

GravityClose() {
    hwnd := WinExist("A")
    if !hwnd {
        Send("!{F4}")
        return
    }

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls == "" || cls == "AutoHotkeyGUI" || cls == "WorkerW"
        || cls == "Progman" || cls == "Shell_TrayWnd") {
        Send("!{F4}")
        return
    }

    ; Maximized and full-screen windows are where PrintWindow costs the most (a
    ; whole-screen bitmap) and where the effect reads as a glitch rather than an
    ; animation, so they close the normal way.
    try {
        if (WinGetMinMax(hwnd) != 0) {
            Send("!{F4}")
            return
        }
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        Send("!{F4}")
        return
    }
    if (w < 1 || h < 1) {
        Send("!{F4}")
        return
    }

    ; Capture window visual
    hbm := 0
    success := false
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    if hdcDest {
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
        if (hbm && hdcMem) {
            oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            ; PW_RENDERFULLCONTENT = 2
            success := DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
            DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
        }
        if hdcMem
            DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    }

    if !success {
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
        Send("!{F4}")
        return
    }

    ; Order matters: put the bitmap copy on screen FIRST, then hide the real
    ; window underneath it. Hiding first left a frame with neither visible - a
    ; black flash of whatever is behind the window, right at the start of the
    ; animation. The copy is pixel-identical and always-on-top, so covering the
    ; original before it disappears is seamless.
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "GravityCloseAnim")
    animGui.MarginX := 0, animGui.MarginY := 0
    pic := animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("x" x " y" y " w" w " h" h " NoActivate")

    try RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
    RS_Commit()

    startW := w, startH := h
    startX := x, startY := y

    animKey := "Gravity_" animGui.Hwnd
    start := QPC()
    ms := Tune("animGravityMs")
    ; Owns the bitmap and the GUI: whichever way this animation ends, both are
    ; released exactly once. The bitmap used to leak on every path except a clean
    ; finish - one 8 MB screen-compatible bitmap per Alt+F4.
    finished := false
    Cleanup() {
        if finished
            return
        finished := true
        gh := 0
        try gh := animGui.Hwnd
        try animGui.Destroy()
        if gh
            RS_RemoveHwnd(gh)      ; our own GUIs raise no shell destroy event
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
    }

    GravityStep(dt, now) {
        if !DllCall("IsWindow", "ptr", animGui.Hwnd) {
            Cleanup()
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            Cleanup()
            try PostMessage(0x0010, 0, 0, , hwnd) ; WM_CLOSE
            SetTimer(CheckGravityClose.Bind(hwnd), -400)
            return false
        }

        ; Falling under gravity is s = 1/2*a*t^2 - quadratic, not cubic. Cubic made
        ; the window hang almost still and then snap away at the end, which reads as
        ; a stutter rather than a drop. Quadratic is both correct and smoother.
        ease := t * t

        curW := Round(startW * (1 - ease * 0.95))
        curH := Round(startH * (1 - ease * 0.95))

        curX := Round(startX + (startW - curW) / 2)
        curY := Round(startY + ease * (startH * 0.8) + (startH - curH) / 2)

        try {
            animGui.Move(curX, curY, curW, curH)
            pic.Move(0, 0, curW, curH)

            if (t > 0.4) {
                alpha := Clamp(Round(255 * (1 - ((t - 0.4) / 0.6))), 0, 255)
                RS_SetAlpha(animGui.Hwnd, alpha, RS_PRI_ANIM)
            }
        }
        return true
    }

    RegisterAnimation(animKey, GravityStep)
}

; The window refused (or has not yet processed) WM_CLOSE - a "Save changes?"
; prompt, typically. Give it its opacity back, and actually commit: without the
; commit the window stayed at alpha 0, alive and focused but invisible.
CheckGravityClose(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
    RS_Commit()
}

global FocusModeEnabled := false
global FocusGuis := []
global SpotlightTarget := {x: 0, y: 0, w: 0, h: 0}
global SpotlightCurrent := {x: 0, y: 0, w: 0, h: 0}
global FocusBounds := {x: 0, y: 0, w: 0, h: 0}
; Snapshotted when focus mode is entered rather than read per layer per frame:
; FocusAnimatorStep runs three layers at 63 fps, and the shape of the vignette
; must not change halfway through a session anyway.
global FocusFeather := 70, FocusRadius := 40
global FocusTargetHwnd := 0

ToggleFocusMode() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    global FocusFeather, FocusRadius
    ; Decide before flipping the flag. Flipping first and then bailing out left
    ; the flag saying "on" with no overlays, so the next press took the off
    ; branch and focus mode could never be entered again.
    if (!FocusModeEnabled && FocusGuis.Length)
        return
    FocusModeEnabled := !FocusModeEnabled

    if (FocusModeEnabled) {
        ; Three stacked layers whose relative weights make the falloff; the
        ; setting scales all three so the shape is preserved at any strength.
        FocusFeather := Tune("focusFeather")
        FocusRadius  := Tune("focusRadius")
        peak := TuneAlpha("focusAlpha")
        alphas := [Round(peak * 140 / 240), Round(peak * 200 / 240), peak]
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        
        loop 3 {
            g := Gui("-Caption -DPIScale +ToolWindow +E0x20", "FocusModeOverlay" A_Index)
            g.BackColor := "000000"
            g.MarginX := 0, g.MarginY := 0
            g.Show("x" vx " y" vy " w" vw " h" vh " NoActivate")
            RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
            FocusGuis.Push({gui: g, targetAlpha: alphas[A_Index], currentAlpha: 0})
        }
        
        FocusTargetHwnd := WinExist("A")
        placed := false
        if (FocusTargetHwnd && IsRestorable(FocusTargetHwnd)) {
            try {
                if (WinGetMinMax(FocusTargetHwnd) == 0) {
                    WinGetPos(&tx, &ty, &tw, &th, FocusTargetHwnd)
                    SpotlightCurrent := {x: tx, y: ty, w: tw, h: th}
                    SpotlightTarget := {x: tx, y: ty, w: tw, h: th}
                    placed := true
                }
            }
        }
        if (!placed) {
            SpotlightCurrent := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
            SpotlightTarget := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
        }
        
        ZOrderSpotlight()
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
        SetTimer(FocusMonitorStep, 50)
        Notify("Focus Mode ON")
    } else {
        CancelAnimation("FocusAnimator")
        SetTimer(FocusMonitorStep, 0)
        ; 'layer', not 'fg' - case-insensitive identifiers make 'fg' the global
        ; foreground colour FG.
        ; FadeGui destroys the layer itself when it reaches 0, which removes the
        ; old 300 ms fade / 350 ms destroy-timer race.
        ; Explicitly 300 ms rather than the shared Overlay fade. These are three
        ; stacked FULL-SCREEN vignette layers; at the ~110 ms a small overlay
        ; wants, the whole desktop snaps from dark to bright and reads as a
        ; flash. Duration here is a property of what is being faded, not a
        ; preference, so it is not a setting.
        for layer in FocusGuis
            FadeGui(layer.gui, 0, 300, true)
        FocusGuis := []
        Notify("Focus Mode OFF")
    }
}

GuiDestroy(g) {
    hwnd := 0
    try hwnd := g.Hwnd
    try g.Destroy()
    if hwnd
        RS_RemoveHwnd(hwnd)
}

ZOrderSpotlight() {
    global FocusGuis, FocusTargetHwnd
    if !FocusTargetHwnd || !DllCall("IsWindow", "ptr", FocusTargetHwnd)
        return
        
    isTopmost := 0
    try isTopmost := WinGetExStyle(FocusTargetHwnd) & 0x8
    prevHwnd := FocusTargetHwnd
    for layer in FocusGuis {
        if (isTopmost)
            WinSetExStyle("+0x8", layer.gui.Hwnd)
        else
            WinSetExStyle("-0x8", layer.gui.Hwnd)
        try RS_SetZOrder(layer.gui.Hwnd, prevHwnd, 0x0013, RS_PRI_ANIM)
        prevHwnd := layer.gui.Hwnd
    }
    ; Called from FocusMonitorStep on a focus change, which does not always
    ; register an animation - so commit rather than hoping someone else will.
    RS_Commit()
}

FocusMonitorStep() {
    global FocusModeEnabled, FocusTargetHwnd, SpotlightTarget
    if !FocusModeEnabled
        return
        
    hwnd := WinExist("A")
    if (hwnd != FocusTargetHwnd) {
        FocusTargetHwnd := hwnd
        ZOrderSpotlight()
    }
    
    if (hwnd && IsRestorable(hwnd) && WinGetMinMax(hwnd) == 0) {
        WinGetPos(&tx, &ty, &tw, &th, hwnd)
        newTarget := {x: tx, y: ty, w: tw, h: th}
    } else {
        MouseGetPos(&mx, &my)
        newTarget := {x: mx, y: my, w: 0, h: 0}
    }
    
    if (SpotlightTarget.x != newTarget.x || SpotlightTarget.y != newTarget.y || SpotlightTarget.w != newTarget.w || SpotlightTarget.h != newTarget.h) {
        SpotlightTarget := newTarget
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
    }
}

FocusAnimatorStep(dt:=0, now:=0) {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FRAME_MS
    global FocusFeather, FocusRadius
    if !FocusModeEnabled || !FocusGuis.Length
        return false
    if (dt <= 0)
        dt := FRAME_MS

    spot := SpotlightCurrent
    t    := SpotlightTarget

    ; Frame-rate-independent exponential smoothing.
    ;
    ; A flat 0.15 per frame meant the spotlight caught up in a fixed number of
    ; FRAMES, so it drifted lazily whenever frames were slow and snapped when they
    ; were fast. Compounding the per-frame retention over the real elapsed time
    ; gives the same feel at any frame rate: after dt ms, the remaining distance is
    ; 0.85^(dt/FRAME_MS).
    f := 1 - (0.85 ** (dt / FRAME_MS))
    spot.x += (t.x - spot.x) * f
    spot.y += (t.y - spot.y) * f
    spot.w += (t.w - spot.w) * f
    spot.h += (t.h - spot.h) * f

    finished := true
    if (Abs(spot.x - t.x) < 0.5 && Abs(spot.y - t.y) < 0.5 && Abs(spot.w - t.w) < 0.5 && Abs(spot.h - t.h) < 0.5) {
        spot.x := t.x
        spot.y := t.y
        spot.w := t.w
        spot.h := t.h
    } else {
        finished := false
    }

    hx := Round(spot.x - FocusBounds.x)
    hy := Round(spot.y - FocusBounds.y)
    hw := Round(spot.w)
    hh := Round(spot.h)

    for layer in FocusGuis {
        pad := (A_Index - 1) * FocusFeather

        px := hx - pad
        py := hy - pad
        pw := hw + pad*2
        ph := hh + pad*2

        region := "0-0 W" FocusBounds.w " H" FocusBounds.h

        if (pw > 0 && ph > 0) {
            region .= " " px "-" py " W" pw " H" ph " R" (FocusRadius + pad) "-" (FocusRadius + pad)
        }

        ; WinSetRegion rebuilds a GDI region, and this runs for three full-screen
        ; overlays every frame. RS_LastRegion already skips an identical string,
        ; but only if we do not build a different one for the same pixels - hence
        ; the integer rounding above rather than per-layer float maths.
        try RS_SetRegion(layer.gui.Hwnd, region, RS_PRI_ANIM)

        if (layer.currentAlpha != layer.targetAlpha) {
            finished := false
            ; Per-millisecond, matching the old 10-per-frame at the nominal rate.
            step := (10 / FRAME_MS) * dt
            if (step < 0.5)
                step := 0.5
            if (layer.currentAlpha < layer.targetAlpha)
                layer.currentAlpha := Min(layer.currentAlpha + step, layer.targetAlpha)
            else
                layer.currentAlpha := Max(layer.currentAlpha - step, layer.targetAlpha)

            try RS_SetAlpha(layer.gui.Hwnd, Integer(layer.currentAlpha + 0.5), RS_PRI_ANIM)
        }
    }
    return !finished
}

; ====== The one Gui fade ======
; Every transient overlay fades the same way, and there used to be five separate
; implementations of it: OsdFadeIn, FadeOutAndDestroy, FadeInDimmer,
; FadeOutAndDestroyDimmer, QuickLookFade and FadeWindow. They had drifted apart -
; different easing (some linear, some not), different durations, and worst of all
; different animation keys per direction, which is what let an OSD fade in and out
; at the same time.
;
; One key per window ("Fade_" hwnd) for BOTH directions, so starting any fade
; cancels the opposite one. The start alpha comes from RS_CurrentAlpha, so a
; reversed fade continues from where the window actually is instead of jumping.
;
;   toAlpha   target opacity, 0-255
;   ms        duration; 0 (the default) means "whatever Overlay fade is set to",
;             which is how the dimmers, Quick Look and the Start-menu blur all
;             end up sharing one user-visible speed instead of three literals
;   destroy   destroy the Gui when it reaches 0 (and forget its render state)
;   onDone    called once, whichever way the fade ends
FadeGui(guiObj, toAlpha, ms := 0, destroy := false, onDone := "") {
    if (ms <= 0)
        ms := Tune("animFadeMs")
    hwnd := 0
    try hwnd := guiObj.Hwnd
    if (!hwnd || !DllCall("IsWindow", "ptr", hwnd)) {
        if onDone
            onDone()
        return
    }

    animKey := "Fade_" hwnd
    CancelAnimation(animKey)
    from := RS_CurrentAlpha(hwnd, toAlpha)
    start := QPC()

    Finish() {
        if destroy {
            try guiObj.Destroy()
            RS_RemoveHwnd(hwnd)        ; our own GUIs raise no shell destroy event
        } else {
            try RS_SetAlpha(hwnd, toAlpha, RS_PRI_ANIM)
        }
        if onDone
            onDone()
    }

    FadeGuiStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            RS_RemoveHwnd(hwnd)
            if onDone
                onDone()
            return false
        }
        t := (now - start) / ms
        if (t >= 1) {
            Finish()
            return false
        }
        e := t * t * (3 - 2 * t)               ; smoothstep
        try RS_SetAlpha(hwnd, Round(from + (toAlpha - from) * e), RS_PRI_ANIM)
        return true
    }

    RegisterAnimation(animKey, FadeGuiStep)
}

ToggleSnap() {
    global SnapEnabled, Win, C
    SnapEnabled := !SnapEnabled
    SyncTray(), SaveSettings()
    if (Win && WinExist("ahk_id " Win.Hwnd))
        try C["snap"].Value := SnapEnabled
    Notify(SnapEnabled ? "Magnetic snap ON" : "Magnetic snap OFF")
}

ToggleMemory() {
    global RestoreEnabled, Win, C
    RestoreEnabled := !RestoreEnabled
    SyncTray(), SaveSettings()
    if (Win && WinExist("ahk_id " Win.Hwnd))
        try C["mem"].Value := RestoreEnabled
    Notify(RestoreEnabled ? "Position memory ON" : "Position memory OFF")
}

; ----- Win+Ctrl+Shift feature toggles ----------------------------------------
; All seven follow ToggleBreathing exactly: flip the flag, persist it, keep the
; settings window in step if it happens to be open, say so, then call the
; feature's Sync* function.
;
; That last step is the one that matters. Each of these features is driven by a
; timer or a registered animation that its Sync* starts and stops; flipping the
; flag alone leaves the feature enabled with nothing running, so it stays
; silently dead until the next restart - and the settings checkbox says it is on.
ToggleFeatureFlag(label, isOn, ctrlKey) {
    global Win, C
    SaveSettings()
    if (Win && WinExist("ahk_id " Win.Hwnd))
        try C[ctrlKey].Value := isOn
    Notify(label " " (isOn ? "ON" : "OFF"))
}

ToggleHotCorners() {
    global HotCornersEnabled
    HotCornersEnabled := !HotCornersEnabled
    ToggleFeatureFlag("Hot corners", HotCornersEnabled, "corners_en")
    SyncHotCornersTimer()
}

ToggleActiveBorder() {
    global ActiveBorderEnabled
    ActiveBorderEnabled := !ActiveBorderEnabled
    ToggleFeatureFlag("Active window border", ActiveBorderEnabled, "border")
    SyncActiveBorderTimer()
}

ToggleCursorWrap() {
    global InfiniteWrapEnabled
    InfiniteWrapEnabled := !InfiniteWrapEnabled
    ToggleFeatureFlag("Infinite cursor wrap", InfiniteWrapEnabled, "wrap")
    SyncCursorWrapTimer()
}

ToggleDimmer() {
    global MultiMonitorDimmerEnabled
    MultiMonitorDimmerEnabled := !MultiMonitorDimmerEnabled
    ToggleFeatureFlag("Multi-monitor dimmer", MultiMonitorDimmerEnabled, "multidimmer")
    SyncDimmerTimer()              ; also fades out and clears the dim overlays
}

ToggleSmartTaskbar() {
    global SmartTaskbarEnabled, OriginalTaskbarState
    SmartTaskbarEnabled := !SmartTaskbarEnabled
    ToggleFeatureFlag("Smart auto-hide taskbar", SmartTaskbarEnabled, "smart_tb")
    ; Switching off has to hand the taskbar back the way ApplyUi does, or it is
    ; left auto-hiding with nothing left to un-hide it.
    if (!SmartTaskbarEnabled && OriginalTaskbarState != -1)
        try SetTaskbarAutoHide(OriginalTaskbarState & 1)
    SyncSmartTaskbar()
}

; No Sync* for these two: magnetic groups is read inline by the drag pipeline and
; grab & pan lives behind a #HotIf, which re-evaluates the flag on every press.
ToggleMagneticGroups() {
    global MagneticGroupsEnabled
    MagneticGroupsEnabled := !MagneticGroupsEnabled
    ToggleFeatureFlag("Magnetic window groups", MagneticGroupsEnabled, "magnetic")
}

ToggleGrabPan() {
    global GrabPanEnabled
    GrabPanEnabled := !GrabPanEnabled
    ToggleFeatureFlag("Grab & pan", GrabPanEnabled, "grabpan")
}

#^t:: {
    hwnd := WinExist("A")
    if !hwnd
        return
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return
    }
    try {
        WinSetAlwaysOnTop(-1, hwnd)
        isTop := WinGetExStyle(hwnd) & 0x8      ; WS_EX_TOPMOST
        try WriteLog(Format("alwaysontop {1} hwnd={2} class={3}", isTop ? "ON" : "OFF", hwnd, WinGetClass(hwnd)))
        Notify(isTop ? "Always on top: ON" : "Always on top: OFF")
    } catch Error as err {
        Notify("Failed to set Always on top (Access Denied)")
    }
}



; =========================================================== Drag detection ===========================================================
; The shell raises MOVESIZESTART / MOVESIZEEND around every window drag, so we
; hook those instead of the mouse. A ~LButton hotkey would make AutoHotkey
; install a low-level mouse hook that wakes on every mouse move - measured at
; ~1.6% of a core just sitting there. MOVESIZEEND also fires after the OS modal
; move loop has finished, which is precisely when repositioning is safe.
global DragHwnd := 0, DragL := 0, DragT := 0, DragR := 0, DragB := 0
global VelX := 0, VelY := 0, PrevX := 0, PrevY := 0
global CurrentDragAlpha := 255
; Not a "Fast" callback. Fast mode runs on top of whatever script thread the
; event interrupted, and this one is not trivial: it queries the window, starts
; an animation and arms a timer. Registering an animation from inside an
; arbitrary interruption point is what corrupted the scheduler's enumeration.
; The event is WINEVENT_OUTOFCONTEXT, so it arrives through our own message
; queue either way and nothing here needs fast-mode semantics.
global WinEventCb := CallbackCreate(WinEvent, , 7)
; Keep the hook handle: without it the hook can never be unhooked, and the
; callback can never be freed. Bye() releases both.
global WinEventHook := DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", WinEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

global MenuEventCb := CallbackCreate(MenuEvent, , 7)
global MenuEventHook := DllCall("SetWinEventHook", "uint", 0x0006, "uint", 0x0006, "ptr", 0,
        "ptr", MenuEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

MenuEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global ContextMenuAnimEnabled
    if (!ContextMenuAnimEnabled || !hwnd || idObject != 0 || idChild != 0)
        return
        
    ; Both queries need a catch, not a bare `try`. A failed WinGetClass leaves cls
    ; unset and a failed WinGetPos leaves w/h unset, and the next line reads them -
    ; outside the try, in a SetWinEventHook callback. Menu windows (#32768) are
    ; created and destroyed constantly, so losing the race here is routine and the
    ; result was an error dialog on a random right-click.
    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls != "#32768")
        return

    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    ; Through the pipeline, not WinSetTransparent/WinSetRegion directly.
    ; MenuAnimStep is a scheduler callback, and the scheduler's contract is that
    ; callbacks only QUEUE - a direct Win32 write from inside the produce phase
    ; skips the batching, the diffing and the priority arbitration, and rebuilds
    ; a GDI region for a menu that RS_LastRegion would have skipped.
    RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
    RS_Commit()

    animKey := "MenuAnim_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150

    MenuAnimStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd)) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        curH := Round(h * ease)
        if (curH > 0) {
            RS_SetRegion(hwnd, "0-0 w" w " h" curH, RS_PRI_ANIM)
            RS_SetAlpha(hwnd, 255, RS_PRI_ANIM)
        }
        return true
    }
    RegisterAnimation(animKey, MenuAnimStep)
}

WinEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global SnapEnabled, RestoreEnabled, ParallaxEnabled
    global DragHwnd, DragL, DragT, DragR, DragB, VelX, VelY, PrevX, PrevY
    global CurrentDragAlpha          ; assigned below - without this it is a local and the reset never lands
    if (idObject != 0 || idChild != 0)
        return
    ; ParallaxEnabled belongs here too: the drag-transparency effect is driven
    ; entirely from this hook, so leaving it out made it silently depend on
    ; snapping or position memory also being switched on.
    if (!SnapEnabled && !RestoreEnabled && !ParallaxEnabled)
        return
    if (event = 0x000A) {                    ; MOVESIZESTART
        if (DragHwnd != 0 && DragHwnd != hwnd) {
            CancelAnimation("SampleVelocity")
            global GhostWindows
            if (!GhostWindows.Has(DragHwnd))
                StartFadeBackAlpha(DragHwnd, CurrentDragAlpha)
        }
        DragHwnd := 0
        if !IsSnappable(hwnd)
            return
        if !GetRects(hwnd, &sL, &sT, &sR, &sB, &sx, &sy)
            return
        CancelAnimation("Glide_" hwnd)
        CancelAnimation("Bounce_" hwnd)
        CancelAnimation("GhostSlideIn_" hwnd)
        CancelAnimation("PortalScaleIn_" hwnd)
        CancelAnimation("Unroll_" hwnd)
        CancelAnimation("FadeBack_" hwnd)

        DragHwnd := hwnd, DragL := sL, DragT := sT, DragR := sR, DragB := sB
        VelX := 0, VelY := 0, PrevX := sL, PrevY := sT
        CurrentDragAlpha := 255
        RegisterAnimation("SampleVelocity", SampleVelocityStep)
        return
    }

    if (hwnd != DragHwnd)                    ; MOVESIZEEND
        return
    CancelAnimation("SampleVelocity")
    DragHwnd := 0
    ; Capture the start rect into the closure. It used to be read from the
    ; globals 50 ms later, so a second drag beginning inside that window
    ; overwrote them and this drag was measured against the wrong origin.
    sL := DragL, sT := DragT, sR := DragR, sB := DragB
    sAlpha := CurrentDragAlpha
    SetTimer(() => FinishDrag(hwnd, sL, sT, sR, sB, sAlpha), -50)    ; defer: FinishDrag enumerates windows
}

SampleVelocityStep(dt, now) {
    global DragHwnd, VelX, VelY, PrevX, PrevY, ParallaxEnabled, CurrentDragAlpha
    if !DragHwnd {
        return false
    }
    if !GetRects(DragHwnd, &L, &T, &R, &B, &x, &y)
        return true
    VelX := VelX * 0.6 + (L - PrevX) * 0.4
    VelY := VelY * 0.6 + (T - PrevY) * 0.4
    vX := L - PrevX
    vY := T - PrevY
    PrevX := L, PrevY := T
    
    global MagneticGroupsEnabled, MagGroups
    if (MagneticGroupsEnabled && (vX != 0 || vY != 0) && MagGroups.Has(DragHwnd)) {
        if (Abs(vX) > 25 || Abs(vY) > 25) {
            UngroupWindow(DragHwnd)
        } else {
            ; Queued, not WinMove'd. This runs inside the produce phase of the
            ; frame loop, where the scheduler's contract says callbacks may only
            ; write through RS_*; a direct WinMove skipped the DeferWindowPos
            ; batching and, at DRAG priority, fought any animation still running
            ; on the towed window instead of overriding it cleanly.
            for other in MagGroups[DragHwnd] {
                if (other != DragHwnd && DllCall("IsWindow", "ptr", other)) {
                    try {
                        WinGetPos(&ox, &oy, &ow, &oh, other)
                        RS_SetPos(other, ox + vX, oy + vY, ow, oh, RS_PRI_DRAG)
                    }
                }
            }
        }
    }
    
    global GhostWindows
    if (ParallaxEnabled && !GhostWindows.Has(DragHwnd)) {
        speed := Sqrt(VelX * VelX + VelY * VelY)
        targetAlpha := Clamp(Round(255 - (speed * 4)), TuneAlpha("parallaxMin"), 255)
        
        CurrentDragAlpha := CurrentDragAlpha * 0.7 + targetAlpha * 0.3
        
        if (CurrentDragAlpha < 250) {
            RS_SetAlpha(DragHwnd, Integer(CurrentDragAlpha), RS_PRI_DRAG)
        } else {
            RS_SetAlpha(DragHwnd, "Off", RS_PRI_DRAG)
        }
    }
    
    global SmartGridEnabled, GridActive
    if (SmartGridEnabled && GetKeyState("Shift", "P")) {
        if (!GridActive)
            ShowSmartGrid()
        UpdateSmartGrid()
    } else if (GridActive) {
        HideSmartGrid()
    }
    
    return true
}

FinishDrag(hwnd, startL, startT, startR, startB, startA) {
    global MIN_DRAG, ParallaxEnabled
    if !DllCall("IsWindow", "ptr", hwnd)
        return

    global GridActive, GridHoverZone
    if (GridActive) {
        ; HideSmartGrid must run even if ApplyGridZone fails, or the zone overlays
        ; are stranded on screen with nothing left that can take them down.
        if (GridHoverZone > 0)
            try ApplyGridZone(hwnd, GridHoverZone)
        HideSmartGrid()
        global GhostWindows
        if (!GhostWindows.Has(hwnd))
            StartFadeBackAlpha(hwnd, startA)
        return
    }

    global GhostWindows
    if (!GhostWindows.Has(hwnd))
        StartFadeBackAlpha(hwnd, startA)

    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - startL) < MIN_DRAG && Abs(eT - startT) < MIN_DRAG
        && Abs(eR - startR) < MIN_DRAG && Abs(eB - startB) < MIN_DRAG)
        return
    minMax := 0
    try minMax := WinGetMinMax(hwnd)
    catch
        return
    if (minMax != 0) {                       ; Windows' own snap maximised it
        WriteLog("skip: window ended maximized")
        return
    }

    WriteLog(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
}

StartFadeBackAlpha(hwnd, startA) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (startA >= 250) {
        RS_SetAlpha(hwnd, "Off", RS_PRI_DRAG)
        RS_Commit()
        return
    }
    animKey := "FadeBack_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 190
    FadeBackStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetAlpha(hwnd, "Off", RS_PRI_DRAG)
            return false
        }
        ; Ease out: the window should rush back to solid the instant you let go,
        ; then settle. A linear ramp made the release feel sluggish.
        e := 1 - (1 - t) * (1 - t)
        RS_SetAlpha(hwnd, Integer(startA + (255 - startA) * e), RS_PRI_DRAG)
        return true
    }
    RegisterAnimation(animKey, FadeBackStep)
}

SnapWindow(hwnd, L, T, R, B, winX, winY) {
    global SnapEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MAX, VelX, VelY
    
    global MonitorThrowEnabled
    if (MonitorThrowEnabled && (Abs(VelX) > 15 || Abs(VelY) > 15)) {
        if ThrowWindowToNextMonitor(hwnd, L, T, R - L, B - T, VelX, VelY)
            return
    }

    ; Carry the release speed forward, so a flick keeps travelling instead of
    ; stopping dead where you let go.
    tx := 0, ty := 0
    if GlideEnabled {
        tx := Clamp(Round(VelX * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
        ty := Clamp(Round(VelY * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
    }
    pL := L + tx, pT := T + ty, pR := R + tx, pB := B + ty
    KeepOnScreen(hwnd, &pL, &pT, &pR, &pB, tx, ty)

    if (SnapEnabled) {
        ; Snap is judged from where the throw would land, not where you let go.
        CollectEdges(hwnd, pL, pT, pR, pB, &vLines, &hLines, NEIGHBOUR_PROX)
        if !ComputeSnap(pL, pT, pR, pB, vLines, hLines, SNAP_DISTANCE, &newL, &newT, CORNER_BOOST)
            newL := pL, newT := pT
    } else {
        newL := pL, newT := pT
    }

    if (newL = L && newT = T) {
        RememberPosition(hwnd)
        global MomentumTiltEnabled
        if (MomentumTiltEnabled && (Abs(VelX) > 3 || Abs(VelY) > 3))
            JelloBounce(hwnd, winX, winY, VelX, VelY)
        return
    }

    ; Frame space -> WinMove space; they differ by the invisible DWM border.
    destX := winX + (newL - L)
    destY := winY + (newT - T)

    ; Everything that should happen WHEN THE WINDOW LANDS is collected into one
    ; handler and handed to Glide, which invokes it from the frame where it puts
    ; the window down. It used to be two parallel SetTimer calls armed for
    ; "glideMs from now", which raced the glide's own last frame by a frame or two
    ; and - worse - still fired if a new drag had cancelled the glide in the
    ; meantime, bouncing a window the user had already grabbed again.
    ;
    ; Both effects were originally applied immediately, which is why neither
    ; worked: the bounce was overwritten by every glide frame (Map keys enumerate
    ; sorted, so "Bounce_" produced before "Glide_"), and the seam flash hung in
    ; empty space at the destination for up to 650 ms before the window arrived.
    ; W/H are hoisted out of the seam-flash guard on purpose: the magnetic-groups
    ; block further down reads them unconditionally, so with seam flash off and
    ; magnetic groups on they were UNSET. SnapWindow runs from FinishDrag's -50 ms
    ; one-shot, so that throw killed the tail of the drag pipeline - no glide, no
    ; VerifySnap, window left wherever the OS dropped it.
    W := R - L
    H := B - T

    global SeamFlashEnabled
    seams := []
    if (SeamFlashEnabled) {
        if (newL != pL) {
            for v in vLines {
                if (Abs(newL - v) < 2) {
                    seams.Push([newL - 1, newT, 3, H])
                    break
                }
                if (Abs(newL + W - v) < 2) {
                    seams.Push([newL + W - 1, newT, 3, H])
                    break
                }
            }
        }
        if (newT != pT) {
            for hLine in hLines {
                if (Abs(newT - hLine) < 2) {
                    seams.Push([newL, newT - 1, W, 3])
                    break
                }
                if (Abs(newT + H - hLine) < 2) {
                    seams.Push([newL, newT + H - 1, W, 3])
                    break
                }
            }
        }
    }
    
    global MagneticGroupsEnabled
    if (MagneticGroupsEnabled && (newL != pL || newT != pT)) {
        if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
            newR := newL + W
            newB := newT + H
            for other in WinGetList() {
                if (other = hwnd || !IsSnappable(other))
                    continue
                if (GetRects(other, &oL, &oT, &oRight, &oB, &ox, &oy)) {
                    touches := false
                    if ((Abs(newL - oRight) < 2 || Abs(newR - oL) < 2) && (newT < oB && newB > oT))
                        touches := true
                    else if ((Abs(newT - oB) < 2 || Abs(newB - oT) < 2) && (newL < oRight && newR > oL))
                        touches := true
                    
                    if (touches) {
                        GroupWindows(hwnd, other)
                    }
                }
            }
        }
    }

    ; Physics: if momentum carried us further than the snap allowed, we crashed
    ; into a wall.
    ; "The snap stopped us short of where the throw was heading" - which is the
    ; same subtraction whichever way we were travelling. This was written as two
    ; branches per axis computing the identical expression; the only thing the
    ; sign test contributed was excluding the case where the snap carried us
    ; FURTHER than the throw, which is not a crash.
    crashX := 0, crashY := 0
    if (Abs(VelX) > 1.5 && tx != 0 && Abs(newL - L) < Abs(tx))
        crashX := tx - (newL - L)
    if (Abs(VelY) > 1.5 && ty != 0 && Abs(newT - T) < Abs(ty))
        crashY := ty - (newT - T)

    landed := OnSnapLanded.Bind(hwnd, destX, destY, crashX, crashY, seams)

    glideMs := 0
    if GlideEnabled {
        glideMs := Glide(hwnd, winX, winY, destX, destY, landed)
    } else {
        ; One-shot: no animation is running, so nothing else would ever flush
        ; this. Without the commit, snapping did nothing at all whenever ice
        ; glide was switched off.
        MoveFast(hwnd, destX, destY)
        RS_Commit()
        landed()
    }

    ; Verify asynchronously. This used to be two PreciseSleep(40) spins inline:
    ; PreciseSleep never pumps messages, so the 80 ms froze every timer in the
    ; process - including the frame loop that had just been armed to run the
    ; glide. Worse, the check then read the position before the glide had moved
    ; anything, so its "one retry" fired on almost every snap and queued a
    ; competing move at the same priority as the animation.
    WriteLog(Format("  settled at L={1} T={2}  (throw {3},{4})", newL, newT, tx, ty))
    SetTimer(VerifySnap.Bind(hwnd, newL, newT), -(Round(glideMs) + 60))
}

; The moment the window comes to rest: spark the seams it touched, then let it
; squish if it hit something hard. Called from Glide's final frame, or directly
; when there is no glide - never from a timer racing the animation.
;
; The size is read HERE rather than at drag end, because the window's own app may
; have resized it during the slide.
OnSnapLanded(hwnd, destX, destY, crashX, crashY, seams) {
    for s in seams
        ShowSeamFlash(s[1], s[2], s[3], s[4])

    if (Abs(crashX) <= 4 && Abs(crashY) <= 4)
        return
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try {
        WinGetPos(, , &w, &h, hwnd)
        RememberPosition(hwnd, destX, destY, w, h)
        BounceSqueeze(hwnd, destX, destY, w, h, crashX, crashY)
    }
}

; Some apps reposition themselves once more after a drag ends. Nudge them back,
; once - but never while our own glide is still flying the window, or we would be
; fighting the animation instead of the app.
VerifySnap(hwnd, newL, newT) {
    global ActiveAnimations
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if ActiveAnimations.Has("Glide_" hwnd) || ActiveAnimations.Has("Bounce_" hwnd)
        return
    if !GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
        return
    if (vL = newL && vT = newT)
        return
    MoveFast(hwnd, vx + (newL - vL), vy + (newT - vT))
    RS_Commit()
    WriteLog(Format("  corrected L={1} T={2} -> L={3} T={4}", vL, vT, newL, newT))
}

; Slides a window and returns the animation length in ms (0 if it moved it
; immediately), so the caller can schedule its verification for after the landing.
;
; `onLanded` is invoked from the frame that puts the window down - and only then.
; It is deliberately NOT called if the window dies mid-slide, or if a new glide
; cancels this one, because in both cases the window never landed where this snap
; intended and anything keyed to the landing would be wrong.
Glide(hwnd, fromX, fromY, toX, toY, onLanded := "") {
    global GLIDE_MS
    dx := toX - fromX, dy := toY - fromY
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 2 || GLIDE_MS < 1) {
        MoveFast(hwnd, toX, toY)
        RS_Commit()
        if onLanded
            onLanded()
        return 0
    }

    ms := Min(GLIDE_MS, 200 + dist * 1.1)
    animKey := "Glide_" hwnd
    CancelAnimation(animKey)

    start := QPC()
    lastX := -99999, lastY := -99999

    GlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, toX, toY, -1, -1, RS_PRI_ANIM)
            if onLanded
                onLanded()
            return false
        }

        e := 1 - (1 - t) ** 5
        nx := Round(fromX + dx * e)
        ny := Round(fromY + dy * e)

        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, -1, -1, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    RegisterAnimation(animKey, GlideStep)
    return ms
}

JelloBounce(hwnd, destX, destY, vx, vy) {
    if (!DllCall("IsWindow", "ptr", hwnd))
        return
        
    try WinGetPos(,, &w, &h, hwnd)
    
    animKey := "Jello_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    
    sqX := Clamp(vx * 1.5, -10, 10)
    sqY := Clamp(vy * 1.5, -10, 10)
    
    JelloStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, destX, destY, w, h, RS_PRI_ANIM)
            return false
        }
        
        decay := Exp(-t * 5)
        osc := Sin(t * 15)
        
        curSqX := Round(sqX * decay * osc)
        curSqY := Round(sqY * decay * osc)
        
        curX := destX - Round(curSqX / 2)
        curY := destY - Round(curSqY / 2)
        curW := w + curSqX
        curH := h + curSqY
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, JelloStep)
}

BounceSqueeze(hwnd, X, Y, W, H, crashX, crashY) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    
    squeezeX := 0, squeezeY := 0
    moveX := 0, moveY := 0
    depth := Tune("animBounce")

    if (crashX > 4) {
        squeezeX := Min(crashX * 0.4, depth)
        moveX := squeezeX
    } else if (crashX < -4) {
        squeezeX := Min(-crashX * 0.4, depth)
        moveX := 0
    }

    if (crashY > 4) {
        squeezeY := Min(crashY * 0.4, depth)
        moveY := squeezeY
    } else if (crashY < -4) {
        squeezeY := Min(-crashY * 0.4, depth)
        moveY := 0
    }
    
    if (squeezeX == 0 && squeezeY == 0)
        return
        
    animKey := "Bounce_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animBounceMs")

    ; One smooth squish-and-release instead of four hard-coded stages at 16/32/48
    ; ms. The old version was three discrete jumps that assumed a frame was exactly
    ; 16 ms - it had no interpolation at all, and a late frame made it skip a stage
    ; or repeat one. sin(pi*t) rises from 0 to the full squeeze at the midpoint and
    ; returns to 0, so it starts and ends exactly at rest with no discontinuity.
    lastW := -1, lastH := -1, lastX := -1, lastY := -1
    BounceStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, X, Y, W, H, RS_PRI_ANIM)
            return false
        }

        e := Sin(3.14159265 * t)
        nx := Round(X + moveX * e)
        ny := Round(Y + moveY * e)
        nw := Round(W - squeezeX * e)
        nh := Round(H - squeezeY * e)
        ; Skip frames that would not change a pixel: SetWindowPos on a real window
        ; costs ~260 us and forces the app to re-layout.
        if (nx != lastX || ny != lastY || nw != lastW || nh != lastH) {
            RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
            lastX := nx, lastY := ny, lastW := nw, lastH := nh
        }
        return true
    }

    RegisterAnimation(animKey, BounceStep)
}

ThrowWindowToNextMonitor(hwnd, L, T, W, H, vx, vy) {
    monCount := MonitorGetCount()
    if (monCount < 2)
        return false
        
    cx := L + W/2
    cy := T + H/2
    
    ; Exclusive on the right and bottom, like MonitorIndexAt. Inclusive bounds
    ; make the shared edge between two monitors belong to both, so a window
    ; centred exactly there matched whichever came first in the enumeration.
    curMon := MonitorIndexAt(cx, cy)
    
    targetMon := 0
    bestDist := 999999
    
    loop monCount {
        if (A_Index == curMon)
            continue
            
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        mx := mL + (mR - mL)/2
        my := mT + (mB - mT)/2
        
        dx := mx - cx
        dy := my - cy
        
        dotProduct := (dx * vx) + (dy * vy)
        if (dotProduct > 0) {
            dist := Sqrt(dx*dx + dy*dy)
            if (dist < bestDist) {
                bestDist := dist
                targetMon := A_Index
            }
        }
    }
    
    if (!targetMon)
        return false
        
    ; Centre on the WORK AREA, not the whole monitor rect: centring on the full
    ; rect on a screen with a taskbar puts the bottom of the window underneath it.
    if !WorkAreaOf(targetMon, &mL, &mT, &mR, &mB)
        MonitorGet(targetMon, &mL, &mT, &mR, &mB)
    destX := mL + Round((mR - mL - W)/2)
    destY := mT + Round((mB - mT - H)/2)

    if !GetRects(hwnd, &curL, &curT, &curR, &curB, &curWinX, &curWinY)
        return false

    winDestX := curWinX + (destX - L)
    winDestY := curWinY + (destY - T)

    ; W and H arrive in FRAME space (SnapWindow passes R-L and B-T of the DWM
    ; extended frame bounds), but BounceSqueeze writes its w/h straight into
    ; RS_SetPos, which is WinMove space. Those differ by the invisible resize
    ; border, so handing the frame size over shrank the window by ~14px on every
    ; single monitor throw - and it never grew back, so repeated throws walked it
    ; smaller and smaller. The window's own rect IS the WinMove size, so read it
    ; rather than deriving it.
    bounceW := W, bounceH := H
    try WinGetPos(, , &bounceW, &bounceH, hwnd)

    Glide(hwnd, curWinX, curWinY, winDestX, winDestY, () => BounceSqueeze(hwnd, winDestX, winDestY, bounceW, bounceH, vx > 0 ? 10 : (vx < 0 ? -10 : 0), 0))
    return true
}

ShowSeamFlash(x, y, w, h) {
    if (w < 1)
        w := 1
    if (h < 1)
        h := 1

    flash := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "SeamFlash")
    flash.BackColor := "00E5FF"
    flash.MarginX := 0, flash.MarginY := 0
    flash.Show("x" x " y" y " w" w " h" h " NoActivate")

    ; Pass the Gui object, not just its handle. The animation outlives this
    ; function, and handing over only the HWND left nothing holding a reference
    ; to the object for those 192 ms.
    FadeSeam(flash, x, y, w, h)
}

FadeSeam(flashGui, x, y, w, h) {
    hwnd := flashGui.Hwnd
    animKey := "FadeSeam_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animSeamMs")   ; duration in ms; never derive this from a frame count

    SeamStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            ; Destroy, not WinClose: WinClose only posts WM_CLOSE and leaves the
            ; Gui alive. One of these is created on every single snap, so a
            ; leaked window here is a leak that grows all session.
            try flashGui.Destroy()
            RS_RemoveHwnd(hwnd)
            return false
        }

        alpha := Round(255 * (1 - t*t))

        if (w < h) {
            shrink := Round(h * t * 0.3)
            RS_SetPos(hwnd, x, y + shrink, w, h - shrink*2, RS_PRI_ANIM)
        } else {
            shrink := Round(w * t * 0.3)
            RS_SetPos(hwnd, x + shrink, y, w - shrink*2, h, RS_PRI_ANIM)
        }

        RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, SeamStep)
}

; Cheaper than WinMove per frame, and leaves z-order and focus alone mid-slide.
; Now delegates to the render pipeline for batched application.
MoveFast(hwnd, x, y) {
    RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_ANIM)
}

Clamp(v, lo, hi) => (v < lo) ? lo : (v > hi) ? hi : v

; A throw must not fling a window off into nowhere.
KeepOnScreen(hwnd, &L, &T, &R, &B, tx, ty) {
    w := R - L, h := B - T

    if (tx != 0 || ty != 0) {
        hmon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if (hmon) {
            monInfo := Buffer(40)
            NumPut("uint", 40, monInfo)
            if DllCall("GetMonitorInfo", "ptr", hmon, "ptr", monInfo) {
                wl := NumGet(monInfo, 20, "int")
                wt := NumGet(monInfo, 24, "int")
                wr := NumGet(monInfo, 28, "int")
                wb := NumGet(monInfo, 32, "int")
                L := Clamp(L, wl, wr - w)
                T := Clamp(T, wt, wb - h)
                R := L + w, B := T + h
                return
            }
        }
    }

    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    margin := 120
    L := Clamp(L, vx - w + margin, vx + vw - margin)
    T := Clamp(T, vy, vy + vh - margin)
    R := L + w, B := T + h
}

; =========================================================== Position memory ===========================================================
IsRestorable(hwnd) {
    if !IsSnappable(hwnd)
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")        ; GW_OWNER
        return false
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return false
            
        title := WinGetTitle(hwnd)
        if RegExMatch(title, "i)^(Picture.?in.?Picture|PiP|Картинка в картинке|Resim içinde resim|Şəkil içində şəkil)$")
            return false
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        ; Browser PiP windows (or popups) often don't have the standard title if localized, 
        ; but they are typically Always-On-Top (0x8) and lack a Maximize Box (0x10000).
        if ((exStyle & 0x8) && !(style & 0x10000)) {
            exe := WinGetProcessName(hwnd)
            if RegExMatch(exe, "i)^(chrome|msedge|firefox|brave|opera|vivaldi)\.exe$")
                return false
        }
            
        ; Every AutoHotkey GUI shares one class, so a single saved entry would
        ; drag every unrelated AHK window to the same spot.
        if (WinGetClass(hwnd) = "AutoHotkeyGUI")
            return false
        if (exStyle & 0x80)                                       ; WS_EX_TOOLWINDOW
            return false
        if !(style & 0x00040000)                                  ; WS_THICKFRAME
            return false
    } catch
        return false
    return true
}

WindowKey(hwnd) {
    try {
        exe := WinGetProcessName(hwnd)
        cls := WinGetClass(hwnd)
    } catch
        return ""
    return SubStr(RegExReplace(exe "_" cls, "[^A-Za-z0-9_]", ""), 1, 80)
}

global WindowCmdLineCache := Map()

GetProcessCommandLine(pid, hwnd) {
    global WindowCmdLineCache
    if WindowCmdLineCache.Has(hwnd)
        return WindowCmdLineCache[hwnd]

    ; The locator is built once. ComObjGet("winmgmts:") connects to the WMI
    ; service, and doing that per window made an already expensive query worse;
    ; this runs from HandleNewWindow's timer, so every millisecond is a stalled
    ; frame. Cached in a static, rebuilt if the service connection goes away.
    static wmi := ""
    cmdLine := ""
    try {
        if !wmi
            wmi := ComObjGet("winmgmts:")
        for proc in wmi.ExecQuery("Select CommandLine from Win32_Process where ProcessId=" pid) {
            cmdLine := proc.CommandLine
            break
        }
    } catch {
        wmi := ""
    }
    
    if DllCall("IsWindow", "ptr", hwnd)
        WindowCmdLineCache[hwnd] := cmdLine
        
    return cmdLine
}

IsMainApplicationWindow(hwnd) {
    return ClassifyWindowImpl(hwnd) == "Main"
}

ClassifyWindowImpl(hwnd) {
    try {
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            return "Transient"
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        if !(style & 0x00040000)
            return "Transient"
            
        if !(style & 0x10000000)
            return "Transient"
            
        if (style & 0x80000000)
            return "Transient"
            
        if (exStyle & 0x80)
            return "Transient"
            
        if IsCloaked(hwnd)
            return "Transient"

        title := WinGetTitle(hwnd)
        
        ; DISTINCTIVE phrases only.
        ;
        ; This list used to contain the bare words Settings, Options, Open,
        ; Print, About, Properties, Account, License, Loading, Progress, Trial,
        ; Welcome, Subscription and Wizard, matched anywhere in the title. Those
        ; are ordinary words in ordinary MAIN window titles - "Options - Mozilla
        ; Firefox", a VS Code "Settings" tab, any document named Account.xlsx -
        ; so position memory was silently switched off for a large slice of real
        ; windows, with nothing to tell the user why their app kept reopening in
        ; the wrong place.
        ;
        ; The generic single words are gone. What remains is multi-word or
        ; unambiguous. The structural tests above (owned window, no thick frame,
        ; tool window, cloaked) already reject most real dialogs, so this list
        ; only has to catch the ones that look structurally like a main window.
        static transientTitles := "i)\b(Getting Started|What's New|First Run|First Launch|Welcome Back"
            . "|Log In|Sign In|Two Factor|Security Check|Account Selection|Account Picker|User Selection|Profile Selection"
            . "|Chrome Profile Picker|Chrome Welcome|Chrome First Run|Chrome Sign In"
            . "|Edge Profile Picker|Edge Welcome|Edge First Run|Firefox Profile Manager|Brave Welcome|Opera Welcome|Arc Onboarding"
            . "|Configuration Wizard|Setup Wizard|InstallShield|MSI Installer|Inno Setup"
            . "|Downloading Update|Installing Update|Patch Installer|Version Upgrade"
            . "|Product Activation|License Activation|Subscription Activation"
            . "|Splash Screen|Boot Screen"
            . "|Profile Picker|User Picker|Folder Picker|File Picker|Color Picker|Font Picker|Emoji Picker|Device Picker|Printer Picker"
            . "|Settings Dialog|Message Box"
            . "|Permission Request|Allow Access|Administrator Prompt|Windows Security|Credential Dialog"
            . "|Visual Studio Installer|JetBrains Toolbox|Creative Cloud Installer|Office Installer|Epic Installer|Steam Installer|Riot Installer|EA Installer"
            . "|Steam Login|Discord Login|Slack Login|Teams Login|Zoom Login|Adobe Login|Epic Login|Battle\.net Login|Riot Login|Dropbox Login|OneDrive Login|Google Login|Apple Login"
            . "|Choose Profile|Save As|Choose Account|Choose Workspace|Workspace Picker|Device Setup|Connection Wizard)\b"
            
        if RegExMatch(title, transientTitles)
            return "Transient"

        pid := WinGetPID(hwnd)
        cmdLine := GetProcessCommandLine(pid, hwnd)
        static cmdLineArgs := "i)(--profile-picker|--first-run|--welcome|--setup|--installer|--install|--update|--updater|--repair|--activation|--login|--signin|--profile-manager)"
        
        if (cmdLine != "" && RegExMatch(cmdLine, cmdLineArgs))
            return "Transient"

    } catch {
        return "Transient"
    }

    return "Main"
}

; Pending position writes, keyed by window key. Same shape as SaveSettings ->
; WriteSettings, and for exactly the same measured reason: one IniWrite costs
; ~771 us, this wrote FOUR of them, and it runs at the end of every drag and
; again from OnSnapLanded - so ~3 ms of blocking disk I/O landed inside the drag
; pipeline, on the timer thread, stalling the frame loop that was mid-glide.
; Buffering makes it ~1 us; the flush happens 900 ms after the last drag.
global PendingPositions := Map()

RememberPosition(hwnd, forceX := "", forceY := "", forceW := "", forceH := "") {
    global RestoreEnabled, PendingPositions
    if (!RestoreEnabled || !IsRestorable(hwnd))
        return
    ; IsMainApplicationWindow is NOT consulted here any more. It reaches a WMI
    ; query (tens of milliseconds of blocking COM) through ClassifyWindowImpl,
    ; and this is an input path. The window was already classified when it was
    ; created - RestorePosition is the gate that matters - and a window we can
    ; snap is a window whose position is worth keeping.
    key := WindowKey(hwnd)
    if (key = "")
        return
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        if (forceX != "")
            x := forceX, y := forceY
        if (forceW != "")
            w := forceW, h := forceH
        if (w <= 0 || h <= 0)
            return
        PendingPositions[key] := {x: x, y: y, w: w, h: h}
        SetTimer(WritePositions, -900)
        WriteLog("  remembered " key " -> " x "," y " " w "x" h)
    }
}

; Bye() calls this directly: on the way out there is no idle for the one-shot.
WritePositions() {
    global PendingPositions, POS_FILE
    SetTimer(WritePositions, 0)
    if !PendingPositions.Count
        return
    pend := PendingPositions
    PendingPositions := Map()
    for key, r in pend {
        try {
            IniWrite(r.x, POS_FILE, key, "x")
            IniWrite(r.y, POS_FILE, key, "y")
            IniWrite(r.w, POS_FILE, key, "w")
            IniWrite(r.h, POS_FILE, key, "h")
        }
    }
}

; The shell tells us when a window is created, so there is no polling timer.
OnMessage(DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), ShellEvent)
; Explorer broadcasts TaskbarCreated to every top-level window when the shell
; restarts, and the shell-hook registration does NOT survive that. It used to be
; registered once at startup, so an Explorer crash - or this app's own "Restart
; Explorer" button - silently killed position memory, the open animations, focus
; pulse, breathing seeding, fly-to-mouse minimize and per-window cleanup for the
; rest of the session, with no error anywhere.
OnMessage(DllCall("RegisterWindowMessage", "str", "TaskbarCreated", "uint"), TaskbarCreated)
RegisterShellHook()

RegisterShellHook() {
    DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)
    return DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
}

TaskbarCreated(*) {
    ok := RegisterShellHook()
    WriteLog("explorer restarted - shell hook re-registered (" (ok ? "ok" : "FAILED") ")")
    ; The taskbar we recorded the auto-hide state of no longer exists.
    global SmartTaskbarEnabled, OriginalTaskbarState
    if (OriginalTaskbarState == -1)
        OriginalTaskbarState := GetTaskbarState()
    if SmartTaskbarEnabled
        SyncSmartTaskbar()
}

ShellEvent(wParam, lParam, *) {
    static HSHELL_WINDOWCREATED := 1
    static HSHELL_GETMINRECT := 5
    
    if ((wParam & 0x7FFF) = HSHELL_GETMINRECT) {
        global FlyMinimizeEnabled, BlackHoleMinimizeEnabled
        if (BlackHoleMinimizeEnabled) {
            rectOffset := A_PtrSize == 8 ? 8 : 4
            cx := Round(A_ScreenWidth / 2)
            cy := Round(A_ScreenHeight)
            NumPut("int", cx - 1, lParam, rectOffset)
            NumPut("int", cy - 1, lParam, rectOffset + 4)
            NumPut("int", cx + 1, lParam, rectOffset + 8)
            NumPut("int", cy + 1, lParam, rectOffset + 12)
            return 1
        } else if (FlyMinimizeEnabled) {
            MouseGetPos(&mx, &my)
            rectOffset := A_PtrSize == 8 ? 8 : 4
            NumPut("int", mx - 10, lParam, rectOffset)
            NumPut("int", my - 10, lParam, rectOffset + 4)
            NumPut("int", mx + 10, lParam, rectOffset + 8)
            NumPut("int", my + 10, lParam, rectOffset + 12)
            return 1
        }
    }
    
    if ((wParam & 0x7FFF) = 2) { ; HSHELL_WINDOWDESTROYED
        if (lParam) {
            global CustomTrans, RolledUpWindows, WinTargetAlpha, WinCurrentAlpha, WinLastActive, WindowCmdLineCache
            if WindowCmdLineCache.Has(lParam)
                WindowCmdLineCache.Delete(lParam)
            if CustomTrans.Has(lParam)
                CustomTrans.Delete(lParam)
            if RolledUpWindows.Has(lParam)
                RolledUpWindows.Delete(lParam)
            if WinTargetAlpha.Has(lParam)
                WinTargetAlpha.Delete(lParam)
            if WinCurrentAlpha.Has(lParam)
                WinCurrentAlpha.Delete(lParam)
            if WinLastActive.Has(lParam)
                WinLastActive.Delete(lParam)
            ; Focus Depth only ever removes the window being switched TO, so
            ; without this the map grows by one entry for every window the user
            ; has focused away from and never returned to, for the whole session.
            global PushedBackWindows
            if PushedBackWindows.Has(lParam)
                PushedBackWindows.Delete(lParam)
            ; Same reasoning for the two layout maps: nothing else ever removes
            ; from them, so without this they grow by one entry per window the
            ; user has ever tiled or resized, for the whole session.
            global LayoutUndo, SizeCycleIdx
            if LayoutUndo.Has(lParam)
                LayoutUndo.Delete(lParam)
            if SizeCycleIdx.Has(lParam)
                SizeCycleIdx.Delete(lParam)
            RS_RemoveHwnd(lParam)
            MC_RemoveHwnd(lParam)      ; MediaCore caches pid/exe per HWND forever otherwise
        }
    }

    if ((wParam & 0x7FFF) = 4) { ; HSHELL_WINDOWACTIVATED
        if (lParam) {
            if !BottomWindows.Has(lParam) {
                PulseWindow(lParam)
            }
            
            global FocusDepthEnabled
            if (FocusDepthEnabled) {
                ApplyFocusDepth(lParam)
            }
            
            global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha, CustomTrans
            if (BreathingEnabled && IsRestorable(lParam) && !WinLastActive.Has(lParam)) {
                baseAlpha := CustomTrans.Has(lParam) ? CustomTrans[lParam] : 255
                WinLastActive[lParam] := QPC()
                WinCurrentAlpha[lParam] := baseAlpha
                WinTargetAlpha[lParam] := baseAlpha
            }
        }
    }

    if ((wParam & 0x7FFF) = HSHELL_WINDOWCREATED) {
        global OpenAnim, GhostHiddenWindows, BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha, CustomTrans
        hwnd := lParam
        if (BreathingEnabled && IsRestorable(hwnd)) {
            baseAlpha := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255
            WinLastActive[hwnd] := QPC()
            WinCurrentAlpha[hwnd] := baseAlpha
            WinTargetAlpha[hwnd] := baseAlpha
        }
        
        ; Only hide a window we are definitely going to animate back.
        ;
        ; This used to hide every un-owned new top-level window and decide
        ; afterwards, in HandleNewWindow, whether to animate it - and the "no
        ; animation after all" branch was the one that queued the reveal without
        ; committing it. Anything not restorable (a dialog, a fixed-size window,
        ; a window that opens maximized, our own settings window) was therefore
        ; left at alpha 0: focused, clickable and completely invisible.
        ;
        ; It also forced WS_EX_LAYERED onto arbitrary foreign windows, which for
        ; a GPU-composited or full-screen one costs a redirection surface and can
        ; break exclusive full-screen presentation. Nothing we then chose not to
        ; animate should ever have paid that.
        if (OpenAnim != "None" && WillAnimateOpen(hwnd)) {
            try {
                RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
                RS_Commit()
                GhostHiddenWindows[hwnd] := true
            }
        }
        SetTimer(() => HandleNewWindow(hwnd), -250)
    }
}

; The one eligibility test, used both before hiding a new window and before
; animating it, so the two can never disagree.
WillAnimateOpen(hwnd) {
    if !hwnd
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")     ; GW_OWNER
        return false
    if !IsRestorable(hwnd)
        return false
    try {
        if (WinGetMinMax(hwnd) != 0)
            return false
    } catch
        return false
    return true
}

RestorePosition(hwnd) {
    global RestoreEnabled, POS_FILE
    if (!RestoreEnabled || !DllCall("IsWindow", "ptr", hwnd))
        return
    if (!IsRestorable(hwnd) || !IsMainApplicationWindow(hwnd))
        return
    key := WindowKey(hwnd)
    if (key = "")
        return
    ; All four must be present and numeric. RememberPosition writes them as four
    ; separate IniWrites inside one try, so a failure part-way leaves a section
    ; with x but no h - and Integer("") throws from this timer callback, which
    ; surfaces as an error dialog every time that app opens a window.
    x := IniRead(POS_FILE, key, "x", "")
    y := IniRead(POS_FILE, key, "y", "")
    w := IniRead(POS_FILE, key, "w", "")
    h := IniRead(POS_FILE, key, "h", "")
    if !(IsInteger(x) && IsInteger(y) && IsInteger(w) && IsInteger(h))
        return

    rx := Integer(x), ry := Integer(y), rw := Integer(w), rh := Integer(h)
    if (rw <= 0 || rh <= 0)          ; a zero-size WinMove would collapse the window
        return

    try {
        exe := WinGetProcessName(hwnd)
        cls := WinGetClass(hwnd)
        
        loop 20 {
            conflict := false
            for other in WinGetList("ahk_class " cls " ahk_exe " exe) {
                if (other = hwnd)
                    continue
                if !DllCall("IsWindowVisible", "ptr", other)
                    continue
                try {
                    WinGetPos(&ox, &oy, &ow, &oh, other)
                    if (Abs(ox - rx) < 5 && Abs(oy - ry) < 5) {
                        conflict := true
                        rx += 30
                        ry += 30
                        break
                    }
                }
            }
            if (!conflict)
                break
        }
    } catch {
    }

    ; Ensure it restores on-screen. Guarded: a monitor can be removed between the
    ; count and the query, and this runs from a timer.
    try {
        intersecting := false
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
            if (rx < wr && rx + rw > wl && ry < wb && ry + rh > wt) {
                intersecting := true
                break
            }
        }
        if (!intersecting) {
            MonitorGetWorkArea(1, &wl, &wt, &wr, &wb)
            if (rw > wr - wl)
                rw := wr - wl
            if (rh > wb - wt)
                rh := wb - wt
            rx := wl + 40
            ry := wt + 40
        }
    }


    try {
        RS_SetPos(hwnd, rx, ry, rw, rh, RS_PRI_USER)
        RS_Commit()
        WriteLog("restored " key " -> " rx "," ry " " rw "x" rh)
        return {x: rx, y: ry, w: rw, h: rh}
    }
}

global GhostHiddenWindows := Map()

HandleNewWindow(hwnd) {
    global OpenAnim, GhostHiddenWindows
    isHidden := GhostHiddenWindows.Has(hwnd)
    if isHidden
        GhostHiddenWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd) {
        RS_RemoveHwnd(hwnd)
        return
    }

    restoredRect := RestorePosition(hwnd)

    if !isHidden
        return

    ; Re-check: 250 ms is long enough for the window to have been maximized,
    ; closed or restyled since we hid it.
    if (OpenAnim != "None" && WillAnimateOpen(hwnd)) {
        if (OpenAnim == "Ghost Slide-In")
            GhostSlideIn(hwnd, restoredRect)
        else if (OpenAnim == "Portal Scale-In")
            PortalScaleIn(hwnd, restoredRect)
        else if (OpenAnim == "Window Unrolling")
            UnrollWindow(hwnd, restoredRect)
        ; Belt and braces: if the animation callback dies before its final
        ; "Off", this un-hides the window anyway. A window we made invisible
        ; must never be able to stay that way.
        SetTimer(RevealWindow.Bind(hwnd), -1200)
        return
    }

    RevealWindow(hwnd)
}

RevealWindow(hwnd) {
    global CustomTrans, GhostWindows
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    ; Do not stomp an opacity the user asked for in the meantime.
    if (CustomTrans.Has(hwnd) || GhostWindows.Has(hwnd))
        return
    try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
    RS_Commit()
}

UnrollWindow(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    ; Reveal first, then clip: the region does the animating here, so the window
    ; must be opaque from the first frame.
    try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)

    animKey := "Unroll_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    UnrollStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            try RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) * (1 - t)
        curH := Round(h * ease)
        if (curH < 1)
            curH := 1
            
        try RS_SetRegion(hwnd, "0-0 W" w " H" curH, RS_PRI_ANIM)
        return true
    }
    
    RegisterAnimation(animKey, UnrollStep)
}

GhostSlideIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }


    startY := y + Tune("animOpenSlide")
    endY := y
    
    MoveFast(hwnd, x, startY)
    RS_Commit()
    
    animKey := "GhostSlideIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    GhostSlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            MoveFast(hwnd, x, endY)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) * (1 - t) ; ease-out
        curY := Round(startY + (endY - startY) * ease)
        MoveFast(hwnd, x, curY)
        
        alpha := Round(255 * ease)
        try RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    
    RegisterAnimation(animKey, GhostSlideStep)
}

PortalScaleIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    animKey := "PortalScaleIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    cX := x + w / 2
    cY := y + h / 2
    
    try RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
    RS_SetPos(hwnd, Round(cX - (w * 0.8) / 2), Round(cY - (h * 0.8) / 2), Round(w * 0.8), Round(h * 0.8), RS_PRI_ANIM)
    RS_Commit()
    
    PortalScaleStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        scale := 0.8 + 0.2 * ease
        
        curW := Round(w * scale)
        curH := Round(h * scale)
        curX := Round(cX - curW / 2)
        curY := Round(cY - curH / 2)
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        
        alpha := Round(255 * (t > 0.4 ? 1 : (t / 0.4)))
        try RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    
    RegisterAnimation(animKey, PortalScaleStep)
}

global PulsingWindows := Map()

PulseWindow(hwnd) {
    global PulseEnabled, PulsingWindows
    if (!PulseEnabled || !DllCall("IsWindow", "ptr", hwnd) || !IsRestorable(hwnd))
        return

    try {
        if (WinGetMinMax(hwnd) != 0) ; skip maximized/minimized
            return
    } catch
        return

    global ActiveAnimations
    ; Never pulse a window that is still being flown somewhere.
    ;
    ; Pulse_<hwnd> and Glide_<hwnd> both write RS_Pos[hwnd] at RS_PRI_ANIM, and
    ; equal priority means last-writer-wins within a flush. AHK enumerates a Map
    ; sorted by key, so "Pulse_" is produced after "Glide_" and won every frame -
    ; and worse, PulseStep captured x/y/w/h at activation, i.e. a MID-GLIDE
    ; position, then restored the window to it on its final frame. Activating a
    ; window mid-snap threw away the snap. Same guard idiom as VerifySnap.
    animKey := "Pulse_" hwnd
    if (ActiveAnimations.Has("Glide_" hwnd) || ActiveAnimations.Has("Bounce_" hwnd))
        return
    if PulsingWindows.Has(hwnd) {
        ; A callback dropped by the scheduler (it swallows exceptions) would
        ; leave this flag set forever and that window could never pulse again.
        if ActiveAnimations.Has(animKey)
            return
        PulsingWindows.Delete(hwnd)
    }

    PulsingWindows[hwnd] := true

    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        PulsingWindows.Delete(hwnd)
        return
    }

    ; The 12 px cap stays internal: it stops the pulse from throwing a
    ; full-screen window several centimetres, which is a property of the
    ; effect, not a preference.
    grow := Tune("animPulse") / 100
    pw := Min(Round(w * grow), 12)
    ph := Min(Round(h * grow), 12)

    start := QPC()
    ms := Tune("animPulseMs")

    ; Same story as the bounce: this was three hard-coded stages at 16/32/48 ms,
    ; which is 3 frames - not an animation so much as a flicker, and it assumed a
    ; frame was exactly 16 ms. sin(pi*t) over 190 ms grows out from the centre and
    ; settles back, which is the single "breath" a macOS focus cue gives you.
    lastX := -99999, lastY := -99999
    PulseStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            PulsingWindows.Delete(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            PulsingWindows.Delete(hwnd)
            return false
        }

        e := Sin(3.14159265 * t)
        gx := Round(pw * e)
        gy := Round(ph * e)
        nx := x - gx, ny := y - gy
        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, w + gx * 2, h + gy * 2, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    RegisterAnimation(animKey, PulseStep)
}

; ====== Multi-Monitor Focus Dimmer ======
SyncDimmerTimer() {
    global MultiMonitorDimmerEnabled, DimmerGuis
    if (MultiMonitorDimmerEnabled) {
        SetTimer(MonitorDimmerTickStep, 200)
    } else {
        SetTimer(MonitorDimmerTickStep, 0)
        for k, g in DimmerGuis {
            FadeGui(g, 0, 0, true)
        }
        DimmerGuis.Clear()
    }
    SyncMediaCore()
}
SyncDimmerTimer()

MonitorDimmerTickStep(dt:=0, now:=0) {
    global MultiMonitorDimmerEnabled, DimmerGuis
    
    if (!MultiMonitorDimmerEnabled)
        return
        
    try count := MonitorGetCount()
    catch
        return
        
    if (count < 2)
        return
        
    try {
        MouseGetPos(&mx, &my)
        activeMon := 1
        ; Exclusive on right/bottom, like MonitorIndexAt. Inclusive bounds make
        ; the shared edge belong to both monitors, so a cursor sitting exactly on
        ; the seam kept the neighbouring monitor un-dimmed.
        activeMon := MonitorIndexAt(mx, my)
        
        Loop count {
            if (A_Index == activeMon || MC_MediaOnMonitor(A_Index)) {
                if DimmerGuis.Has(A_Index) {
                    g := DimmerGuis[A_Index]
                    DimmerGuis.Delete(A_Index)
                    FadeGui(g, 0, 0, true)
                }
            } else {
                if !DimmerGuis.Has(A_Index) {
                    MonitorGet(A_Index, &L, &T, &R, &B)
                    g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20 +E0x8000000")
                    g.BackColor := "000000"
                    RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
                    RS_Commit()
                    g.Show("NoActivate x" L " y" T " w" (R-L) " h" (B-T))
                    DimmerGuis[A_Index] := g
                    FadeGui(g, TuneAlpha("dimmerAlpha"))
                }
            }
        }
    }
}

; ====== macOS Quick Look ======
IsTypingInExplorer() {
    try {
        ctrl := ControlGetClassNN(ControlGetFocus("A"))
        if (InStr(ctrl, "Edit") || InStr(ctrl, "Search") || InStr(ctrl, "Windows.UI.Core.CoreWindow"))
            return true
    }
    return false
}

GetSelectedExplorerFile() {
    try {
        hwnd := WinExist("A")
        for window in ComObject("Shell.Application").Windows {
            if (window.HWND == hwnd) {
                sel := window.Document.SelectedItems
                if (sel.Count > 0)
                    return sel.Item(0).Path
            }
        }
    }
    return ""
}

ToggleQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        CloseQuickLook()
        return true
    }
    path := GetSelectedExplorerFile()
    if (!path || !FileExist(path) || InStr(FileExist(path), "D"))
        return false 
        
    ; Build into a local and only publish it once there is something to show.
    ; Assigning QuickLookGui up front and then returning false for an unsupported
    ; extension left a created-but-never-shown window in the global, which made
    ; the next Space press take the "close it" branch and swallow the keystroke -
    ; so Space alternated between working and doing nothing.
    ext := StrLower(RegExReplace(path, ".*\.([^.]+)$", "$1"))
    if !(ext ~= "^(png|jpg|jpeg|gif|bmp|txt|md|ini|ahk|csv|log|json|xml|ps1|bat|cmd)$")
        return false

    g := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound +Border -DPIScale")
    g.BackColor := "111111"
    g.MarginX := 20
    g.MarginY := 20

    try {
        if (ext ~= "^(png|jpg|jpeg|gif|bmp)$")
            g.AddPicture("w-1 h-1", path)
        else
            g.AddEdit("w600 h400 ReadOnly Background111111 cWhite -E0x200", FileRead(path, "m4096"))
    } catch {
        try g.Destroy()
        return false
    }

    QuickLookGui := g
    RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
    RS_Commit()
    g.Show("NoActivate AutoSize Center")
    FadeGui(g, 255)
    SetTimer(CheckQuickLookFocusStep, 100)
    return true
}

CloseQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        SetTimer(CheckQuickLookFocusStep, 0)
        guiObj := QuickLookGui
        QuickLookGui := "" 
        FadeGui(guiObj, 0, 0, true)
    }
}

CheckQuickLookFocusStep() {
    global QuickLookGui
    if !QuickLookGui {
        SetTimer(CheckQuickLookFocusStep, 0)
        return
    }

    ahwnd := WinExist("A")
    ; WinGetClass(0) throws, and an uncaught throw in a timer thread pops an
    ; error dialog and kills the timer. There is routinely no active window at
    ; all - during a desktop switch, or on the lock screen.
    cls := ""
    if ahwnd
        try cls := WinGetClass(ahwnd)
    if (ahwnd != QuickLookGui.Hwnd && cls != "CabinetWClass")
        CloseQuickLook()
}

; ====== Smart Auto-Hide Taskbar ======
global SmartTaskbarLastState := -1

SyncSmartTaskbar() {
    global SmartTaskbarEnabled, SmartTaskbarLastState
    ; Reset the remembered state on every toggle. As a `static` inside the monitor
    ; it survived being switched off and on again, so the first evaluation after a
    ; re-enable could match the stale value and skip applying anything.
    SmartTaskbarLastState := -1
    if (SmartTaskbarEnabled)
        SetTimer(SmartTaskbarMonitorStep, 200)
    else
        SetTimer(SmartTaskbarMonitorStep, 0)
}
SyncSmartTaskbar()

SmartTaskbarMonitorStep() {
    global SmartTaskbarEnabled, SmartTaskbarLastState

    if !SmartTaskbarEnabled
        return
        
    try {
        tbHwnd := WinExist("ahk_class Shell_TrayWnd")
        if !tbHwnd
            return
            
        ; Get taskbar height
        WinGetPos(,, &tw, &th, tbHwnd)
        if (th < 10)
            th := 48 ; Fallback
            
        ; The primary monitor, not enumeration index 1 - Shell_TrayWnd is the
        ; PRIMARY taskbar, and on many setups those are different screens, which
        ; made every window test below compare against the wrong rectangle.
        MonitorGet(MonitorGetPrimary(), &ML, &MT, &MR, &MB)
        tbActiveTop := MB - th
        
        shouldHide := false
        hwnds := WinGetList()
        for hwnd in hwnds {
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
            ; Read the window state ONCE. It was queried again below for the
            ; maximized test - two cross-process calls per window, five times a
            ; second, for one piece of information.
            mm := WinGetMinMax(hwnd)
            if (mm == -1) ; Minimized
                continue
                
            cls := WinGetClass(hwnd)
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
                continue
                
            if (WinGetExStyle(hwnd) & 0x80) ; WS_EX_TOOLWINDOW
                continue
                
            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            if (ww == 0 || wh == 0)
                continue
                
            ; Check if on primary monitor
            if (wx >= MR || wx + ww <= ML || wy >= MB || wy + wh <= MT)
                continue
                
            if (mm == 1 || wy + wh > tbActiveTop) {
                shouldHide := true
                break
            }
        }
        
        if (shouldHide != SmartTaskbarLastState) {
            SetTaskbarAutoHide(shouldHide)
            SmartTaskbarLastState := shouldHide
        }
    }
}

GetTaskbarState() {
    try {
        cbSize := A_PtrSize == 8 ? 48 : 36
        abd := Buffer(cbSize, 0)
        NumPut("uint", cbSize, abd, 0)
        hwnd := WinExist("ahk_class Shell_TrayWnd")
        if !hwnd
            return -1
        NumPut("ptr", hwnd, abd, A_PtrSize == 8 ? 8 : 4)
        return DllCall("Shell32\SHAppBarMessage", "uint", 4, "ptr", abd)
    }
    return -1
}

SetTaskbarAutoHide(hide) {
    try {
        cbSize := A_PtrSize == 8 ? 48 : 36
        abd := Buffer(cbSize, 0)
        NumPut("uint", cbSize, abd, 0)
        hwnd := WinExist("ahk_class Shell_TrayWnd")
        if !hwnd
            return
        NumPut("ptr", hwnd, abd, A_PtrSize == 8 ? 8 : 4)
        NumPut("ptr", hide ? 1 : 2, abd, A_PtrSize == 8 ? 40 : 32)
        DllCall("Shell32\SHAppBarMessage", "uint", 10, "ptr", abd)
    }
}

; ====== macOS Hot Corners ======
SyncHotCornersTimer() {
    global HotCornersEnabled
    if (HotCornersEnabled)
        SetTimer(HotCornersMonitorStep, 50)
    else
        SetTimer(HotCornersMonitorStep, 0)
}
SyncHotCornersTimer()

SyncCursorWrapTimer() {
    global InfiniteWrapEnabled
    if (InfiniteWrapEnabled)
        SetTimer(CursorWrapMonitorStep, 20)
    else
        SetTimer(CursorWrapMonitorStep, 0)
}
SyncCursorWrapTimer()

; Virtual-screen metrics, cached. This runs 50 times a second; four SysGet calls
; plus a monitor enumeration per tick bought nothing, because the answer only
; changes when the display configuration does - and WM_DISPLAYCHANGE tells us.
global ScreenGeom := ""

ScreenMetrics() {
    global ScreenGeom
    if !IsObject(ScreenGeom) {
        vLeft := SysGet(76), vTop := SysGet(77)
        vWidth := SysGet(78), vHeight := SysGet(79)
        mons := []
        try {
            loop MonitorGetCount() {
                MonitorGet(A_Index, &L, &T, &R, &B)
                mons.Push({l: L, t: T, r: R, b: B})
            }
        }
        ScreenGeom := {left: vLeft, top: vTop, width: vWidth, height: vHeight
                     , right: vLeft + vWidth, bottom: vTop + vHeight, mons: mons}
    }
    return ScreenGeom
}

OnMessage(0x007E, InvalidateScreenMetrics)     ; WM_DISPLAYCHANGE
InvalidateScreenMetrics(*) {
    global ScreenGeom, DimmerGuis, FocusModeEnabled, FocusBounds, FocusGuis
    ScreenGeom := ""

    ; Dropping the cache is not enough - the overlays SIZED from it are still on
    ; screen at the old geometry. After a resolution change or a monitor being
    ; plugged in, the dimmers covered the wrong rectangles and the focus vignette
    ; left a bright band down whatever the desktop had just gained.
    ;
    ; Dimmers are cheap to rebuild: drop them and let the 200 ms tick recreate
    ; them against the new layout on its next pass.
    for k, g in DimmerGuis
        try GuiDestroy(g)
    DimmerGuis.Clear()

    ; The focus overlays cannot be dropped - they ARE focus mode - so resize them
    ; in place and re-anchor the region maths to the new virtual screen.
    if (FocusModeEnabled && FocusGuis.Length) {
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        for layer in FocusGuis
            try RS_SetPos(layer.gui.Hwnd, vx, vy, vw, vh, RS_PRI_ANIM)
        RS_Commit()
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
    }
}

; Teleport the cursor across the outer edges of the virtual desktop - but only
; when the user clearly meant it.
;
; The original was a single stateless test: "is x at the outermost pixel column?
; then jump". That fires on any contact whatsoever with the outer edge, and the
; outer edge is somewhere the pointer lands constantly - throwing it left to hit
; a Back button, a window's close box, a scrollbar, the Start button. Windows
; clamps the pointer at the edge, so a fast reach parks it there for several
; ticks and the jump was indistinguishable from a deliberate one. It also fired
; mid-drag, teleporting the cursor out from under a window being moved.
;
; Intent is inferred from three things, all of which must hold:
;
;   1. APPROACH SPEED at the moment of contact. A deliberate push arrives fast;
;      a pointer that drifted to the edge while the user read something does not.
;      Sampled from the tick before contact, because once the pointer is clamped
;      at the edge its measured speed is zero by definition.
;   2. DWELL. It must stay in the band for wrap.delay. Leaving resets the state,
;      so a glance off the edge never accumulates toward a wrap.
;   3. COOLDOWN since the last wrap, so one gesture cannot chain.
;
; Setting wrap.speed or wrap.delay to 0 disables that gate on its own, which is
; how the old instant behaviour stays reachable.
;
; Suppression while a mouse button is down is NOT configurable: teleporting the
; cursor mid-drag is never what anyone wants, and HotCornersMonitorStep already
; sets that precedent.
CursorWrapMonitorStep() {
    global InfiniteWrapEnabled, DragHwnd
    static lastX := 0, lastY := 0, lastAt := 0     ; previous sample, for speed
    static contactAt := 0                          ; when the current contact began
    static contactSide := 0                        ; -1 left, +1 right, 0 none
    static approachOk := false                     ; speed gate passed on contact
    static cooldownUntil := 0

    if (!InfiniteWrapEnabled)
        return

    now := A_TickCount
    MouseGetPos(&mx, &my)

    prevX := lastX, prevY := lastY, prevAt := lastAt
    lastX := mx, lastY := my, lastAt := now

    ; A drag is in progress: no wrapping, and no state either - releasing the
    ; button at the edge must not count as a completed dwell.
    if (DragHwnd || GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
        || GetKeyState("MButton", "P")) {
        contactSide := 0
        return
    }

    g := ScreenMetrics()
    tol := Tune("wrapTol")

    ; The rightmost addressable column is right-1, so the right band is measured
    ; from there. Getting this wrong by one is the difference between a band of
    ; `tol` pixels and one that can never be entered at all.
    side := 0
    if (mx <= g.left + tol)
        side := -1
    else if (mx >= g.right - 1 - tol)
        side := 1

    if (!side) {
        contactSide := 0
        return
    }
    if (now < cooldownUntil)
        return

    if (side != contactSide) {
        ; First tick of this contact. Judge the approach from the movement that
        ; brought us here.
        contactSide := side
        contactAt := now
        minSpeed := Tune("wrapSpeed")
        approachOk := (minSpeed <= 0)
        if (!approachOk && prevAt && now > prevAt) {
            dist := Sqrt((mx - prevX) ** 2 + (my - prevY) ** 2)
            approachOk := (dist * 1000 / (now - prevAt)) >= minSpeed
        }
        return
    }

    if (!approachOk)
        return
    if (now - contactAt < Tune("wrapDelay"))
        return

    ; Land clear of the band we just left, or the destination would satisfy the
    ; contact test immediately and the pointer would sit armed on the far edge.
    inset := tol + 8
    tx := (side < 0) ? (g.right - 1 - inset) : (g.left + inset)
    ty := my

    ; The virtual desktop is a bounding box, not a surface: with monitors of
    ; different heights or vertical offsets, (tx, ty) can land in a hole. Project
    ; onto the nearest monitor that spans tx. Bounds are exclusive on the right
    ; and bottom, matching MonitorIndexAt and MC_MonitorIndexForRect.
    inside := false
    for m in g.mons {
        if (tx >= m.l && tx < m.r && ty >= m.t && ty < m.b) {
            inside := true
            break
        }
    }
    if (!inside) {
        bestDy := 0, bestY := "", edgePad := 5
        for m in g.mons {
            if (tx < m.l || tx >= m.r)
                continue
            if (ty < m.t)
                dy := m.t - ty, projY := m.t + edgePad
            else if (ty >= m.b)
                dy := ty - m.b + 1, projY := m.b - 1 - edgePad
            else
                dy := 0, projY := ty
            if (bestY == "" || dy < bestDy)
                bestDy := dy, bestY := projY
        }
        ; No monitor spans tx at all - the arrangement has no surface on that
        ; side at this height. Refuse rather than teleport into nothing.
        if (bestY == "") {
            contactSide := 0
            return
        }
        ty := bestY
    }

    MouseMove(tx, ty, 0)
    cooldownUntil := now + Tune("wrapCool")
    contactSide := 0
    lastX := tx, lastY := ty
}

HotCornersMonitorStep() {
    global HotCornersEnabled, HotCornerTL, HotCornerTR, HotCornerBL, HotCornerBR
    static LastCorner := "None", EnteredAt := 0, Fired := false

    if (!HotCornersEnabled)
        return

    try {
        if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P") || GetKeyState("MButton", "P"))
            return
            
        MouseGetPos(&mx, &my)

        g := ScreenMetrics()
        count := g.mons.Length
        activeMon := 1
        Loop count {
            m := g.mons[A_Index]
            L := m.l, T := m.t, R := m.r, B := m.b
            if (mx >= L && mx <= R - 1 && my >= T && my <= B - 1) {
                activeMon := A_Index
                break
            }
        }
        
        m := g.mons[activeMon]
        L := m.l, T := m.t, R := m.r, B := m.b

        currentCorner := "None"
        thresh := Tune("cornerSize")
        
        if (mx <= L + thresh && my <= T + thresh)
            currentCorner := "TL"
        else if (mx >= R - 1 - thresh && my <= T + thresh)
            currentCorner := "TR"
        else if (mx <= L + thresh && my >= B - 1 - thresh)
            currentCorner := "BL"
        else if (mx >= R - 1 - thresh && my >= B - 1 - thresh)
            currentCorner := "BR"
            
        ; Same dwell model as the cursor wrap, and for the same reason: a corner
        ; is where you throw the pointer to reach a close box or the Start
        ; button, so bare entry is not intent. EnteredAt is stamped on the first
        ; tick in a corner and the action waits for corners.delay; leaving resets
        ; it. Fired stops one dwell from re-firing every tick while the pointer
        ; stays parked there.
        if (currentCorner != LastCorner) {
            LastCorner := currentCorner
            EnteredAt := A_TickCount
            Fired := false
        }
        if (currentCorner == "None" || Fired)
            return
        if (A_TickCount - EnteredAt < Tune("cornerDelay"))
            return

        action := "None"
        if (currentCorner == "TL")
            action := HotCornerTL
        else if (currentCorner == "TR")
            action := HotCornerTR
        else if (currentCorner == "BL")
            action := HotCornerBL
        else if (currentCorner == "BR")
            action := HotCornerBR

        Fired := true
        if (action != "None")
            ExecuteHotCornerAction(action)
    }
}

ExecuteHotCornerAction(action) {
    if (action == "Task View")
        Send("#{Tab}")
    else if (action == "Show Desktop")
        Send("#d")
    else if (action == "Action Center")
        Send("#a")
    else if (action == "Start Menu")
        Send("{LWin}")
    else if (action == "Lock Screen")
        DllCall("user32\LockWorkStation")
    else if (action == "Mute Volume")
        Send("{Volume_Mute}")
}

; ====== Premium Volume OSD ======
ChangeVolumeOSD(dir) {
    try {
        stepPct := Tune("osdStep")
        SoundSetVolume((dir > 0 ? "+" : "-") stepPct)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

ToggleMuteOSD() {
    try {
        SoundSetMute(-1)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

GetVolumeOSDPos(&x, &visibleY, &hiddenY) {
    ; Not monitor 1: that is an enumeration index, not the primary, and the OSD
    ; answers a scroll over a taskbar that may be on any screen.
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    
    dpiScale := 1.0
    try {
        rect := Buffer(16)
        NumPut("Int", WL, "Int", WT, "Int", WR, "Int", WB, rect)
        if hMonitor := DllCall("MonitorFromRect", "Ptr", rect, "UInt", 2, "Ptr") {
            DllCall("Shcore\GetDpiForMonitor", "Ptr", hMonitor, "Int", 0, "UInt*", &dpiX:=0, "UInt*", &dpiY:=0)
            if dpiY
                dpiScale := dpiY / 96.0
        }
    }
    
    x := WL + (WR - WL - 280) // 2
    margin := Round(75 * dpiScale)
    visibleY := WB - 64 - margin
    hiddenY := WB + 10
}

ShowVolumeOSD(vol, isMuted) {
    global OsdGui, OsdHiding

    if (OsdGui) {
        ; Reuse the window even if it is mid-fade-out. Previously HideVolumeOSD
        ; cleared OsdGui immediately, so a notch during the 100 ms fade built a
        ; SECOND OSD on top of the one still fading - two semi-transparent copies
        ; at the same coordinates, which reads as a flicker. The shared fade key
        ; cancels the outgoing fade, and OsdFadeIn brings this one back.
        UpdateOSD(vol, isMuted)
        ; UpdateOSD destroys the window and clears OsdGui if any of its controls
        ; have gone. Everything below dereferences it, and NotchAnim's argument
        ; is evaluated OUTSIDE any try - so on that path an ordinary wheel notch
        ; over the taskbar popped an error dialog. Re-check, and rebuild on the
        ; next notch instead.
        if (!OsdGui)
            return
        try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
        if OsdHiding {
            OsdHiding := false
            ; Explicit fallback rather than a bare `try`: a failed WinGetPos leaves
            ; cy UNSET and NotchAnim reads it. The parked position is the right
            ; default - that is where a hidden OSD sits.
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            cy := hiddenY
            try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
            NotchAnim(OsdGui.Hwnd, cy, visibleY, true)
        }
    } else {
        try {
            OsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
            OsdGui.BackColor := "181818"
            RS_SetAlpha(OsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()


            OsdGui.SetFont("s24 cWhite", "Segoe UI Emoji")
            OsdGui.AddText("vIcon x15 y12 w40 h40 BackgroundTrans Center", GetSpeakerIcon(vol, isMuted))
            
            OsdGui.SetFont("s10 cWhite bold", "Segoe UI")
            pctStr := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
            OsdGui.AddText("vPct x55 y21 w50 h24 BackgroundTrans Right", pctStr)
            
            OsdGui.AddText("x115 y29 w150 h6 Background333333")
            w := Max(1, Round(150 * (vol / 100)))
            OsdGui.AddText("vBar x115 y29 w" w " h6 BackgroundFFFFFF")
            
            OsdGui.Show("NoActivate w280 h64")
            try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
            RS_SetRegion(OsdGui.Hwnd, "0-0 w280 h64 r20-20", RS_PRI_ANIM)
            
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            OsdGui.Move(x, y)
            
            NotchAnim(OsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; A plain one-shot, re-armed on every notch, so it hides 1.5 s after the LAST
    ; scroll. This was an entry in the animation scheduler, which meant 95 frames
    ; of the 15 ms loop - holding timeBeginPeriod(1) and running a full produce +
    ; flush pass - purely to compare two numbers. Nothing was animating.
    SetTimer(HideVolumeOSD, -Tune("osdHide"))
}

UpdateOSD(vol, isMuted) {
    global OsdGui
    try {
        OsdGui["Icon"].Text := GetSpeakerIcon(vol, isMuted)
        OsdGui["Pct"].Text := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
        w := Max(1, Round(150 * (vol / 100)))
        OsdGui["Bar"].Move(,, w)
        if (isMuted)
            OsdGui["Bar"].Opt("+Background555555")
        else
            OsdGui["Bar"].Opt("+BackgroundFFFFFF")
        OsdGui["Bar"].Redraw()
    } catch {
        try OsdGui.Destroy()
        OsdGui := ""
    }
}

GetSpeakerIcon(vol, isMuted) {
    if (isMuted || vol == 0)
        return "🔇"
    if (vol < 30)
        return "🔈"
    if (vol < 70)
        return "🔉"
    return "🔊"
}

HideVolumeOSD() {
    global OsdGui, OsdHiding
    if (!OsdGui)
        return
    OsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetVolumeOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
    NotchAnim(OsdGui.Hwnd, cy, hiddenY, false, ClearVolumeOSD)
}

ClearVolumeOSD() {
    global OsdGui, OsdHiding
    OsdGui := ""
    OsdHiding := false
}

; ====== Live Window PiP ======
OnMessage(0x0084, WM_NCHITTEST_PiP)

WM_NCHITTEST_PiP(wParam, lParam, msg, hwnd) {
    global PipGuis
    ; Runs for every WM_NCHITTEST on every window this process owns, which is
    ; every mouse move over the settings window and all the overlays. Bail out
    ; before touching anything when there are no PiP windows at all.
    if !PipGuis.Count
        return
    for src, pip in PipGuis {
        if (pip.Hwnd == hwnd) {
            x := lParam << 48 >> 48
            y := lParam << 32 >> 48
            if !WinGetPosSafe(hwnd, &winX, &winY, &winW, &winH)
                return
            if (x < winX + 5 || x > winX + winW - 5 || y < winY + 5 || y > winY + winH - 5)
                return
            return 2 ; HTCAPTION
        }
    }
}

WinGetPosSafe(hwnd, &x, &y, &w, &h) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        return true
    }
    return false
}

; One place that tears a PiP down, so the thumbnail handle, the window and the
; map entry can never get out of step.
ClosePiP(srcHwnd) {
    global PipGuis
    if !PipGuis.Has(srcHwnd)
        return
    pip := PipGuis[srcHwnd]
    PipGuis.Delete(srcHwnd)
    hwnd := 0
    try hwnd := pip.Hwnd
    try DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pip.ThumbId)
    try pip.Destroy()
    if hwnd
        RS_RemoveHwnd(hwnd)
}

TogglePiP() {
    global PipGuis

    srcHwnd := WinExist("A")
    if !srcHwnd
        return

    cls := ""
    try cls := WinGetClass(srcHwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd")
        return

    ; Win+Ctrl+P while a PiP thumbnail itself is focused closes that thumbnail.
    for s, pip in PipGuis {
        if (pip.Hwnd == srcHwnd) {
            ClosePiP(s)
            return
        }
    }

    if PipGuis.Has(srcHwnd) {
        ClosePiP(srcHwnd)
        return
    }

    ; -DPIScale like every other overlay: without it Gui.Show scales the
    ; requested w/h by the system DPI, so a PiP asked for 320x180 came out
    ; half as big again on a 150% display and no longer matched its source.
    PipGui := Gui("-Caption +ToolWindow +AlwaysOnTop +Resize +Border -DPIScale")
    PipGui.BackColor := "000000"

    sw := 0, sh := 0
    try WinGetClientPos(,, &sw, &sh, srcHwnd)
    if (sw > 0 && sh > 0) {
        ph := 200
        pw := Round(ph * (sw / sh))
    } else {
        pw := 320, ph := 180
    }


    PipGui.Show("w" pw " h" ph " NoActivate")
    
    thumbId := 0
    hr := DllCall("dwmapi\DwmRegisterThumbnail", "ptr", PipGui.Hwnd, "ptr", srcHwnd, "ptr*", &thumbId)
    if (hr != 0) {
        PipGui.Destroy()
        return
    }
    
    PipGui.ThumbId := thumbId
    PipGui.SourceHwnd := srcHwnd
    PipGuis[srcHwnd] := PipGui
    
    PipGui.OnEvent("Size", PipGuiResize)
    PipGui.OnEvent("ContextMenu", PipGuiContextMenu)
    PipGuiResize(PipGui, 0, pw, ph)
    SetTimer(PiPMonitorStep, 100)
}

PipGuiResize(guiObj, minMax, width, height) {
    if !guiObj.HasProp("ThumbId")
        return
        
    alpha := 255
    try {
        a := WinGetTransparent(guiObj.Hwnd)
        if (a != "")
            alpha := a
    }

    props := Buffer(48, 0)
    NumPut("UInt", 0x1D, props, 0) ; 0x19 | 0x04 = 0x1D
    NumPut("Int", 0, props, 4)
    NumPut("Int", 0, props, 8)
    NumPut("Int", width, props, 12)
    NumPut("Int", height, props, 16)
    NumPut("UChar", alpha, props, 36)
    NumPut("Int", 1, props, 40)
    NumPut("Int", 1, props, 44)
    DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", guiObj.ThumbId, "ptr", props)
}

PipGuiContextMenu(guiObj, *) {
    ; Went through PipGuis.Delete() directly, which throws if PiPMonitorStep had
    ; already removed the entry because the source window closed.
    try ClosePiP(guiObj.SourceHwnd)
}

PiPMonitorStep() {
    global PipGuis
    if (PipGuis.Count == 0) {
        SetTimer(PiPMonitorStep, 0)
        return
    }

    for srcHwnd, pipGui in PipGuis.Clone() {
        if !DllCall("IsWindow", "ptr", srcHwnd) {
            ClosePiP(srcHwnd)
            continue
        }
        
        try {
            alpha := WinGetTransparent(pipGui.Hwnd)
            if (alpha == "")
                alpha := 255
            if (!pipGui.HasProp("LastAlpha") || pipGui.LastAlpha != alpha) {
                pipGui.LastAlpha := alpha
                props := Buffer(48, 0)
                NumPut("UInt", 0x04, props, 0)
                NumPut("UChar", alpha, props, 36)
                DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", pipGui.ThumbId, "ptr", props)
            }
        }
    }
}

; ====== Global Mic Kill-Switch ======
ToggleDefaultMic() {
    try {
        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        pDevice := 0
        ComCall(4, IMMDeviceEnumerator, "UInt", 1, "UInt", 0, "Ptr*", &pDevice)
        if !pDevice
            return -1
            
        IID_IAudioEndpointVolume := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", IID_IAudioEndpointVolume)
        
        pAudioEndpointVolume := 0
        ComCall(3, pDevice, "Ptr", IID_IAudioEndpointVolume, "UInt", 23, "Ptr", 0, "Ptr*", &pAudioEndpointVolume)
        ObjRelease(pDevice)
        if !pAudioEndpointVolume
            return -1
            
        muted := 0
        ComCall(15, pAudioEndpointVolume, "Int*", &muted)
        
        newMuted := !muted
        ComCall(14, pAudioEndpointVolume, "Int", newMuted, "Ptr", 0)
        
        ObjRelease(pAudioEndpointVolume)
        return newMuted
    }
    return -1
}

ShowMicOSD(isMuted) {
    global MicOsdGui, MicOsdHiding

    if (MicOsdGui) {
        UpdateMicOSD(isMuted)
        if MicOsdHiding {           ; revive it rather than stacking a second one
            MicOsdHiding := false
            try FadeGui(MicOsdGui, TuneAlpha("osdAlpha"))
        }
    } else {
        try {
            MicOsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
            
            if (isMuted) {
                MicOsdGui.BackColor := "8B0000" 
                txt := "🎙️ Mic Muted"
            } else {
                MicOsdGui.BackColor := "006400" 
                txt := "🎙️ Mic Active"
            }
            
            RS_SetAlpha(MicOsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()


            MicOsdGui.SetFont("s20 cWhite bold", "Segoe UI")
            MicOsdGui.AddText("vText x0 y15 w240 h40 BackgroundTrans Center", txt)
            
            MicOsdGui.Show("NoActivate w240 h70")
            RS_SetRegion(MicOsdGui.Hwnd, "0-0 w240 h70 r20-20", RS_PRI_ANIM)
            
            GetMicOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            MicOsdGui.Move(x, y)
            
            NotchAnim(MicOsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; Plain one-shot, same reasoning as the volume OSD: this was 127 frames of the
    ; animation loop spent comparing a deadline.
    SetTimer(HideMicOSD, -Tune("osdHide"))
}

UpdateMicOSD(isMuted) {
    global MicOsdGui
    try {
        if (isMuted) {
            MicOsdGui.BackColor := "8B0000"
            MicOsdGui["Text"].Text := "🎙️ Mic Muted"
        } else {
            MicOsdGui.BackColor := "006400"
            MicOsdGui["Text"].Text := "🎙️ Mic Active"
        }
    } catch {
        try MicOsdGui.Destroy()
        MicOsdGui := ""
    }
}

HideMicOSD() {
    global MicOsdGui, MicOsdHiding
    if (!MicOsdGui)
        return
    MicOsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetMicOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, MicOsdGui.Hwnd)
    NotchAnim(MicOsdGui.Hwnd, cy, hiddenY, false, ClearMicOSD)
}

; Mirrors GetVolumeOSDPos so the two OSDs pick their monitor the same way. The
; mic OSD keeps its top-of-screen notch placement; only the monitor choice moved.
GetMicOSDPos(&x, &visibleY, &hiddenY) {
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    x := WL + (WR - WL - 240) // 2
    visibleY := WT + 10
    hiddenY := WT - 70
}

ClearMicOSD() {
    global MicOsdGui, MicOsdHiding
    MicOsdGui := ""
    MicOsdHiding := false
}

; ====== Quick Spotlight Launcher ======
ToggleSpotlight() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    
    if (SpotlightGui) {
        hwnd := 0
        try hwnd := SpotlightGui.Hwnd
        try SpotlightGui.Destroy()
        SpotlightGui := "", SpotlightInput := "", SpotlightResult := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
        return
    }


    SpotlightGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    SpotlightGui.BackColor := "202020" 
    
    SpotlightGui.SetFont("s24 cWhite", "Segoe UI")
    SpotlightInput := SpotlightGui.AddEdit("x20 y20 w600 h45 -VScroll -E0x200 Background202020 cWhite")
    
    SpotlightGui.SetFont("s14 cAAAAAA", "Segoe UI")
    SpotlightResult := SpotlightGui.AddText("x20 y85 w600 h35", "Type to search, calculate, or run...")
    
    SpotlightInput.OnEvent("Change", SpotlightOnChange)
    
    activeMon := MonitorGetPrimary()
    MonitorGet(activeMon, &L, &T, &R, &B)
    w := 640, h := 140
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 3 
    
    ; Round the corners and set the opacity BEFORE showing it. Doing it after Show
    ; meant one frame of a hard-edged, fully opaque grey rectangle before the
    ; region and alpha landed - a visible flash on every launch. The dimmer and the
    ; OSDs already did it in this order; this one did not.
    RS_SetRegion(SpotlightGui.Hwnd, "0-0 w640 h140 r20-20", RS_PRI_ANIM)
    RS_SetAlpha(SpotlightGui.Hwnd, 240, RS_PRI_ANIM)
    RS_Commit()
    SpotlightGui.Show("x" x " y" y " w" w " h" h)
}

SpotlightOnChange(ctrl, *) {
    global SpotlightResult
    text := Trim(ctrl.Value)
    if (text = "") {
        SpotlightResult.Text := "Type to search, calculate, or run..."
        return
    }

    ; A fresh MSHTML document per keystroke is not cheap, but it is only reached
    ; for arithmetic-looking input and a reused document has to be open()ed and
    ; close()d to be re-writable - which fails silently inside this try and would
    ; take the calculator with it. Left as it is on purpose.
    ; The character class is the guard: only digits, whitespace, brackets and the
    ; four operators ever reach eval, so nothing can escape arithmetic.
    if RegExMatch(text, "^[\d\+\-\*\/\.\(\)\s]+$") && RegExMatch(text, "\d") {
        try {
            doc := ComObject("htmlfile")
            doc.write("<body><script>document.write(eval('" text "'));</script></body>")
            ans := doc.body.innerText
            if (ans != "") {
                SpotlightResult.Text := "= " ans
                return
            }
        }
    }


    if FileExist(text) {
        SpotlightResult.Text := "Open path: " text
        return
    }
    
    SpotlightResult.Text := "Run: " text
}

SpotlightExecute() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    text := Trim(SpotlightInput.Value)
    if (text = "")
        return
        
    resText := SpotlightResult.Text
    
    if (SubStr(resText, 1, 2) == "= ") {
        A_Clipboard := LTrim(resText, "= ")
        ToggleSpotlight()
        return
    }
    
    ToggleSpotlight()
    try {
        Run(text)
    } catch {
        q := StrReplace(text, " ", "+")
        try Run("https://www.google.com/search?q=" q)
    }
}

; ====== Smart Active Border ======
GetAccentColor() {
    color := 0
    blend := 0
    hr := DllCall("dwmapi\DwmGetColorizationColor", "UInt*", &color, "Int*", &blend)
    if (hr == 0)
        return Format("{:06X}", color & 0xFFFFFF)
    return "00D7FF" 
}

SyncActiveBorderTimer() {
    global ActiveBorderEnabled
    ; A 50 ms timer, not a registered animation.
    ;
    ; ActiveBorderMonitorStep is a MONITOR - it polls the active window and
    ; returns true unconditionally - so registering it meant ActiveAnimations was
    ; never empty, the scheduler never hit its "nothing is animating" shutdown,
    ; and enabling the border pinned the 15 ms frame loop AND timeBeginPeriod(1)
    ; on for the rest of the session. That is the same "do not put a countdown in
    ; the scheduler" mistake the OSD auto-hides were fixed for, and 50 ms is the
    ; cadence this feature was always documented as using.
    ;
    ; DrawActiveBorder calls RS_Commit() itself, which is what a one-shot
    ; producer outside the frame loop has to do.
    if (ActiveBorderEnabled)
        SetTimer(ActiveBorderMonitorStep, 50)
    else {
        SetTimer(ActiveBorderMonitorStep, 0)
        DestroyActiveBorder()
    }
}
SyncActiveBorderTimer()

ActiveBorderMonitorStep() {
    global ActiveBorderEnabled, LastBorderHwnd, LastBorderX, LastBorderY, LastBorderW, LastBorderH
    if (!ActiveBorderEnabled)
        return

    hwnd := WinExist("A")
    if (!hwnd) {
        HideActiveBorder()
        return
    }
    
    ; Guarded, like IsMouseOverTaskbar: this runs 20 times a second on whatever
    ; window happens to be active, and the active window can be destroyed between
    ; WinExist("A") and the next line. An uncaught throw here would pop an error
    ; dialog and kill the timer, taking the feature out for the whole session.
    cls := "", style := 0
    try {
        cls := WinGetClass(hwnd)
        style := WinGetStyle(hwnd)
    } catch {
        HideActiveBorder()
        return
    }

    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "AutoHotkeyGUI") {
        HideActiveBorder()
        return
    }

    if (!(style & 0x10000000) || (style & 0x01000000) || (style & 0x20000000)) { ; Not visible OR Maximized OR Minimized
        HideActiveBorder()
        return
    }


    ; Measure the window, never the render queue.
    ;
    ; This used to read a PENDING RS_Pos entry as if it were a position. Every
    ; move-only producer - Glide, MoveFast, the curtain, the toast bounce -
    ; queues w and h as -1 to mean SWP_NOSIZE, so W and H came back as -1, failed
    ; the "W < 50" sanity test below and hid the border. The result was that the
    ; border blinked out for the whole of every glide, snap, pulse and layout
    ; key: it disappeared exactly when the window was moving, which is when it
    ; was most visible that something was wrong.
    ;
    ; A queued rect is also a request, not a fact - it has not been applied yet,
    ; and a higher-priority write in the same flush can still replace it.
    {
        rect := Buffer(16, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rect, "uint", 16)
        if (hr == 0) {
            X := NumGet(rect, 0, "Int")
            Y := NumGet(rect, 4, "Int")
            R := NumGet(rect, 8, "Int")
            B := NumGet(rect, 12, "Int")
            W := R - X
            H := B - Y
        } else {
            try WinGetPos(&X, &Y, &W, &H, hwnd)
            catch {
                HideActiveBorder()
                return
            }
        }
    }
    
    if (W < 50 || H < 50) {
        HideActiveBorder()
        return
    }
    
    SizeChanged := (W != LastBorderW || H != LastBorderH)
    if (hwnd == LastBorderHwnd && X == LastBorderX && Y == LastBorderY && !SizeChanged)
        return
        
    LastBorderHwnd := hwnd
    LastBorderX := X, LastBorderY := Y, LastBorderW := W, LastBorderH := H
    
    DrawActiveBorder(X, Y, W, H, SizeChanged)
}

global ActiveBorderShown := false

DrawActiveBorder(X, Y, W, H, SizeChanged:=true) {
    global ActiveBorderGui, ActiveBorderShown

    if (!ActiveBorderGui) {
        ActiveBorderGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
        ActiveBorderGui.BackColor := (BorderColor = "auto") ? GetAccentColor() : BorderColor
        ; Created hidden on purpose, so the region and position are in place
        ; before it is ever shown - otherwise it flashes as a 1px dot at 0,0.
        ActiveBorderGui.Show("NoActivate Hide x0 y0 w1 h1")
        ActiveBorderShown := false
        SizeChanged := true
    }

    t := Tune("borderThick")

    try {
        if SizeChanged {
            rect1 := "0-0 w" W " h" t
            rect2 := "0-" (H-t) " w" W " h" t
            rect3 := "0-" t " w" t " h" (H-2*t)
            rect4 := (W-t) "-" t " w" t " h" (H-2*t)
            RS_SetRegion(ActiveBorderGui.Hwnd, rect1 "  " rect2 "  " rect3 "  " rect4, RS_PRI_ANIM)
        }

        RS_SetPos(ActiveBorderGui.Hwnd, X, Y, W, H, RS_PRI_ANIM)
        RS_SetAlpha(ActiveBorderGui.Hwnd, TuneAlpha("borderAlpha"), RS_PRI_ANIM)
        RS_Commit()

        ; And then actually show it. Nothing did: the window was created with
        ; "Hide" and only ever received SetWindowPos (SWP_NOACTIVATE, no
        ; SWP_SHOWWINDOW) and WinSetTransparent, neither of which shows a hidden
        ; window - so the border was never visible at all.
        if !ActiveBorderShown {
            ActiveBorderGui.Show("NoActivate")
            ActiveBorderShown := true
        }
    }
}

; Transient hide, for when focus moves to a window that gets no border. Hides
; rather than destroys: this fires on every focus change, and destroying meant a
; fresh Gui (plus a permanent set of RenderCore map entries for the dead handle)
; every single time.
HideActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    if (ActiveBorderGui && ActiveBorderShown) {
        try ActiveBorderGui.Hide()
        ActiveBorderShown := false
    }
}

; Real teardown, for switching the feature off and for exit.
DestroyActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    ActiveBorderShown := false
    if (ActiveBorderGui) {
        hwnd := 0
        try hwnd := ActiveBorderGui.Hwnd
        try ActiveBorderGui.Destroy()
        ActiveBorderGui := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
    }
}

; ====== Always on Bottom (Desktop Widget) ======
GetDesktopHwnd() {
    desktopHwnd := WinExist("ahk_class Progman")
    hwnds := WinGetList("ahk_class WorkerW")
    for w in hwnds {
        if DllCall("FindWindowEx", "ptr", w, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0) {
            desktopHwnd := w
            break
        }
    }
    return desktopHwnd
}

ToggleAlwaysOnBottom() {
    global BottomWindows
    ; Deliberately NOT guarded with a `static busy` flag.
    ; #MaxThreadsPerHotkey 2 does let a second press interrupt this one, but
    ; every exit below is an early `return` - and AHK v2 has no `finally`, so a
    ; guard would have to be cleared on each of a dozen paths. Miss one and the
    ; flag latches true and the hotkey is dead for the rest of the session,
    ; which is far worse than the race: re-entry here re-runs the same branch
    ; and writes the same Map entry twice, which is idempotent.

    hwnd := WinExist("A")
    if !hwnd
        return

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return

    if BottomWindows.Has(hwnd) {
        RestoreFromBottom(hwnd)
        return
    }

    desktop := GetDesktopHwnd()
    if !desktop
        return

    X := "", Y := "", W := "", H := ""
    try WinGetPos(&X, &Y, &W, &H, hwnd)

    ; No GetParent() here on purpose. For a window without WS_CHILD - which is
    ; every window this hotkey accepts - Win32 GetParent returns the OWNER, not
    ; the parent. Recording that and handing it back to SetParent on restore
    ; turned an owned top-level window into a CHILD of its owner: clipped to the
    ; owner's client area, not alt-tabbable, and impossible to move back out.
    ; A top-level window's parent is the desktop, so restore passes 0.
    ;
    ; The return value must also be checked BEFORE we record anything: SetParent
    ; fails across integrity levels and for some shell/UWP windows, and on failure
    ; the window used to be listed as pinned anyway and then teleported by the
    ; ScreenToClient conversion below.
    if !DllCall("SetParent", "ptr", hwnd, "ptr", desktop, "ptr") {
        Notify("Cannot pin this window to the desktop")
        return
    }

    ; Record the screen rect: reparenting is undone at exit, and the window has to
    ; go back to where it was on screen, not to client coordinates of a desktop it
    ; is no longer a child of.
    BottomWindows[hwnd] := {x: X, y: Y, w: W, h: H}

    if (X != "") {
        pt := Buffer(8)
        NumPut("Int", X, pt, 0)
        NumPut("Int", Y, pt, 4)
        DllCall("ScreenToClient", "ptr", desktop, "ptr", pt)
        nX := NumGet(pt, 0, "Int")
        nY := NumGet(pt, 4, "Int")

        RS_SetPos(hwnd, nX, nY, W, H, RS_PRI_USER)
        RS_Commit()
    }
}

; Put a desktop-pinned window back where it came from. Shared by the hotkey and
; by Bye(), because a window left parented to WorkerW cannot be alt-tabbed to,
; cannot be moved normally, and dies with the next Explorer restart.
RestoreFromBottom(hwnd) {
    global BottomWindows
    if !BottomWindows.Has(hwnd)
        return
    info := BottomWindows[hwnd]
    BottomWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd)
        return

    ; Where it is now, so a widget the user dragged around stays put. GetWindowRect
    ; reports screen coordinates even for a child window, so this is still valid
    ; while it is parented to the desktop. The pinning-time rect is the fallback.
    x := info.x, y := info.y, w := info.w, h := info.h
    try WinGetPos(&x, &y, &w, &h, hwnd)

    ; 0 = the desktop, i.e. back to being a real top-level window. See the note in
    ; ToggleAlwaysOnBottom for why the old GetParent() handle was wrong.
    DllCall("SetParent", "ptr", hwnd, "ptr", 0, "ptr")

    if (x != "")
        RS_SetPos(hwnd, x, y, w, h, RS_PRI_USER)
    RS_SetZOrder(hwnd, 0, 0x0013, RS_PRI_USER)      ; HWND_TOP
    RS_Commit()
}

; ====== Global Text Expander ======
IsExpanderActive(*) {
    global TextExpanderEnabled
    return TextExpanderEnabled
}

SyncTextExpander() {
    static lastSnippets := Chr(1)      ; sentinel: never equal to a real read
    HotIf(IsExpanderActive)

    try IniRead(INI, "snippets")
    catch {
        ; ASCII only in this file (AutoHotkey reads a BOM-less script in the
        ; system codepage, so anything else turns to mojibake on another
        ; machine). Users can put any text they like in settings.ini itself -
        ; that is read as a file, not as source.
        try IniWrite("your.email@example.com", INI, "snippets", "@@mail")
        try IniWrite("+994501234567", INI, "snippets", "@@tel")
        try IniWrite("Thanks!", INI, "snippets", "@@ty")
    }
    
    ; ApplyUi calls this on every checkbox click and every debounced keystroke, and
    ; re-registering the snippets costs a measured 113 us plus a 64 us section read
    ; for nothing. The snippets live in settings.ini and only change when the user
    ; edits that file, so compare and bail.
    str := ""
    try str := IniRead(INI, "snippets",, "")
    if (str == lastSnippets) {
        HotIf()
        return
    }
    lastSnippets := str

    Loop Parse str, "`n", "`r" {
        if (A_LoopField == "")
            continue
        parts := StrSplit(A_LoopField, "=", " `t", 2)
        if (parts.Length == 2)
            try Hotstring(":?*T:" parts[1], parts[2], "On")
    }


    try Hotstring(":?*:@@date", (*) => Send(FormatTime(, "yyyy-MM-dd")), "On")
    try Hotstring(":?*:@@time", (*) => Send(FormatTime(, "HH:mm")), "On")
    
    HotIf()
}
SyncTextExpander()

; ====== Proximity Ghost Window ======
GetDistToRect(px, py, rx, ry, rw, rh) {
    cx := Max(Min(px, rx + rw), rx)
    cy := Max(Min(py, ry + rh), ry)
    return Sqrt((px - cx)**2 + (py - cy)**2)
}

ToggleGhostMode() {
    global GhostWindows
    ; Deliberately NOT guarded with a `static busy` flag.
    ; #MaxThreadsPerHotkey 2 does let a second press interrupt this one, but
    ; every exit below is an early `return` - and AHK v2 has no `finally`, so a
    ; guard would have to be cleared on each of a dozen paths. Miss one and the
    ; flag latches true and the hotkey is dead for the rest of the session,
    ; which is far worse than the race: re-entry here re-runs the same branch
    ; and writes the same Map entry twice, which is idempotent.

    hwnd := WinExist("A")
    if !hwnd
        return

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return

    if GhostWindows.Has(hwnd) {
        UnGhostWindow(hwnd)
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitorStep, 0)
        SyncMediaCore()
        return
    }

    exStyle := 0
    try exStyle := WinGetExStyle(hwnd)
    catch
        return

    ; A window that is already click-through is not one we can take over: we
    ; would have no way to tell our change from its own. Previously this fell
    ; through and still forced always-on-top, leaving the window topmost with
    ; nothing recorded and no way to undo it.
    if (exStyle & 0x20)
        return

    try {
        WinSetExStyle("+0x20", hwnd)          ; WS_EX_TRANSPARENT
        ; Through the pipeline, not WinSetTransparent(255) directly: this still
        ; forces WS_EX_LAYERED on, but it also records 255 in RS_LastAlpha. A
        ; direct call left the cache stale, so the very first proximity write
        ; could be dropped as "already applied" and the window sat opaque until
        ; the mouse moved far enough to ask for a different value.
        RS_SetAlpha(hwnd, 255, RS_PRI_AMBIENT)
        RS_Commit()
        WinSetAlwaysOnTop(1, hwnd)
    } catch
        return

    GhostWindows[hwnd] := {exStyle: exStyle}
    if (GhostWindows.Count == 1)
        SetTimer(GhostMonitorStep, 25)
    SyncMediaCore()
}

; Undo everything ToggleGhostMode did. Shared with Bye(), because a ghost left
; behind is a permanently click-through, always-on-top, semi-transparent window
; that the user has no way to recover without restarting the app.
UnGhostWindow(hwnd) {
    global GhostWindows
    if !GhostWindows.Has(hwnd)
        return
    orig := GhostWindows[hwnd]
    GhostWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd)
        return

    try {
        RS_SetAlpha(hwnd, "Off", RS_PRI_AMBIENT)
        RS_Commit()                            ; nothing else will flush this
        if !(orig.exStyle & 0x20)
            WinSetExStyle("-0x20", hwnd)
        if !(orig.exStyle & 0x8)
            WinSetAlwaysOnTop(0, hwnd)
    }
}

GhostMonitorStep() {
    global GhostWindows

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)

    maxDist := Tune("ghostRange") + 0.0     ; float: it divides below
    minAlpha := TuneAlpha("ghostAlpha")
    maxAlpha := 255
    clickDist := Tune("ghostClick")
    anyMedia := MC_AnyMedia()          ; hoisted: this runs 40 times a second

    ; Clone() only when something actually died; the common case is that nothing
    ; has, and this timer runs 40 times a second.
    dead := ""
    for hwnd, info in GhostWindows {
        if !DllCall("IsWindow", "ptr", hwnd) {
            if !IsObject(dead)
                dead := []
            dead.Push(hwnd)
            continue
        }

        try {
            WinGetPos(&X, &Y, &W, &H, hwnd)
            dist := GetDistToRect(mx, my, X, Y, W, H)

            if (dist == 0 || (anyMedia && MC_IsMediaHwnd(hwnd)))
                targetAlpha := maxAlpha
            else if (dist >= maxDist)
                targetAlpha := minAlpha
            else {
                ratio := 1.0 - (dist / maxDist)
                targetAlpha := minAlpha + Integer(ratio * (maxAlpha - minAlpha))
            }
            
            ; Queue only. The single commit after the loop applies every ghost
            ; in one batched pass; committing in here meant one full flush per
            ; ghosted window, 40 times a second.
            if (!info.HasProp("lastAlpha") || info.lastAlpha != targetAlpha) {
                RS_SetAlpha(hwnd, targetAlpha, RS_PRI_AMBIENT)
                info.lastAlpha := targetAlpha
            }

            ; Read the real style rather than caching it: WinGetExStyle costs
            ; 0.28 us, and reading it back is what makes this self-correcting if
            ; the window changes its own styles. Not worth caching.
            ;
            ; Hysteresis, not a bare threshold: a cursor resting near the
            ; boundary crosses it on the sub-pixel jitter of an ordinary hand,
            ; and each crossing rewrote WS_EX_TRANSPARENT 40 times a second -
            ; so the window flickered between clickable and not.
            isClickThrough := (WinGetExStyle(hwnd) & 0x20)
            if (dist < clickDist) {
                if (isClickThrough)
                    WinSetExStyle("-0x20", hwnd)
            } else if (dist > clickDist + 12) {
                if (!isClickThrough)
                    WinSetExStyle("+0x20", hwnd)
            }
        }
    }

    if IsObject(dead) {
        for hwnd in dead
            GhostWindows.Delete(hwnd)
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitorStep, 0)
    }

    ; A monitor timer, not an animation: nothing else flushes for it, so without
    ; this the proximity fade never reached the screen at all.
    RS_Commit()
}

OnExit(Bye)
Bye(*) {
    global TrayIcons, BossKeyActive, BossKeyWindows, BossKeyMuteState
    global WinEventHook, WinEventCb, RolledUpWindows, CustomTrans
    global OriginalTaskbarState, SmartTaskbarEnabled, DimmerGuis, OsdGui, PipGuis, MicOsdGui, SpotlightGui
    global WinCurrentAlpha, GhostWindows, BottomWindows, FocusGuis

    ; Stop producing before we start undoing, so no timer or animation frame can
    ; re-apply a state we have just cleaned up. Bye also runs on tray -> Restart,
    ; so everything below has to be correct for a reload, not just a shutdown.
    try StopScheduler(true)
    try SetTimer(BreathingMonitorStep, 0)
    try SetTimer(GhostMonitorStep, 0)
    try SetTimer(ActiveBorderMonitorStep, 0)
    try SetTimer(MonitorDimmerTickStep, 0)
    try SetTimer(SmartTaskbarMonitorStep, 0)
    try SetTimer(HotCornersMonitorStep, 0)
    try SetTimer(CursorWrapMonitorStep, 0)
    try SetTimer(FocusMonitorStep, 0)
    try SetTimer(PiPMonitorStep, 0)
    try SetTimer(CheckQuickLookFocusStep, 0)
    try SetTimer(MC_Tick, 0)
    ; The rest of the timers in the program. Every one of these was left running
    ; through the whole teardown, and several of them re-create the very overlays
    ; and window state Bye() exists to undo - CheckTaskbarAndUI can build a fresh
    ; full-screen Start-menu blur AFTER RS_Shutdown() has run. Bye() is also the
    ; tray -> Restart path, so this is not academic.
    try SetTimer(CheckTaskbarAndUI, 0)
    try SetTimer(ShakeDetector, 0)
    try SetTimer(RenderShakeFind, 0)
    try SetTimer(CheckMouseIdle, 0)
    try SetTimer(UpdateBreathe, 0)
    try SetTimer(UpdateRipples, 0)
    try SetTimer(UpdateSparks, 0)
    try SetTimer(UpdateDragTrail, 0)
    try SetTimer(CheckElasticDrag, 0)
    try SetTimer(CheckMagDrag, 0)
    try SetTimer(UpdateMag, 0)
    try SetTimer(RenderMotionBlur, 0)
    try SetTimer(UpdateCarousel, 0)
    try SetTimer(RenderElasticScroll, 0)

    ; Rubber-band scroll parks a foreign window at an offset from its own base.
    ; Nothing else puts it back, so exiting mid-lean left it displaced.
    global ElasticHwnd, ElasticBaseX, ElasticBaseY
    if (ElasticHwnd && DllCall("IsWindow", "ptr", ElasticHwnd))
        try WinMove(ElasticBaseX, ElasticBaseY, , , ElasticHwnd)
    ElasticHwnd := 0

    try MC_Shutdown()

    try DestroyActiveBorder()

    for layer in FocusGuis
        try GuiDestroy(layer.gui)
    FocusGuis := []

    if (SpotlightGui)
        try SpotlightGui.Destroy()

    for src, pip in PipGuis.Clone()
        try ClosePiP(src)

    if (OsdGui)
        try OsdGui.Destroy()
        
    if (MicOsdGui)
        try MicOsdGui.Destroy()

    for k, g in DimmerGuis
        try GuiDestroy(g)      ; .Hwnd throws on an already-destroyed Gui
    DimmerGuis.Clear()

    ; The smart-grid zone overlays are +AlwaysOnTop tool windows. Nothing else
    ; destroys them, so exiting mid-drag used to leave them on screen.
    global SmartGridGuis
    for g in SmartGridGuis
        try GuiDestroy(g)
    SmartGridGuis := []

    if (SmartTaskbarEnabled && OriginalTaskbarState != -1)
        SetTaskbarAutoHide(OriginalTaskbarState & 1)

    if (BossKeyActive) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        try SoundSetMute(BossKeyMuteState)
    }

    for hwnd in TrayIcons {
        cbSize := A_PtrSize == 8 ? 976 : 956
        nid := Buffer(cbSize, 0)
        NumPut("uint", cbSize, nid, 0)
        NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
        NumPut("uint", hwnd, nid, A_PtrSize == 8 ? 16 : 8)
        DllCall("shell32\Shell_NotifyIconW", "uint", 2, "ptr", nid)
        try WinShow(hwnd)
    }

    ; Nothing here is left behind for the next process to trip over. Everything we
    ; changed about a foreign window has to be changed back, through the map that
    ; recorded it - a rolled-up window keeps its clipping region until something
    ; clears it, a dimmed one keeps its alpha, a ghost stays click-through and
    ; topmost, and a desktop-pinned widget stays a child of WorkerW.
    for hwnd in RolledUpWindows {
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_SetRegion(hwnd, "", RS_PRI_USER)
    }
    for hwnd, alpha in CustomTrans {
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
    }
    ; Breathing-dimmed windows: nothing used to queue anything for these, so
    ; exiting while windows were dimmed left them dimmed permanently.
    for hwnd, alpha in WinCurrentAlpha {
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
    }
    for hwnd, info in GhostWindows.Clone()
        try UnGhostWindow(hwnd)
    for hwnd, info in BottomWindows.Clone()
        try RestoreFromBottom(hwnd)

    ; Three more maps that record foreign-window state we have to hand back, and
    ; that nothing else can. Each of these used to outlive the process:
    ;   Focus Depth  - windows left at 98% size and alpha 210, forever
    ;   Curtain Drop - every window on the desktop parked below the screen
    ;   Shatter      - the target window alive and invisible at x = -19999
    try RestoreFocusDepth()
    try RestoreCurtain()
    try RestoreShatters()

    RS_Commit()
    RS_Flush()
    RS_Shutdown()

    ; Unhook before the callback goes away - the OS must not be left holding a
    ; pointer into a freed thunk.
    if (WinEventHook)
        try DllCall("UnhookWinEvent", "ptr", WinEventHook)
    if (WinEventCb)
        try CallbackFree(WinEventCb)
        
    if (MenuEventHook)
        try DllCall("UnhookWinEvent", "ptr", MenuEventHook)
    if (MenuEventCb)
        try CallbackFree(MenuEventCb)
        
    try DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)

    ; Both of these are normally deferred to an idle timer. On the way out there
    ; is no idle, so write straight through - a queued timer would never fire.
    try WriteSettings()
    try WritePositions()
    try FlushLog()
    Return 0
}


; ====== MediaCore Integration ======
SyncMediaCore() {
    global BreathingEnabled, MultiMonitorDimmerEnabled, ProximityGhostEnabled, ParallaxEnabled
    global MediaFallbackList, BREATHE_IDLE_MS
    wanted := BreathingEnabled || MultiMonitorDimmerEnabled || ProximityGhostEnabled || ParallaxEnabled
    MC_SetFallbackList(MediaFallbackList)
    ; Keep MediaCore's hold window derived from the breathing threshold rather
    ; than left at its default; MC_HoldMs explains why they must stay tied.
    MC_SetHoldMs(BREATHE_IDLE_MS)
    MC_SetWanted(wanted, MultiMonitorDimmerEnabled, QPC())
    if wanted
        SetTimer(MC_Tick, 250)
    else
        SetTimer(MC_Tick, 0)
}

; MediaCore takes the clock as a parameter so it stays include-safe (see its
; header).  SetTimer calls its callback with no arguments, so the clock is read
; here rather than there - a callback with required parameters fails outright
; with "Invalid callback function".
MC_Tick() {
    global SchedulerRunning
    ; Tell MediaCore when something is animating so its COM sweep stays out of
    ; the frame loop's way - see MC_SweepStep.
    MC_SweepStep(QPC(), SchedulerRunning)
    ; Piggyback the render-cache sweep on a timer that is already awake. Our own
    ; overlay windows raise no shell destroy notification, so without a periodic
    ; pass their entries would sit in the last-applied caches forever - and a
    ; recycled HWND would inherit them. Skip it mid-animation too; it walks two
    ; Maps and there is no hurry.
    if !SchedulerRunning
        RS_SweepDead()
}

QPC() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &count:=0)
    return count * 1000 / freq
}

; ============================================================================
; Shake to Find (macOS style cursor finder)
; ============================================================================
global ShakeFindActive := false
global ShakePrevX := 0
global ShakePrevY := 0
global ShakeDir := 0
global ShakeCount := 0
global ShakeLastTime := 0

global SF_Size := 0
global SF_TargetSize := 150
global SF_Vel := 0
global SF_Gui := 0
global SF_Hwnd := 0
global SF_Phase := 0
global SF_CircleSize := 200

; Creates the highlight overlay on first use. It used to be built at startup
; whether or not either consumer was switched on, which is a permanent
; always-on-top layered window for a feature that may never run.
;
; SF_Gui must be global. A Gui window dies with the last reference to its object,
; so keeping only its Hwnd left SF_Hwnd dangling the moment this function
; returned, and RenderShakeFind then threw inside a timer callback.
InitShakeFind() {
    global SF_Gui, SF_Hwnd
    if (SF_Gui && SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
        return true
    try {
        SF_Gui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
        SF_Gui.BackColor := "White"
        SF_Hwnd := SF_Gui.Hwnd
        WinSetTransparent(160, SF_Hwnd)
        return true
    }
    SF_Gui := 0, SF_Hwnd := 0
    return false
}

; The Sync* this timer never had. ShakeDetector polls the mouse and the idle
; timer 25 times a second and serves TWO features; with both off it was pure
; overhead, and it was armed unconditionally from InitShakeFind at startup.
SyncShakeDetector() {
    global ShakeFindEnabled, CursorYawnEnabled, ShakeFindActive
    if (ShakeFindEnabled || CursorYawnEnabled) {
        SetTimer(ShakeDetector, 40)
        return
    }
    SetTimer(ShakeDetector, 0)
    ; Switched off mid-highlight: take the circle down, or it is stranded at
    ; whatever size it had reached with nothing left to shrink it.
    if ShakeFindActive {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        global SF_Hwnd
        if (SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
            try DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0)   ; SW_HIDE
    }
}

ShakeDetector() {
    global ShakeFindEnabled, ShakeFindActive
    global ShakePrevX, ShakePrevY, ShakeDir, ShakeCount, ShakeLastTime
    global SF_TargetSize, SF_Phase
    
    global CursorYawnEnabled, CursorYawnActive, CursorYawnIdleTime
    if (CursorYawnEnabled) {
        idle := A_TimeIdlePhysical
        if (idle > CursorYawnIdleTime) {
            CursorYawnActive := true
        } else if (idle < 100 && CursorYawnActive) {
            CursorYawnActive := false
            TriggerCursorYawn()
        }
    }
    
    if (!ShakeFindEnabled)
        return
        
    MouseGetPos(&mx, &my)
    dx := mx - ShakePrevX
    dy := my - ShakePrevY
    ShakePrevX := mx
    ShakePrevY := my
    
    t := A_TickCount
    if (t - ShakeLastTime > 300) {
        ShakeCount := 0
    }
    
    if (Abs(dx) > 15) {
        dir := dx > 0 ? 1 : -1
        if (dir != ShakeDir) {
            ShakeDir := dir
            ShakeCount++
            ShakeLastTime := t
            
            if (ShakeCount >= Tune("shakeCount") && !ShakeFindActive) {
                ShakeCount := 0
                StartShakeFind()
            }
        }
    }
    
    if (ShakeFindActive && t - ShakeLastTime > 200) {
        if (SF_Phase == 1) {
            SF_Phase := 2
            SF_TargetSize := 0
        }
    }
}

StartShakeFind() {
    global ShakeFindActive, SF_Phase, SF_TargetSize, SF_Size, SF_Vel
    if !InitShakeFind()
        return
    ShakeFindActive := true
    SF_Phase := 1
    SF_TargetSize := Tune("shakeSize")
    SF_Size := 10
    SF_Vel := 0
    SetTimer(RenderShakeFind, 16)
}

RenderShakeFind() {
    global ShakeFindActive, SF_Size, SF_TargetSize, SF_Vel, SF_Hwnd, SF_CircleSize

    ; 16 ms timer: a throw here would pop an error dialog and kill the timer for
    ; the rest of the session, so the overlay must be verified before it is used.
    if (!SF_Hwnd || !DllCall("IsWindow", "ptr", SF_Hwnd)) {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        return
    }

    if (!ShakeFindActive) {
        SetTimer(RenderShakeFind, 0)
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        return
    }
    
    SF_Vel += (SF_TargetSize - SF_Size) * 0.4
    SF_Vel *= 0.6 ; friction
    SF_Size += SF_Vel
    
    if (SF_Size < 2 && SF_TargetSize == 0) {
        ShakeFindActive := false
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        SetTimer(RenderShakeFind, 0)
        return
    }
    
    MouseGetPos(&mx, &my)
    s := Round(SF_Size)
    if (s > SF_CircleSize)
        s := SF_CircleSize
        
    if (s > 0) {
        try {
            WinSetRegion("0-0 w" s " h" s " E", SF_Hwnd)
            DllCall("SetWindowPos", "ptr", SF_Hwnd, "ptr", -1, "int", mx - s//2, "int", my - s//2, "int", s, "int", s, "uint", 0x50) ; SWP_NOACTIVATE | SWP_SHOWWINDOW
        } catch {
            ShakeFindActive := false
            SetTimer(RenderShakeFind, 0)
        }
    }
}

TriggerCursorYawn() {
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "White"
    WinSetTransparent(220, guiObj.Hwnd)
    
    animKey := "CursorYawn_" . guiObj.Hwnd
    start := QPC()
    ms := 1000
    
    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            guiObj.Destroy()
            return false
        }
        
        baseSize := 24
        w := baseSize
        h := baseSize
        
        if (t < 0.35) {
            p := t / 0.35
            ease := 1 - (1 - p) ** 3
            h := baseSize + (45 * ease)
            w := baseSize - (12 * ease)
        } else if (t < 0.7) {
            p := (t - 0.35) / 0.35
            ease := 0.5 - Cos(p * 3.14159) * 0.5
            h := baseSize + 45 - (55 * ease)
            w := baseSize - 12 + (40 * ease)
        } else {
            p := (t - 0.7) / 0.3
            ease := p * p
            h := (baseSize - 10) * (1 - ease)
            w := (baseSize + 28) * (1 - ease)
            
            alpha := Round(220 * (1 - ease))
            try WinSetTransparent(alpha, guiObj.Hwnd)
        }
        
        if (w < 2)
            w := 2
        if (h < 2)
            h := 2
            
        WinSetRegion("0-0 w" Round(w) " h" Round(h) " E", guiObj.Hwnd)
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(mx - w/2), "int", Round(my - h/2), "int", Round(w), "int", Round(h), "uint", 0x14)
        return true
    }
    
    guiObj.Show("NA x" mx " y" my " w" 24 " h" 24)
    RegisterAnimation(animKey, Step)
}

; ============================================================================
; Magnetic Window Groups
; ============================================================================
; This declaration was missing entirely. Every user of MagGroups declares it
; `global` and then calls .Has() on it, so with nothing ever assigning it AHK's
; default #Warn VarUnset popped a modal warning dialog on startup, and the first
; drag would have thrown on an unset variable. Grouping could never have worked.
global MagGroups := Map()

GroupWindows(h1, h2) {
    global MagGroups
    g1 := MagGroups.Has(h1) ? MagGroups[h1] : [h1]
    g2 := MagGroups.Has(h2) ? MagGroups[h2] : [h2]
    
    if (g1 = g2)
        return
        
    newGroup := []
    for h in g1
        newGroup.Push(h)
    for h in g2 {
        found := false
        for eh in newGroup
            if (eh = h)
                found := true
        if !found
            newGroup.Push(h)
    }
    
    for h in newGroup
        MagGroups[h] := newGroup
}

UngroupWindow(h) {
    global MagGroups
    if !MagGroups.Has(h)
        return
    grp := MagGroups[h]
    MagGroups.Delete(h)
    
    newGrp := []
    for eh in grp {
        if (eh != h)
            newGrp.Push(eh)
    }
    
    if (newGrp.Length == 1) {
        MagGroups.Delete(newGrp[1])
    } else {
        for eh in newGrp
            MagGroups[eh] := newGrp
    }
}

; ============================================================================
; Rubber-Band Elastic Scroll
; ============================================================================
global ElasticHwnd := 0
global ElasticOffsetY := 0
global ElasticTargetY := 0
global ElasticVel := 0
global ElasticBaseX := 0
global ElasticBaseY := 0
global ElasticEdgeStates := Map()
global ElasticAwayCounts := Map()

ElasticScroll(hwnd, dir, startX, startY) {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global ElasticEdgeStates, ElasticAwayCounts
    
    if !ElasticEdgeStates.Has(hwnd) {
        ElasticEdgeStates[hwnd] := 0
        ElasticAwayCounts[hwnd] := 0
    }
    
    state := ElasticEdgeStates[hwnd]
    threshold := 5
    
    if (dir == 1) {
        if (state == 1) {
            return
        } else if (state == -1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := 1
            ElasticAwayCounts[hwnd] := 0
        }
    } else {
        if (state == -1) {
            return
        } else if (state == 1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := -1
            ElasticAwayCounts[hwnd] := 0
        }
    }
    
    if (ElasticHwnd != hwnd) {
        if (ElasticHwnd) {
            try WinMove(ElasticBaseX, ElasticBaseY,,, ElasticHwnd)
        }
        ElasticHwnd := hwnd
        ElasticBaseX := startX
        ElasticBaseY := startY
        ElasticOffsetY := 0
        ElasticTargetY := 0
        ElasticVel := 0
        SetTimer(RenderElasticScroll, 16)
    }
    
    ElasticTargetY := dir * Tune("elasticAmt")
        
    SetTimer(ElasticTimeout, -150)
}

ElasticTimeout() {
    global ElasticTargetY
    ElasticTargetY := 0
}

RenderElasticScroll() {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global DragHwnd
    
    if (!DllCall("IsWindow", "ptr", ElasticHwnd) || DragHwnd == ElasticHwnd) {
        SetTimer(RenderElasticScroll, 0)
        if (DragHwnd == ElasticHwnd)
            try WinMove(ElasticBaseX, ElasticBaseY,,, ElasticHwnd)
        ElasticHwnd := 0
        return
    }
    
    ElasticVel += (ElasticTargetY - ElasticOffsetY) * 0.4
    ElasticVel *= 0.6
    ElasticOffsetY += ElasticVel
    
    if (Abs(ElasticTargetY) < 1 && Abs(ElasticOffsetY) < 1 && Abs(ElasticVel) < 1) {
        try WinMove(ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY),,, ElasticHwnd)
        SetTimer(RenderElasticScroll, 0)
        ElasticHwnd := 0
        return
    }
    
    try WinMove(ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY),,, ElasticHwnd)
}

; ============================================================================
; Text Selection Magnifier
; ============================================================================
global MagActive := false
global MagHostGui := ""
global MagFrameGui := ""
global MagChildHwnd := 0
global MagFailed := false
global MagStartX := 0, MagStartY := 0

; Returns false if the magnifier is not usable on this machine. Every step is
; checked: MagInitialize can fail outright, and the whole thing is inside a try
; because it runs from a mouse-drag timer where a throw is an error dialog.
;
; MagFailed latches, so a machine without a working Magnification.dll pays the
; failed init exactly once instead of on every text drag.
InitMag() {
    global MagHostGui, MagFrameGui, MagChildHwnd, MagFailed

    if MagFailed
        return false
    try {
        if !DllCall("LoadLibrary", "str", "Magnification.dll", "ptr")
            throw Error("Magnification.dll")
        if !DllCall("Magnification\MagInitialize")
            throw Error("MagInitialize")

        MagFrameGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        MagFrameGui.BackColor := "2A2A2A"
        WinSetRegion("0-0 w144 h144 E", MagFrameGui.Hwnd)

        ; WS_EX_LAYERED (0x80000) is REQUIRED on the host of a magnifier control -
        ; the API documents it, and without it the control has no surface to
        ; present into, which is why this effect had never actually shown a loupe.
        MagHostGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x80000")
        WinSetRegion("0-0 w140 h140 E", MagHostGui.Hwnd)

        MagChildHwnd := DllCall("CreateWindowEx", "uint", 0
            , "str", "Magnifier"
            , "str", "MagnifierWindow"
            , "uint", 0x50000000 ; WS_CHILD | WS_VISIBLE
            , "int", 0, "int", 0, "int", 140, "int", 140
            , "ptr", MagHostGui.Hwnd, "ptr", 0, "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "ptr", 0, "ptr")
        if !MagChildHwnd
            throw Error("CreateWindowEx Magnifier")

        Transform := Buffer(36, 0)
        NumPut("float", 2.0, Transform, 0)
        NumPut("float", 2.0, Transform, 16)
        NumPut("float", 1.0, Transform, 32)
        DllCall("Magnification\MagSetWindowTransform", "ptr", MagChildHwnd, "ptr", Transform)
        return true
    } catch as e {
        MagFailed := true
        MagChildHwnd := 0
        try MagFrameGui.Destroy()
        try MagHostGui.Destroy()
        MagFrameGui := "", MagHostGui := ""
        WriteLog("magnifier unavailable - " e.Message)
        return false
    }
}

; Returns whether the loupe is actually on screen. The caller MUST honour it:
; arming UpdateMag regardless is what turned a missing Magnification.dll into an
; error dialog on every text drag, because UpdateMag then dereferenced
; MagFrameGui.Hwnd on an empty string, outside any try, from a 16 ms timer.
ShowMag(mx, my) {
    global MagHostGui, MagFrameGui, MagChildHwnd
    if (!MagChildHwnd && !InitMag())
        return false
    if (!MagFrameGui || !MagHostGui)
        return false
    try {
        MagFrameGui.Show("x-1000 y-1000 w144 h144 NoActivate")
        MagHostGui.Show("x-1000 y-1000 w140 h140 NoActivate")
        return true
    }
    return false
}

HideMag() {
    global MagHostGui, MagFrameGui
    if (MagHostGui) {
        MagHostGui.Hide()
        MagFrameGui.Hide()
    }
}

CheckMagDrag() {
    global MagStartX, MagStartY, MagActive
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckMagDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - MagStartX) > 5 || Abs(my - MagStartY) > 5) {
        SetTimer(CheckMagDrag, 0)
        ; Only start tracking if there is actually a loupe to track with.
        if ShowMag(mx, my) {
            MagActive := true
            SetTimer(UpdateMag, 16)
        }
    }
}

UpdateMag() {
    global MagActive, MagChildHwnd, MagHostGui, MagFrameGui
    if (!GetKeyState("LButton", "P")) {
        SetTimer(UpdateMag, 0)
        MagActive := false
        HideMag()
        return
    }

    ; 16 ms timer: a throw here kills the timer for the session, so the overlay
    ; is verified before it is used rather than assumed.
    if (!MagChildHwnd || !MagFrameGui || !MagHostGui) {
        SetTimer(UpdateMag, 0)
        MagActive := false
        return
    }

    try {
        MouseGetPos(&mx, &my)

        SourceRect := Buffer(16, 0)
        NumPut("int", mx - 35, SourceRect, 0)
        NumPut("int", my - 35, SourceRect, 4)
        NumPut("int", mx + 35, SourceRect, 8)
        NumPut("int", my + 35, SourceRect, 12)
        DllCall("Magnification\MagSetWindowSource", "ptr", MagChildHwnd, "ptr", SourceRect)

        DllCall("SetWindowPos", "ptr", MagFrameGui.Hwnd, "ptr", -1, "int", mx - 72, "int", my - 162, "int", 0, "int", 0, "uint", 0x55)
        DllCall("SetWindowPos", "ptr", MagHostGui.Hwnd, "ptr", -1, "int", mx - 70, "int", my - 160, "int", 0, "int", 0, "uint", 0x55)
    }
}

; ============================================================================
; Smart Tiling Grid
; ============================================================================
global GridActive := false
global GridHoverZone := 0
global SmartGridZones := []
global SmartGridGuis := []

ShowSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridActive, GridHoverZone
    
    MouseGetPos(&mx, &my)
    mon := MonitorIndexAt(mx, my)
    if !WorkAreaOf(mon, &wl, &wt, &wr, &wb)
        return
    w := wr - wl, h := wb - wt
    SmartGridZones := []
    if (w / h > 2.0) {
        cw := w // 3
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wl + cw*2, B: wb})
        SmartGridZones.Push({L: wl + cw*2, T: wt, R: wr, B: wb})
    } else {
        cw := w // 2, ch := h // 2
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wr, B: wt + ch})
        SmartGridZones.Push({L: wl + cw, T: wt + ch, R: wr, B: wb})
    }
    
    gap := Tune("gridGap")
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (SmartGridGuis.Length < A_Index) {
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            SmartGridGuis.Push(g)
        }
        g := SmartGridGuis[A_Index]
        g.BackColor := "111111"
        WinSetTransparent(100, g.Hwnd)
        
        gx := z.L + gap, gy := z.T + gap, gw := (z.R - z.L) - gap * 2, gh := (z.B - z.T) - gap * 2
        g.Show("x" gx " y" gy " w" gw " h" gh " NoActivate")
    }
    
    GridHoverZone := 0
    GridActive := true
}

UpdateSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridHoverZone
    
    MouseGetPos(&mx, &my)
    hovered := 0
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (mx >= z.L && mx <= z.R && my >= z.T && my <= z.B) {
            hovered := A_Index
            break
        }
    }
    
    if (hovered != GridHoverZone) {
        if (GridHoverZone > 0) {
            g := SmartGridGuis[GridHoverZone]
            g.BackColor := "111111"
            WinSetTransparent(100, g.Hwnd)
        }
        GridHoverZone := hovered
        if (hovered > 0) {
            g := SmartGridGuis[hovered]
            g.BackColor := "0078D7"
            WinSetTransparent(180, g.Hwnd)
        }
    }
}

HideSmartGrid() {
    global SmartGridGuis, GridActive, GridHoverZone
    for g in SmartGridGuis {
        g.Hide()
    }
    GridActive := false
    GridHoverZone := 0
}

ApplyGridZone(hwnd, zoneIndex) {
    global SmartGridZones
    if (zoneIndex < 1 || zoneIndex > SmartGridZones.Length)
        return
    z := SmartGridZones[zoneIndex]

    ; Unguarded, this throws when the window dies between FinishDrag's IsWindow
    ; check and here - which is a real race, because FinishDrag runs from a -50 ms
    ; one-shot. The throw killed the timer thread before HideSmartGrid() could
    ; run, stranding three dark zone overlays on screen until the app restarted.
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY)
        return
    frameW := fR - fL
    frameH := fB - fT
    try WinGetPos(,, &rawW, &rawH, hwnd)
    catch
        return
        
    diffW := rawW - frameW
    diffH := rawH - frameH
    diffX := fL - winX
    diffY := fT - winY
    
    finalX := z.L - diffX
    finalY := z.T - diffY
    finalW := (z.R - z.L) + diffW
    finalH := (z.B - z.T) + diffH
    
    gap := Tune("gridGap")
    destX := finalX + gap
    destY := finalY + gap
    destW := finalW - gap*2
    destH := finalH - gap*2
    
    try WinMove(destX, destY, destW, destH, hwnd)
    catch
        return
    RememberPosition(hwnd)

    global MomentumTiltEnabled
    if (MomentumTiltEnabled) {
        cpx := (z.L == 0) ? -15 : ((z.R >= A_ScreenWidth) ? 15 : 0)
        cpy := (z.T == 0) ? -15 : ((z.B >= A_ScreenHeight) ? 15 : 0)
        if (cpx != 0 || cpy != 0)
            BounceSqueeze(hwnd, destX, destY, destW, destH, cpx, cpy)
    }
}

; ============================================================================
; Mouse & Cursors FX
; ============================================================================

; Armed by SyncCursorFxTimer() rather than unconditionally at load.
SyncCursorFxTimer() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (BreatheCursorEnabled) {
        SetTimer(CheckMouseIdle, 1000)
        return
    }
    SetTimer(CheckMouseIdle, 0)
    if BreatheCursorActive {
        BreatheCursorActive := false
        StopBreatheCursor()
    }
}

global BreatheCursorActive := false
global BreatheGui := ""
global BreatheStart := 0

CheckMouseIdle() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (!BreatheCursorEnabled)
        return
        
    if (A_TimeIdleMouse > 10000) { 
        if (!BreatheCursorActive) {
            BreatheCursorActive := true
            StartBreatheCursor()
        }
    } else {
        if (BreatheCursorActive) {
            BreatheCursorActive := false
            StopBreatheCursor()
        }
    }
}

StartBreatheCursor() {
    global BreatheGui, BreatheStart
    if (!BreatheGui) {
        BreatheGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        BreatheGui.BackColor := "White"
        WinSetRegion("0-0 w40 h40 E", BreatheGui.Hwnd)
        WinSetTransparent(0, BreatheGui.Hwnd)
    }
    BreatheStart := QPC()
    SetTimer(UpdateBreathe, 16)
}

StopBreatheCursor() {
    global BreatheGui
    SetTimer(UpdateBreathe, 0)
    if (BreatheGui) {
        BreatheGui.Hide()
    }
}

UpdateBreathe() {
    global BreatheGui, BreatheStart, BreatheCursorActive
    if (!BreatheCursorActive) {
        SetTimer(UpdateBreathe, 0)
        BreatheGui.Hide()
        return
    }
    MouseGetPos(&mx, &my)
    
    ; QPC() already returns MILLISECONDS (count * 1000 / freq). Multiplying again
    ; turned this 3-second breathing cycle into a 3-millisecond one - a ~333 Hz
    ; strobe of a 20-40 px white circle rather than a slow pulse.
    t := QPC() - BreatheStart
    cycle := Mod(t, 3000) / 3000
    val := (Sin(cycle * 6.28318 - 1.57079) + 1) / 2
    
    size := Round(20 + 20 * val)
    alpha := Round(20 + 40 * val)
    
    WinSetRegion("0-0 w" size " h" size " E", BreatheGui.Hwnd)
    try WinSetTransparent(alpha, BreatheGui.Hwnd)
    
    DllCall("SetWindowPos", "ptr", BreatheGui.Hwnd, "ptr", -1, "int", mx - size//2, "int", my - size//2, "int", 0, "int", 0, "uint", 0x55)
}

global Ripples := []
SpawnRipple(x, y) {
    global Ripples
    idx := 0
    loop Ripples.Length {
        if (!Ripples[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Ripples.Length >= 5) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "White"
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0}
        Ripples.Push(r)
        idx := Ripples.Length
    }
    
    r := Ripples[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    
    SetTimer(UpdateRipples, 16)
}

UpdateRipples() {
    global Ripples
    now := QPC()
    activeCount := 0
    
    loop Ripples.Length {
        r := Ripples[A_Index]
        if (!r.Active)
            continue
            
        ; QPC() is already in milliseconds - see the note in UpdateBreathe. With
        ; the extra * 1000 the first tick arrived at t = 16000 against a 300 unit
        ; lifetime, so every ripple died before a single frame was drawn.
        t := now - r.Start
        if (t > 300) {
            r.Active := false
            r.Gui.Hide()
            continue
        }
        
        activeCount++
        ease := 1 - (1 - (t / 300)) ** 2
        size := Round(10 + 40 * ease)
        alpha := Round(80 * (1 - ease))
        
        WinSetRegion("0-0 w" size " h" size " E", r.Gui.Hwnd)
        try WinSetTransparent(alpha, r.Gui.Hwnd)
        DllCall("SetWindowPos", "ptr", r.Gui.Hwnd, "ptr", -1, "int", r.x - size//2, "int", r.y - size//2, "int", 0, "int", 0, "uint", 0x55)
    }
    
    if (activeCount == 0)
        SetTimer(UpdateRipples, 0)
}

global DragTrailGui := ""
global DragTrailActive := false
global DragTrailX := 0, DragTrailY := 0, DragTrailVX := 0, DragTrailVY := 0

CheckElasticDrag() {
    global DragTrailStartX, DragTrailStartY, DragTrailActive
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckElasticDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - DragTrailStartX) > 10 || Abs(my - DragTrailStartY) > 10) {
        SetTimer(CheckElasticDrag, 0)
        DragTrailActive := true
        StartDragTrail(mx, my)
    }
}

StartDragTrail(startX, startY) {
    global DragTrailGui, DragTrailX, DragTrailY, DragTrailVX, DragTrailVY
    if (!DragTrailGui) {
        DragTrailGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        DragTrailGui.BackColor := "Gray"
        WinSetRegion("0-0 w16 h16 E", DragTrailGui.Hwnd)
    }
    DragTrailX := startX
    DragTrailY := startY
    DragTrailVX := 0
    DragTrailVY := 0
    try WinSetTransparent(80, DragTrailGui.Hwnd)
    SetTimer(UpdateDragTrail, 16)
}

UpdateDragTrail() {
    global DragTrailGui, DragTrailActive, DragTrailX, DragTrailY, DragTrailVX, DragTrailVY
    if (!GetKeyState("LButton", "P")) {
        SetTimer(UpdateDragTrail, 0)
        DragTrailActive := false
        DragTrailGui.Hide()
        return
    }
    
    MouseGetPos(&mx, &my)
    
    dx := mx - DragTrailX
    dy := my - DragTrailY
    
    DragTrailVX += dx * 0.2
    DragTrailVY += dy * 0.2
    
    DragTrailVX *= 0.65 
    DragTrailVY *= 0.65
    
    DragTrailX += DragTrailVX
    DragTrailY += DragTrailVY
    
    DllCall("SetWindowPos", "ptr", DragTrailGui.Hwnd, "ptr", -1, "int", Round(DragTrailX - 8), "int", Round(DragTrailY - 8), "int", 0, "int", 0, "uint", 0x55)
}

global LastActiveHwnd := 0
global PushedBackWindows := Map()

; ApplyUi (when the checkbox is cleared) and Bye() both call this. PushBackWindow
; pins a window at 98% size and alpha 210, and BringForwardWindow was the only
; reversal - reachable only from ApplyFocusDepth, which only runs while the
; feature is on. So turning Focus Depth off, or exiting, left every window the
; user had ever switched away from permanently shrunk and translucent.
RestoreFocusDepth() {
    global PushedBackWindows
    for hwnd, orig in PushedBackWindows.Clone() {
        try CancelAnimation("FocusDepth_" hwnd)
        if (DllCall("IsWindow", "ptr", hwnd)) {
            try RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_USER)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_USER)
        }
    }
    PushedBackWindows := Map()
}

ApplyFocusDepth(newActive) {
    global LastActiveHwnd, PushedBackWindows
    if (LastActiveHwnd && LastActiveHwnd != newActive && DllCall("IsWindow", "ptr", LastActiveHwnd)) {
        PushBackWindow(LastActiveHwnd)
    }
    if (newActive && DllCall("IsWindow", "ptr", newActive)) {
        BringForwardWindow(newActive)
    }
    LastActiveHwnd := newActive
}

; RS_PRI_ANIM, not RS_PRI_USER, throughout this pair.
;
; Focus Depth fires on every activation, so at USER priority it out-ranked the
; glide, the bounce and the pulse on whatever window you had just switched away
; from - the depth animation won every arbitration and the other effect silently
; produced nothing. It is an ambient depth cue, not a user command; ANIM is the
; band it belongs in, and RestoreFocusDepth keeps USER because that IS explicit.
PushBackWindow(hwnd) {
    global PushedBackWindows
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return
        
    PushedBackWindows[hwnd] := {x: x, y: y, w: w, h: h}
    
    animKey := "FocusDepth_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150
    
    PushBackStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            nw := Round(w * 0.98)
            nh := Round(h * 0.98)
            nx := x + Round((w - nw) / 2)
            ny := y + Round((h - nh) / 2)
            RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
            try RS_SetAlpha(hwnd, 210, RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) ** 2
        scale := 1.0 - (0.02 * ease)
        nw := Round(w * scale)
        nh := Round(h * scale)
        nx := x + Round((w - nw) / 2)
        ny := y + Round((h - nh) / 2)
        alpha := Round(255 - (45 * ease))
        
        RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
        try RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, PushBackStep)
}

BringForwardWindow(hwnd) {
    global PushedBackWindows
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return
        
    if (!PushedBackWindows.Has(hwnd))
        return
        
    orig := PushedBackWindows[hwnd]
    PushedBackWindows.Delete(hwnd)
    
    animKey := "FocusDepth_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150
    
    BringForwardStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_ANIM)
            try RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) ** 2
        curW := w + Round((orig.w - w) * ease)
        curH := h + Round((orig.h - h) * ease)
        curX := orig.x + Round((orig.w - curW) / 2)
        curY := orig.y + Round((orig.h - curH) / 2)
        
        alpha := 210 + Round(45 * ease)
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        try RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, BringForwardStep)
}

NotchAnim(hwnd, startY, destY, fadeIn := true, onDone := "") {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
        
    animKey := "Notch_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animNotchMs")
    
    ; Needs a catch: x is read by NotchStep on every frame, and a bare `try` would
    ; leave it unset. Callers reach this from a hotkey and from one-shot timers.
    try WinGetPos(&x, &cy, &w, &h, hwnd)
    catch
        return

    NotchStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            try RS_SetAlpha(hwnd, fadeIn ? 220 : "Off", RS_PRI_USER)
            if onDone
                onDone()
            return false
        }
        
        ease := fadeIn ? (1 - (1 - t) ** 3) : (t ** 3)
        curY := Round(startY + (destY - startY) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        
        alpha := fadeIn ? Round(220 * ease) : Round(220 * (1 - ease))
        try RS_SetAlpha(hwnd, alpha, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, NotchStep)
}

; ONE global keyboard observer, shared by every feature that needs to know a key
; was pressed. A global hook wakes this process on every keystroke, so it is
; started and stopped to match its consumers rather than being left running at
; load. UpdateKeyboardHook() is the Sync* for it: ApplyUi calls it on every
; settings change, and the auto-execute call at the bottom of the file does the
; initial start once LoadSettings has run.
global SparkHook := InputHook("V L0")
SparkHook.OnKeyDown := OnObservedKeyDown

; When a key that is NOT a modifier was last pressed. IsDoublePress needs this to
; tell a deliberate double-tap from two ordinary shortcuts in a row.
global LastNonModifierKeyTime := 0

UpdateKeyboardHook() {
    global SparkHook, SparkTypingEnabled, MicKillSwitchEnabled, SpotlightEnabled
    ; Braces are required. AHK v2 has a Try/Catch/Else form, so a bare
    ; "try X" followed by "else" binds the else to the try, not to the if.
    if (SparkTypingEnabled || MicKillSwitchEnabled || SpotlightEnabled) {
        try SparkHook.Start()
    } else {
        try SparkHook.Stop()
    }
}

OnObservedKeyDown(ih, vk, sc) {
    global LastNonModifierKeyTime
    ; Shift/Ctrl/Alt (0x10-0x12), their L/R forms (0xA0-0xA5) and the Win keys
    ; (0x5B/0x5C) do not count - a double-tap gesture is made of those, so
    ; recording them here would make every gesture look like ordinary typing.
    if !(vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C
        || vk = 0xA0 || vk = 0xA1 || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5)
        LastNonModifierKeyTime := A_TickCount

    OnTypingSpark(ih, vk, sc)
}

global Sparks := []
OnTypingSpark(ih, vk, sc) {
    global SparkTypingEnabled
    if (!SparkTypingEnabled)
        return
        
    if !CaretGetPos(&cx, &cy)
        return
        
    SpawnSpark(cx, cy)
}

SpawnSpark(x, y) {
    global Sparks
    idx := 0
    loop Sparks.Length {
        if (!Sparks[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Sparks.Length >= 30) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "FFAA00"
        WinSetRegion("0-0 w4 h4 E", g.Hwnd)
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0, vx: 0, vy: 0}
        Sparks.Push(r)
        idx := Sparks.Length
    }
    
    r := Sparks[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    r.vx := (Random() - 0.5) * 6
    r.vy := (Random() - 0.5) * 6 - 2
    
    try WinSetTransparent(200, r.Gui.Hwnd)
    SetTimer(UpdateSparks, 16)
}

UpdateSparks() {
    global Sparks
    now := QPC()
    activeCount := 0
    
    loop Sparks.Length {
        r := Sparks[A_Index]
        if (!r.Active)
            continue
            
        ; QPC() is already in milliseconds - see the note in UpdateBreathe. Same
        ; bug as UpdateRipples: no spark ever survived to its first drawn frame.
        t := now - r.Start
        if (t > 400) {
            r.Active := false
            r.Gui.Hide()
            continue
        }
        
        activeCount++
        
        r.vy += 0.2 
        r.x += r.vx
        r.y += r.vy
        
        alpha := Round(200 * (1 - (t / 400)))
        
        try WinSetTransparent(alpha, r.Gui.Hwnd)
        DllCall("SetWindowPos", "ptr", r.Gui.Hwnd, "ptr", -1, "int", r.x, "int", r.y, "int", 0, "int", 0, "uint", 0x55)
    }
    
    if (activeCount == 0)
        SetTimer(UpdateSparks, 0)
}

global CurtainDropped := false
global CurtainWindows := Map()

; Gated in the hotkey criteria rather than re-sending #d from the body. With the
; feature off the key is simply not claimed, so Windows' own show-desktop runs -
; CLAUDE.md lists Win+D as deliberately not touched.
#HotIf CurtainDropEnabled
#d:: {
    global CurtainDropped, CurtainWindows

    if (CurtainDropped) {
        CurtainDropped := false
        for hwnd, rect in CurtainWindows {
            if DllCall("IsWindow", "ptr", hwnd) {
                CurtainBounceUp(hwnd, rect.x, rect.y, rect.w, rect.h)
            }
        }
        CurtainWindows := Map()
    } else {
        CurtainDropped := true
        CurtainWindows := Map()
        
        for hwnd in WinGetList() {
            if !IsSnappable(hwnd)
                continue
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
                
            try WinGetPos(&x, &y, &w, &h, hwnd)
            catch
                continue
                
            if (w == 0 || h == 0)
                continue
                
            CurtainWindows[hwnd] := {x: x, y: y, w: w, h: h}
            CurtainDropDown(hwnd, x, y, w, h)
        }
    }
}
#HotIf

; Bye() calls this. CurtainWindows is the ONLY record of where these windows came
; from, and dropping them parks every one of them below the screen - so exiting
; while the curtain is down used to leave the whole desktop off-screen with
; nothing anywhere that could put it back.
RestoreCurtain() {
    global CurtainDropped, CurtainWindows
    for hwnd, rect in CurtainWindows {
        if DllCall("IsWindow", "ptr", hwnd) {
            try CancelAnimation("Curtain_" hwnd)
            try RS_SetPos(hwnd, rect.x, rect.y, rect.w, rect.h, RS_PRI_USER)
        }
    }
    CurtainWindows := Map()
    CurtainDropped := false
}

CurtainDropDown(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 250
    destY := A_ScreenHeight + 50
    
    DropStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        
        ease := t ** 3
        curY := Round(y + (destY - y) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, DropStep)
}

CurtainBounceUp(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    startY := A_ScreenHeight + 50
    
    UpStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_USER)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        curY := Round(startY + (y - startY) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, UpStep)
}

global CarouselActive := false
global CarouselGui := ""
global CarouselIndex := 1
global CarouselWindows := []
global Thumbnails := []
global CarouselAngleOffset := 0

#HotIf CarouselAltTabEnabled && !CarouselActive
*!Tab:: {
    global CarouselActive, CarouselWindows, CarouselIndex, Thumbnails, CarouselAngleOffset, CarouselGui
    CarouselActive := true
    CarouselWindows := []
    Thumbnails := []
    CarouselIndex := 1
    CarouselAngleOffset := 0
    
    for hwnd in WinGetList() {
        if !IsSnappable(hwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        CarouselWindows.Push(hwnd)
    }
    if CarouselWindows.Length == 0 {
        CarouselActive := false
        Send("!{Tab}")
        return
    }
    
    CarouselGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    CarouselGui.BackColor := "111111"
    CarouselGui.Show("w" A_ScreenWidth " h" A_ScreenHeight " x0 y0")
    try WinSetTransparent(220, CarouselGui.Hwnd)
    
    for hwnd in CarouselWindows {
        thumbId := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", CarouselGui.Hwnd, "ptr", hwnd, "ptr*", &thumbId)
        Thumbnails.Push(thumbId)
    }
    
    SetTimer(UpdateCarousel, 16)
}
#HotIf

#HotIf CarouselActive
*!Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex++
    if (CarouselIndex > CarouselWindows.Length)
        CarouselIndex := 1
    CarouselAngleOffset += 1
}
*!+Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex--
    if (CarouselIndex < 1)
        CarouselIndex := CarouselWindows.Length
    CarouselAngleOffset -= 1
}
; Both Alt keys, plus Escape. The opening hotkey is *!Tab, which fires on either
; Alt - so closing on LAlt alone meant that opening the carousel with RAlt left a
; full-screen AlwaysOnTop window up, a 16 ms timer running, and #HotIf
; CarouselActive swallowing !Tab and !+Tab. Alt+Tab itself was then dead and the
; only way out was Task Manager.
~LAlt up::CloseCarousel(true)
~RAlt up::CloseCarousel(true)
~Esc::CloseCarousel(false)
#HotIf

CloseCarousel(activateChoice) {
    global CarouselActive, CarouselGui, CarouselWindows, CarouselIndex, Thumbnails
    if (!CarouselActive)
        return
    CarouselActive := false
    SetTimer(UpdateCarousel, 0)

    for thumbId in Thumbnails {
        try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", thumbId)
    }
    Thumbnails := []

    ; The chosen window can close while the carousel is open, and the index can
    ; be stale if the list was rebuilt - neither may throw out of a hotkey.
    hwnd := 0
    if (CarouselIndex >= 1 && CarouselIndex <= CarouselWindows.Length)
        hwnd := CarouselWindows[CarouselIndex]

    if (CarouselGui) {
        try RS_RemoveHwnd(CarouselGui.Hwnd)
        try CarouselGui.Destroy()
    }
    CarouselGui := ""

    if (activateChoice && hwnd && DllCall("IsWindow", "ptr", hwnd))
        try WinActivate(hwnd)
}

UpdateCarousel() {
    global CarouselGui, CarouselWindows, Thumbnails, CarouselIndex, CarouselAngleOffset, CarouselActive
    if (!CarouselActive)
        return
        
    if (CarouselAngleOffset > 0)
        CarouselAngleOffset *= 0.8
    else if (CarouselAngleOffset < 0)
        CarouselAngleOffset *= 0.8
        
    if (Abs(CarouselAngleOffset) < 0.05)
        CarouselAngleOffset := 0
        
    num := CarouselWindows.Length
    centerX := A_ScreenWidth / 2
    centerY := A_ScreenHeight / 2
    radiusX := A_ScreenWidth * 0.35
    radiusY := A_ScreenHeight * 0.15
    
    PI := 3.14159265
    angleStep := (2 * PI) / num
    
    loop num {
        idx := A_Index
        thumbId := Thumbnails[idx]
        
        dist := idx - CarouselIndex
        if (dist > num / 2)
            dist -= num
        if (dist < -num / 2)
            dist += num
            
        angle := (dist + CarouselAngleOffset) * angleStep + (PI / 2)
        
        z := Sin(angle)
        x := centerX + Cos(angle) * radiusX
        y := centerY + z * radiusY
        
        scale := 0.4 + (z + 1) * 0.3
        
        tw := Round(800 * scale)
        th := Round(450 * scale)
        tx := Round(x - tw / 2)
        ty := Round(y - th / 2)
        
        ; DWM_THUMBNAIL_PROPERTIES layout - this was wrong at all five call sites
        ; and is why no DWM thumbnail effect in this file ever rendered anything:
        ;
        ;    0  DWORD dwFlags
        ;    4  RECT  rcDestination          (4 x LONG)
        ;   20  RECT  rcSource               (4 x LONG)
        ;   36  BYTE  opacity
        ;   37  (3 bytes of padding)
        ;   40  BOOL  fVisible
        ;   44  BOOL  fSourceClientAreaOnly
        ;   48  = sizeof
        ;
        ; fVisible was written at 37, i.e. into the padding, so DWM read 0 at
        ; offset 40 - and since DWM_TNP_VISIBLE (0x08) was set it was explicitly
        ; told to keep the thumbnail hidden. Buffer(45) was also 3 bytes short of
        ; the struct while DWM_TNP_SOURCECLIENTAREAONLY (0x10) made DWM read
        ; offset 44-47, past the end of it. DWM_TNP_OPACITY (0x04) was never set,
        ; so every opacity write was ignored too.
        ;
        ; DWM_TNP_RECTSOURCE (0x02) is deliberately NOT set here: this site never
        ; writes rcSource, and claiming it left DWM using an empty {0,0,0,0} rect.
        props := Buffer(48, 0)
        NumPut("uint", 0x01 | 0x04 | 0x08 | 0x10, props, 0)
        NumPut("int", tx, props, 4)
        NumPut("int", ty, props, 8)
        NumPut("int", tx + tw, props, 12)
        NumPut("int", ty + th, props, 16)

        opacity := Round(255 * (0.3 + (z + 1) * 0.35))
        NumPut("char", opacity, props, 36)
        NumPut("int", 1, props, 40)

        DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", thumbId, "ptr", props)
    }
}

global MotionBlurScrollSpeed := 0
global MotionBlurLastTime := 0
global MotionBlurGui := ""
global MotionBlurThumb := 0
global MotionBlurActiveHwnd := 0

TriggerMotionBlur(hwnd, dir) {
    global MotionBlurScrollSpeed, MotionBlurLastTime, MotionBlurActiveHwnd
    now := QPC()
    dt := now - MotionBlurLastTime
    
    ; 120 ms, not 0.1. QPC() already returns MILLISECONDS, so the old threshold
    ; was a tenth of a millisecond - true between any two wheel events - and the
    ; accumulator was reset on every notch. The effect could never build up past
    ; one notch's worth, which is why it always looked like it did nothing.
    if (dt > 120 || hwnd != MotionBlurActiveHwnd)
        MotionBlurScrollSpeed := 0
        
    MotionBlurScrollSpeed += dir * 12
    MotionBlurLastTime := now
    MotionBlurActiveHwnd := hwnd
    
    SetTimer(RenderMotionBlur, 16)
}

RenderMotionBlur() {
    global MotionBlurScrollSpeed, MotionBlurGui, MotionBlurThumb, MotionBlurActiveHwnd
    
    MotionBlurScrollSpeed *= 0.82
    if (Abs(MotionBlurScrollSpeed) < 3 || !DllCall("IsWindow", "ptr", MotionBlurActiveHwnd)) {
        MotionBlurScrollSpeed := 0
        if (MotionBlurGui) {
            if (MotionBlurThumb)
                DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", MotionBlurThumb)
            MotionBlurGui.Destroy()
            MotionBlurGui := ""
            MotionBlurThumb := 0
        }
        SetTimer(RenderMotionBlur, 0)
        return
    }
    
    hwnd := MotionBlurActiveHwnd
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
        
    if (!MotionBlurGui) {
        MotionBlurGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        MotionBlurGui.BackColor := "EEFFFF"
        MotionBlurGui.Show("NA Hide")
        MotionBlurThumb := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", MotionBlurGui.Hwnd, "ptr", hwnd, "ptr*", &MotionBlurThumb)
    }
    
    offset := Round(MotionBlurScrollSpeed * 1.5)
    if (offset == 0)
        return
        
    DllCall("SetWindowPos", "ptr", MotionBlurGui.Hwnd, "ptr", -1, "int", x, "int", y, "int", w, "int", h, "uint", 0x10 | 0x40) ; SWP_NOACTIVATE | SWP_SHOWWINDOW
    
    ; See the struct layout note in UpdateCarousel. No rcSource here either, so
    ; DWM_TNP_RECTSOURCE (0x02) stays off.
    props := Buffer(48, 0)
    NumPut("uint", 0x01 | 0x04 | 0x08 | 0x10, props, 0) ; dwFlags
    NumPut("int", 0, props, 4)
    NumPut("int", offset, props, 8)
    NumPut("int", w, props, 12)
    NumPut("int", h + offset, props, 16)

    alpha := Min(Round(Abs(MotionBlurScrollSpeed) * 3), 120)
    NumPut("char", alpha, props, 36)
    NumPut("int", 1, props, 40)

    DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", MotionBlurThumb, "ptr", props)
    try WinSetTransColor("EEFFFF " alpha, MotionBlurGui.Hwnd)
}

global TaskbarWaveGui := ""
global TaskbarWaveThumb := 0

RenderTaskbarWave() {
    global TaskbarWaveGui, TaskbarWaveThumb, TaskbarWaveEnabled

    ; The flag check is INSIDE the teardown condition, not above it. It used to
    ; return first, which meant unchecking the box while the mouse was over the
    ; taskbar skipped the only cleanup path there is - leaving a 100 px
    ; AlwaysOnTop window stuck on screen, unreachable, until the app restarted.
    if (!TaskbarWaveEnabled || !IsMouseOverTaskbar()) {
        if (TaskbarWaveGui) {
            try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", TaskbarWaveThumb)
            try RS_RemoveHwnd(TaskbarWaveGui.Hwnd)
            try TaskbarWaveGui.Destroy()
            TaskbarWaveGui := ""
            TaskbarWaveThumb := 0
        }
        return
    }

    MouseGetPos(&mx, &my)
    hwnd := WinExist("ahk_class Shell_TrayWnd")
    if (!hwnd)
        return
        
    ; A bare `try` leaves tx/ty UNSET on failure and srcX/srcY below read them.
    ; This runs on the 32 ms CheckTaskbarAndUI timer, so that throw would kill
    ; Start Menu Blur, Toast Bounce, Lightsaber Seam and Privacy Blur along with
    ; this feature for the rest of the session.
    try WinGetPos(&tx, &ty, &tw, &th, hwnd)
    catch
        return

    if (!TaskbarWaveGui) {
        TaskbarWaveGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        TaskbarWaveGui.BackColor := "000000"
        TaskbarWaveThumb := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", TaskbarWaveGui.Hwnd, "ptr", hwnd, "ptr*", &TaskbarWaveThumb)
        WinSetTransColor("000000 255", TaskbarWaveGui.Hwnd) 
        WinSetRegion("0-0 w100 h100 E", TaskbarWaveGui.Hwnd) 
        TaskbarWaveGui.Show("NA x0 y0 w100 h100 Hide")
    }
    
    size := 100
    zoom := 1.3
    
    srcX := Round(mx - tx - (size / zoom / 2))
    srcY := Round(my - ty - (size / zoom / 2))
    srcW := Round(size / zoom)
    srcH := Round(size / zoom)
    
    destX := Round(mx - size / 2)
    destY := Round(my - size / 2)
    
    DllCall("SetWindowPos", "ptr", TaskbarWaveGui.Hwnd, "ptr", -1, "int", destX, "int", destY, "int", size, "int", size, "uint", 0x10 | 0x40)
    
    ; See the struct layout note in UpdateCarousel. rcSource IS written here, so
    ; DWM_TNP_RECTSOURCE (0x02) is correct.
    props := Buffer(48, 0)
    NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
    NumPut("int", 0, props, 4)
    NumPut("int", 0, props, 8)
    NumPut("int", size, props, 12)
    NumPut("int", size, props, 16)

    NumPut("int", srcX, props, 20)
    NumPut("int", srcY, props, 24)
    NumPut("int", srcX + srcW, props, 28)
    NumPut("int", srcY + srcH, props, 32)

    NumPut("char", 255, props, 36)
    NumPut("int", 1, props, 40)

    DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", TaskbarWaveThumb, "ptr", props)
}

global StartMenuBlurGui := ""
global KnownToasts := Map()

CheckTaskbarAndUI() {
    global TaskbarWaveEnabled, StartMenuBlurEnabled, ToastBounceEnabled, LightsaberSeamEnabled
    
    ; Called unconditionally on purpose. Each of these checks its own flag as its
    ; FIRST act and tears its overlay down when the flag is off; gating them here
    ; instead is what stranded the taskbar magnifier, the Start-menu blur and the
    ; lightsaber glow on screen when their box was unchecked mid-effect.
    RenderTaskbarWave()
    CheckStartMenu()
    CheckLightsaber()
    CheckPrivacyBlur()

    ; Toast bounce holds no overlay of its own - it only animates shell windows -
    ; so there is nothing to clean up and it can stay gated.
    if (ToastBounceEnabled)
        CheckToasts()
}

global LS_Gui := 0
global LS_Active := false
global LS_Hwnd := 0
global LS_Alpha := 0
global LS_Progress := 0

; Built on first use rather than at startup, so a disabled feature owns no
; window. Returns false if the overlay could not be created, which is the only
; thing CheckLightsaber needs to know.
InitLightsaber() {
    global LS_Gui, LS_Hwnd
    if (LS_Gui && LS_Hwnd && DllCall("IsWindow", "ptr", LS_Hwnd))
        return true
    try {
        LS_Gui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        LS_Gui.BackColor := "00FFFF"
        LS_Hwnd := LS_Gui.Hwnd
        WinSetTransparent(0, LS_Hwnd)
        return true
    }
    LS_Gui := 0, LS_Hwnd := 0
    return false
}

; The enabled test lives INSIDE this function, not at the CheckTaskbarAndUI call
; site, for the same reason RenderTaskbarWave's does: unchecking the box while the
; glow is lit used to stop the only code that could ever take it down, leaving a
; cyan bar welded across a window edge until the app restarted.
CheckLightsaber() {
    global LS_Active, LS_Hwnd, LS_Alpha, LS_Progress, LS_Gui, LightsaberSeamEnabled

    if (!LightsaberSeamEnabled) {
        if (LS_Active || LS_Alpha > 0) {
            LS_Active := false
            LS_Alpha := 0
            try DllCall("ShowWindow", "ptr", LS_Hwnd, "int", 0)   ; SW_HIDE
        }
        return
    }

    MouseGetPos(&mx, &my, &mHwnd)
    cursor := A_Cursor

    if ((cursor == "SizeWE" || cursor == "SizeNS") && mHwnd) {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, mHwnd)
            
            isEdge := false
            edgeX := wx
            edgeY := wy
            edgeW := 3
            edgeH := 3
            
            if (cursor == "SizeWE") {
                isLeftEdge := Abs(mx - wx) < 20
                isRightEdge := Abs(mx - (wx + ww)) < 20
                if (isLeftEdge || isRightEdge) {
                    isEdge := true
                    edgeX := isLeftEdge ? wx - 1 : wx + ww - 2
                    edgeY := wy
                    edgeW := 3
                    edgeH := wh
                }
            } else if (cursor == "SizeNS") {
                isTopEdge := Abs(my - wy) < 20
                isBottomEdge := Abs(my - (wy + wh)) < 20
                if (isTopEdge || isBottomEdge) {
                    isEdge := true
                    edgeX := wx
                    edgeY := isTopEdge ? wy - 1 : wy + wh - 2
                    edgeW := ww
                    edgeH := 3
                }
            }
            
            if (isEdge) {
                if (!LS_Active) {
                    if !InitLightsaber()
                        return
                    LS_Active := true
                    LS_Progress := 0
                    if (cursor == "SizeWE")
                        LS_Gui.Show("NA x" edgeX " y" my " w" edgeW " h2")
                    else
                        LS_Gui.Show("NA x" mx " y" edgeY " w2 h" edgeH)
                }
                
                if (LS_Progress < 1) {
                    LS_Progress += 0.12 
                    if (LS_Progress > 1)
                        LS_Progress := 1
                }
                
                ease := 1 - (1 - LS_Progress) ** 3 
                
                curY := my - (my - edgeY) * ease
                curH := 2 + (edgeH - 2) * ease
                
                curX := mx - (mx - edgeX) * ease
                curW := 2 + (edgeW - 2) * ease
                
                if (cursor == "SizeWE") {
                    DllCall("SetWindowPos", "ptr", LS_Hwnd, "ptr", -1, "int", edgeX, "int", Round(curY), "int", edgeW, "int", Round(curH), "uint", 0x14 | 0x40)
                } else {
                    DllCall("SetWindowPos", "ptr", LS_Hwnd, "ptr", -1, "int", Round(curX), "int", edgeY, "int", Round(curW), "int", edgeH, "uint", 0x14 | 0x40)
                }
                
                if (LS_Alpha < 180) {
                    LS_Alpha += 25
                    if (LS_Alpha > 180)
                        LS_Alpha := 180
                    WinSetTransparent(LS_Alpha, LS_Hwnd)
                }
                return
            }
        }
    }
    
    if (LS_Active) {
        if (LS_Alpha > 0) {
            LS_Alpha -= 25
            if (LS_Alpha <= 0) {
                LS_Alpha := 0
                LS_Active := false
                DllCall("ShowWindow", "ptr", LS_Hwnd, "int", 0) 
            } else {
                WinSetTransparent(LS_Alpha, LS_Hwnd)
            }
        }
    }
}

; Same shape, and this one is worse when it goes wrong: the stranded overlay is a
; full-screen 170-alpha black sheet, so switching the feature off while the Start
; menu was open used to leave the whole desktop dimmed until restart.
CheckStartMenu() {
    global StartMenuBlurGui, StartMenuBlurEnabled

    if (!StartMenuBlurEnabled) {
        if (StartMenuBlurGui) {
            FadeGui(StartMenuBlurGui, 0, 0, true)
            StartMenuBlurGui := ""
        }
        return
    }

    startHwnd := WinExist("Start ahk_class Windows.UI.Core.CoreWindow")
    if (!startHwnd)
        startHwnd := WinExist("Start ahk_class Windows.UI.Composition.DesktopWindowContentBridge")
        
    isVisible := false
    if (startHwnd && DllCall("IsWindowVisible", "ptr", startHwnd)) {
        isVisible := true
    }
    
    if (isVisible && !StartMenuBlurGui) {
        StartMenuBlurGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        StartMenuBlurGui.BackColor := "000000"
        StartMenuBlurGui.Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
        DllCall("SetWindowPos", "ptr", StartMenuBlurGui.Hwnd, "ptr", startHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13) 
        FadeGui(StartMenuBlurGui, 170)
        
        ; Runs on a 32 ms timer, so a throw here would pop an error dialog and
        ; kill the timer - taking Taskbar Wave, Toast Bounce, Lightsaber Seam and
        ; Privacy Blur down with it. A bare `try` leaves sx/sy UNSET when the
        ; query fails, and the next line reads them.
        try WinGetPos(&sx, &sy, &sw, &sh, startHwnd)
        catch
            return
        RS_SetPos(startHwnd, sx, sy + 50, -1, -1, RS_PRI_USER)
        AnimStartMenuSlide(startHwnd, sx, sy + 50, sy)
    } else if (!isVisible && StartMenuBlurGui) {
        FadeGui(StartMenuBlurGui, 0, 0, true)
        StartMenuBlurGui := ""
    }
}

; x is a real coordinate, not a placeholder. RS_SetPos treats a negative value as
; SWP_NOSIZE for w/h ONLY - x and y are stored verbatim - so passing -1 as x here
; slammed the Start menu to x = -1 on every frame and it slid down the left edge
; of the screen instead of up from the taskbar.
AnimStartMenuSlide(hwnd, x, startY, destY) {
    animKey := "StartSlide"
    CancelAnimation(animKey)
    start := QPC()
    ms := 300

    SlideStep(dt, now) {
        if (!DllCall("IsWindowVisible", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        ease := 1 - (1 - t) ** 3
        curY := Round(startY + (destY - startY) * ease)
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, SlideStep)
}

CheckToasts() {
    global KnownToasts
    list := WinGetList("New notification ahk_class Windows.UI.Core.CoreWindow")
    for hwnd in list {
        if (!KnownToasts.Has(hwnd)) {
            KnownToasts[hwnd] := true
            ; Runs on a 32 ms timer and enumerates shell toast windows, which
            ; ShellExperienceHost creates and destroys constantly - so the window
            ; dying between WinGetList above and WinGetPos here is routine, not
            ; exotic. A bare `try` leaves x/y/w/h UNSET and the next line reads w,
            ; which throws OUTSIDE the try and kills this timer - and with it
            ; Taskbar Wave, Start Menu Blur, Lightsaber Seam and Privacy Blur.
            try WinGetPos(&x, &y, &w, &h, hwnd)
            catch
                continue
            if (w > 0) {
                AnimToastBounce(hwnd, x + 350, x, y)
            }
        }
    }
    
    for hwnd in KnownToasts.Clone() {
        if (!DllCall("IsWindow", "ptr", hwnd))
            KnownToasts.Delete(hwnd)
    }
}

; y is a real coordinate. RS_SetPos treats a negative value as SWP_NOSIZE for w/h
; ONLY - x and y are stored verbatim - so passing -1 as y here slammed every toast
; to y = -1 and they flew across the top of the screen instead of bouncing in at
; their own height.
AnimToastBounce(hwnd, startX, destX, y) {
    animKey := "Toast_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 500

    BounceStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, destX, y, -1, -1, RS_PRI_USER)
            return false
        }
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        curX := Round(startX + (destX - startX) * ease)
        RS_SetPos(hwnd, curX, y, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, BounceStep)
}

; The largest idle cost in the program had no Sync* at all: this was armed
; unconditionally at load and ran ~31 times a second forever, and four of its
; five consumers default ON. CheckToasts alone enumerates every top-level window
; with a title filter on each tick.
;
; One tick is still needed after the last consumer is switched off, so each
; sub-check can tear its overlay down - hence the deferred stop rather than an
; immediate one.
SyncTaskbarUiTimer() {
    global TaskbarWaveEnabled, StartMenuBlurEnabled, ToastBounceEnabled
    global LightsaberSeamEnabled, PrivacyBlurEnabled, PrivacyBlurWindows
    ; PrivacyBlur counts only while something is actually marked private -
    ; the flag alone gives the poll nothing to do. AddPrivacyBlur and
    ; RemovePrivacyBlur call back in here when that changes.
    wanted := TaskbarWaveEnabled || StartMenuBlurEnabled || ToastBounceEnabled
            || LightsaberSeamEnabled || (PrivacyBlurEnabled && PrivacyBlurWindows.Count > 0)
    if (wanted) {
        SetTimer(CheckTaskbarAndUI, 32)
        return
    }
    CheckTaskbarAndUI()            ; final pass: every sub-check cleans up
    SetTimer(CheckTaskbarAndUI, 0)
}

; ----------------------------------------------------------------------------
; 5. Black Hole Delete
; ----------------------------------------------------------------------------
global ActiveDeleteGuis := Map()

#HotIf BlackHoleDeleteEnabled && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class WorkerW") || WinActive("ahk_class Progman")) && A_Cursor != "IBeam"
~Delete:: {
    hwnd := WinExist("A")
    TriggerBlackHoleDelete(hwnd)
}
#HotIf

TriggerBlackHoleDelete(hwnd) {
    global ActiveDeleteGuis
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "EEFFFF"
    
    thumb := 0
    DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
    
    size := 140
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    srcX := mx - wx - (size/2)
    srcY := my - wy - (size/2)
    
    guiObj.Show("NA x" (mx - size/2) " y" (my - size/2) " w" size " h" size)
    WinSetTransColor("EEFFFF", guiObj.Hwnd)
    
    animKey := "DeleteHole_" . guiObj.Hwnd
    start := QPC()
    ms := 600
    
    startX := mx - size/2
    startY := my - size/2
    
    ; MonitorGetPrimary takes no parameters - it RETURNS the monitor number.
    prim := MonitorGetPrimary()
    MonitorGet(prim, &mL, &mT, &mR, &mB)
    destX := mL + 50
    destY := mT + 50
    
    distX := Abs(destX - startX)
    distY := Abs(destY - startY)
    
    ActiveDeleteGuis[animKey] := {gui: guiObj, thumb: thumb}
    
    Step(dt, now) {
        if (!ActiveDeleteGuis.Has(animKey))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            CleanDeleteGui(animKey)
            return false
        }
        
        ease := t * t * t 
        
        curX := startX + (destX - startX) * ease
        curY := startY + (destY - startY) * ease
        
        if (distX > distY) {
            curW := Round(size * (1 + ease * 2)) 
            curH := Round(size * (1 - ease * 0.8)) 
        } else {
            curW := Round(size * (1 - ease * 0.8)) 
            curH := Round(size * (1 + ease * 2)) 
        }
        
        scaleDown := 1 - ease
        curW := Round(curW * scaleDown)
        curH := Round(curH * scaleDown)
        
        if (curW < 1)
            curW := 1
        if (curH < 1)
            curH := 1
            
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", curW, "int", curH, "uint", 0x14) 
        
        ; See the struct layout note in UpdateCarousel.
        props := Buffer(48, 0)
        NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
        NumPut("int", 0, props, 4)
        NumPut("int", 0, props, 8)
        NumPut("int", curW, props, 12)
        NumPut("int", curH, props, 16)

        NumPut("int", Round(srcX), props, 20)
        NumPut("int", Round(srcY), props, 24)
        NumPut("int", Round(srcX + size), props, 28)
        NumPut("int", Round(srcY + size), props, 32)

        alpha := Round(255 * (1 - ease))
        NumPut("char", alpha, props, 36)
        NumPut("int", 1, props, 40)

        DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", props)
        return true
    }
    RegisterAnimation(animKey, Step)
}

CleanDeleteGui(animKey) {
    global ActiveDeleteGuis
    if (ActiveDeleteGuis.Has(animKey)) {
        obj := ActiveDeleteGuis[animKey]
        DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", obj.thumb)
        obj.gui.Destroy()
        ActiveDeleteGuis.Delete(animKey)
    }
}

; ----------------------------------------------------------------------------
; 6. Shatter to Close
; ----------------------------------------------------------------------------
global ActiveShatters := Map()

#HotIf ShatterEnabled
+!F4:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        TriggerShatterClose(hwnd)
    }
}
#HotIf

TriggerShatterClose(hwnd) {
    global ActiveShatters
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    gridX := 4
    gridY := 4
    pieceW := ww / gridX
    pieceH := wh / gridY
    
    shards := []
    
    loop gridX {
        col := A_Index
        loop gridY {
            row := A_Index
            
            guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            guiObj.BackColor := "EEFFFF"
            WinSetTransColor("EEFFFF", guiObj.Hwnd)
            
            thumb := 0
            DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
            
            srcX := (col - 1) * pieceW
            srcY := (row - 1) * pieceH
            
            cx := wx + srcX + pieceW/2
            cy := wy + srcY + pieceH/2
            
            winCx := wx + ww/2
            winCy := wy + wh/2
            
            vx := (cx - winCx) * (Random(15, 40) / 100) 
            vy := (cy - winCy) * (Random(15, 40) / 100) - Random(5, 20) 
            
            spinW := Random(1, 8) * 0.1
            spinH := Random(1, 8) * 0.1
            
            shards.Push({gui: guiObj, thumb: thumb, x: wx + srcX, y: wy + srcY, w: pieceW, h: pieceH, srcX: srcX, srcY: srcY, vx: vx, vy: vy, spinW: spinW, spinH: spinH})
        }
    }
    
    animKey := "Shatter_" . hwnd

    ; Every other animation producer in this file cancels its own key before
    ; re-registering. Without it a second Shift+Alt+F4 on the same window
    ; overwrote the map entry and orphaned the first batch of 16 Guis and 16 DWM
    ; thumbnails, with nothing left holding a reference that could free them.
    CancelAnimation(animKey)
    CleanShatter(animKey)

    ; The real window is parked far off-screen so only the shards are visible.
    ; wx/wy go into the map BEFORE that happens: this is the only record of where
    ; it belongs, and Bye() needs it to put the window back if we exit mid-flight.
    ActiveShatters[animKey] := {shards: shards, hwnd: hwnd, x: wx, y: wy}

    RS_SetPos(hwnd, -19999, wy, -1, -1, RS_PRI_USER)

    start := QPC()
    ms := 1000

    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            CleanShatter(animKey)
            if (DllCall("IsWindow", "ptr", hwnd)) {
                try RS_SetPos(hwnd, wx, wy, -1, -1, RS_PRI_USER)
                try WinClose(hwnd)
            }
            return false
        }
        
        alpha := Round(255 * (1 - (t ** 2))) 
        
        for s in shards {
            s.vy += 1.2 ; Gravity
            s.x += s.vx
            s.y += s.vy
            
            curW := s.w * Abs(Cos(t * 15 * s.spinW))
            curH := s.h * Abs(Cos(t * 15 * s.spinH))
            
            if (curW < 1)
                curW := 1
            if (curH < 1)
                curH := 1
                
            curX := s.x + (s.w - curW)/2
            curY := s.y + (s.h - curH)/2
            
            DllCall("SetWindowPos", "ptr", s.gui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", Round(curW), "int", Round(curH), "uint", 0x14 | 0x40) 
            
            ; See the struct layout note in UpdateCarousel.
            props := Buffer(48, 0)
            NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
            NumPut("int", 0, props, 4)
            NumPut("int", 0, props, 8)
            NumPut("int", Round(curW), props, 12)
            NumPut("int", Round(curH), props, 16)

            NumPut("int", Round(s.srcX), props, 20)
            NumPut("int", Round(s.srcY), props, 24)
            NumPut("int", Round(s.srcX + s.w), props, 28)
            NumPut("int", Round(s.srcY + s.h), props, 32)

            NumPut("char", alpha, props, 36)
            NumPut("int", 1, props, 40)

            DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", s.thumb, "ptr", props)
        }
        return true
    }
    
    RegisterAnimation(animKey, Step)
}

CleanShatter(animKey) {
    global ActiveShatters
    if (ActiveShatters.Has(animKey)) {
        obj := ActiveShatters[animKey]
        for s in obj.shards {
            DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", s.thumb)
            s.gui.Destroy()
        }
        ActiveShatters.Delete(animKey)
    }
}

; Bye() calls this. TriggerShatterClose parks the real window at x = -19999 and
; the ONLY thing that ever moves it back is the animation's final frame - which
; never arrives if the callback throws (the scheduler silently deregisters it) or
; if we exit mid-flight. The window was then alive, invisible and unrecoverable.
RestoreShatters() {
    global ActiveShatters
    for animKey, obj in ActiveShatters.Clone() {
        if (DllCall("IsWindow", "ptr", obj.hwnd))
            try RS_SetPos(obj.hwnd, obj.x, obj.y, -1, -1, RS_PRI_USER)
        try CancelAnimation(animKey)
        try CleanShatter(animKey)
    }
}

; ----------------------------------------------------------------------------
; 8. Privacy Blur on Unfocus
; ----------------------------------------------------------------------------

#HotIf PrivacyBlurEnabled
#!b:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        if (PrivacyBlurWindows.Has(hwnd)) {
            RemovePrivacyBlur(hwnd)
        } else {
            AddPrivacyBlur(hwnd)
        }
    }
}
#HotIf

AddPrivacyBlur(hwnd) {
    global PrivacyBlurWindows
    if (PrivacyBlurWindows.Has(hwnd))
        return
        
    guiObj := Gui("-Caption +ToolWindow -DPIScale +E0x20")
    guiObj.Opt("+Owner" hwnd)
    guiObj.BackColor := "222222"
    WinSetTransparent(0, guiObj.Hwnd)
    
    accent := Buffer(16, 0)
    NumPut("int", 3, accent, 0) 
    NumPut("int", 2, accent, 4) 
    NumPut("int", 0x88222222, accent, 8) 
    NumPut("int", 0, accent, 12) 
    
    data := Buffer(24, 0)
    NumPut("int", 19, data, 0) 
    NumPut("ptr", accent.Ptr, data, A_PtrSize)
    NumPut("int", 16, data, A_PtrSize + A_PtrSize)
    
    DllCall("user32\SetWindowCompositionAttribute", "ptr", guiObj.Hwnd, "ptr", data)
    
    PrivacyBlurWindows[hwnd] := {gui: guiObj, active: false}
    ; The first private window is what makes the 32 ms poll necessary.
    SyncTaskbarUiTimer()
}

RemovePrivacyBlur(hwnd) {
    global PrivacyBlurWindows
    if (PrivacyBlurWindows.Has(hwnd)) {
        try PrivacyBlurWindows[hwnd].gui.Destroy()
        PrivacyBlurWindows.Delete(hwnd)
        SyncTaskbarUiTimer()      ; the last one lets the poll stop
    }
}

CheckPrivacyBlur() {
    global PrivacyBlurWindows, PrivacyBlurEnabled, BossKeyActive
    ; Switched off: take the frosted sheets down. Returning early instead left an
    ; opaque overlay welded over every window that had been marked private, with
    ; the feature that owns it disabled and no way to reach it - the same failure
    ; as the Start-menu blur and the lightsaber glow.
    if (!PrivacyBlurEnabled) {
        for hwnd, obj in PrivacyBlurWindows {
            if obj.active {
                obj.active := false
                try CancelAnimation("BlurFade_" obj.gui.Hwnd)
                try DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)   ; SW_HIDE
            }
        }
        return
    }

    ; With every window hidden nothing is active, so every private window would
    ; take the inactive branch below and get SWP_SHOWWINDOW plus a fade to opaque
    ; - drawing the shape of what the user just hid onto the empty desktop.
    if (BossKeyActive)
        return

    activeHwnd := WinExist("A")

    ; Collect, then delete. Deleting the current item shifts the remainder under
    ; the live enumerator index and silently skips the next private window - the
    ; documented Map rule that MC_Expire and BreathingAnimatorStep already follow.
    dead := []
    for hwnd, obj in PrivacyBlurWindows {
        if (!DllCall("IsWindow", "ptr", hwnd)) {
            try obj.gui.Destroy()
            dead.Push(hwnd)
            continue
        }
        
        isActive := (hwnd == activeHwnd)
        
        if (isActive) {
            if (obj.active) {
                obj.active := false
                
                animKey := "BlurFade_" . obj.gui.Hwnd
                start := QPC()
                ms := 200
                Step(dt, now) {
                    t := (now - start) / ms
                    if (t >= 1) {
                        DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)
                        return false
                    }
                    WinSetTransparent(Round(255 * (1 - (t**2))), obj.gui.Hwnd)
                    return true
                }
                RegisterAnimation(animKey, Step)
            }
        } else {
            try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            catch
                continue
                
            if (!obj.active) {
                obj.active := true
                DllCall("SetWindowPos", "ptr", obj.gui.Hwnd, "ptr", -1, "int", wx, "int", wy, "int", ww, "int", wh, "uint", 0x14 | 0x40) 
                
                animKey := "BlurFade_" . obj.gui.Hwnd
                start := QPC()
                ms := 300
                StepOut(dt, now) {
                    t := (now - start) / ms
                    if (t >= 1) {
                        WinSetTransparent(255, obj.gui.Hwnd)
                        return false
                    }
                    WinSetTransparent(Round(255 * (t**3)), obj.gui.Hwnd)
                    return true
                }
                RegisterAnimation(animKey, StepOut)
            } else {
                DllCall("SetWindowPos", "ptr", obj.gui.Hwnd, "ptr", -1, "int", wx, "int", wy, "int", ww, "int", wh, "uint", 0x14)
            }
        }
    }

    for hwnd in dead
        PrivacyBlurWindows.Delete(hwnd)
}

; ============================================================================
; Deferred init - MUST stay at the bottom of the file
; ============================================================================
; Top-level "global X := ..." initialisers execute in file order as part of the
; auto-execute thread, so anything that writes a global declared further down the
; file gets silently clobbered when execution reaches that declaration. These
; three used to be called next to LoadSettings() near the top, which reset
; SF_Hwnd / LS_Gui / LS_Hwnd to 0 immediately after they were assigned and armed
; ShakeDetector's 40 ms timer before the variables it reads existed. Anything
; that touches a global declared below line ~150 belongs here, not up there.
; InitShakeFind() and InitLightsaber() are NOT called here any more - both build
; their overlay lazily, on first use, so a feature nobody enabled costs nothing.
SyncShakeDetector()
SyncCursorFxTimer()
SyncTaskbarUiTimer()
UpdateKeyboardHook()
