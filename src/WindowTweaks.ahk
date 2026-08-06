#Requires AutoHotkey v2.0
#SingleInstance Force
#Include SnapCore.ahk
Persistent
DetectHiddenWindows false
SetWinDelay -1
#MaxThreadsPerHotkey 2

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

global GlideEnabled  := true
global GLIDE_THROW   := 0.9
global GLIDE_MS      := 650
global GLIDE_MAX     := 500

global SnapEnabled    := true
global RestoreEnabled := true
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
global OsdGui := "", OsdTimer := ""
global LivePipEnabled := true
global PipGuis := Map()
global GrabPanEnabled := true
global GrabPanEnabled := true
global MicKillSwitchEnabled := true
global MicOsdGui := "", MicOsdTimer := ""
global InfiniteWrapEnabled := true
global SpotlightEnabled := true
global SpotlightGui := "", SpotlightInput := "", SpotlightResult := ""
global ActiveBorderEnabled := true
global ActiveBorderGui := ""
global LastBorderHwnd := 0, LastBorderX := "", LastBorderY := "", LastBorderW := "", LastBorderH := ""
global AlwaysOnBottomEnabled := true
global BottomWindows := Map()
global TextExpanderEnabled := true
global MiddleClickCloseEnabled := true
global ProximityGhostEnabled := true
global GhostWindows := Map()

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

IniStr(section, key, defaultVal) {
    try return IniRead(INI, section, key, defaultVal)
    return defaultVal
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
    OpenAnim := IniStr("memory", "openanim", "Ghost Slide-In")
    FlyMinimizeEnabled := IniStr("memory", "fly", "1") = "1"
    RollUpEnabled := IniStr("memory", "rollup", "1") = "1"
    TrayMinimizeEnabled := IniStr("memory", "traymin", "1") = "1"
    BossKeyEnabled := IniStr("memory", "bosskey", "1") = "1"
    AltDragEnabled := IniStr("memory", "altdrag", "1") = "1"
    TaskbarScrollEnabled := IniStr("memory", "taskbarscroll", "1") = "1"
    QuickFolderJumpEnabled := IniStr("memory", "quickfolder", "1") = "1"
    PlainPasteEnabled := IniStr("memory", "plainpaste", "1") = "1"
    SmartCapsEnabled := IniStr("memory", "smartcaps", "1") = "1"
    SmartCapsAction := IniStr("memory", "smartcaps_act", "Escape")
    ParallaxEnabled := IniStr("memory", "parallax", "1") = "1"
    QuickLookEnabled := IniStr("memory", "quicklook", "1") = "1"
    MultiMonitorDimmerEnabled := IniStr("memory", "multidimmer", "0") = "1"
    HotCornersEnabled := IniStr("corners", "enabled", "0") = "1"
    HotCornerTL := IniStr("corners", "tl", "None")
    HotCornerTR := IniStr("corners", "tr", "Task View")
    HotCornerBL := IniStr("corners", "bl", "None")
    HotCornerBR := IniStr("corners", "br", "Show Desktop")
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

SaveSettings() {
    global
    try IniWrite(SnapEnabled ? 1 : 0,    INI, "snap", "enabled")
    try IniWrite(SeamFlashEnabled ? 1 : 0, INI, "snap", "flash")
    try IniWrite(SNAP_DISTANCE,          INI, "snap", "distance")
    try IniWrite(Round(CORNER_BOOST, 2), INI, "snap", "cornerBoost")
    try IniWrite(NEIGHBOUR_PROX,         INI, "snap", "neighbour")
    try IniWrite(GlideEnabled ? 1 : 0,   INI, "glide", "enabled")
    try IniWrite(Round(GLIDE_THROW, 2),  INI, "glide", "throw")
    try IniWrite(GLIDE_MS,               INI, "glide", "ms")
    try IniWrite(RestoreEnabled ? 1 : 0, INI, "memory", "enabled")
    try IniWrite(BreathingEnabled ? 1 : 0, INI, "memory", "breathing")
    try IniWrite(PulseEnabled ? 1 : 0, INI, "memory", "pulse")
    try IniWrite(OpenAnim, INI, "memory", "openanim")
    try IniWrite(FlyMinimizeEnabled ? 1 : 0, INI, "memory", "fly")
    try IniWrite(RollUpEnabled ? 1 : 0, INI, "memory", "rollup")
    try IniWrite(TrayMinimizeEnabled ? 1 : 0, INI, "memory", "traymin")
    try IniWrite(BossKeyEnabled ? 1 : 0, INI, "memory", "bosskey")
    try IniWrite(AltDragEnabled ? 1 : 0, INI, "memory", "altdrag")
    try IniWrite(TaskbarScrollEnabled ? 1 : 0, INI, "memory", "taskbarscroll")
    try IniWrite(QuickFolderJumpEnabled ? 1 : 0, INI, "memory", "quickfolder")
    try IniWrite(PlainPasteEnabled ? 1 : 0, INI, "memory", "plainpaste")
    try IniWrite(SmartCapsEnabled ? 1 : 0, INI, "memory", "smartcaps")
    try IniWrite(SmartCapsAction, INI, "memory", "smartcaps_act")
    try IniWrite(ParallaxEnabled ? 1 : 0, INI, "memory", "parallax")
    try IniWrite(QuickLookEnabled ? 1 : 0, INI, "memory", "quicklook")
    try IniWrite(MultiMonitorDimmerEnabled ? 1 : 0, INI, "memory", "multidimmer")
    try IniWrite(HotCornersEnabled ? 1 : 0, INI, "corners", "enabled")
    try IniWrite(HotCornerTL, INI, "corners", "tl")
    try IniWrite(HotCornerTR, INI, "corners", "tr")
    try IniWrite(HotCornerBL, INI, "corners", "bl")
    try IniWrite(HotCornerBR, INI, "corners", "br")
    try IniWrite(PremiumVolumeOSDEnabled ? 1 : 0, INI, "memory", "osd")
    try IniWrite(LivePipEnabled ? 1 : 0, INI, "memory", "pip")
    try IniWrite(GrabPanEnabled ? 1 : 0, INI, "memory", "grabpan")
    try IniWrite(MicKillSwitchEnabled ? 1 : 0, INI, "memory", "mickill")
    try IniWrite(InfiniteWrapEnabled ? 1 : 0, INI, "memory", "wrap")
    try IniWrite(SpotlightEnabled ? 1 : 0, INI, "memory", "spotlight")
    try IniWrite(ActiveBorderEnabled ? 1 : 0, INI, "memory", "border")
    try IniWrite(AlwaysOnBottomEnabled ? 1 : 0, INI, "memory", "bottom")
    try IniWrite(TextExpanderEnabled ? 1 : 0, INI, "memory", "expander")
    try IniWrite(MiddleClickCloseEnabled ? 1 : 0, INI, "memory", "midclose")
    try IniWrite(ProximityGhostEnabled ? 1 : 0, INI, "memory", "ghost")
    try IniWrite(SmartTaskbarEnabled ? 1 : 0, INI, "taskbar", "smart")
    ; ExplorerPatcher treats any non-zero OldTaskbar as "Win10 taskbar", and the
    ; shipped .reg uses 2. Only write when the on/off state actually changes, so
    ; selecting Win10 does not quietly rewrite a working 2 down to a 1.
    ; SaveSettings is assume-global, so every name assigned here becomes a
    ; global - keep these prefixed so they cannot collide with a local elsewhere.
    try {
        epCur := 0
        try epCur := RegRead(EP_KEY, "OldTaskbar", 0)
        epWant := (EP_Style == "Win10")
        if (epWant != (epCur != 0))
            RegWrite(epWant ? 1 : 0, "REG_DWORD", EP_KEY, "OldTaskbar")
    }
    try RegWrite(EP_IconSize == "Small" ? 1 : 0, "REG_DWORD", ADVANCED_KEY, "TaskbarSmallIcons")
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

WriteLog(s) {
    global DEBUG, LOG_FILE
    if DEBUG
        try FileAppend(A_Now "  " s "`n", LOG_FILE)
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
    C["smartcaps_act"] := pg.AddDropDownList("x320 yp-3 w90 Choose" (SmartCapsAction=="Escape"?1 : 2), ["Escape", "Backspace"])
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
    C["openanim"] := pg.AddDropDownList("x160 yp-3 w160 Choose" (OpenAnim=="None"?1 : OpenAnim=="Window Unrolling"?3 : 2), ["None", "Ghost Slide-In", "Window Unrolling"])

    ; ---- Hot Corners
    pg := CreatePage("📐 Hot Corners")
    Head(pg, CW, FG, "macOS Hot Corners")
    Sub(pg, CW, cSub, "Throw your mouse into the corners of the screen to trigger actions.", "xm y+10")
    
    C["corners_en"] := Box(pg, CW, FG, "Enable Hot Corners", HotCornersEnabled, "xm y+16")
    
    actions := ["None", "Task View", "Show Desktop", "Action Center", "Start Menu", "Lock Screen", "Mute Volume"]
    
    Lbl(pg, FG, "Top Left:", "xm y+20")
    C["corner_tl"] := pg.AddDropDownList("x140 yp-3 w130", actions)
    C["corner_tl"].Choose(HotCornerTL)
    
    Lbl(pg, FG, "Top Right:", "x+30 yp+3")
    C["corner_tr"] := pg.AddDropDownList("x+10 yp-3 w130", actions)
    C["corner_tr"].Choose(HotCornerTR)
    
    Lbl(pg, FG, "Bottom Left:", "xm y+20")
    C["corner_bl"] := pg.AddDropDownList("x140 yp-3 w130", actions)
    C["corner_bl"].Choose(HotCornerBL)
    
    Lbl(pg, FG, "Bottom Right:", "x+30 yp+3")
    C["corner_br"] := pg.AddDropDownList("x+10 yp-3 w130", actions)
    C["corner_br"].Choose(HotCornerBR)

    ; ---- General
    pg := CreatePage("⚙️ General")
    Head(pg, CW, FG, "General Settings")
    
    C["auto"] := Box(pg, CW, FG, "Start with Windows", IsAutoStart(), "xm y+16")
    
    C["smart_tb"] := Box(pg, CW, FG, "Smart Auto-Hide Taskbar (macOS style)", SmartTaskbarEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Only hides taskbar when windows maximize or touch the bottom edge.", "xm y+8")

    Lbl(pg, FG, "Taskbar Style", "xm y+16")
    C["epStyle"] := pg.AddDropDownList("x170 yp-3 w100 Choose" (EP_Style=="Win10" ? 1 : 2), ["Win10", "Win11"])
    Sub(pg, 220, cSub, "Win10 supports small icons", "x+16 yp+3")
    
    Lbl(pg, FG, "Icon Size", "xm y+16")
    C["epIconSize"] := pg.AddDropDownList("x170 yp-3 w100 Choose" (EP_IconSize=="Small" ? 1 : 2), ["Small", "Large"])
    
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

    g.OnEvent("Close", (*) => (SaveSettings(), SetTimer(ApplyUi, 0), g.Destroy(), Win := ""))
    g.OnEvent("Escape", (*) => (SaveSettings(), SetTimer(ApplyUi, 0), g.Destroy(), Win := ""))

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

ApplyUi() {
    ; Bare 'global', like LoadSettings/SaveSettings. A partial list is a trap
    ; here: AHK v2 makes a silent local out of any name assigned but not
    ; declared, so a missing entry means that control quietly does nothing.
    global
    if !Win
        return

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
        
        SyncHotCornersTimer()
        SyncCursorWrapTimer()
        
        SpotlightEnabled := C["spotlight"].Value
        ActiveBorderEnabled := C["border"].Value
        SyncActiveBorderTimer()
        
        AlwaysOnBottomEnabled := C["bottom"].Value
        
        TextExpanderEnabled := C["expander"].Value
        SyncTextExpander()
        
        PlainPasteEnabled := C["plainpaste"].Value
        SmartCapsEnabled := C["smartcaps"].Value
        SmartCapsAction := C["smartcaps_act"].Text
        ParallaxEnabled := C["parallax"].Value

        oldSmartTaskbar := SmartTaskbarEnabled
        SmartTaskbarEnabled := C["smart_tb"].Value
        if (oldSmartTaskbar && !SmartTaskbarEnabled && OriginalTaskbarState != -1)
            SetTaskbarAutoHide(OriginalTaskbarState & 1)

        EP_Style       := C["epStyle"].Text
        EP_IconSize    := C["epIconSize"].Text

        SNAP_DISTANCE  := Integer(Clamp(NumOr(C["dist"].Value, SNAP_DISTANCE), 1, 300))
        CORNER_BOOST   :=         Clamp(NumOr(C["boost"].Value, CORNER_BOOST), 1, 10)
        NEIGHBOUR_PROX := Integer(Clamp(NumOr(C["prox"].Value, NEIGHBOUR_PROX), 0, 1000))
        GLIDE_THROW    :=         Clamp(NumOr(C["throw"].Value, GLIDE_THROW), 0, 5)
        GLIDE_MS       := Integer(Clamp(NumOr(C["gms"].Value, GLIDE_MS), 0, 3000))

        if (C["auto"].Value != IsAutoStart())
            SetAutoStart(C["auto"].Value)

        SyncTray()
        SyncBreathingTimers()        ; start/stop the polling to match the checkbox
        SyncSmartTaskbar()
        SyncDimmerTimer()
        SyncHotCornersTimer()
        SaveSettings()

    }
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
    if WinGetClass(hwnd) != "#32770"
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
        Sleep 50
        ControlSend("{Enter}", "Edit1", hwnd)
        Sleep 150
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
    Sleep 50
    Send("^v")
    Sleep 100
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
    
    if (!dragged) {
        Send("{Blind}{MButton}")
    }
}
#HotIf

global CustomTrans := Map()

ChangeTransparency(dir) {
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    try {
        current := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255
    } catch {
        current := 255
    }
    
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
        try WinSetTransparent("Off", hwnd)
        CustomTrans.Delete(hwnd)
        Notify("Transparency: OFF")
    } else {
        try WinSetTransparent(current, hwnd)
        pct := Round((current / 255) * 100)
        Notify("Opacity: " pct "%")
    }
}

global RolledUpWindows := Map()

ToggleRollUp(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    if RolledUpWindows.Has(hwnd) {
        origH := RolledUpWindows[hwnd]
        RolledUpWindows.Delete(hwnd)
        
        WinGetPos(&x, &y, &w, &h, hwnd)
        
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        wh := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        ch := NumGet(rc, 12, "int")
        caption := wh - ch
        if (caption < 30)
            caption := 35
            
        steps := 12
        Loop steps {
            if !DllCall("IsWindow", "ptr", hwnd)
                return
            t := A_Index / steps
            ease := 1 - (1 - t) * (1 - t)
            curH := caption + Round((origH - caption) * ease)
            try WinSetRegion("0-0 W" w " H" curH, hwnd)
            Sleep 16
        }
        try WinSetRegion("", hwnd)
    } else {
        WinGetPos(&x, &y, &w, &h, hwnd)
        RolledUpWindows[hwnd] := h
        
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        wh := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        ch := NumGet(rc, 12, "int")
        caption := wh - ch
        if (caption < 30)
            caption := 35
            
        steps := 12
        Loop steps {
            if !DllCall("IsWindow", "ptr", hwnd)
                return
            t := A_Index / steps
            ease := 1 - (1 - t) * (1 - t)
            curH := h - Round((h - caption) * ease)
            try WinSetRegion("0-0 W" w " H" curH, hwnd)
            Sleep 16
        }
        try WinSetRegion("0-0 W" w " H" caption, hwnd)
    }
}

AltDragMove() {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return
        
    if WinGetMinMax(hwnd) != 0
        return
        
    if !WinActive(hwnd)
        try WinActivate(hwnd)
        
    global ParallaxEnabled, GlideEnabled, SnapEnabled
    global VelX, VelY, GLIDE_THROW, GLIDE_MAX
    vX := 0, vY := 0

    Loop {
        if !GetKeyState("LButton", "P") || !GetKeyState("Alt", "P")
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
                try WinSetTransparent(alpha, hwnd)
            }
            
            WinGetPos(&wX, &wY,,, hwnd)
            wX += vX
            wY += vY
            mX := nX
            mY := nY
            try WinMove(wX, wY,,, hwnd)
        } else {
            vX := 0, vY := 0
            if ParallaxEnabled
                try WinSetTransparent(255, hwnd)
        }
        Sleep 10
    }
    
    if ParallaxEnabled
        try WinSetTransparent("Off", hwnd)

    ; Hand off to the same release pipeline a title-bar drag uses. SnapWindow
    ; reads VelX/VelY to carry the throw forward and calls Glide itself, so
    ; there is nothing to schedule separately.
    VelX := vX, VelY := vY
    if (SnapEnabled) {
        if GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
            SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    } else if (GlideEnabled && (Abs(vX) > 5 || Abs(vY) > 5)) {
        ; Snap off, glide on: throw it by hand, then keep it on screen.
        WinGetPos(&gx, &gy, &gw, &gh, hwnd)
        tx := gx + Clamp(Round(vX * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
        ty := gy + Clamp(Round(vY * GLIDE_THROW * 12), -GLIDE_MAX, GLIDE_MAX)
        gR := tx + gw, gB := ty + gh
        KeepOnScreen(hwnd, &tx, &ty, &gR, &gB, vX, vY)
        Glide(hwnd, gx, gy, tx, ty)
    }
    RememberPosition(hwnd)
}

AltDragResize() {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return
        
    WinGetPos(&wX, &wY, &wW, &wH, hwnd)
    if WinGetMinMax(hwnd) != 0
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
        
    Loop {
        if !GetKeyState("RButton", "P") || !GetKeyState("Alt", "P")
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
            try WinMove(wX, wY, wW, wH, hwnd)
        }
        Sleep 10
    }
}

global TrayIcons := Map()
OnMessage(0x1000, TrayIconClick)

TrayIconClick(wParam, lParam, msg, hwnd) {
    if (lParam == 0x0202) {
        if TrayIcons.Has(wParam)
            RestoreFromTray(wParam)
    }
}

HideToTray(hwnd := 0) {
    global TrayMinimizeEnabled
    if (!TrayMinimizeEnabled)
        return
        
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    title := WinGetTitle(hwnd)
    if (title == "")
        title := "Hidden Window"
        
    hIcon := DllCall("SendMessage", "ptr", hwnd, "uint", 0x7F, "ptr", 2, "ptr", 0, "ptr")
    if !hIcon
        hIcon := DllCall("SendMessage", "ptr", hwnd, "uint", 0x7F, "ptr", 0, "ptr", 0, "ptr")
    if !hIcon
        hIcon := DllCall("GetClassLongPtr", "ptr", hwnd, "int", -14, "ptr")
        
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
    if (!BossKeyEnabled)
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
        
        for hwnd in hwnds {
            cls := ""
            try cls := WinGetClass(hwnd)
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd")
                continue
                
            global Win
            if (Win && hwnd == Win.Hwnd)
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
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive
    if (BreathingEnabled) {
        SetTimer(BreathingMonitor, 200)
        SetTimer(BreathingAnimator, 32)
        return
    }
    SetTimer(BreathingMonitor, 0)
    SetTimer(BreathingAnimator, 0)
    ; Hand every window its opacity back before we stop animating it, or a
    ; window dimmed at the moment of the toggle stays dim for good.
    for hwnd, alpha in WinCurrentAlpha {
        if DllCall("IsWindow", "ptr", hwnd)
            try WinSetTransparent(CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : "Off", hwnd)
    }
    WinTargetAlpha.Clear(), WinCurrentAlpha.Clear(), WinLastActive.Clear()
}
SyncBreathingTimers()

; Breathing does the pruning for its own three Maps, but CustomTrans and
; RolledUpWindows outlive it, so with breathing off they grew for the whole
; session. Cheap enough to run always: one IsWindow per tracked window.
PruneWindowMaps() {
    global CustomTrans, RolledUpWindows
    for hwnd in CustomTrans.Clone()
        if !DllCall("IsWindow", "ptr", hwnd)
            CustomTrans.Delete(hwnd)
    for hwnd in RolledUpWindows.Clone()
        if !DllCall("IsWindow", "ptr", hwnd)
            RolledUpWindows.Delete(hwnd)
}
SetTimer(PruneWindowMaps, 5000)

BreathingMonitor() {
    global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha
    if !BreathingEnabled
        return
        
    MouseGetPos(,, &mHwnd)
    aHwnd := WinExist("A")
    hwnds := WinGetList()
    now := A_TickCount
    
    For hwnd in hwnds {
        if !IsRestorable(hwnd)
            continue
            
        baseAlpha := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255
            
        if !WinLastActive.Has(hwnd) {
            WinLastActive[hwnd] := now
            WinCurrentAlpha[hwnd] := baseAlpha
            WinTargetAlpha[hwnd] := baseAlpha
        }
        
        if (hwnd == aHwnd || hwnd == mHwnd) {
            WinLastActive[hwnd] := now
            WinTargetAlpha[hwnd] := baseAlpha
        } else {
            if (now - WinLastActive[hwnd] > 6000) ; 6 seconds
                WinTargetAlpha[hwnd] := Min(baseAlpha, 180)
        }
    }
}

BreathingAnimator() {
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive
    if !BreathingEnabled
        return
        
    For hwnd, target in WinTargetAlpha {
        if !DllCall("IsWindow", "ptr", hwnd) {
            WinTargetAlpha.Delete(hwnd)
            WinCurrentAlpha.Delete(hwnd)
            WinLastActive.Delete(hwnd)
            if CustomTrans.Has(hwnd)
                CustomTrans.Delete(hwnd)
            continue
        }
        
        current := WinCurrentAlpha[hwnd]
        if (current == target)
            continue
            
        if (target == 255)
            step := 25 ; Wake up fast
        else
            step := 2  ; Fall asleep very slowly
            
        if (current < target)
            current := Min(current + step, target)
        else
            current := Max(current - step, target)
        
        WinCurrentAlpha[hwnd] := current
        
        try {
            if (current == 255)
                WinSetTransparent("Off", hwnd)
            else
                WinSetTransparent(current, hwnd)
        }
    }
}
$!F4::GravityClose()

GravityClose() {
    hwnd := WinExist("A")
    if !hwnd {
        Send("!{F4}")
        return
    }
    
    cls := WinGetClass(hwnd)
    if (cls == "AutoHotkeyGUI" || cls == "WorkerW" || cls == "Progman" || cls == "Shell_TrayWnd") {
        Send("!{F4}")
        return
    }
    
    WinGetPos(&x, &y, &w, &h, hwnd)
    
    ; Capture window visual
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
    oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
    
    ; PW_RENDERFULLCONTENT = 2
    success := DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
    
    DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    
    if !success {
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
        Send("!{F4}")
        return
    }
    
    ; Make real window invisible temporarily
    try WinSetTransparent(0, hwnd)
    
    ; Create animation GUI
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "GravityCloseAnim")
    animGui.MarginX := 0, animGui.MarginY := 0
    ; No '*': that would hand the handle to AHK to free, and we free it
    ; ourselves after Destroy() below. One owner, not two.
    pic := animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("x" x " y" y " w" w " h" h " NoActivate")
    
    ; Black Hole / Gravity Drop animation
    steps := 20
    startW := w, startH := h
    startX := x, startY := y
    
    Loop steps {
        t := A_Index / steps
        ease := t * t * t ; cubic ease in
        
        curW := Round(startW * (1 - ease * 0.95))
        curH := Round(startH * (1 - ease * 0.95))
        
        curX := Round(startX + (startW - curW) / 2)
        curY := Round(startY + ease * (startH * 0.8) + (startH - curH) / 2)
        
        try {
            animGui.Move(curX, curY, curW, curH)
            pic.Move(0, 0, curW, curH)
            
            if (t > 0.4) {
                alpha := Clamp(Round(255 * (1 - ((t - 0.4) / 0.6))), 0, 255)
                WinSetTransparent(alpha, animGui.Hwnd)
            }
        }
        Sleep 16
    }
    
    animGui.Destroy()
    if hbm
        DllCall("DeleteObject", "ptr", hbm)

    ; Close the real window
    try PostMessage(0x0010, 0, 0, , hwnd) ; WM_CLOSE
    
    ; If it doesn't close (e.g. unsaved changes prompt), make it visible again
    if !WinWaitClose(hwnd, 0.4) {
        try WinSetTransparent("Off", hwnd)
    }
}

global FocusModeEnabled := false
global FocusGuis := []
global SpotlightTarget := {x: 0, y: 0, w: 0, h: 0}
global SpotlightCurrent := {x: 0, y: 0, w: 0, h: 0}
global FocusBounds := {x: 0, y: 0, w: 0, h: 0}
global FocusTargetHwnd := 0

ToggleFocusMode() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    FocusModeEnabled := !FocusModeEnabled
    
    if (FocusModeEnabled) {
        if FocusGuis.Length
            return
            
        alphas := [140, 200, 240] ; Vignette layers opacity
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        
        loop 3 {
            g := Gui("-Caption -DPIScale +ToolWindow +E0x20", "FocusModeOverlay" A_Index)
            g.BackColor := "000000"
            g.MarginX := 0, g.MarginY := 0
            g.Show("x" vx " y" vy " w" vw " h" vh " NoActivate")
            WinSetTransparent(0, g.Hwnd)
            FocusGuis.Push({gui: g, targetAlpha: alphas[A_Index], currentAlpha: 0})
        }
        
        FocusTargetHwnd := WinExist("A")
        if (FocusTargetHwnd && IsRestorable(FocusTargetHwnd) && WinGetMinMax(FocusTargetHwnd) == 0) {
            WinGetPos(&tx, &ty, &tw, &th, FocusTargetHwnd)
            SpotlightCurrent := {x: tx, y: ty, w: tw, h: th}
            SpotlightTarget := {x: tx, y: ty, w: tw, h: th}
        } else {
            SpotlightCurrent := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
            SpotlightTarget := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
        }
        
        ZOrderSpotlight()
        SetTimer(FocusAnimator, 16)
        Notify("Focus Mode ON")
    } else {
        SetTimer(FocusAnimator, 0)
        ; 'layer', not 'fg' - case-insensitive identifiers make 'fg' the global
        ; foreground colour FG.
        for layer in FocusGuis {
            FadeWindow(layer.gui.Hwnd, layer.currentAlpha, 0, 300)
            SetTimer(GuiDestroy.Bind(layer.gui), -350)
        }
        FocusGuis := []
        Notify("Focus Mode OFF")
    }
}

GuiDestroy(g) {
    try g.Destroy()
}

ZOrderSpotlight() {
    global FocusGuis, FocusTargetHwnd
    if !FocusTargetHwnd || !DllCall("IsWindow", "ptr", FocusTargetHwnd)
        return
        
    prevHwnd := FocusTargetHwnd
    for layer in FocusGuis {
        try DllCall("SetWindowPos", "ptr", layer.gui.Hwnd, "ptr", prevHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        prevHwnd := layer.gui.Hwnd
    }
}

FocusAnimator() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    if !FocusModeEnabled || !FocusGuis.Length
        return
        
    hwnd := WinExist("A")
    if (hwnd != FocusTargetHwnd) {
        FocusTargetHwnd := hwnd
        ZOrderSpotlight()
    }
    
    if (hwnd && IsRestorable(hwnd) && WinGetMinMax(hwnd) == 0) {
        WinGetPos(&tx, &ty, &tw, &th, hwnd)
        SpotlightTarget := {x: tx, y: ty, w: tw, h: th}
    } else {
        MouseGetPos(&mx, &my)
        SpotlightTarget := {x: mx, y: my, w: 0, h: 0}
    }
    
    ; 'spot', not 'c' - 'c' is the global control Map C.
    spot := SpotlightCurrent
    t    := SpotlightTarget

    spot.x := spot.x * 0.85 + t.x * 0.15
    spot.y := spot.y * 0.85 + t.y * 0.15
    spot.w := spot.w * 0.85 + t.w * 0.15
    spot.h := spot.h * 0.85 + t.h * 0.15

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

        try WinSetRegion(region, layer.gui.Hwnd)

        ; Both directions. With only the fade-in branch, a lowered target left
        ; the outer if permanently true and re-issued the same alpha every 16ms.
        if (layer.currentAlpha != layer.targetAlpha) {
            if (layer.currentAlpha < layer.targetAlpha)
                layer.currentAlpha := Min(layer.currentAlpha + 12, layer.targetAlpha)
            else
                layer.currentAlpha := Max(layer.currentAlpha - 12, layer.targetAlpha)
            try WinSetTransparent(layer.currentAlpha, layer.gui.Hwnd)
        }
    }
}

FadeWindow(hwnd, startAlpha, endAlpha, durationMs) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    steps := 15
    sleepTime := durationMs / steps
    alphaStep := (endAlpha - startAlpha) / steps
    
    Loop steps {
        currentAlpha := startAlpha + (A_Index * alphaStep)
        try WinSetTransparent(Integer(currentAlpha), hwnd)
        Sleep sleepTime
    }
    try WinSetTransparent(endAlpha, hwnd)
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
global WinEventCb := CallbackCreate(WinEvent, "F", 7)
; Keep the hook handle: without it the hook can never be unhooked, and the
; callback can never be freed. Bye() releases both.
global WinEventHook := DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", WinEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

WinEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global SnapEnabled, RestoreEnabled, DragHwnd, DragL, DragT, DragR, DragB, VelX, VelY, PrevX, PrevY
    global CurrentDragAlpha          ; assigned below - without this it is a local and the reset never lands
    if (idObject != 0)
        return
    if (!SnapEnabled && !RestoreEnabled)
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
        SetTimer(SampleVelocity, 16)
        return
    }

    if (hwnd != DragHwnd)                    ; MOVESIZEEND
        return
    SetTimer(SampleVelocity, 0)
    DragHwnd := 0
    SetTimer(() => FinishDrag(hwnd), -50)    ; defer: FinishDrag enumerates windows
}

; Release speed in px per frame, smoothed so one jittery frame can't dominate.
SampleVelocity() {
    global DragHwnd, VelX, VelY, PrevX, PrevY, ParallaxEnabled, CurrentDragAlpha
    if !DragHwnd {
        SetTimer(SampleVelocity, 0)
        return
    }
    if !GetRects(DragHwnd, &L, &T, &R, &B, &x, &y)
        return
    VelX := VelX * 0.6 + (L - PrevX) * 0.4
    VelY := VelY * 0.6 + (T - PrevY) * 0.4
    PrevX := L, PrevY := T
    
    if (ParallaxEnabled) {
        speed := Sqrt(VelX * VelX + VelY * VelY)
        targetAlpha := Clamp(Round(255 - (speed * 4)), 60, 255)
        
        CurrentDragAlpha := CurrentDragAlpha * 0.7 + targetAlpha * 0.3
        
        ; Braces are load-bearing: AHK v2's Try has its own Else clause, so a
        ; braceless one-line try swallows the else and fails to parse.
        if (CurrentDragAlpha < 250) {
            try WinSetTransparent(Integer(CurrentDragAlpha), DragHwnd)
        } else {
            try WinSetTransparent("Off", DragHwnd)
        }
    }
}

FinishDrag(hwnd) {
    global MIN_DRAG, DragL, DragT, DragR, DragB, ParallaxEnabled, CurrentDragAlpha
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - DragL) < MIN_DRAG && Abs(eT - DragT) < MIN_DRAG
        && Abs(eR - DragR) < MIN_DRAG && Abs(eB - DragB) < MIN_DRAG)
        return
    if (WinGetMinMax(hwnd) != 0) {           ; Windows' own snap maximised it
        WriteLog("skip: window ended maximized")
        return
    }
    
    if (ParallaxEnabled)
        SetTimer(FadeBackAlpha.Bind(hwnd, CurrentDragAlpha), -1)
        
    WriteLog(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    RememberPosition(hwnd)
}

FadeBackAlpha(hwnd, startA) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
        
    if (startA >= 250) {
        try WinSetTransparent("Off", hwnd)
        return
    }
        
    steps := 12
    stepSize := (255 - startA) / steps
    
    Loop steps {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
        cur := startA + (A_Index * stepSize)
        try WinSetTransparent(Integer(cur), hwnd)
        Sleep 16
    }
    try WinSetTransparent("Off", hwnd)
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

    if GlideEnabled
        Glide(hwnd, winX, winY, destX, destY)
    else
        MoveFast(hwnd, destX, destY)
        
    global SeamFlashEnabled
    if (SeamFlashEnabled) {
        W := R - L
        H := B - T
        if (newL != pL) {
            for v in vLines {
                if (Abs(newL - v) < 2) {
                    ShowSeamFlash(newL - 1, newT, 3, H)
                    break
                }
                if (Abs(newL + W - v) < 2) {
                    ShowSeamFlash(newL + W - 1, newT, 3, H)
                    break
                }
            }
        }
        if (newT != pT) {
            for hLine in hLines {
                if (Abs(newT - hLine) < 2) {
                    ShowSeamFlash(newL, newT - 1, W, 3)
                    break
                }
                if (Abs(newT + H - hLine) < 2) {
                    ShowSeamFlash(newL, newT + H - 1, W, 3)
                    break
                }
            }
        }
    }
        
    ; Physics: if momentum carried us further than the snap allowed, we crashed into a wall
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
    
    if (Abs(crashX) > 4 || Abs(crashY) > 4) {
        WinGetPos(&currentX, &currentY, &currentW, &currentH, hwnd)
        BounceSqueeze(hwnd, destX, destY, currentW, currentH, crashX, crashY)
    }

    Sleep 40
    if !GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
        return
    ; One retry: some apps reposition themselves once more after a drag.
    if (vL != newL || vT != newT) {
        MoveFast(hwnd, vx + (newL - vL), vy + (newT - vT))
        Sleep 40
        GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
    }
    WriteLog(Format("  settled at L={1} T={2}  (throw {3},{4}) (verified L={5} T={6})",
               newL, newT, tx, ty, vL, vT))
}

; Quintic ease-out: quick off the mark, then a long soft tail, which is what
; reads as sliding on ice. Driven by elapsed time rather than fixed steps -
; Sleep overshoots its requested delay and that unevenness reads as stutter.
Glide(hwnd, fromX, fromY, toX, toY) {
    global GLIDE_MS
    dx := toX - fromX, dy := toY - fromY
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 2 || GLIDE_MS < 1) {
        MoveFast(hwnd, toX, toY)
        return
    }
    ; Longer than it looks: the quintic tail means most of this time is spent
    ; barely moving, which is the part that reads as ice.
    ms := Min(GLIDE_MS, 200 + dist * 1.1)

    DllCall("winmm\timeBeginPeriod", "uint", 1)      ; make the short sleeps honest
    ; finally: anything throwing inside the loop would otherwise leak the 1ms
    ; global timer resolution for the life of the process.
    try {
        start := A_TickCount
        lastX := -99999, lastY := -99999
        loop {
            t := (A_TickCount - start) / ms
            if (t >= 1)
                break
            e := 1 - (1 - t) ** 5
            nx := Round(fromX + dx * e)
            ny := Round(fromY + dy * e)
            if (nx != lastX || ny != lastY) {        ; skip sub-pixel frames
                MoveFast(hwnd, nx, ny)
                lastX := nx, lastY := ny
            }
            Sleep 4
        }
    } finally {
        DllCall("winmm\timeEndPeriod", "uint", 1)
    }
    MoveFast(hwnd, toX, toY)
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
        
    ; Animate the squeeze (bounce against the wall)
    MoveAndSize(hwnd, X + moveX*0.5, Y + moveY*0.5, W - squeezeX*0.5, H - squeezeY*0.5)
    Sleep 16
    MoveAndSize(hwnd, X + moveX, Y + moveY, W - squeezeX, H - squeezeY)
    Sleep 16
    MoveAndSize(hwnd, X + moveX*0.4, Y + moveY*0.4, W - squeezeX*0.4, H - squeezeY*0.4)
    Sleep 16
    MoveAndSize(hwnd, X, Y, W, H)
}

MoveAndSize(hwnd, x, y, w, h) {
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y, "int", w, "int", h, "uint", 0x0004 | 0x0010)
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
    
    SetTimer(FadeSeam.Bind(flash.Hwnd, w, h), -10)
}

FadeSeam(hwnd, w, h) {
    steps := 12
    WinGetPos(&x, &y, &cw, &ch, hwnd)
    
    Loop steps {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
        t := A_Index / steps
        alpha := Round(255 * (1 - t*t))
        
        if (w < h) {
            shrink := Round(h * t * 0.3)
            try DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y + shrink, "int", w, "int", h - shrink*2, "uint", 0x0004 | 0x0010)
        } else {
            shrink := Round(w * t * 0.3)
            try DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x + shrink, "int", y, "int", w - shrink*2, "int", h, "uint", 0x0004 | 0x0010)
        }
        
        try WinSetTransparent(alpha, hwnd)
        Sleep 16
    }
    try WinClose("ahk_id " hwnd)
}

; Cheaper than WinMove per frame, and leaves z-order and focus alone mid-slide.
MoveFast(hwnd, x, y) {
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y,
            "int", 0, "int", 0, "uint", 0x0001 | 0x0004 | 0x0010)
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
DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), ShellEvent)

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
    
    if ((wParam & 0x7FFF) = 4) { ; HSHELL_WINDOWACTIVATED
        if (lParam)
            SetTimer(PulseWindow.Bind(lParam), -10)
    }

    if ((wParam & 0x7FFF) = HSHELL_WINDOWCREATED) {
        global OpenAnim, GhostHiddenWindows
        hwnd := lParam
        if (OpenAnim != "None" && !DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")) {
            try {
                WinSetTransparent(0, hwnd)
                GhostHiddenWindows[hwnd] := true
            }
        }
        SetTimer(() => HandleNewWindow(hwnd), -250)
    }
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


    ; Ensure it restores on-screen
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
    
    try {
        WinMove(rx, ry, rw, rh, hwnd)
        WriteLog("restored " key " -> " rx "," ry " " rw "x" rh)
    }
}

global GhostHiddenWindows := Map()

HandleNewWindow(hwnd) {
    global OpenAnim, GhostHiddenWindows
    isHidden := GhostHiddenWindows.Has(hwnd)
    if isHidden
        GhostHiddenWindows.Delete(hwnd)
        
    if !DllCall("IsWindow", "ptr", hwnd)
        return
        
    RestorePosition(hwnd)
    
    if (isHidden && OpenAnim != "None" && IsRestorable(hwnd) && WinGetMinMax(hwnd) == 0) {
        if (OpenAnim == "Ghost Slide-In")
            GhostSlideIn(hwnd)
        else if (OpenAnim == "Window Unrolling")
            UnrollWindow(hwnd)
    } else if (isHidden) {
        try WinSetTransparent("Off", hwnd)
    }
}

UnrollWindow(hwnd) {
    WinGetPos(&x, &y, &w, &h, hwnd)
    if (w = 0 || h = 0) {
        try WinSetTransparent("Off", hwnd)
        return
    }
    
    try WinSetTransparent("Off", hwnd)
    
    steps := 12
    Loop steps {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
            
        t := A_Index / steps
        ease := 1 - (1 - t) * (1 - t)
        
        curH := Round(h * ease)
        if (curH < 1)
            curH := 1
            
        try WinSetRegion("0-0 W" w " H" curH, hwnd)
        Sleep 16
    }
    
    try WinSetRegion("", hwnd)
}

GhostSlideIn(hwnd) {
    WinGetPos(&x, &y, &w, &h, hwnd)
    if (w = 0 || h = 0) {
        try WinSetTransparent("Off", hwnd)
        return
    }
    
    startY := y + 30
    endY := y
    
    MoveFast(hwnd, x, startY)
    
    steps := 15
    Loop steps {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
            
        t := A_Index / steps
        ease := 1 - (1 - t) * (1 - t) ; ease-out
        
        curY := Round(startY + (endY - startY) * ease)
        MoveFast(hwnd, x, curY)
        
        alpha := Round(255 * ease)
        try WinSetTransparent(alpha, hwnd)
        
        Sleep 16
    }
    
    try WinSetTransparent("Off", hwnd)
    MoveFast(hwnd, x, endY)
}

global PulsingWindows := Map()

PulseWindow(hwnd) {
    global PulseEnabled, PulsingWindows
    if (!PulseEnabled || !DllCall("IsWindow", "ptr", hwnd) || !IsRestorable(hwnd))
        return
        
    if (WinGetMinMax(hwnd) != 0) ; skip maximized/minimized
        return
        
    if PulsingWindows.Has(hwnd)
        return
        
    PulsingWindows[hwnd] := true

    ; finally, not a plain trailing Delete: the Sleeps let other threads run, so
    ; a window closing mid-pulse would throw out of WinGetPos and strand the
    ; entry - after which that hwnd could never pulse again.
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)

        pw := Min(Round(w * 0.015), 12)
        ph := Min(Round(h * 0.015), 12)

        MoveAndSize(hwnd, x - Round(pw/2), y - Round(ph/2), w + pw, h + ph)
        Sleep 16
        MoveAndSize(hwnd, x - pw, y - ph, w + pw*2, h + ph*2)
        Sleep 16
        MoveAndSize(hwnd, x - Round(pw/2), y - Round(ph/2), w + pw, h + ph)
        Sleep 16
        MoveAndSize(hwnd, x, y, w, h)
    } finally {
        PulsingWindows.Delete(hwnd)
    }
}

; ====== Multi-Monitor Focus Dimmer ======
SyncDimmerTimer() {
    global MultiMonitorDimmerEnabled, DimmerGuis
    if (MultiMonitorDimmerEnabled) {
        SetTimer(MonitorDimmerTick, 200)
    } else {
        SetTimer(MonitorDimmerTick, 0)
        for k, g in DimmerGuis {
            SetTimer(FadeOutAndDestroyDimmer.Bind(g), -1)
        }
        DimmerGuis.Clear()
    }
}
SyncDimmerTimer()

MonitorDimmerTick() {
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
            if (A_Index == activeMon) {
                if DimmerGuis.Has(A_Index) {
                    g := DimmerGuis[A_Index]
                    DimmerGuis.Delete(A_Index)
                    SetTimer(FadeOutAndDestroyDimmer.Bind(g), -1)
                }
            } else {
                if !DimmerGuis.Has(A_Index) {
                    MonitorGet(A_Index, &L, &T, &R, &B)
                    g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20 +E0x8000000")
                    g.BackColor := "000000"
                    WinSetTransparent(0, g.Hwnd)
                    g.Show("NoActivate x" L " y" T " w" (R-L) " h" (B-T))
                    DimmerGuis[A_Index] := g
                    SetTimer(FadeInDimmer.Bind(g), -1)
                }
            }
        }
    }
}

FadeInDimmer(g) {
    try {
        hwnd := g.Hwnd
        alpha := 0
        Loop 15 {
            if !DllCall("IsWindow", "ptr", hwnd)
                return
            alpha += 8
            try WinSetTransparent(alpha, hwnd)
            Sleep 10
        }
    }
}

FadeOutAndDestroyDimmer(g) {
    try {
        hwnd := g.Hwnd
        alpha := 120
        Loop 15 {
            if !DllCall("IsWindow", "ptr", hwnd)
                return
            alpha -= 8
            try WinSetTransparent(alpha, hwnd)
            Sleep 10
        }
        try g.Destroy()
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
        
    QuickLookGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound +Border")
    QuickLookGui.BackColor := "111111"
    QuickLookGui.MarginX := 20
    QuickLookGui.MarginY := 20
    
    ext := StrLower(RegExReplace(path, ".*\.([^.]+)$", "$1"))
    try {
        if (ext ~= "^(png|jpg|jpeg|gif|bmp)$") {
            QuickLookGui.AddPicture("w-1 h-1", path)
        } else if (ext ~= "^(txt|md|ini|ahk|csv|log|json|xml|ps1|bat|cmd)$") {
            txt := FileRead(path, "m4096") 
            QuickLookGui.AddEdit("w600 h400 ReadOnly Background111111 cWhite -E0x200", txt)
        } else {
            return false 
        }
    } catch {
        QuickLookGui.Destroy()
        QuickLookGui := ""
        return false
    }
    
    WinSetTransparent(0, QuickLookGui.Hwnd)
    QuickLookGui.Show("NoActivate AutoSize Center")
    QuickLookFade(QuickLookGui.Hwnd, 0, 255)
    SetTimer(CheckQuickLookFocus, 200)
    return true
}

QuickLookFade(hwnd, startA, endA) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    step := (endA > startA) ? 25 : -25
    alpha := startA
    Loop {
        alpha += step
        if (step > 0 && alpha >= endA) || (step < 0 && alpha <= endA) {
            try WinSetTransparent(endA, hwnd)
            break
        }
        try WinSetTransparent(alpha, hwnd)
        Sleep 10
    }
}

CloseQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        SetTimer(CheckQuickLookFocus, 0)
        guiObj := QuickLookGui
        QuickLookGui := "" 
        QuickLookFade(guiObj.Hwnd, 255, 0)
        try guiObj.Destroy()
    }
}

CheckQuickLookFocus() {
    global QuickLookGui
    if !QuickLookGui
        return
    ahwnd := WinExist("A")
    if (ahwnd != QuickLookGui.Hwnd && WinGetClass(ahwnd) != "CabinetWClass")
        CloseQuickLook()
}

; ====== Smart Auto-Hide Taskbar ======
SyncSmartTaskbar() {
    global SmartTaskbarEnabled
    if (SmartTaskbarEnabled)
        SetTimer(SmartTaskbarMonitor, 200)
    else
        SetTimer(SmartTaskbarMonitor, 0)
}
SyncSmartTaskbar()

SmartTaskbarMonitor() {
    global SmartTaskbarEnabled
    static LastState := -1
    
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
            if (WinGetMinMax(hwnd) == -1) ; Minimized
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
                
            if (WinGetMinMax(hwnd) == 1 || wy + wh > tbActiveTop) {
                shouldHide := true
                break
            }
        }
        
        if (shouldHide != LastState) {
            SetTaskbarAutoHide(shouldHide)
            LastState := shouldHide
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
        SetTimer(HotCornersMonitor, 100)
    else
        SetTimer(HotCornersMonitor, 0)
}
SyncHotCornersTimer()

SyncCursorWrapTimer() {
    global InfiniteWrapEnabled
    if (InfiniteWrapEnabled)
        SetTimer(CursorWrapMonitor, 15)
    else
        SetTimer(CursorWrapMonitor, 0)
}
SyncCursorWrapTimer()

CursorWrapMonitor() {
    global InfiniteWrapEnabled
    if (!InfiniteWrapEnabled)
        return
        
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    
    vLeft := SysGet(76)
    vTop := SysGet(77)
    vWidth := SysGet(78)
    vHeight := SysGet(79)
    vRight := vLeft + vWidth
    vBottom := vTop + vHeight
    
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
        count := MonitorGetCount()
        valid := false
        Loop count {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (mx >= L && mx <= R && my >= T && my <= B) {
                valid := true
                break
            }
        }
        
        if (!valid) {
            closestDiff := 999999
            bestY := my
            Loop count {
                MonitorGet(A_Index, &L, &T, &R, &B)
                if (mx >= L && mx <= R) {
                    if (my < T)
                        dy := T - my, projY := T + 5
                    else if (my >= B)
                        dy := my - B + 1, projY := B - 5
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

HotCornersMonitor() {
    global HotCornersEnabled, HotCornerTL, HotCornerTR, HotCornerBL, HotCornerBR
    static LastCorner := "None"
    
    if (!HotCornersEnabled)
        return
        
    try {
        MouseGetPos(&mx, &my)
        
        count := MonitorGetCount()
        activeMon := 1
        Loop count {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (mx >= L && mx <= R - 1 && my >= T && my <= B - 1) {
                activeMon := A_Index
                break
            }
        }
        
        MonitorGet(activeMon, &L, &T, &R, &B)
        
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
    global OsdGui, OsdTimer
    
    if (OsdGui) {
        UpdateOSD(vol, isMuted)
    } else {
        try {
            OsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
            OsdGui.BackColor := "181818"
            WinSetTransparent(0, OsdGui.Hwnd)
            
            OsdGui.SetFont("s24 cWhite", "Segoe UI Emoji")
            OsdGui.AddText("vIcon x20 y12 w40 h40 BackgroundTrans Center", GetSpeakerIcon(vol, isMuted))
            
            OsdGui.AddText("x70 y29 w150 h6 Background333333")
            w := Max(1, Round(150 * (vol / 100)))
            OsdGui.AddText("vBar x70 y29 w" w " h6 BackgroundFFFFFF")
            
            OsdGui.Show("NoActivate w240 h64")
            WinSetRegion("w240 h64 r20-20", OsdGui.Hwnd)
            
            MonitorGet(1, &L, &T, &R, &B)
            x := L + (R - L - 240) // 2
            y := B - 150
            OsdGui.Move(x, y)
            
            SetTimer(() => OsdFadeIn(OsdGui.Hwnd), -1)
        }
    }
    
    if (OsdTimer)
        SetTimer(OsdTimer, 0)
    OsdTimer := () => HideVolumeOSD()
    SetTimer(OsdTimer, -1500)
}

UpdateOSD(vol, isMuted) {
    global OsdGui
    try {
        OsdGui["Icon"].Text := GetSpeakerIcon(vol, isMuted)
        w := Max(1, Round(150 * (vol / 100)))
        OsdGui["Bar"].Move(,,, w)
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

OsdFadeIn(hwnd) {
    alpha := 0
    Loop 10 {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
        alpha += 22
        try WinSetTransparent(alpha, hwnd)
        Sleep 10
    }
    try WinSetTransparent(220, hwnd)
}

HideVolumeOSD() {
    global OsdGui, OsdTimer
    OsdTimer := ""
    if (!OsdGui)
        return
        
    hwnd := OsdGui.Hwnd
    OsdGui := ""
    
    alpha := 220
    Loop 10 {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
        alpha -= 22
        try WinSetTransparent(alpha, hwnd)
        Sleep 10
    }
    try WinClose(hwnd)
}

; ====== Live Window PiP ======
OnMessage(0x0084, WM_NCHITTEST_PiP)

WM_NCHITTEST_PiP(wParam, lParam, msg, hwnd) {
    global PipGuis
    if IsSet(PipGuis) {
        for src, pip in PipGuis {
            if (pip.Hwnd == hwnd) {
                x := lParam << 48 >> 48
                y := lParam << 32 >> 48
                WinGetPos(&winX, &winY, &winW, &winH, hwnd)
                if (x < winX + 5 || x > winX + winW - 5 || y < winY + 5 || y > winY + winH - 5)
                    return 
                return 2 ; HTCAPTION
            }
        }
    }
}

TogglePiP() {
    global PipGuis
    if !IsSet(PipGuis)
        PipGuis := Map()
        
    srcHwnd := WinExist("A")
    if !srcHwnd
        return
        
    cls := WinGetClass(srcHwnd)
    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd")
        return
        
    for s, pip in PipGuis {
        if (pip.Hwnd == srcHwnd) {
            DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pip.ThumbId)
            pip.Destroy()
            PipGuis.Delete(s)
            return
        }
    }
    
    if PipGuis.Has(srcHwnd) {
        pip := PipGuis[srcHwnd]
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pip.ThumbId)
        pip.Destroy()
        PipGuis.Delete(srcHwnd)
        return
    }
    
    PipGui := Gui("-Caption +ToolWindow +AlwaysOnTop +Resize +Border")
    PipGui.BackColor := "000000"
    
    WinGetClientPos(,, &sw, &sh, srcHwnd)
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
    SetTimer(PiPMonitor, 1000)
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
    global PipGuis
    DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", guiObj.ThumbId)
    guiObj.Destroy()
    PipGuis.Delete(guiObj.SourceHwnd)
}

PiPMonitor() {
    global PipGuis
    if !IsSet(PipGuis) || PipGuis.Count == 0 {
        SetTimer(PiPMonitor, 0)
        return
    }
        
    for srcHwnd, pipGui in PipGuis.Clone() {
        if !DllCall("IsWindow", "ptr", srcHwnd) {
            DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pipGui.ThumbId)
            pipGui.Destroy()
            PipGuis.Delete(srcHwnd)
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
    global MicOsdGui, MicOsdTimer
    
    if (MicOsdGui) {
        UpdateMicOSD(isMuted)
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
            
            WinSetTransparent(0, MicOsdGui.Hwnd)
            
            MicOsdGui.SetFont("s20 cWhite bold", "Segoe UI")
            MicOsdGui.AddText("vText x0 y15 w240 h40 BackgroundTrans Center", txt)
            
            MicOsdGui.Show("NoActivate w240 h70")
            WinSetRegion("w240 h70 r20-20", MicOsdGui.Hwnd)
            
            MonitorGet(1, &L, &T, &R, &B)
            x := L + (R - L - 240) // 2
            y := T + 100 
            MicOsdGui.Move(x, y)
            
            SetTimer(() => OsdFadeIn(MicOsdGui.Hwnd), -1)
        }
    }
    
    if (MicOsdTimer)
        SetTimer(MicOsdTimer, 0)
    MicOsdTimer := () => HideMicOSD()
    SetTimer(MicOsdTimer, -2000)
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
    global MicOsdGui, MicOsdTimer
    MicOsdTimer := ""
    if (!MicOsdGui)
        return
        
    hwnd := MicOsdGui.Hwnd
    MicOsdGui := ""
    
    alpha := 220
    Loop 10 {
        if !DllCall("IsWindow", "ptr", hwnd)
            return
        alpha -= 22
        try WinSetTransparent(alpha, hwnd)
        Sleep 10
    }
    try WinClose(hwnd)
}

; ====== Quick Spotlight Launcher ======
ToggleSpotlight() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    
    if (SpotlightGui) {
        try SpotlightGui.Destroy()
        SpotlightGui := ""
        return
    }
    
    SpotlightGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    SpotlightGui.BackColor := "202020" 
    
    SpotlightGui.SetFont("s24 cWhite", "Segoe UI")
    SpotlightInput := SpotlightGui.AddEdit("x20 y20 w600 h45 -VScroll -E0x200 Background202020 cWhite")
    
    SpotlightGui.SetFont("s14 cAAAAAA", "Segoe UI")
    SpotlightResult := SpotlightGui.AddText("x20 y85 w600 h35", "Type to search, calculate, or run...")
    
    SpotlightInput.OnEvent("Change", SpotlightOnChange)
    
    MonitorGetPrimary(&activeMon)
    MonitorGet(activeMon, &L, &T, &R, &B)
    w := 640, h := 140
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 3 
    
    SpotlightGui.Show("x" x " y" y " w" w " h" h)
    WinSetRegion("w640 h140 r20-20", SpotlightGui.Hwnd)
    WinSetTransparent(240, SpotlightGui.Hwnd)
}

SpotlightOnChange(ctrl, *) {
    global SpotlightResult
    text := Trim(ctrl.Value)
    if (text = "") {
        SpotlightResult.Text := "Type to search, calculate, or run..."
        return
    }
    
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
        SetTimer(ActiveBorderMonitor, 15)
    else {
        SetTimer(ActiveBorderMonitor, 0)
        HideActiveBorder()
    }
}
SyncActiveBorderTimer()

ActiveBorderMonitor() {
    global ActiveBorderEnabled, LastBorderHwnd, LastBorderX, LastBorderY, LastBorderW, LastBorderH
    if (!ActiveBorderEnabled)
        return
        
    hwnd := WinExist("A")
    if (!hwnd) {
        HideActiveBorder()
        return
    }
    
    cls := WinGetClass(hwnd)
    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "AutoHotkeyGUI") {
        HideActiveBorder()
        return
    }
    
    style := WinGetStyle(hwnd)
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
    
    if (hwnd == LastBorderHwnd && X == LastBorderX && Y == LastBorderY && W == LastBorderW && H == LastBorderH)
        return
        
    LastBorderHwnd := hwnd
    LastBorderX := X, LastBorderY := Y, LastBorderW := W, LastBorderH := H
    
    DrawActiveBorder(X, Y, W, H)
}

DrawActiveBorder(X, Y, W, H) {
    global ActiveBorderGui
    
    if (!ActiveBorderGui) {
        ActiveBorderGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20") 
        ActiveBorderGui.BackColor := GetAccentColor()
    }
    
    t := 2 ; Thickness
    
    try {
        ActiveBorderGui.Show("NoActivate x" X " y" Y " w" W " h" H)
        rect1 := "0-0 w" W " h" t
        rect2 := "0-" (H-t) " w" W " h" t
        rect3 := "0-" t " w" t " h" (H-2*t)
        rect4 := (W-t) "-" t " w" t " h" (H-2*t)
        
        WinSetRegion(rect1 "  " rect2 "  " rect3 "  " rect4, ActiveBorderGui.Hwnd)
    }
}

HideActiveBorder() {
    global ActiveBorderGui, LastBorderHwnd
    LastBorderHwnd := 0
    if (ActiveBorderGui) {
        try ActiveBorderGui.Destroy()
        ActiveBorderGui := ""
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
        
    cls := WinGetClass(hwnd)
    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return
        
    if BottomWindows.Has(hwnd) {
        oldParent := BottomWindows[hwnd]
        try WinGetPos(&X, &Y, &W, &H, hwnd)
        
        DllCall("SetParent", "ptr", hwnd, "ptr", oldParent)
        BottomWindows.Delete(hwnd)
        
        if IsSet(X)
            try WinMove(X, Y, W, H, hwnd)
            
        WinSetTop(hwnd)
    } else {
        oldParent := DllCall("GetParent", "ptr", hwnd)
        if !oldParent
            oldParent := 0
            
        desktop := GetDesktopHwnd()
        
        try WinGetPos(&X, &Y, &W, &H, hwnd)
        
        DllCall("SetParent", "ptr", hwnd, "ptr", desktop)
        BottomWindows[hwnd] := oldParent
        
        if IsSet(X) {
            pt := Buffer(8)
            NumPut("Int", X, pt, 0)
            NumPut("Int", Y, pt, 4)
            DllCall("ScreenToClient", "ptr", desktop, "ptr", pt)
            nX := NumGet(pt, 0, "Int")
            nY := NumGet(pt, 4, "Int")
            
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", nX, "int", nY, "int", W, "int", H, "uint", 0x0014) 
        }
    }
}

; ====== Global Text Expander ======
IsExpanderActive(*) {
    global TextExpanderEnabled
    return TextExpanderEnabled
}

SyncTextExpander() {
    HotIf(IsExpanderActive)
    
    try IniRead(INI, "snippets")
    catch {
        try IniWrite("your.email@example.com", INI, "snippets", "@@mail")
        try IniWrite("+994501234567", INI, "snippets", "@@tel")
        try IniWrite("Təşəkkürlər!", INI, "snippets", "@@ty")
    }
    
    str := IniRead(INI, "snippets",, "")
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
        
    cls := WinGetClass(hwnd)
    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return
        
    if GhostWindows.Has(hwnd) {
        orig := GhostWindows[hwnd]
        GhostWindows.Delete(hwnd)
        
        try {
            WinSetTransparent("Off", hwnd)
            if !(orig.exStyle & 0x20)
                WinSetExStyle("-0x20", hwnd)
            if !(orig.exStyle & 0x8)
                WinSetAlwaysOnTop(0, hwnd)
        }
            
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitor, 0)
    } else {
        exStyle := WinGetExStyle(hwnd)
        GhostWindows[hwnd] := {exStyle: exStyle}
        
        WinSetAlwaysOnTop(1, hwnd)
        SetTimer(GhostMonitor, 25) 
    }
}

GhostMonitor() {
    global GhostWindows
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    
    maxDist := 350.0
    minAlpha := 40
    maxAlpha := 255
    
    for hwnd, info in GhostWindows.Clone() {
        if !DllCall("IsWindow", "ptr", hwnd) {
            GhostWindows.Delete(hwnd)
            continue
        }
        
        try {
            WinGetPos(&X, &Y, &W, &H, hwnd)
            dist := GetDistToRect(mx, my, X, Y, W, H)
            
            if (dist == 0)
                targetAlpha := maxAlpha
            else if (dist >= maxDist)
                targetAlpha := minAlpha
            else {
                ratio := 1.0 - (dist / maxDist)
                targetAlpha := minAlpha + Integer(ratio * (maxAlpha - minAlpha))
            }
            
            if (!info.HasProp("lastAlpha") || info.lastAlpha != targetAlpha) {
                WinSetTransparent(targetAlpha, hwnd)
                info.lastAlpha := targetAlpha
            }
            
            exStyle := WinGetExStyle(hwnd)
            isClickThrough := (exStyle & 0x20)
            
            if (dist < 80) { 
                if (isClickThrough)
                    WinSetExStyle("-0x20", hwnd)
            } else {
                if (!isClickThrough)
                    WinSetExStyle("+0x20", hwnd)
            }
        }
    }
}

OnExit(Bye)
Bye(*) {
    global TrayIcons, BossKeyActive, BossKeyWindows, BossKeyMuteState
    global WinEventHook, WinEventCb, RolledUpWindows, CustomTrans
    global OriginalTaskbarState, SmartTaskbarEnabled, DimmerGuis, OsdGui, PipGuis, MicOsdGui, SpotlightGui, ActiveBorderGui

    if (ActiveBorderGui)
        try ActiveBorderGui.Destroy()

    if (SpotlightGui)
        try SpotlightGui.Destroy()

    if IsSet(PipGuis) {
        for src, pip in PipGuis {
            DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pip.ThumbId)
            pip.Destroy()
        }
    }

    if (OsdGui)
        try OsdGui.Destroy()
        
    if (MicOsdGui)
        try MicOsdGui.Destroy()

    for k, g in DimmerGuis {
        if DllCall("IsWindow", "ptr", g.Hwnd)
            try g.Destroy()
    }

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

    ; Nothing here is left behind for the next process to trip over: a rolled-up
    ; window keeps its clipping region until something clears it, and a dimmed
    ; one keeps its alpha.
    for hwnd in RolledUpWindows {
        if DllCall("IsWindow", "ptr", hwnd)
            try WinSetRegion(, hwnd)
    }
    for hwnd, alpha in CustomTrans {
        if DllCall("IsWindow", "ptr", hwnd)
            try WinSetTransparent("Off", hwnd)
    }

    SetTimer(BreathingMonitor, 0)
    SetTimer(BreathingAnimator, 0)
    SetTimer(PruneWindowMaps, 0)

    ; Unhook before the callback goes away - the OS must not be left holding a
    ; pointer into a freed thunk.
    if (WinEventHook)
        try DllCall("UnhookWinEvent", "ptr", WinEventHook)
    if (WinEventCb)
        try CallbackFree(WinEventCb)
    try DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)

    SaveSettings()
    Return 0
}
