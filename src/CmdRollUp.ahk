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
        Anim_Claim(hwnd, "region", animKey, RollDownStep)
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
        Anim_Claim(hwnd, "region", animKey, RollUpStep)
    }
}

