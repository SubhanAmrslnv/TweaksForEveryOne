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

global Win := "", Pages := Map(), NavItems := Map(), CurPage := ""
global C := Map(), LastTb := ""

LoadSettings()
RotateLog()
BuildTray()


Log("=== Window Tweaks " VERSION " started ===")

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
    SNAP_DISTANCE  := Integer(IniNum("snap", "distance", 30))
    CORNER_BOOST   := IniNum("snap", "cornerBoost", 2.2)
    NEIGHBOUR_PROX := Integer(IniNum("snap", "neighbour", 90))
    GlideEnabled   := IniStr("glide", "enabled", "1") = "1"
    GLIDE_THROW    := IniNum("glide", "throw", 0.9)
    GLIDE_MS       := Integer(IniNum("glide", "ms", 650))
    RestoreEnabled := IniStr("memory", "enabled", "1") = "1"
    EP_Style := "Win11"
    try EP_Style := RegRead("HKCU\\Software\\ExplorerPatcher", "TbStyle") == 1 ? "Win10" : "Win11"
    EP_IconSize := "Large"
    try EP_IconSize := RegRead("HKCU\\Software\\ExplorerPatcher", "Tb10SmallBtn") == 1 ? "Small" : "Large"
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
    try IniWrite(SNAP_DISTANCE,          INI, "snap", "distance")
    try IniWrite(Round(CORNER_BOOST, 2), INI, "snap", "cornerBoost")
    try IniWrite(NEIGHBOUR_PROX,         INI, "snap", "neighbour")
    try IniWrite(GlideEnabled ? 1 : 0,   INI, "glide", "enabled")
    try IniWrite(Round(GLIDE_THROW, 2),  INI, "glide", "throw")
    try IniWrite(GLIDE_MS,               INI, "glide", "ms")
    try IniWrite(RestoreEnabled ? 1 : 0, INI, "memory", "enabled")
    try RegWrite(EP_Style == "Win10" ? 1 : 0, "REG_DWORD", "HKCU\\Software\\ExplorerPatcher", "TbStyle")
    try RegWrite(EP_IconSize == "Small" ? 1 : 0, "REG_DWORD", "HKCU\\Software\\ExplorerPatcher", "Tb10SmallBtn")
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

Log(s) {
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
}

; =========================================================== Settings window ===========================================================
IsDark() {
    try return (RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                        "AppsUseLightTheme") = 0)
    return true
}

ShowWin() {
    global Win
    if (Win != "") {
        WinActivate("ahk_id " Win.Hwnd)
        return
    }
    BuildWin()
}

BuildWin() {
    global Win, Pages, NavItems, C, CurPage, VERSION
    global SnapEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MS
    global RestoreEnabled, EP_Style, EP_IconSize
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
    for name in ["Snapping", "Ice Glide", "Windows", "Taskbar", "General"] {
        t := g.AddText("x0 y" ny " w" SW " h42 +0x200 c" FG " Background" NAV, "      " name)
        t.OnEvent("Click", NavClick.Bind(name))
        NavItems[name] := t
        ny += 42
    }

    g.SetFont("s8", "Segoe UI")
    g.AddText("x20 y" (H - 40) " w160 c" cSub " Background" NAV, "Win+Ctrl+W  opens this")

    ; --- content ---
    CX := SW + 28, CW := W - SW - 56

    CreatePage(name) {
        pg := Gui("+Parent" Win.Hwnd " -Caption")
        pg.BackColor := BG
        pg.MarginX := 0, pg.MarginY := 26
        return pg
    }

    ; ---- Snapping
    pg := CreatePage("Snapping")
    Head(pg, CW, FG, "Magnetic snapping")
    Sub(pg, CW, cSub, "Release a dragged window near a screen edge, a corner, or another`nwindow's edge and it jumps flush against it.", "xm y+10")
    C["snap"] := Box(pg, CW, FG, "Enable magnetic snapping", SnapEnabled, "xm y+16")
    Lbl(pg, FG, "Snap distance", "xm y+16")
    C["dist"] := pg.AddEdit("x170 yp-3 w70 Number", SNAP_DISTANCE)
    Sub(pg, 260, cSub, "px from an edge", "x+12 yp+3")
    Lbl(pg, FG, "Corner boost", "xm y+16")
    C["boost"] := pg.AddEdit("x170 yp-3 w70", CORNER_BOOST)
    Sub(pg, 260, cSub, "x stronger at corners", "x+12 yp+3")
    Lbl(pg, FG, "Neighbour reach", "xm y+16")
    C["prox"] := pg.AddEdit("x170 yp-3 w70 Number", NEIGHBOUR_PROX)
    Sub(pg, 260, cSub, "px to nearby windows", "x+12 yp+3")
    Sub(pg, CW, cSub, "Corners pull harder than plain edges: once one axis locks on, the other`nis retried with a threshold `"corner boost`" times larger, so a window`nhugging the left edge drops into the corner from much further away.`n`nDragging to a screen edge is something Windows already does itself. The`nnew behaviour here is windows sticking to each other.", "xm y+24")
    Pages["Snapping"] := pg

    ; ---- Ice Glide
    pg := CreatePage("Ice Glide")
    Head(pg, CW, FG, "Ice glide")
    Sub(pg, CW, cSub, "Let go mid-drag and the window keeps sliding, decelerating, then settles`nonto whatever edge it drifts near.", "xm y+10")
    C["glide"] := Box(pg, CW, FG, "Enable ice glide", GlideEnabled, "xm y+16")
    Lbl(pg, FG, "Throw strength", "xm y+16")
    C["throw"] := pg.AddEdit("x170 yp-3 w70", GLIDE_THROW)
    Sub(pg, 260, cSub, "0 = stop where you let go", "x+12 yp+3")
    Lbl(pg, FG, "Slide time", "xm y+16")
    C["gms"] := pg.AddEdit("x170 yp-3 w70 Number", GLIDE_MS)
    Sub(pg, 260, cSub, "ms maximum", "x+12 yp+3")
    Sub(pg, CW, cSub, "The slide follows a quintic ease-out - quick off the mark, then a long`nsoft tail, which is what reads as sliding on ice rather than simply`nmoving. Each frame is positioned from the real clock rather than by`ncounting fixed steps, because timer overshoot is what shows up as`nstutter.`n`nRequires `"Show window contents while dragging`" - see ANIMATIONS.md.", "xm y+24")
    Pages["Ice Glide"] := pg

    ; ---- Windows
    pg := CreatePage("Windows")
    Head(pg, CW, FG, "Windows")
    Sub(pg, CW, cSub, "Always on top, and remembering where apps live.", "xm y+10")
    Lbl(pg, FG, "Always on top", "xm y+16")
    Sub(pg, CW, cSub, "Win+Ctrl+T pins or unpins whichever window is active. A tray`nnotification confirms which state it went to.", "xm y+8")
    C["mem"] := Box(pg, CW, FG, "Remember window positions", RestoreEnabled, "xm y+24")
    b := pg.AddButton("xm y+16 w190 h30", "Forget saved positions")
    b.OnEvent("Click", (*) => ForgetPositions())
    Sub(pg, CW, cSub, "Each app's size and position is remembered per program and window type,`nthen reapplied when you next open a window of that app.`n`nDialogs, popups and tool windows are excluded on purpose - every Chrome`npopup shares a window class with the main Chrome window, so restoring by`nclass alone would fling popups to the main window's geometry.", "xm y+24")
    Pages["Windows"] := pg

    ; ---- Taskbar
    pg := CreatePage("Taskbar")
    Head(pg, CW, FG, "Taskbar settings")
    Sub(pg, CW, cSub, "Requires ExplorerPatcher. Win10 style enables responsive small icons.", "xm y+10")
    
    Lbl(pg, FG, "Taskbar Style", "xm y+16")
    C["epStyle"] := pg.AddDropDownList("x170 yp-3 w100 Choose " (EP_Style=="Win10" ? 1 : 2), ["Win10", "Win11"])
    Sub(pg, 220, cSub, "Win10 supports small icons", "x+16 yp+3")
    
    Lbl(pg, FG, "Icon Size", "xm y+16")
    C["epIconSize"] := pg.AddDropDownList("x170 yp-3 w100 Choose " (EP_IconSize=="Small" ? 1 : 2), ["Small", "Large"])
    
    b2 := pg.AddButton("xm y+24 w150 h30", "Restart Explorer")
    b2.OnEvent("Click", (*) => RestartExplorer())
    Sub(pg, CW, cSub, "Explorer must be restarted to apply taskbar style changes.", "xm y+16")
    Pages["Taskbar"] := pg

    ; ---- General
    pg := CreatePage("General")
    Head(pg, CW, FG, "General")
    C["auto"] := Box(pg, CW, FG, "Start with Windows", IsAutoStart(), "xm y+16")
    b := pg.AddButton("xm y+24 w150 h30", "Open log")
    b.OnEvent("Click", (*) => OpenLog())
    b2 := pg.AddButton("x+12 yp w150 h30", "Open folder")
    b2.OnEvent("Click", (*) => Run(A_ScriptDir))
    b3 := pg.AddButton("xm y+12 w150 h30", "Hotkeys")
    b3.OnEvent("Click", (*) => ShowHotkeys())
    b4 := pg.AddButton("x+12 yp w150 h30", "Guide")
    b4.OnEvent("Click", (*) => OpenDoc("GUIDE.md"))
    Sub(pg, CW, cSub, "Everything lives in one folder and writes nothing outside it:`n`n    settings.ini              your settings`n    window-positions.ini      remembered window geometry`n    snap.log                  every drag, and why it did or didn't snap`n`nNo registry keys, no system files, no services, no DLLs.`n`nGUIDE.md covers everything. ANIMATIONS.md lists the Windows settings`nthis program needs in order to look right.", "xm y+24")
    Pages["General"] := pg

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
    SelectPage("Snapping")
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
    c := pg.AddCheckbox(pos " w" w " c" col (checked ? " Checked" : ""), txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return c
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
    global Win, C, SnapEnabled, RestoreEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MS
    global EP_Style, EP_IconSize
    if !Win
        return

    try {
        SnapEnabled    := C["snap"].Value
        GlideEnabled   := C["glide"].Value
        RestoreEnabled := C["mem"].Value

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
        SaveSettings()

    }
}

NumOr(text, fallback) => IsNumber(text) ? Number(text) : fallback

IndexOf(arr, val) {
    for i, v in arr
        if (v = val)
            return i
    return 1
}
RestartExplorer() {
    RunWait('taskkill /f /im explorer.exe', , "Hide")
    Run "explorer.exe"
}

ShowHotkeys() {
    MsgBox(
    "Win+Ctrl+W`tSettings`n"
  . "Win+Ctrl+T`tAlways on top (active window)`n"
  . "Win+Ctrl+S`tMagnetic snapping on / off`n"
  . "Win+Ctrl+M`tPosition memory on / off`n`n"
  . "HOTKEYS.md explains conflicts and how to change these.",
    "Window Tweaks - hotkeys", "Iconi")
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
        try Log(Format("alwaysontop {1} hwnd={2} class={3}", isTop ? "ON" : "OFF", hwnd, WinGetClass(hwnd)))
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
global WinEventCb := CallbackCreate(WinEvent, "F", 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", WinEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

WinEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global SnapEnabled, RestoreEnabled, DragHwnd, DragL, DragT, DragR, DragB, VelX, VelY, PrevX, PrevY
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
    global DragHwnd, VelX, VelY, PrevX, PrevY
    if !DragHwnd {
        SetTimer(SampleVelocity, 0)
        return
    }
    if !GetRects(DragHwnd, &L, &T, &R, &B, &x, &y)
        return
    VelX := VelX * 0.6 + (L - PrevX) * 0.4
    VelY := VelY * 0.6 + (T - PrevY) * 0.4
    PrevX := L, PrevY := T
}

FinishDrag(hwnd) {
    global MIN_DRAG, DragL, DragT, DragR, DragB
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - DragL) < MIN_DRAG && Abs(eT - DragT) < MIN_DRAG
        && Abs(eR - DragR) < MIN_DRAG && Abs(eB - DragB) < MIN_DRAG)
        return
    if (WinGetMinMax(hwnd) != 0) {           ; Windows' own snap maximised it
        Log("skip: window ended maximized")
        return
    }
    Log(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    RememberPosition(hwnd)
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

    Sleep 40
    if !GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
        return
    ; One retry: some apps reposition themselves once more after a drag.
    if (vL != newL || vT != newT) {
        MoveFast(hwnd, vx + (newL - vL), vy + (newT - vT))
        Sleep 40
        GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
    }
    Log(Format("  settled at L={1} T={2}  (throw {3},{4}) (verified L={5} T={6})",
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
    start := A_TickCount
    lastX := -99999, lastY := -99999
    loop {
        t := (A_TickCount - start) / ms
        if (t >= 1)
            break
        e := 1 - (1 - t) ** 5
        nx := Round(fromX + dx * e)
        ny := Round(fromY + dy * e)
        if (nx != lastX || ny != lastY) {            ; skip sub-pixel frames
            MoveFast(hwnd, nx, ny)
            lastX := nx, lastY := ny
        }
        Sleep 4
    }
    DllCall("winmm\timeEndPeriod", "uint", 1)
    MoveFast(hwnd, toX, toY)
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
        ; Every AutoHotkey GUI shares one class, so a single saved entry would
        ; drag every unrelated AHK window to the same spot.
        if (WinGetClass(hwnd) = "AutoHotkeyGUI")
            return false
        if (WinGetExStyle(hwnd) & 0x80)                           ; WS_EX_TOOLWINDOW
            return false
        if !(WinGetStyle(hwnd) & 0x00040000)                      ; WS_THICKFRAME
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
        Log("  remembered " key " -> " x "," y " " w "x" h)
    }
}

; The shell tells us when a window is created, so there is no polling timer.
DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), ShellEvent)

ShellEvent(wParam, lParam, *) {
    static HSHELL_WINDOWCREATED := 1
    if (wParam & 0x7FFF) != HSHELL_WINDOWCREATED
        return
    ; A freshly created window isn't laid out yet; moving it immediately gets
    ; overwritten by the app's own initial placement.
    hwnd := lParam
    SetTimer(() => RestorePosition(hwnd), -250)
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
    x := IniRead(POS_FILE, key, "x", "")
    if (x = "")
        return
    y := IniRead(POS_FILE, key, "y", "")
    w := IniRead(POS_FILE, key, "w", "")
    h := IniRead(POS_FILE, key, "h", "")
    
    rx := Integer(x), ry := Integer(y), rw := Integer(w), rh := Integer(h)
    
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
        Log("restored " key " -> " rx "," ry " " rw "x" rh)
    }
}

OnExit(Bye)
Bye(*) {
    SaveSettings()
    Return 0
}
