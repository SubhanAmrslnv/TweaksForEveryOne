; Feature toggles - the tray menu, and the one place a feature flag is flipped.
;
; Function definitions only, no top-level statements.
;
; Every toggle does the same five things, which is why they live together: flip
; the flag, persist it, update the settings checkbox if the window is open,
; notify, and call the feature's Sync*. THAT LAST STEP IS WHAT ACTUALLY STARTS OR
; STOPS THE TIMER - flipping a flag alone leaves the feature running and its
; overlay on screen.
;
; A TRAY LABEL STRING IS ITS OWN LOOKUP KEY. SyncTray() passes the whole
; "Magnetic snap<tab>Shift+Alt+S" to Check/Uncheck, and m.Default matches on it
; too, so the label appears at three sites per item. Written out by hand it had
; drifted at two - every one still read Win+Ctrl+* long after the bindings moved
; to Shift+Alt, and correcting only the m.Add call would have silently killed the
; tick marks. The TRAY_* constants in FeatureFlags.ahk are used at every site.
;
; The always-on-top hotkey lives here rather than in InputBindings.ahk because it
; has no named function to delegate to - it is the whole feature. It self-excludes
; by PID so it cannot pin this program's own GUI.

; =========================================================== Tray ===========================================================
BuildTray() {
    try TraySetIcon(A_ScriptDir "\WindowTweaks.ico")
    A_IconTip := "Window Tweaks " VERSION
    m := A_TrayMenu
    m.Delete()
    global TRAY_SETTINGS, TRAY_SNAP, TRAY_MEMORY, TRAY_BREATHING, TRAY_STEALTH
    m.Add(TRAY_SETTINGS, (*) => ShowWin())
    m.Add()
    m.Add(TRAY_SNAP, (*) => ToggleSnap())
    m.Add(TRAY_MEMORY, (*) => ToggleMemory())
    m.Add(TRAY_BREATHING, (*) => ToggleBreathing())
    m.Add()
    ; The engine runs inside this process but its settings are a separate GUI,
    ; and nothing here used to point at it - triple-Esc was the only way to
    ; discover the feature exists at all.
    m.Add(TRAY_STEALTH, (*) => OpenStealthPanicSettings())
    m.Add()
    m.Add("Restart", (*) => Reload())
    m.Add("Exit", (*) => ExitApp())
    m.Default := TRAY_SETTINGS
    SyncTray()
}

SyncTray() {
    global SnapEnabled, RestoreEnabled, BreathingEnabled
    global TRAY_SNAP, TRAY_MEMORY, TRAY_BREATHING
    try SnapEnabled ? A_TrayMenu.Check(TRAY_SNAP)
                    : A_TrayMenu.Uncheck(TRAY_SNAP)
    try RestoreEnabled ? A_TrayMenu.Check(TRAY_MEMORY)
                       : A_TrayMenu.Uncheck(TRAY_MEMORY)
    try BreathingEnabled ? A_TrayMenu.Check(TRAY_BREATHING)
                         : A_TrayMenu.Uncheck(TRAY_BREATHING)
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

; ----- Shift+Alt feature toggles -------------------------------------------
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
    PlayHotkeySound(isOn ? "toggleon" : "toggleoff")
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

; #HotIf is positional, not scoped, and bleeds across #Include boundaries: a
; module that leaves a context open applies it to the first hotkeys of the next
; included file. This one is context-free, so it opens and closes bare.
#HotIf !GameModeActive
+!o:: {
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
#HotIf
