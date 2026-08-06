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
global DEBUG          := true

; How long a window must go untouched before breathing dims it. MediaCore's hold
; window is derived from this (MC_SetHoldMs in SyncMediaCore) so the two can never
; be set into a dim/wake flicker - see MC_HoldMs() in MediaCore.ahk.
global BREATHE_IDLE_MS := 6000

global GlideEnabled  := true
global GLIDE_THROW   := 0.9
global GLIDE_MS      := 650
global GLIDE_MAX     := 500

global SnapEnabled    := true
global RestoreEnabled := true
global BreathingEnabled := true
global PulseEnabled := true
global OpenAnim := "Ghost Slide-In"
global ParallaxEnabled := true
global SeamFlashEnabled := true
global FlyMinimizeEnabled := true
global RollUpEnabled := true
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
global MiddleClickCloseEnabled := true
global ProximityGhostEnabled := true
global GhostWindows := Map()
global MediaFallbackList := "youtube.exe; spotify.exe; vlc.exe; potplayermini64.exe; mpc-hc64.exe; netflix.exe"

; The single source of truth for every enumerated setting: LoadSettings validates
; against these lists and BuildWin populates its dropdowns from the same ones, so
; the stored value and the control's contents cannot drift apart.
global OPEN_ANIMS     := ["None", "Ghost Slide-In", "Window Unrolling"]
global CAPS_ACTIONS   := ["Escape", "Backspace"]
global CORNER_ACTIONS := ["None", "Task View", "Show Desktop", "Action Center", "Start Menu", "Lock Screen", "Mute Volume"]
global EP_STYLES      := ["Win10", "Win11"]
global EP_ICON_SIZES  := ["Small", "Large"]

global Win := "", Pages := Map(), NavItems := Map(), CurPage := ""
global C := Map()

LoadSettings()
RotateLog()
BuildTray()


WriteLog("=== Window Tweaks " VERSION " started ===")

; =========================================================== Settings ===========================================================
IniNum(section, key, defaultVal) {
    try return Number(IniRead(INI, section, key, defaultVal))
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

LoadSettings() {
    global
    SnapEnabled    := IniStr("snap", "enabled", "1") = "1"
    SeamFlashEnabled := IniStr("snap", "flash", "1") = "1"
    SNAP_DISTANCE  := Integer(IniNum("snap", "distance", 30))
    CORNER_BOOST   := IniNum("snap", "cornerBoost", 2.2)
    NEIGHBOUR_PROX := Integer(IniNum("snap", "neighbour", 90))
    GlideEnabled   := IniStr("glide", "enabled", "1") = "1"
    GLIDE_THROW    := IniNum("glide", "throw", 0.9)
    GLIDE_MS       := Integer(IniNum("glide", "ms", 650))
    RestoreEnabled := IniStr("memory", "enabled", "1") = "1"
    BreathingEnabled := IniStr("memory", "breathing", "1") = "1"
    PulseEnabled := IniStr("memory", "pulse", "1") = "1"
    OpenAnim := IniPick("memory", "openanim", OPEN_ANIMS, "Ghost Slide-In")
    FlyMinimizeEnabled := IniStr("memory", "fly", "1") = "1"
    RollUpEnabled := IniStr("memory", "rollup", "1") = "1"
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
    MiddleClickCloseEnabled := IniStr("memory", "midclose", "1") = "1"
    ProximityGhostEnabled := IniStr("memory", "ghost", "1") = "1"
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
    ; A corrupt INI must not stop the program from starting.
    if (SNAP_DISTANCE < 1 || SNAP_DISTANCE > 300)
        SNAP_DISTANCE := 30
    if (CORNER_BOOST < 1 || CORNER_BOOST > 10)
        CORNER_BOOST := 2.2
    if (NEIGHBOUR_PROX < 0 || NEIGHBOUR_PROX > 1000)
        NEIGHBOUR_PROX := 90
    if (GLIDE_THROW < 0 || GLIDE_THROW > 5)
        GLIDE_THROW := 0.9
    if (GLIDE_MS < 0 || GLIDE_MS > 3000)
        GLIDE_MS := 650

}

; Written values, so an unchanged key is never written again.
;
; Measured: one IniWrite costs 771 us, and SaveSettings writes 45 keys - 34.6 ms
; of blocking disk I/O. It runs on every checkbox click, every debounced keystroke
; in the settings window, and every toggle hotkey, so Win+Ctrl+S used to stall the
; whole process for 35 ms. A toggle changes exactly one key; writing only that one
; costs 0.8 ms, and SaveSettings() no longer writes at all - it queues.
global IniCache := Map()

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
    PutIni(SeamFlashEnabled ? 1 : 0, "snap", "flash")
    PutIni(SNAP_DISTANCE,            "snap", "distance")
    PutIni(Round(CORNER_BOOST, 2),   "snap", "cornerBoost")
    PutIni(NEIGHBOUR_PROX,           "snap", "neighbour")
    PutIni(GlideEnabled ? 1 : 0,     "glide", "enabled")
    PutIni(Round(GLIDE_THROW, 2),    "glide", "throw")
    PutIni(GLIDE_MS,                 "glide", "ms")
    PutIni(RestoreEnabled ? 1 : 0,   "memory", "enabled")
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
global LogBuf := ""
global LOG_FLUSH_BYTES := 16384        ; hard cap so a burst cannot grow forever

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
    global SnapEnabled, RestoreEnabled
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
    global SnapEnabled, SeamFlashEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MS
    global RestoreEnabled, BreathingEnabled, PulseEnabled, OpenAnim, FlyMinimizeEnabled, RollUpEnabled, TrayMinimizeEnabled, BossKeyEnabled, AltDragEnabled, TaskbarScrollEnabled, QuickFolderJumpEnabled, PlainPasteEnabled, SmartCapsEnabled, SmartCapsAction, ParallaxEnabled, EP_Style, EP_IconSize
    global NAV, SEL, SELF, FG

    dark := IsDark()
    BG   := dark ? "1F1F1F" : "F5F5F5"      ; content background
    NAV  := dark ? "171717" : "E6E6E6"      ; sidebar
    FG   := dark ? "FFFFFF" : "141414"      ; primary text
    cSub  := dark ? "9A9A9A" : "5A5A5A"      ; secondary text
    SEL  := dark ? "0F5FA6" : "CCE4F7"      ; selected nav
    SELF := dark ? "FFFFFF" : "0A0A0A"      ; selected nav text

    W := 780, H := 560, SW := 196

    g := Gui("-MaximizeBox -Resize +OwnDialogs", "Window Tweaks")
    g.BackColor := BG
    g.MarginX := 0, g.MarginY := 0
    Win := g
    Pages := Map(), NavItems := Map(), C := Map()

    ; --- sidebar ---
    g.AddText("x0 y0 w" SW " h" H " Background" NAV)
    g.SetFont("s13 bold", "Segoe UI")
    g.AddText("x20 y22 w160 c" FG " Background" NAV, "Window Tweaks")
    g.SetFont("s8 norm", "Segoe UI")
    g.AddText("x21 y50 w160 c" cSub " Background" NAV, "version " VERSION)

    g.SetFont("s10 norm", "Segoe UI")
    ny := 88
    for name in ["🪟 Window Management", "⚡ Power Features", "🔊 System & Media", "🖥️ Multi-Monitor", "📐 Hot Corners", "⚙️ General"] {
        t := g.AddText("x0 y" ny " w" SW " h42 +0x200 c" FG " Background" NAV, "    " name)
        t.OnEvent("Click", NavClick.Bind(name))
        NavItems[name] := t
        ny += 42
    }

    g.SetFont("s8", "Segoe UI")
    g.AddText("x20 y" (H - 40) " w160 c" cSub " Background" NAV, "Win+Ctrl+W  opens this")

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
    Lbl(pg, FG, "Snap distance", "xm y+12")
    C["dist"] := pg.AddEdit("x170 yp-3 w70 Number", SNAP_DISTANCE)
    Sub(pg, 260, cSub, "px from an edge", "x+12 yp+3")
    Lbl(pg, FG, "Corner boost", "xm y+12")
    C["boost"] := pg.AddEdit("x170 yp-3 w70", CORNER_BOOST)
    Sub(pg, 260, cSub, "x stronger at corners", "x+12 yp+3")
    Lbl(pg, FG, "Neighbour reach", "xm y+12")
    C["prox"] := pg.AddEdit("x170 yp-3 w70 Number", NEIGHBOUR_PROX)
    Sub(pg, 260, cSub, "px to nearby windows", "x+12 yp+3")
    C["flash"] := Box(pg, CW, FG, "Magnetic Seam Flash (neon spark on snap)", SeamFlashEnabled, "xm y+16")
    
    C["glide"] := Box(pg, CW, FG, "Enable ice glide (Physics-based throwing)", GlideEnabled, "xm y+16")
    Lbl(pg, FG, "Throw strength", "xm y+12")
    C["throw"] := pg.AddEdit("x170 yp-3 w70", GLIDE_THROW)
    Sub(pg, 260, cSub, "0 = stop where you let go", "x+12 yp+3")
    Lbl(pg, FG, "Slide time", "xm y+12")
    C["gms"] := pg.AddEdit("x170 yp-3 w70 Number", GLIDE_MS)
    Sub(pg, 260, cSub, "ms maximum", "x+12 yp+3")

    C["parallax"] := Box(pg, CW, FG, "Parallax Dragging (Velocity Transparency)", ParallaxEnabled, "xm y+16")
    C["altdrag"] := Box(pg, CW, FG, "Linux-Style Alt-Drag (Move & Resize)", AltDragEnabled, "xm y+12")
    
    C["fly"] := Box(pg, CW, FG, "Fly-to-Mouse Minimize (vacuum effect)", FlyMinimizeEnabled, "xm y+16")
    C["grabpan"] := Box(pg, CW, FG, "Universal Grab & Pan (Middle-Click Drag)", GrabPanEnabled, "xm y+12")
    C["rollup"] := Box(pg, CW, FG, "Window Roll-Up (Win+Ctrl+R)", RollUpEnabled, "xm y+12")
    
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

    ; ---- Multi-Monitor
    pg := CreatePage("🖥️ Multi-Monitor")
    Head(pg, CW, FG, "Multi-Monitor & Visuals")
    Sub(pg, CW, cSub, "Dual/Triple monitor optimizations and focus effects.", "xm y+10")
    
    C["wrap"] := Box(pg, CW, FG, "Infinite Cursor Wrap (Seamless edges)", InfiniteWrapEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Move your cursor past the left/right edges of your screen to teleport to the other side.", "xm y+8")
    
    C["multidimmer"] := Box(pg, CW, FG, "Multi-Monitor Focus Dimmer", MultiMonitorDimmerEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Automatically dims all monitors by 50% except the one your mouse is currently on.", "xm y+8")
    
    C["border"] := Box(pg, CW, FG, "Smart Active Border (Neon Focus)", ActiveBorderEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Draws a sleek, accent-colored border around the currently active window.", "xm y+8")
    
    C["breath"] := Box(pg, CW, FG, "Breathing (dim inactive windows)", BreathingEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Windows fade to 70% opacity after 6 seconds of inactivity.", "xm y+8")
    
    C["pulse"] := Box(pg, CW, FG, "Focus Pulse (Heartbeat on active)", PulseEnabled, "xm y+16")
    
    Lbl(pg, FG, "New window animation", "xm y+16")
    C["openanim"] := pg.AddDropDownList("x160 yp-3 w160 Choose" IndexOf(OPEN_ANIMS, OpenAnim), OPEN_ANIMS)

    ; ---- Hot Corners
    pg := CreatePage("📐 Hot Corners")
    Head(pg, CW, FG, "macOS Hot Corners")
    Sub(pg, CW, cSub, "Throw your mouse into the corners of the screen to trigger actions.", "xm y+10")
    
    C["corners_en"] := Box(pg, CW, FG, "Enable Hot Corners", HotCornersEnabled, "xm y+16")
    
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
    
    C["smart_tb"] := Box(pg, CW, FG, "Smart Auto-Hide Taskbar (macOS style)", SmartTaskbarEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Only hides taskbar when windows maximize or touch the bottom edge.", "xm y+8")

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
            ctl.OnEvent("Change", (*) => ApplyUi())
        else if InStr(ctl.Type, "CheckBox")
            ctl.OnEvent("Click", (*) => ApplyUi())
        else {
            ; Typed fields apply on their own, debounced, so a value takes
            ; effect without needing to click something else afterwards.
            ctl.OnEvent("Change", (*) => SetTimer(ApplyUi, -600))
            ctl.OnEvent("LoseFocus", (*) => ApplyUi())
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
Lbl(pg, col, txt, pos := "xm y+16") {
    pg.SetFont("s10 norm", "Segoe UI")
    t := pg.AddText(pos " w160 c" col, txt)
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
        if (pname = name)
            pg.Show("x224 y0 w528 h560 NoActivate")
        else
            pg.Hide()
    }
    
    for pname, item in NavItems {
        item.Opt((pname = name) ? "Background" SEL " c" SELF : "Background" NAV " c" FG)
        item.Redraw()
    }
    CurPage := name
}

; Closing the window used to run SaveSettings() and only THEN cancel the pending
; debounced ApplyUi, so a value typed within 600 ms of closing was thrown away.
; Apply first, then save, then tear down.
CloseWin(g) {
    global Win
    SetTimer(ApplyUi, 0)
    ApplyUi()
    SaveSettings()
    try g.Destroy()
    Win := ""
}

ApplyUi() {
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
    uiOldGhost := ProximityGhostEnabled
    uiOldBottom := AlwaysOnBottomEnabled
    uiOldPip := LivePipEnabled
    try {
        SnapEnabled    := C["snap"].Value
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
        InfiniteWrapEnabled := C["wrap"].Value
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

        SNAP_DISTANCE  := Integer(Clamp(NumOr(C["dist"].Value, SNAP_DISTANCE), 1, 300))
        CORNER_BOOST   :=         Clamp(NumOr(C["boost"].Value, CORNER_BOOST), 1, 10)
        NEIGHBOUR_PROX := Integer(Clamp(NumOr(C["prox"].Value, NEIGHBOUR_PROX), 0, 1000))
        GLIDE_THROW    :=         Clamp(NumOr(C["throw"].Value, GLIDE_THROW), 0, 5)
        GLIDE_MS       := Integer(Clamp(NumOr(C["gms"].Value, GLIDE_MS), 0, 3000))

        uiAutoStart := C["auto"].Value
    } catch as e {
        WriteLog("ApplyUi: could not read a control - " e.Message)
    }

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

    try SyncTray()
    try SyncBreathingTimers()        ; start/stop the polling to match the checkbox
    try SyncSmartTaskbar()
    try SyncDimmerTimer()
    try SyncHotCornersTimer()
    try SyncCursorWrapTimer()
    try SyncActiveBorderTimer()
    try SyncTextExpander()
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
    global POS_FILE
    try {
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

#HotIf MicKillSwitchEnabled
~LAlt:: {
    if (A_PriorHotkey == "~LAlt" && A_TimeSincePriorHotkey < 400) {
        state := ToggleDefaultMic()
        if (state != -1)
            ShowMicOSD(state)
    }
}
#HotIf

#HotIf SpotlightEnabled
~LCtrl:: {
    if (A_PriorHotkey == "~LCtrl" && A_TimeSincePriorHotkey < 400)
        ToggleSpotlight()
}
~RCtrl:: {
    if (A_PriorHotkey == "~RCtrl" && A_TimeSincePriorHotkey < 400)
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


    lp := ((sY & 0xFFFF) << 16) | (sX & 0xFFFF)
    res := 0
    DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x84, "ptr", 0, "ptr", lp, "uint", 2, "uint", 50, "ptr*", &res)
    
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
    
    if (!GrabPanEnabled) {
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
        Send("{Blind}{MButton}")
    }
}
#HotIf

global CustomTrans := Map()

global PendingTransMsg := ""

ChangeTransparency(dir) {
    global CustomTrans, PendingTransMsg
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return

    current := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

    step := 25
    if (dir > 0)
        current += step
    else
        current -= step

    if (current > 255)
        current := 255
    if (current < 50)
        current := 50

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
    ms := 190              ; duration in ms, not a frame count

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

                if ParallaxEnabled {
                    vel := Sqrt(vX**2 + vY**2)
                    alpha := 255 - Round(vel * 3)
                    if (alpha < 100)
                        alpha := 100
                    RS_SetAlpha(hwnd, alpha, RS_PRI_DRAG)
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
                if ParallaxEnabled
                    RS_SetAlpha(hwnd, 255, RS_PRI_DRAG)
            }
            ; Sleep, not PreciseSleep: this yields, so the frame loop keeps
            ; running other animations instead of being starved by a spin.
            Sleep(10)
        }
    }
    busy := false

    if ParallaxEnabled {
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
    ; Only the HIDE direction is gated. Gating both meant that turning the feature
    ; off while it was active left every window on the desktop hidden with no way
    ; to get them back short of quitting - the one path that must always work is
    ; the one that undoes what we already did.
    if (!BossKeyEnabled && !BossKeyActive)
        return

    if (BossKeyActive) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        BossKeyWindows := []
        try SoundSetMute(BossKeyMuteState)
        BossKeyActive := false
    } else {
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



BreathingMonitorStep() {
    global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha, CustomTrans
    if !BreathingEnabled
        return
        
    MouseGetPos(,, &mHwnd)
    aHwnd := WinExist("A")
    now := QPC()

    needsAnimation := false
    ; One O(1) check instead of a 1.7 us MC_IsMediaHwnd per tracked window. When
    ; nothing is playing - the usual case - MC_IsMediaHwnd would return false for
    ; every window anyway, so short-circuiting is behaviour-identical.
    anyMedia := MC_AnyMedia()

    for hwnd, lastActive in WinLastActive {
        if !DllCall("IsWindow", "ptr", hwnd)
            continue

        baseAlpha := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

        if (hwnd == aHwnd || hwnd == mHwnd || (anyMedia && MC_IsMediaHwnd(hwnd))) {
            WinLastActive[hwnd] := now
            WinTargetAlpha[hwnd] := baseAlpha
        } else {
            if (now - lastActive > BREATHE_IDLE_MS)
                WinTargetAlpha[hwnd] := Min(baseAlpha, 180)
        }
        
        if (WinTargetAlpha[hwnd] != WinCurrentAlpha[hwnd])
            needsAnimation := true
    }
    
    if (needsAnimation)
        RegisterAnimation("BreathingAnimator", BreathingAnimatorStep)
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
$!F4::GravityClose()

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
    ms := 320
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
global FocusTargetHwnd := 0

ToggleFocusMode() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    ; Decide before flipping the flag. Flipping first and then bailing out left
    ; the flag saying "on" with no overlays, so the next press took the off
    ; branch and focus mode could never be entered again.
    if (!FocusModeEnabled && FocusGuis.Length)
        return
    FocusModeEnabled := !FocusModeEnabled

    if (FocusModeEnabled) {
        alphas := [140, 200, 240] ; Vignette layers opacity
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
        
    prevHwnd := FocusTargetHwnd
    for layer in FocusGuis {
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
        pad := (A_Index - 1) * 70

        px := hx - pad
        py := hy - pad
        pw := hw + pad*2
        ph := hh + pad*2

        region := "0-0 W" FocusBounds.w " H" FocusBounds.h

        if (pw > 0 && ph > 0) {
            region .= " " px "-" py " W" pw " H" ph " R" (40 + pad) "-" (40 + pad)
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
;   destroy   destroy the Gui when it reaches 0 (and forget its render state)
;   onDone    called once, whichever way the fade ends
FadeGui(guiObj, toAlpha, ms := 110, destroy := false, onDone := "") {
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
        DragHwnd := 0
        if !IsSnappable(hwnd)
            return
        if !GetRects(hwnd, &sL, &sT, &sR, &sB, &sx, &sy)
            return
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
    SetTimer(() => FinishDrag(hwnd, sL, sT, sR, sB), -50)    ; defer: FinishDrag enumerates windows
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
    PrevX := L, PrevY := T
    
    if (ParallaxEnabled) {
        speed := Sqrt(VelX * VelX + VelY * VelY)
        targetAlpha := Clamp(Round(255 - (speed * 4)), 60, 255)
        
        CurrentDragAlpha := CurrentDragAlpha * 0.7 + targetAlpha * 0.3
        
        if (CurrentDragAlpha < 250) {
            RS_SetAlpha(DragHwnd, Integer(CurrentDragAlpha), RS_PRI_DRAG)
        } else {
            RS_SetAlpha(DragHwnd, "Off", RS_PRI_DRAG)
        }
    }
    return true
}

FinishDrag(hwnd, startL, startT, startR, startB) {
    global MIN_DRAG, ParallaxEnabled, CurrentDragAlpha
    if !DllCall("IsWindow", "ptr", hwnd)
        return
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

    if (ParallaxEnabled)
        StartFadeBackAlpha(hwnd, CurrentDragAlpha)

    WriteLog(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    RememberPosition(hwnd)
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

    if !SnapEnabled {
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

    ; Snap is judged from where the throw would land, not where you let go.
    CollectEdges(hwnd, pL, pT, pR, pB, &vLines, &hLines, NEIGHBOUR_PROX)
    if !ComputeSnap(pL, pT, pR, pB, vLines, hLines, SNAP_DISTANCE, &newL, &newT, CORNER_BOOST)
        newL := pL, newT := pT

    if (newL = L && newT = T)
        return

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
    global SeamFlashEnabled
    seams := []
    if (SeamFlashEnabled) {
        W := R - L
        H := B - T
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

    ; Physics: if momentum carried us further than the snap allowed, we crashed
    ; into a wall.
    crashX := 0, crashY := 0
    if (Abs(VelX) > 1.5) {
        if (tx > 0 && (newL - L) < tx)
            crashX := tx - (newL - L)
        else if (tx < 0 && (newL - L) > tx)
            crashX := tx - (newL - L)
    }
    if (Abs(VelY) > 1.5) {
        if (ty > 0 && (newT - T) < ty)
            crashY := ty - (newT - T)
        else if (ty < 0 && (newT - T) > ty)
            crashY := ty - (newT - T)
    }

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
    if ActiveAnimations.Has("Glide_" hwnd)
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

BounceSqueeze(hwnd, X, Y, W, H, crashX, crashY) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    
    squeezeX := 0, squeezeY := 0
    moveX := 0, moveY := 0
    
    if (crashX > 4) {
        squeezeX := Min(crashX * 0.4, 15)
        moveX := squeezeX
    } else if (crashX < -4) {
        squeezeX := Min(-crashX * 0.4, 15)
        moveX := 0
    }
    
    if (crashY > 4) {
        squeezeY := Min(crashY * 0.4, 15)
        moveY := squeezeY
    } else if (crashY < -4) {
        squeezeY := Min(-crashY * 0.4, 15)
        moveY := 0
    }
    
    if (squeezeX == 0 && squeezeY == 0)
        return
        
    animKey := "Bounce_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150

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
    ms := 190              ; duration in ms; never derive this from a frame count

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

RememberPosition(hwnd) {
    global POS_FILE, RestoreEnabled
    if (!RestoreEnabled || !IsRestorable(hwnd))
        return
    key := WindowKey(hwnd)
    if (key = "")
        return
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        IniWrite(x, POS_FILE, key, "x")
        IniWrite(y, POS_FILE, key, "y")
        IniWrite(w, POS_FILE, key, "w")
        IniWrite(h, POS_FILE, key, "h")
        WriteLog("  remembered " key " -> " x "," y " " w "x" h)
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
    OriginalTaskbarState := GetTaskbarState()
    if SmartTaskbarEnabled
        SyncSmartTaskbar()
}

ShellEvent(wParam, lParam, *) {
    static HSHELL_WINDOWCREATED := 1
    static HSHELL_GETMINRECT := 5
    
    if ((wParam & 0x7FFF) = HSHELL_GETMINRECT) {
        global FlyMinimizeEnabled
        if (FlyMinimizeEnabled) {
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
            global CustomTrans, RolledUpWindows, WinTargetAlpha, WinCurrentAlpha, WinLastActive
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
            RS_RemoveHwnd(lParam)
            MC_RemoveHwnd(lParam)      ; MediaCore caches pid/exe per HWND forever otherwise
        }
    }

    if ((wParam & 0x7FFF) = 4) { ; HSHELL_WINDOWACTIVATED
        if (lParam) {
            if !BottomWindows.Has(lParam) {
                PulseWindow(lParam)
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
    if !IsRestorable(hwnd)
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

    RestorePosition(hwnd)

    if !isHidden
        return

    ; Re-check: 250 ms is long enough for the window to have been maximized,
    ; closed or restyled since we hid it.
    if (OpenAnim != "None" && WillAnimateOpen(hwnd)) {
        if (OpenAnim == "Ghost Slide-In")
            GhostSlideIn(hwnd)
        else if (OpenAnim == "Window Unrolling")
            UnrollWindow(hwnd)
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

UnrollWindow(hwnd) {
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch {
        RevealWindow(hwnd)
        return
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
    ms := 190              ; duration in ms, not a frame count
    
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

GhostSlideIn(hwnd) {
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch {
        RevealWindow(hwnd)
        return
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }


    startY := y + 30
    endY := y
    
    MoveFast(hwnd, x, startY)
    
    animKey := "GhostSlideIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 240              ; duration in ms, not a frame count
    
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
    animKey := "Pulse_" hwnd
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

    pw := Min(Round(w * 0.015), 12)
    ph := Min(Round(h * 0.015), 12)

    start := QPC()
    ms := 190

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
            FadeGui(g, 0, 150, true)
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
        Loop count {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (mx >= L && mx <= R && my >= T && my <= B) {
                activeMon := A_Index
                break
            }
        }
        
        Loop count {
            if (A_Index == activeMon || MC_MediaOnMonitor(A_Index)) {
                if DimmerGuis.Has(A_Index) {
                    g := DimmerGuis[A_Index]
                    DimmerGuis.Delete(A_Index)
                    FadeGui(g, 0, 150, true)
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
                    FadeGui(g, 120, 150)
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

    g := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound +Border")
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
        FadeGui(guiObj, 0, 110, true)
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
            
        MonitorGet(1, &ML, &MT, &MR, &MB)
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
    global ScreenGeom
    ScreenGeom := ""
}

CursorWrapMonitorStep() {
    global InfiniteWrapEnabled
    if (!InfiniteWrapEnabled)
        return

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)

    g := ScreenMetrics()
    vLeft := g.left, vTop := g.top
    vRight := g.right, vBottom := g.bottom

    wrapped := false
    
    if (mx <= vLeft) {
        mx := vRight - 2
        wrapped := true
    }
    else if (mx >= vRight - 1) {
        mx := vLeft + 1
        wrapped := true
    }
    
    if (wrapped) {
        valid := false
        for m in g.mons {
            if (mx >= m.l && mx <= m.r && my >= m.t && my <= m.b) {
                valid := true
                break
            }
        }

        if (!valid) {
            closestDiff := 999999
            bestY := my
            for m in g.mons {
                if (mx >= m.l && mx <= m.r) {
                    if (my < m.t)
                        dy := m.t - my, projY := m.t + 5
                    else if (my >= m.b)
                        dy := my - m.b + 1, projY := m.b - 5
                    else
                        dy := 0, projY := my

                    if (dy < closestDiff) {
                        closestDiff := dy
                        bestY := projY
                    }
                }
            }
            my := bestY
        }
        MouseMove(mx, my, 0)
    }
}

HotCornersMonitorStep() {
    global HotCornersEnabled, HotCornerTL, HotCornerTR, HotCornerBL, HotCornerBR
    static LastCorner := "None"

    if (!HotCornersEnabled)
        return

    try {
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
        thresh := 5
        
        if (mx <= L + thresh && my <= T + thresh)
            currentCorner := "TL"
        else if (mx >= R - 1 - thresh && my <= T + thresh)
            currentCorner := "TR"
        else if (mx <= L + thresh && my >= B - 1 - thresh)
            currentCorner := "BL"
        else if (mx >= R - 1 - thresh && my >= B - 1 - thresh)
            currentCorner := "BR"
            
        if (currentCorner != LastCorner) {
            if (currentCorner != "None") {
                action := "None"
                if (currentCorner == "TL")
                    action := HotCornerTL
                else if (currentCorner == "TR")
                    action := HotCornerTR
                else if (currentCorner == "BL")
                    action := HotCornerBL
                else if (currentCorner == "BR")
                    action := HotCornerBR
                    
                if (action != "None")
                    ExecuteHotCornerAction(action)
            }
            LastCorner := currentCorner
        }
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
        if (dir > 0)
            SoundSetVolume("+2")
        else
            SoundSetVolume("-2")
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

ToggleMuteOSD() {
    try {
        SoundSetMute(-1)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
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
        if OsdHiding {
            OsdHiding := false
            try FadeGui(OsdGui, 220)
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
            RS_SetRegion(OsdGui.Hwnd, "0-0 w280 h64 r20-20", RS_PRI_ANIM)
            
            MonitorGet(1, &L, &T, &R, &B)
            x := L + (R - L - 280) // 2
            y := B - 150
            OsdGui.Move(x, y)
            
            FadeGui(OsdGui, 220)
        }
    }

    ; A plain one-shot, re-armed on every notch, so it hides 1.5 s after the LAST
    ; scroll. This was an entry in the animation scheduler, which meant 95 frames
    ; of the 15 ms loop - holding timeBeginPeriod(1) and running a full produce +
    ; flush pass - purely to compare two numbers. Nothing was animating.
    SetTimer(HideVolumeOSD, -1500)
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
    ; The Gui stays in the global until the fade actually finishes, so a notch
    ; arriving mid-fade can revive this window instead of stacking a new one on it.
    OsdHiding := true
    FadeGui(OsdGui, 0, 110, true, ClearVolumeOSD)
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

    PipGui := Gui("-Caption +ToolWindow +AlwaysOnTop +Resize +Border")
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
    props := Buffer(48, 0)
    NumPut("UInt", 0x19, props, 0) 
    NumPut("Int", 0, props, 4)
    NumPut("Int", 0, props, 8)
    NumPut("Int", width, props, 12)
    NumPut("Int", height, props, 16)
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
        if !DllCall("IsWindow", "ptr", srcHwnd)
            ClosePiP(srcHwnd)
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
            try FadeGui(MicOsdGui, 220)
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
            
            MonitorGet(1, &L, &T, &R, &B)
            x := L + (R - L - 240) // 2
            y := T + 100 
            MicOsdGui.Move(x, y)
            
            FadeGui(MicOsdGui, 220)
        }
    }

    ; Plain one-shot, same reasoning as the volume OSD: this was 127 frames of the
    ; animation loop spent comparing a deadline.
    SetTimer(HideMicOSD, -2000)
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
    FadeGui(MicOsdGui, 0, 110, true, ClearMicOSD)
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
        ActiveBorderGui.BackColor := GetAccentColor()
        ; Created hidden on purpose, so the region and position are in place
        ; before it is ever shown - otherwise it flashes as a 1px dot at 0,0.
        ActiveBorderGui.Show("NoActivate Hide x0 y0 w1 h1")
        ActiveBorderShown := false
        SizeChanged := true
    }

    t := 2 ; Thickness

    try {
        if SizeChanged {
            rect1 := "0-0 w" W " h" t
            rect2 := "0-" (H-t) " w" W " h" t
            rect3 := "0-" t " w" t " h" (H-2*t)
            rect4 := (W-t) "-" t " w" t " h" (H-2*t)
            RS_SetRegion(ActiveBorderGui.Hwnd, rect1 "  " rect2 "  " rect3 "  " rect4, RS_PRI_ANIM)
        }

        RS_SetPos(ActiveBorderGui.Hwnd, X, Y, W, H, RS_PRI_ANIM)
        RS_SetAlpha(ActiveBorderGui.Hwnd, 255, RS_PRI_ANIM)
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

    oldParent := DllCall("GetParent", "ptr", hwnd)
    if !oldParent
        oldParent := 0

    desktop := GetDesktopHwnd()
    if !desktop
        return

    X := "", Y := "", W := "", H := ""
    try WinGetPos(&X, &Y, &W, &H, hwnd)

    DllCall("SetParent", "ptr", hwnd, "ptr", desktop)
    ; Record the screen rect too: reparenting is undone at exit, and the window
    ; has to go back to where it was on screen, not to client coordinates of a
    ; desktop it is no longer a child of.
    BottomWindows[hwnd] := {parent: oldParent, x: X, y: Y, w: W, h: H}

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

    DllCall("SetParent", "ptr", hwnd, "ptr", info.parent)

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
        WinSetTransparent(255, hwnd)          ; force WS_EX_LAYERED on
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

    maxDist := 350.0
    minAlpha := 40
    maxAlpha := 255
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
            
            if (!info.HasProp("lastAlpha") || info.lastAlpha != targetAlpha) {
                RS_SetAlpha(hwnd, targetAlpha, RS_PRI_AMBIENT)
                info.lastAlpha := targetAlpha
            }

            ; Read the real style rather than caching it: WinGetExStyle costs
            ; 0.28 us, and reading it back is what makes this self-correcting if
            ; the window changes its own styles. Not worth caching.
            isClickThrough := (WinGetExStyle(hwnd) & 0x20)
            if (dist < 80) {
                if (isClickThrough)
                    WinSetExStyle("-0x20", hwnd)
            } else {
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
    try StopScheduler()
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

    RS_Flush()
    RS_Shutdown()

    ; Unhook before the callback goes away - the OS must not be left holding a
    ; pointer into a freed thunk.
    if (WinEventHook)
        try DllCall("UnhookWinEvent", "ptr", WinEventHook)
    if (WinEventCb)
        try CallbackFree(WinEventCb)
    try DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)

    ; Both of these are normally deferred to an idle timer. On the way out there
    ; is no idle, so write straight through - a queued timer would never fire.
    try WriteSettings()
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
