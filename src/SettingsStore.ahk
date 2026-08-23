; Settings store - settings.ini read, write and validation.
;
; Function definitions and global initialisers only, no top-level statements.
; LoadSettings() is called once, by Boot().
;
; NOTHING KEYED TO INPUT MAY TOUCH THE DISK. One IniWrite measured 770 us, so a
; full 45-key save was 34 ms on whatever thread called it - including the frame
; loop. Every write is diffed against IniCache and the file is written by an idle
; one-shot: SaveSettings() arms it, WriteSettings() does the work. Bye() calls
; WriteSettings() directly because there is no idle on the way out.
;
; The trade-off that buys: a settings change is written ~700 ms after the last
; edit rather than instantly, so a hard kill - not an exit or a reload - inside
; that window loses it. This is also why anything that needs the persisted state
; must let the program exit gracefully; taskkill without /F posts WM_CLOSE and
; lets OnExit(Bye) run, Stop-Process -Force does not and truncates the file.
;
; A SPACE FOLLOWED BY ; STARTS A COMMENT EVEN INSIDE A DOUBLE-QUOTED STRING.
; x := "a ; b" fails to load with Missing """; x := "a; b" is fine. That is why
; the shipped media_fallback default writes "a.exe; b.exe" and never
; "a.exe ; b.exe". Check any literal here that contains a semicolon.

global INI      := A_ScriptDir "\settings.ini"

; Single backslashes. AHK escapes with a backtick, so "HKCU\\Software\\..."
; is a literal double backslash naming a key that cannot exist.
global EP_KEY       := "HKCU\Software\ExplorerPatcher"

global ADVANCED_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

global IniCache := Map()

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
; Shift+Alt+W permanently dead, and a value the dropdown cannot show leaves the
; GUI displaying one thing while the engine uses another.
; The weather location is validated by SHAPE, not by range or membership, for the
; same reason BorderColor is: it is not a number and there is no list to check it
; against. What survives is pasted into a URL, so anything that is not plausibly
; part of a place name is dropped rather than escaped, and the length is capped.
CleanClockLocation(s) {
    s := RegExReplace(Trim(s), "[^A-Za-z0-9 ,.+-]", "")
    s := Trim(RegExReplace(s, " {2,}", " "))
    return (StrLen(s) > 60) ? Trim(SubStr(s, 1, 60)) : s
}

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
    BlackHoleMinimizeEnabled := IniStr("memory", "blackhole", "1") = "1"
    MomentumTiltEnabled := IniStr("mouse", "momentum", "1") = "1"
    CurtainDropEnabled := IniStr("memory", "curtain", "1") = "1"
    TaskbarWaveEnabled := IniStr("taskbar", "wave", "0") = "1"
    CustomClockEnabled := IniStr("taskbar", "customclock", "1") = "1"
    ClockLocation := CleanClockLocation(IniStr("taskbar", "clocklocation", ""))
    ; Membership, not range - see the note on IniPick. A hand-edited value the
    ; dropdown cannot display would throw inside BuildWin and kill Shift+Alt+W.
    ClockUnits := IniPick("taskbar", "clockunits", CLOCK_UNITS, "Celsius")
    ClockAnchor := IniPick("taskbar", "clockanchor", CLOCK_ANCHORS, "TrayEdge")
    ClockWeatherEnabled := IniStr("taskbar", "clockweather", "1") = "1"
    ToastBounceEnabled := IniStr("taskbar", "toastbounce", "1") = "1"
    MonitorThrowEnabled := IniStr("mouse", "monthrow", "1") = "1"
    BlackHoleDeleteEnabled := IniStr("mouse", "blackhole", "0") = "1"
    CursorYawnEnabled := IniStr("mouse", "cursoryawn", "1") = "1"
    ShatterEnabled := IniStr("mouse", "shatter", "0") = "1"
    ; SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX, GLIDE_THROW, GLIDE_MS,
    ; GLIDE_MAX, BREATHE_IDLE_MS and CursorYawnIdleTime are all loaded, clamped
    ; and mirrored back into their globals by TuneLoad() at the end of this
    ; function, along with every other tunable number.
    GlideEnabled   := IniStr("glide", "enabled", "1") = "1"
    RestoreEnabled := IniStr("memory", "enabled", "1") = "1"
    GravityCloseEnabled := IniStr("memory", "gravityclose", "1") = "1"
    DEBUG := IniStr("memory", "debuglog", "0") = "1"
    BreathingEnabled := IniStr("memory", "breathing", "1") = "1"
    OpenAnim := IniPick("memory", "openanim", OPEN_ANIMS, "Ghost Slide-In")
    FlyMinimizeEnabled := IniStr("memory", "fly", "1") = "1"
    RollUpEnabled := IniStr("memory", "rollup", "0") = "1"
    TrayMinimizeEnabled := IniStr("memory", "traymin", "1") = "1"
    BossKeyEnabled := IniStr("memory", "bosskey", "1") = "1"
    AltDragEnabled := IniStr("memory", "altdrag", "1") = "1"
    TaskbarScrollEnabled := IniStr("memory", "taskbarscroll", "1") = "1"
    QuickFolderJumpEnabled := IniStr("memory", "quickfolder", "1") = "1"
    PlainPasteEnabled := IniStr("memory", "plainpaste", "1") = "1"
    MorphingPasteEnabled := IniStr("memory", "morphingpaste", "1") = "1"
    ClipboardAppendEnabled := IniStr("memory", "clipboardappend", "1") = "1"
    SmoothCaretEnabled := IniStr("mouse", "smoothcaret", "1") = "1"
    TypingSoundsEnabled := IniStr("mouse", "typingsounds", "1") = "1"
    CopyFeedbackEnabled := IniStr("mouse", "copyfeedback", "1") = "1"
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
    PutIni(BlackHoleMinimizeEnabled ? 1 : 0, "memory", "blackhole")
    PutIni(MomentumTiltEnabled ? 1 : 0, "mouse", "momentum")
    PutIni(CurtainDropEnabled ? 1 : 0, "memory", "curtain")
    PutIni(TaskbarWaveEnabled ? 1 : 0, "taskbar", "wave")
    PutIni(CustomClockEnabled ? 1 : 0, "taskbar", "customclock")
    PutIni(ClockLocation, "taskbar", "clocklocation")
    PutIni(ClockUnits, "taskbar", "clockunits")
    PutIni(ClockAnchor, "taskbar", "clockanchor")
    PutIni(ClockWeatherEnabled ? 1 : 0, "taskbar", "clockweather")
    PutIni(ToastBounceEnabled ? 1 : 0, "taskbar", "toastbounce")
    PutIni(MonitorThrowEnabled ? 1 : 0, "mouse", "monthrow")
    PutIni(BlackHoleDeleteEnabled ? 1 : 0, "mouse", "blackhole")
    PutIni(CursorYawnEnabled ? 1 : 0, "mouse", "cursoryawn")
    PutIni(ShatterEnabled ? 1 : 0, "mouse", "shatter")
    PutIni(GlideEnabled ? 1 : 0,     "glide", "enabled")
    PutIni(RestoreEnabled ? 1 : 0,   "memory", "enabled")
    PutIni(GravityCloseEnabled ? 1 : 0, "memory", "gravityclose")
    PutIni(DEBUG ? 1 : 0,            "memory", "debuglog")
    PutIni(BorderColor,              "border", "color")
    TuneSave()                       ; every tunable number, in one pass
    PutIni(BreathingEnabled ? 1 : 0, "memory", "breathing")
    PutIni(OpenAnim, "memory", "openanim")
    PutIni(FlyMinimizeEnabled ? 1 : 0, "memory", "fly")
    PutIni(RollUpEnabled ? 1 : 0, "memory", "rollup")
    PutIni(TrayMinimizeEnabled ? 1 : 0, "memory", "traymin")
    PutIni(BossKeyEnabled ? 1 : 0, "memory", "bosskey")
    PutIni(AltDragEnabled ? 1 : 0, "memory", "altdrag")
    PutIni(TaskbarScrollEnabled ? 1 : 0, "memory", "taskbarscroll")
    PutIni(QuickFolderJumpEnabled ? 1 : 0, "memory", "quickfolder")
    PutIni(PlainPasteEnabled ? 1 : 0, "memory", "plainpaste")
    PutIni(MorphingPasteEnabled ? 1 : 0, "memory", "morphingpaste")
    PutIni(ClipboardAppendEnabled ? 1 : 0, "memory", "clipboardappend")
    PutIni(SmoothCaretEnabled ? 1 : 0, "mouse", "smoothcaret")
    PutIni(TypingSoundsEnabled ? 1 : 0, "mouse", "typingsounds")
    PutIni(CopyFeedbackEnabled ? 1 : 0, "mouse", "copyfeedback")
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
