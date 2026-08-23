; Tuning registry - one row per user-tunable NUMBER, and the runtime built on it.
;
; Function definitions and global initialisers only, no top-level statements.
;
; TUNE_SPEC is the single source of truth for a number's INI section and key, its
; default, its lo/hi bounds, its step, its decimal places, and the settings page,
; label and hint it is rendered with. Loading, clamping, persistence and the
; settings control are all GENERATED from it. Adding a setting is one TUNE_SPEC
; row plus one TuneRow() call on the page it belongs to. Nothing else.
;
; It exists because the original five numeric settings repeated their range in
; three places - the declared default, the clamp block at the end of LoadSettings
; and the Clamp() call in ApplyUi - and those had already drifted.
;
; Three rules come with it:
;
; lo IS THE LOWEST USABLE VALUE, not the lowest legal one. A feature is switched
; off with its checkbox, never by typing 0 into its duration. Where 0 does mean
; something - "stop where you let go", "screen edges only", "gate disabled" - the
; row's hint says so.
;
; step IS DOCUMENTATION, NOT QUANTISATION. These are typed fields; snapping 33 to
; 35 while someone is typing 330 is hostile. It is surfaced in the hint instead.
;
; OPACITY IS ALWAYS A PERCENTAGE, stored 0-100 and converted by TuneAlpha(), so
; the unit never varies between features. Durations are always ms, distances px.
;
; The map is TUNE_VAL, not TUNE: AHK identifiers are case-insensitive, so a TUNE
; map and a Tune() accessor are the same name and the script refuses to load.

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
  TS("snapDist"     , "snap"     , "distance"    ,     30,     4,    120,     1, 0, "win"    , "Snap distance"          , "px from an edge, at an average drag speed")
, TS("snapAdapt"    , "snap"     , "adapt"       ,   0.55,     0,      1,  0.05, 2, "win"    , "Snap speed response"    , "0 = fixed reach, 1 = strongly speed-scaled")
, TS("snapHyst"     , "snap"     , "hyst"        ,      6,     0,     30,     1, 0, "win"    , "Edge stickiness"        , "px an edge you already touch wins ties by")
, TS("snapBoost"    , "snap"     , "cornerBoost" ,    2.2,     1,      5,   0.1, 1, "win"    , "Corner boost"           , "x stronger at corners")
, TS("snapProx"     , "snap"     , "neighbour"   ,     90,     0,    400,    10, 0, "win"    , "Neighbour reach"        , "px to nearby windows, 0 = edges only")
, TS("glideThrow"   , "glide"    , "throw"       ,    0.9,     0,      3,   0.1, 1, "win"    , "Throw strength"         , "0 = stop where you let go")
, TS("glideMs"      , "glide"    , "ms"          ,    650,   120,   1500,    10, 0, "win"    , "Slide time"             , "ms maximum")
, TS("glideMax"     , "glide"    , "max"         ,    500,   100,   2000,    50, 0, "win"    , "Throw distance"         , "px a flick can carry a window")
, TS("glideSettle"  , "glide"    , "settle"      ,      6,     0,     30,     1, 0, "win"    , "Settle overshoot"       , "px past the target on a hard landing, 0 = none")
, TS("parallaxMin"  , "memory"   , "parallaxmin" ,     24,    10,    100,     5, 0, "win"    , "Drag opacity floor"     , "% at full drag speed")
, TS("parallaxFrom" , "memory"   , "parallaxfrom",     40,     0,   2000,    10, 0, "win"    , "Drag fade starts at"    , "px/s of drag speed before it fades at all")
, TS("parallaxFull" , "memory"   , "parallaxfull",    600,   100,   6000,    50, 0, "win"    , "Drag fade full at"      , "px/s where the opacity floor is reached")
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
, TS("keyVol"       , "mouse"    , "keysoundvol" ,     80,     5,    100,     5, 0, "multi"  , "Keystroke volume"       , "% of full scale")
, TS("hotkeyVol"    , "mouse"    , "hotkeysoundvol",   90,     5,    100,     5, 0, "multi"  , "Hotkey sound volume"    , "% of full scale")
, TS("keyTone"      , "mouse"    , "keysoundtone",    100,    60,    180,     5, 0, "multi"  , "Keystroke pitch"        , "% - lower is a deeper thock, higher is a sharper clack")
, TS("shakeCount"   , "mouse"    , "shakecount"  ,      6,     3,     15,     1, 0, "multi"  , "Shake sensitivity"      , "direction changes to trigger")
, TS("shakeSize"    , "mouse"    , "shakesize"   ,    150,    50,    400,    10, 0, "multi"  , "Shake highlight size"   , "px across")
, TS("cornerSize"   , "corners"  , "size"        ,      5,     1,     40,     1, 0, "corners", "Corner size"            , "px square that arms the corner")
, TS("cornerDelay"  , "corners"  , "delay"       ,    150,     0,   2000,    25, 0, "corners", "Hold time"              , "ms in the corner, 0 = instant")
, TS("animOpenMs"   , "anim"     , "openms"      ,    240,    60,   1000,    10, 0, "anim"   , "New window"             , "ms for the open animation")
, TS("animOpenSlide", "anim"     , "openslide"   ,     30,     5,    200,     5, 0, "anim"   , "Slide-in distance"      , "px Ghost Slide-In rises")
, TS("animBounceMs" , "anim"     , "bouncems"    ,    150,    60,    600,    10, 0, "anim"   , "Snap bounce"            , "ms")
, TS("animBounce"   , "anim"     , "bounce"      ,     15,     1,     40,     1, 0, "anim"   , "Snap bounce depth"      , "px of squash on impact")
, TS("animRollMs"   , "anim"     , "rollupms"    ,    190,    60,    800,    10, 0, "anim"   , "Roll-up"                , "ms")
, TS("animGravityMs", "anim"     , "gravityms"   ,    320,   100,   1500,    20, 0, "anim"   , "Gravity close"          , "ms for the Alt+F4 drop")
, TS("animFadeMs"   , "anim"     , "fadems"      ,    110,    30,    500,    10, 0, "anim"   , "Overlay fade"           , "ms for dimmers and previews")
, TS("animNotchMs"  , "anim"     , "notchms"     ,    150,    50,    600,    10, 0, "anim"   , "OSD slide"              , "ms for the notch drop")
, TS("focusAlpha"   , "focus"    , "alpha"       ,     94,    30,    100,     5, 0, "anim"   , "Focus mode dim"         , "% outside the active window")
, TS("focusFeather" , "focus"    , "feather"     ,     70,     0,    200,    10, 0, "anim"   , "Focus mode softness"    , "px of falloff per layer")
, TS("focusRadius"  , "focus"    , "radius"      ,     40,     0,    200,     5, 0, "anim"   , "Focus mode corners"     , "px corner radius")
, TS("transStep"    , "trans"    , "step"        ,     25,     5,     64,     1, 0, "anim"   , "Transparency step"      , "alpha per Shift+Alt+wheel notch")
, TS("transMin"     , "trans"    , "min"         ,     20,     5,     90,     5, 0, "anim"   , "Transparency floor"     , "% the wheel will not go below")
, TS("clockFont"    , "taskbar"  , "clockfont"   ,      7,     6,     14,     1, 0, "general", "Clock text size"        , "pt; two lines of it have to fit the taskbar height")
]

global TUNE_VAL       := Map()      ; key -> validated value
global TUNE_INDEX := Map()      ; key -> spec row, built once by TuneInit()

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

Clamp(v, lo, hi) => (v < lo) ? lo : (v > hi) ? hi : v
