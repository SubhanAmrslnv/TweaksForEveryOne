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
    ; of them on exit; there was no reason for Shift+Alt+Y not to.
    global BottomWindows, CustomTrans, CurtainWindows
    for hwnd, info in BottomWindows.Clone() {
        try RestoreFromBottom(hwnd)
        n += 1
    }
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
    Notify(n ? "Restored " n " window(s)" : "Nothing to restore")
}
