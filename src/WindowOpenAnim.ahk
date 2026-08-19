; Window lifecycle - classify a window, remember where it was, put it back, and
; animate it in. Owns the shell hook.
;
; Function definitions and global initialisers only, no top-level statements.
; Boot() registers the SHELLHOOK and TaskbarCreated handlers and calls
; RegisterShellHook() as the very last thing it does, because ShellEvent is the
; widest-reaching callback in the program - created, destroyed, activated and
; minimised - so nothing may still be uninitialised when it starts delivering.
;
; NEW WINDOWS ARE DETECTED VIA RegisterShellHookWindow, NOT POLLING - AND THAT
; REGISTRATION DOES NOT SURVIVE AN EXPLORER RESTART. Explorer broadcasts
; TaskbarCreated when the shell comes back; handling it and re-registering is the
; only thing keeping position memory, the open animations, focus pulse, breathing
; seeding, fly-to-mouse minimize and per-window cleanup alive after an Explorer
; crash - or after this program's own "Restart Explorer" button.
;
; POSITION MEMORY IS KEYED ON exe + WINDOW CLASS, and excludes dialogs, owned
; windows, WS_EX_TOOLWINDOW, anything without WS_THICKFRAME, and Picture-in-
; Picture. Every Chrome popup shares a class with the main window.
;
; NOTHING KEYED TO INPUT MAY TOUCH THE DISK. window-positions.ini was written
; with four synchronous IniWrites (~771 us each) at the end of every drag AND
; again from OnSnapLanded. It is buffered in PendingPositions and flushed by a
; 900 ms one-shot. For the same reason RememberPosition does NOT call
; IsMainApplicationWindow, which reaches a WMI query through ClassifyWindowImpl -
; tens of milliseconds of blocking COM on the drag path. Classification belongs
; on the window-created path, where RestorePosition already does it.
;
; NEVER MAKE A FOREIGN WINDOW LAYERED SPECULATIVELY. WinSetTransparent forces
; WS_EX_LAYERED; on a GPU-composited or full-screen window that costs a
; redirection surface and can break exclusive full-screen presentation.
; WillAnimateOpen() is the single eligibility test, applied BEFORE hiding a new
; window rather than after - get that backwards and brand-new windows sit at
; alpha 0, invisible but focused and clickable.
;
; The per-HWND state Maps are pruned in the HSHELL_WINDOWDESTROYED branch of the
; shell hook. Anything keyed on hwnd anywhere in the program has to be pruned
; there too, or it leaks for the session.

global GhostHiddenWindows := Map()

global PulsingWindows := Map()

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

RevealWindow(hwnd) {
    global GhostWindows
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    ; The CustomTrans guard is gone: clearing the "open" layer cannot stomp an
    ; opacity the user asked for in the meantime, because the base is a separate
    ; factor. The ghost guard stays - a window that became a ghost while the open
    ; animation was pending is no longer this code's to reveal.
    if GhostWindows.Has(hwnd)
        return
    try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
    RS_Commit()
}

UnrollWindow(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    ; Reveal first, then clip: the region does the animating here, so the window
    ; must be opaque from the first frame.
    try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)

    animKey := "Unroll_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
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
    
    Anim_Claim(hwnd, "region", animKey, UnrollStep)
}

GhostSlideIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }


    startY := y + Tune("animOpenSlide")
    endY := y
    
    MoveFast(hwnd, x, startY)
    RS_Commit()
    
    animKey := "GhostSlideIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    GhostSlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            MoveFast(hwnd, x, endY)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) * (1 - t) ; ease-out
        curY := Round(startY + (endY - startY) * ease)
        MoveFast(hwnd, x, curY)
        
        try RS_SetAlphaLayer(hwnd, "open", ease, RS_PRI_ANIM)
        return true
    }
    
    Anim_Claim(hwnd, "geom", animKey, GhostSlideStep)
}

PortalScaleIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    animKey := "PortalScaleIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    cX := x + w / 2
    cY := y + h / 2
    
    try RS_SetAlphaLayer(hwnd, "open", 0.0, RS_PRI_ANIM)
    RS_SetPos(hwnd, Round(cX - (w * 0.8) / 2), Round(cY - (h * 0.8) / 2), Round(w * 0.8), Round(h * 0.8), RS_PRI_ANIM)
    RS_Commit()
    
    PortalScaleStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        scale := 0.8 + 0.2 * ease
        
        curW := Round(w * scale)
        curH := Round(h * scale)
        curX := Round(cX - curW / 2)
        curY := Round(cY - curH / 2)
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        
        try RS_SetAlphaLayer(hwnd, "open", (t > 0.4 ? 1.0 : (t / 0.4)), RS_PRI_ANIM)
        return true
    }
    
    Anim_Claim(hwnd, "geom", animKey, PortalScaleStep)
}

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
    ; Never pulse a window that is still being flown somewhere.
    ;
    ; Pulse_<hwnd> and Glide_<hwnd> both write RS_Pos[hwnd] at RS_PRI_ANIM, and
    ; equal priority means last-writer-wins within a flush. AHK enumerates a Map
    ; sorted by key, so "Pulse_" is produced after "Glide_" and won every frame -
    ; and worse, PulseStep captured x/y/w/h at activation, i.e. a MID-GLIDE
    ; position, then restored the window to it on its final frame. Activating a
    ; window mid-snap threw away the snap. Same guard idiom as VerifySnap.
    animKey := "Pulse_" hwnd
    if Anim_Owner(hwnd, "geom")
        return
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

    ; The 12 px cap stays internal: it stops the pulse from throwing a
    ; full-screen window several centimetres, which is a property of the
    ; effect, not a preference.
    grow := Tune("animPulse") / 100
    pw := Min(Round(w * grow), 12)
    ph := Min(Round(h * grow), 12)

    start := QPC()
    ms := Tune("animPulseMs")

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

        ; t**0.7 skews the half-sine so the window jumps out quickly and eases
        ; back slowly. A symmetric pulse spends as long growing as returning,
        ; which reads as a wobble rather than as "this window just took focus".
        e := Sin(3.14159265 * t ** 0.7)
        gx := Round(pw * e)
        gy := Round(ph * e)
        nx := x - gx, ny := y - gy
        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, w + gx * 2, h + gy * 2, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, PulseStep)
}

