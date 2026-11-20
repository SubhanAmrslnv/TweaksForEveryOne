global RolledUpWindows := Map()
global RollDownPending := Map()     ; hwnd -> true while the returning window may still be clipped

; Explicit resizes replace both sorts of roll animation. Keep the cleanup
; tied to state as well as ownership so a retired callback cannot strand a clip.
ReleaseWindowRollClip(hwnd) {
    global RolledUpWindows, RollDownPending
    wasClipped := RolledUpWindows.Has(hwnd) || RollDownPending.Has(hwnd)
    openUnroll := ReleaseOpenUnrollClip(hwnd, RS_PRI_USER)
    if openUnroll
        RS_ClearAlphaLayer(hwnd, "open", RS_PRI_USER)
    Anim_Release(hwnd, "region")
    if RolledUpWindows.Has(hwnd)
        RolledUpWindows.Delete(hwnd)
    if RollDownPending.Has(hwnd)
        RollDownPending.Delete(hwnd)
    if (wasClipped && !openUnroll)
        RS_SetRegion(hwnd, "", RS_PRI_USER)
}

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
    global RolledUpWindows, RollDownPending
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return
    isRolled := RolledUpWindows.Has(hwnd)
    if (!isRolled && !IsRestorable(hwnd))
        return
        
    animKey := "RollUp_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animRollMs")   ; duration in ms, not a frame count

    ; Measure once, guarded. The window can close between IsRestorable and here,
    ; and an uncaught WinGetPos in a hotkey thread is an error dialog.
    try
        WinGetPos(&x, &y, &w, &h, hwnd)
    catch {
        if (isRolled) {
            ReleaseWindowRollClip(hwnd)
            RS_Commit()
        }
        return
    }
    caption := CaptionHeight(hwnd)
    if ReleaseOpenUnrollClip(hwnd, RS_PRI_USER) {
        RS_ClearAlphaLayer(hwnd, "open", RS_PRI_USER)
        RS_Commit()
    }

    if (isRolled) {
        origH := RolledUpWindows[hwnd]
        RollDownPending[hwnd] := true
        RolledUpWindows.Delete(hwnd)
        clearQueued := false

        RollDownStep(dt, now) {
            if (!RollDownPending.Has(hwnd) || !DllCall("IsWindow", "ptr", hwnd))
                return false
            if clearQueued {
                if (RS_LastRegion.Get(hwnd, "") = "")
                    RollDownPending.Delete(hwnd)
                return false
            }
            t := (now - start) / ms
            if (t >= 1) {
                RS_SetRegion(hwnd, "", RS_PRI_ANIM)
                clearQueued := true
                return true
            }
            ease := 1 - (1 - t) * (1 - t)
            curH := caption + Round((origH - caption) * ease)
            RS_SetRegion(hwnd, "0-0 W" w " H" curH, RS_PRI_ANIM)
            return true
        }
        Anim_Claim(hwnd, "region", animKey, RollDownStep)
    } else {
        RolledUpWindows[hwnd] := h
        if RollDownPending.Has(hwnd)
            RollDownPending.Delete(hwnd)

        RollUpStep(dt, now) {
            if (!RolledUpWindows.Has(hwnd) || !DllCall("IsWindow", "ptr", hwnd))
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

