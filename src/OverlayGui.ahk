; Overlay Gui lifecycle - one way to fade, drop and destroy a transient overlay.
;
; Function definitions only, no top-level statements.
;
; Two rules these exist to enforce, both of which have cost real debugging time:
;
; A Gui object must outlive its animation. Pass the Gui OBJECT into the closure,
; not just its Hwnd, and finish with Destroy() - never WinClose, which only posts
; WM_CLOSE and leaves the object alive. Some of these are created many times a
; session, so a leak here grows all session.
;
; Call RS_RemoveHwnd(hwnd) when the overlay dies. Our own WS_EX_TOOLWINDOW /
; NoActivate windows raise no shell destroy notification, so nothing else will
; prune their entries out of the RenderCore alpha and region caches.

GuiDestroy(g) {
    hwnd := 0
    try hwnd := g.Hwnd
    try g.Destroy()
    if hwnd
        RS_RemoveHwnd(hwnd)
}

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
;   ms        duration; 0 (the default) means "whatever Overlay fade is set to",
;             which is how the dimmers, Quick Look and the Start-menu blur all
;             end up sharing one user-visible speed instead of three literals
;   destroy   destroy the Gui when it reaches 0 (and forget its render state)
;   onDone    called once, whichever way the fade ends
FadeGui(guiObj, toAlpha, ms := 0, destroy := false, onDone := "") {
    if (ms <= 0)
        ms := Tune("animFadeMs")
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

NotchAnim(hwnd, startY, destY, fadeIn := true, onDone := "") {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
        
    animKey := "Notch_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animNotchMs")
    
    ; Needs a catch: x is read by NotchStep on every frame, and a bare `try` would
    ; leave it unset. Callers reach this from a hotkey and from one-shot timers.
    try WinGetPos(&x, &cy, &w, &h, hwnd)
    catch
        return

    NotchStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            try RS_SetAlpha(hwnd, fadeIn ? 220 : 0, RS_PRI_USER)
            if onDone
                onDone()
            return false
        }
        
        ease := fadeIn ? (1 - (1 - t) ** 3) : (t ** 3)
        curY := Round(startY + (destY - startY) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        
        alpha := fadeIn ? Round(220 * ease) : Round(220 * (1 - ease))
        try RS_SetAlpha(hwnd, alpha, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, NotchStep)
}
