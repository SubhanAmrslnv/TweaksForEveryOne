; Process lifecycle - the one ordered startup sequence.
;
; Function definitions only, no top-level statements. Everything this module
; exists for happens inside Boot(), which the entry file calls as its last line,
; after every #Include.
;
; WHY Boot() exists. AHK v2 runs all top-level code in file order as a single
; auto-execute thread, so a "global X := ..." further down the file has not run
; yet when an earlier top-level call fires. A call that arms a timer, builds a
; Gui, talks to COM or registers a hook can therefore read state that does not
; exist yet - or have the state it just wrote reset underneath it when execution
; reaches the declaration. Worse, several of those calls pump the message queue,
; so a shell event queued during startup got dispatched right there: a window
; closing at that moment reached ShellEvent's HSHELL_WINDOWDESTROYED cleanup and
; threw "This global variable has not been assigned a value" on a map declared
; thousands of lines below where the hook had been registered. It reproduced on
; a fresh install (the setup window closes as the app starts) and almost never
; when running from src\ on a quiet desktop.
;
; The program used to work around that with a "deferred init" block pinned to
; the bottom of WindowTweaks.ahk, plus a rule about which four calls were allowed
; above it. Boot() removes the class instead of documenting it: it runs after
; every module's declarations have run, so nothing it calls can be clobbered and
; #Include order is documentation rather than semantics.
;
; scripts\Check-Split.ps1 check 8 enforces the other half of the rule - no
; module may carry a top-level call of its own.

Boot() {
    ; Reload() starts the new process before the old one exits, and the tray
    ; Restart item goes through Reload(). A second Boot() would stack every
    ; OnMessage handler and register OnExit(Bye) twice, so Bye would run twice.
    static done := false
    if done
        return
    done := true

    ; Settings first: every Sync* below branches on a flag this loads, and
    ; SyncTray/BuildTray read the values to set their tick marks.
    LoadSettings()
    RotateLog()
    SyncTray()
    BuildTray()
    WriteLog("=== Window Tweaks " VERSION " started ===")

    ; Tray icons injected by Minimize-to-Tray talk back through this one.
    OnMessage(0x1000, TrayIconClick)

    ; MOVESIZESTART/END and the menu-popup event. Kept out of a top-level
    ; initialiser so the hooks cannot start delivering before the state their
    ; callbacks read has been declared.
    InstallDragHooks()

    ; The shell tells us when a window is created, so there is no polling timer.
    OnMessage(DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), ShellEvent)
    ; Explorer broadcasts TaskbarCreated to every top-level window when the shell
    ; restarts, and the shell-hook registration does NOT survive that. Without
    ; re-registering, an Explorer crash - or this app's own "Restart Explorer"
    ; button - silently killed position memory, the open animations, focus pulse,
    ; breathing seeding, fly-to-mouse minimize and per-window cleanup for the rest
    ; of the session, with no error anywhere.
    OnMessage(DllCall("RegisterWindowMessage", "str", "TaskbarCreated", "uint"), TaskbarCreated)
    OnMessage(0x007E, InvalidateScreenMetrics)     ; WM_DISPLAYCHANGE

    ; Live Window PiP. These run for every message of their kind that reaches any
    ; window this process owns, which is why each handler's first act is to check
    ; the hwnd against PipGuis and return unhandled.
    OnMessage(0x0084, WM_NCHITTEST_PiP)
    OnMessage(0x00A7, PiP_NCMouseEvents) ; WM_NCMBUTTONDOWN
    OnMessage(0x0201, PiP_MouseEvents) ; LBUTTONDOWN
    OnMessage(0x0202, PiP_MouseEvents) ; LBUTTONUP
    OnMessage(0x0204, PiP_MouseEvents) ; RBUTTONDOWN
    OnMessage(0x0205, PiP_MouseEvents) ; RBUTTONUP
    OnMessage(0x0207, PiP_MouseEvents) ; MBUTTONDOWN
    OnMessage(0x0208, PiP_MouseEvents) ; MBUTTONUP
    OnMessage(0x020A, PiP_MouseEvents) ; MOUSEWHEEL
    OnMessage(0x0200, PiP_MouseEvents) ; MOUSEMOVE

    OnExit(Bye)

    ; Feature arming. Each Sync* starts or stops its own polling timer according
    ; to the flag LoadSettings() just read, so a feature nobody enabled costs
    ; nothing. InitShakeFind() is deliberately NOT called: it builds its overlay
    ; lazily on first use.
    SyncShakeDetector()
    SyncCursorFxTimer()
    SyncTaskbarUiTimer()
    SyncBreathingTimers()
    SyncDimmerTimer()
    SyncSmartTaskbar()
    SyncHotCornersTimer()
    SyncCursorWrapTimer()
    SyncActiveBorderTimer()
    SyncTextExpander()
    SyncCustomClockTimer()
    ; Not a Sync: a one-off probe of a Windows setting that the drag effects
    ; cannot work without. If it is off this ENABLES it - a persisted, system-wide
    ; change - then logs and notifies. It is not undone by Bye().
    CheckDragFullWindows()
    UpdateKeyboardHook()
    ; Last of all. ShellEvent is the widest-reaching callback in the program -
    ; window created, destroyed, activated and minimised - so nothing else may
    ; still be uninitialised when the shell starts delivering to it.
    RegisterShellHook()
}

global VERSION := "1.0"

; Registered by Boot(), not here: across a Reload() a top-level OnExit would be
; installed by the new process while the old one still holds the original, and
; Bye() hands every foreign window's state back.
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
    try SetTimer(CheckElasticDrag, 0)
    try SetTimer(CheckMagDrag, 0)
    ; The custom clock repeats every second and was the only timer still
    ; running through teardown. Bye() is also the tray -> Restart path, so it
    ; survived past RS_Shutdown() with a live Gui behind it.
    try SetTimer(UpdateCustomClock, 0)
    try HideCustomClock()

    ; Keystroke sounds play asynchronously straight out of a Buffer we own, so
    ; playback has to be purged before those buffers are dropped - and Bye() is
    ; also the tray -> Restart path, where the next process starts its own.
    try SetTimer(AK_BuildBank, 0)
    try AK_Shutdown()

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
    for hwnd, info in GhostWindows.Clone()
        try UnGhostWindow(hwnd)
    for hwnd, info in BottomWindows.Clone()
        try RestoreFromBottom(hwnd)

    ; Two more maps that record foreign-window state we have to hand back, and
    ; that nothing else can. Both of these used to outlive the process:
    ;   Curtain Drop - every window on the desktop parked below the screen
    ;   Shatter      - the target window alive and invisible at x = -19999
    try RestoreCurtain()
    try RestoreShatters()

    ; Last, and after every restorer above, because those clear their own layers
    ; and a record that has gone neutral has already pruned itself. This is the
    ; sweep for anything they missed. It replaces two hand-written loops over
    ; CustomTrans and WinCurrentAlpha, which between them knew about only two of
    ; the six things that can dim a window.
    try RS_ResetAllAlphaState(RS_PRI_USER)

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
