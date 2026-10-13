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

; MOST MODERN WINDOWS ARE CLOAKED WHEN THEY ARE CREATED. Chromium and Electron
; (Edge, Chrome, VS Code, Teams), UWP/WinUI frames and Windows 11 Explorer are
; all DWM-cloaked at HSHELL_WINDOWCREATED and uncloaked after their first frame.
; IsSnappable rejects a cloaked window - correctly, it is not on screen - and
; nothing ever looked again, so the open animation only ever ran for classic
; Win32 windows. A cloaked newcomer is now parked in PendingOpen and animated
; when EVENT_OBJECT_UNCLOAKED says it has actually appeared. Entries older than
; OPEN_PENDING_MS are ignored: a window that stays cloaked that long is on
; another virtual desktop, not opening.
;
; ONE ANIMATION PER WINDOW, EVER. An app that hides and re-shows its window (a
; tray restore, a re-used frame) raises HSHELL_WINDOWCREATED again, and running
; the slide a second time captured its start point from mid-slide and left the
; window offset. OpenAnimated is pruned on destroy like every per-hwnd map.
global GhostHiddenWindows := Map()
global PendingOpen := Map()          ; hwnd -> tick it was created cloaked
global OpenAnimated := Map()         ; hwnd -> true once its open animation began
global UncloakCb := 0, UncloakHook := 0
global OPEN_PENDING_MS := 3000

; Called from Boot(). Out-of-context, not "F" mode: the callback only arms a
; one-shot, but it reads Maps that a timer may be mutating.
InstallOpenAnimHook() {
    global UncloakCb, UncloakHook
    UncloakCb := CallbackCreate(UncloakEvent, , 7)
    UncloakHook := DllCall("SetWinEventHook", "uint", 0x8018, "uint", 0x8018, "ptr", 0
            , "ptr", UncloakCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")   ; EVENT_OBJECT_UNCLOAKED
}

; Called from Bye(). Unhook before freeing the thunk the OS points at.
RemoveOpenAnimHook() {
    global UncloakCb, UncloakHook
    if (UncloakHook)
        try DllCall("UnhookWinEvent", "ptr", UncloakHook)
    if (UncloakCb)
        try CallbackFree(UncloakCb)
    UncloakHook := 0, UncloakCb := 0
}

UncloakEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global PendingOpen, OPEN_PENDING_MS
    if (!hwnd || idObject != 0 || idChild != 0 || !PendingOpen.Has(hwnd))
        return
    born := PendingOpen[hwnd]
    PendingOpen.Delete(hwnd)
    if (A_TickCount - born > OPEN_PENDING_MS)
        return
    ; Not from inside the hook: hiding and registering an animation is timer work.
    SetTimer(OpenAnimAfterUncloak.Bind(hwnd), -1)
}

OpenAnimAfterUncloak(hwnd) {
    global OpenAnim
    if (OpenAnim == "None")
        return
    if OpenAnimHide(hwnd)
        StartOpenAnimation(hwnd, "")
}

; Should a newly created window be remembered until it uncloaks? Only the cheap
; structural tests here - the full eligibility test runs once it is visible.
OpenAnimWantsUncloak(hwnd) {
    if !hwnd || !IsCloaked(hwnd)
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")     ; GW_OWNER
        return false
    return DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") == hwnd
}

; Remember a cloaked newcomer. Swept when it grows, so a window that is created
; cloaked and then neither uncloaked nor destroyed cannot accumulate.
OpenAnimPend(hwnd) {
    global PendingOpen, OPEN_PENDING_MS
    if (PendingOpen.Count > 64) {
        stale := []
        for h, t in PendingOpen
            if (A_TickCount - t > OPEN_PENDING_MS)
                stale.Push(h)
        for h in stale
            PendingOpen.Delete(h)
    }
    PendingOpen[hwnd] := A_TickCount
}

; Take a window to alpha 0 ahead of its open animation. The single place that
; decides a window will be animated, so the de-dupe lives here.
OpenAnimHide(hwnd) {
    global OpenAnimated
    if OpenAnimated.Has(hwnd) {
        OpenAnimLog(hwnd, "skip: already animated once")
        return false
    }
    if !WillAnimateOpen(hwnd, true)
        return false
    try {
        RS_SetAlphaLayer(hwnd, "open", 0.0, RS_PRI_ANIM)
        RS_Commit()
    } catch
        return false
    OpenAnimated[hwnd] := true
    return true
}

; Run the selected style on a window OpenAnimHide already hid. Re-checks
; eligibility: it can have been maximised, closed or restyled since.
StartOpenAnimation(hwnd, restoredRect) {
    global OpenAnim
    if (OpenAnim != "None" && WillAnimateOpen(hwnd, true)) {
        OpenAnimLog(hwnd, "start " OpenAnim)
        if (OpenAnim == "Ghost Slide-In")
            GhostSlideIn(hwnd, restoredRect)
        else if (OpenAnim == "Portal Scale-In")
            PortalScaleIn(hwnd, restoredRect)
        else if (OpenAnim == "Window Unrolling")
            UnrollWindow(hwnd, restoredRect)
        ; Belt and braces: if the animation callback dies before its final
        ; clear, this un-hides the window anyway. A window we made invisible
        ; must never be able to stay that way.
        SetTimer(RevealWindow.Bind(hwnd), -(Tune("animOpenMs") + 1000))
        return
    }
    RevealWindow(hwnd)
}

; Buffered and gated on [memory] debuglog, so it costs nothing when off. The
; open animation used to fail silently, which is why it read as "does nothing".
OpenAnimLog(hwnd, msg) {
    global DEBUG
    if !DEBUG
        return
    cls := "", exe := ""
    try cls := WinGetClass(hwnd)
    try exe := WinGetProcessName(hwnd)
    WriteLog("open-anim " msg " [" exe " / " cls " / " Format("0x{:X}", hwnd) "]")
}

WillAnimateOpen(hwnd, logWhy := false) {
    if !hwnd
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") {   ; GW_OWNER
        if logWhy
            OpenAnimLog(hwnd, "skip: owned window (dialog)")
        return false
    }
    if !IsRestorable(hwnd) {
        if logWhy
            OpenAnimLog(hwnd, "skip: not a resizable main window (cloaked, tool, fixed-size or ours)")
        return false
    }
    try {
        if (WinGetMinMax(hwnd) != 0) {
            if logWhy
                OpenAnimLog(hwnd, "skip: opened minimised or maximised")
            return false
        }
    } catch
        return false
    return true
}

RevealWindow(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    ; Clearing the "open" layer cannot stomp an opacity anyone else asked for:
    ; the user's base and the ghost layer are separate factors. The old ghost
    ; guard returned early here and so left a window that became a ghost during
    ; its open animation stuck with the open layer at 0 as well.
    try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
    ; An unroll that never finished would leave the window clipped.
    if (Anim_Owner(hwnd, "region") == "Unroll_" hwnd) {
        CancelAnimation("Unroll_" hwnd)
        try RS_SetRegion(hwnd, "", RS_PRI_ANIM)
    }
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

    ; Clip FIRST, while the window is still at alpha 0, and reveal on the first
    ; frame. Clearing the layer before the first region was applied used to put
    ; one full-height frame on screen before the blind started rolling - alpha
    ; and region are applied in that order within one flush.
    try RS_SetRegion(hwnd, "0-0 W" w " H1", RS_PRI_ANIM)
    RS_Commit()

    animKey := "Unroll_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    revealed := false
    
    UnrollStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        if !revealed {
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            revealed := true
        }
            
        t := (now - start) / ms
        if (t >= 1) {
            try RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            OpenAnimLog(hwnd, "finish unroll")
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
            
        ; Follow the window's live x. An app that places itself after showing
        ; (Chromium restoring its bounds) moves horizontally under us, and pinning
        ; the x captured at the start dragged it back to where it first appeared.
        ; The slide owns y only.
        try {
            WinGetPos(&liveX, , , , hwnd)
            x := liveX
        }
        t := (now - start) / ms
        if (t >= 1) {
            MoveFast(hwnd, x, endY)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            OpenAnimLog(hwnd, "finish slide")
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

    ; A window with a minimum size (WM_GETMINMAXINFO) refuses to shrink to 80%,
    ; and centring on the size we ASKED for then walked it sideways every frame.
    ; Start from the size it actually accepted.
    minScale := 0.8
    try {
        WinGetPos(, , &aw, &ah, hwnd)
        minScale := Min(1.0, Max(minScale, aw / w, ah / h))
    }
    
    PortalScaleStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            OpenAnimLog(hwnd, "finish portal")
            return false
        }
        
        ; Cubic ease-out. The back-ease this replaced overshot past 1.0, so the
        ; window briefly grew beyond its own final rect and the app re-laid out
        ; at a size it was never going to keep.
        ease := 1 - (1 - t) ** 3
        
        scale := minScale + (1 - minScale) * ease
        
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
