; from looking at the screen - rolled up to a title bar, ghosted click-through,
; hidden into the tray - is undone here in one press.
RestoreAllWindows() {
    global RolledUpWindows, RollDownPending, UnrollPending, GhostWindows, TrayIcons
    global BossKeyActive, BossKeyWindows
    global StealthPanicActive, StealthHiddenWindows
    n := 0

    ; Restore Boss Key and Stealth Panic hidden windows first so subsequent
    ; unroll / un-ghost operations can act on visible windows.
    if (BossKeyActive || BossKeyWindows.Length) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd) {
                try WinShow(hwnd)
                n += 1
            }
        }
        BossKeyWindows := []
        BossKeyActive := false
    }
    PanicSetSpeakerMute("BossKey", false)

    if (IsSet(StealthPanicActive) && StealthPanicActive) {
        liveStealth := 0
        for hwnd in StealthHiddenWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                liveStealth += 1
        }
        try RestoreStealthPanic()
        if (StealthHiddenWindows.Length) {
            for hwnd in StealthHiddenWindows {
                if DllCall("IsWindow", "ptr", hwnd)
                    try WinShow(hwnd)
            }
            StealthHiddenWindows := []
        }
        n += liveStealth
    } else if (IsSet(StealthHiddenWindows) && StealthHiddenWindows.Length) {
        for hwnd in StealthHiddenWindows {
            if DllCall("IsWindow", "ptr", hwnd) {
                try WinShow(hwnd)
                n += 1
            }
        }
        StealthHiddenWindows := []
    }

    ; Iterate clones throughout: RestoreFromTray, ToggleRollUp and UnGhostWindow
    ; each delete from the very Map being walked, which shifts the remainder
    ; under the enumerator and silently skips the next entry.
    ; Restore TrayIcons BEFORE RolledUpWindows so hidden rolled-up windows are
    ; shown first.
    for hwnd in TrayIcons.Clone() {
        if RestoreFromTray(hwnd)
            n += 1
    }

    ; A returning window can still be clipped even after its animator stops.
    for pending in [RollDownPending.Clone(), UnrollPending.Clone()] {
        for hwnd in pending {
            ReleaseWindowRollClip(hwnd)
            if DllCall("IsWindow", "ptr", hwnd)
                n += 1
        }
    }

    for hwnd in RolledUpWindows.Clone() {
        if DllCall("IsWindow", "ptr", hwnd) {
            ToggleRollUp(hwnd)
            n += 1
        } else {
            RolledUpWindows.Delete(hwnd)
        }
    }

    for hwnd in GhostWindows.Clone() {
        isLive := DllCall("IsWindow", "ptr", hwnd)
        UnGhostWindow(hwnd)
        if isLive
            n += 1
    }
    if (GhostWindows.Count == 0)
        SetTimer(GhostMonitorStep, 0)

    ; Everything else this program can do to a window that the user cannot undo
    ; by hand. Each of these is reachable only through a hotkey that lives behind
    ; its feature flag, so switching the feature off strands the state with no way
    ; back - which is exactly what a panic key is for. Bye() already reverses all
    ; of them on exit; there was no reason for Shift+Alt+Y not to.
    global CustomTrans, CurtainWindows
    for hwnd, alpha in CustomTrans.Clone() {
        if DllCall("IsWindow", "ptr", hwnd)
            n += 1
        CustomTrans.Delete(hwnd)
    }
    ; Every window ANY layer is still dimming, not just the ones the user set by
    ; hand. Enumerating CustomTrans alone missed a window left dim by a stranded
    ; breathe, ghost or drag layer - which is precisely the state a panic key
    ; exists to clear, and the one the user cannot see the cause of.
    RS_ResetAllAlphaState(RS_PRI_USER)
    if CurtainWindows.Count {
        n += CurtainWindows.Count
        try RestoreCurtain()
    }
    try RestoreShatters()
    RS_Commit()                     ; one-shot producer: nothing else will flush

    SyncMediaCore()
    PlayHotkeySound(n ? "alert" : "command")
    Notify(n ? "Restored " n " window(s)" : "Nothing to restore")
}
