; Drag pipeline - from the moment a window starts moving to the moment it lands.
;
; Function definitions and global initialisers only, no top-level statements.
; Boot() calls InstallDragHooks(); DropPlacement.ahk decides where the window
; actually goes once FinishDrag hands off.
;
; The shell raises MOVESIZESTART / MOVESIZEEND around every window drag, so we
; hook those instead of the mouse. MOVESIZEEND also fires AFTER the OS modal move
; loop has finished, which is the only moment repositioning is safe.
;
; The callbacks are deliberately NOT created in "F" (fast) mode. Fast mode runs
; on top of whatever script thread the event interrupted and must be trivial;
; WinEvent queries the window, registers an animation and arms a timer.
; Registering an animation from an arbitrary interruption point is what corrupted
; the scheduler's enumeration.
;
; NOTHING IN THIS PATH MAY BLOCK. SnapWindow used to spin twice for 40 ms in a
; busy-wait that never pumped messages, which froze every timer in the process -
; including the frame loop that had just been armed to run the glide it had
; started. Verification is a one-shot timer instead. Use Sleep, which yields, if
; you ever need to wait.
;
; VELOCITY IS PIXELS PER SECOND, and every consumer is calibrated in that unit.
; SampleVelocityStep was once handed dt and ignored it, smoothing raw per-frame
; displacement instead - so the throw gain, the monitor-throw and tilt
; thresholds, the parallax ramp and the magnetic-group break were all silently
; calibrated to a 15 ms frame, and under load the same hand motion reported up to
; 3x the velocity. The smoothing constant is a time constant for the same reason.
; AltDragMove samples on its own Sleep(10) cadence and publishes the same unit,
; which is what makes an alt-drag and a title-bar drag of equal speed throw the
; same distance.
;
; ParallaxAlpha names BOTH ENDS of its ramp rather than a gain. The old
; "255 - speed * 0.06" put an ordinary 400 px/s drag at 225/255 - a change nobody
; can see - and only reached the floor past 3200 px/s. It was doing exactly what
; it said and was still indistinguishable from switched off.

; =========================================================== Drag detection ===========================================================
; The shell raises MOVESIZESTART / MOVESIZEEND around every window drag, so we
; hook those instead of the mouse. A ~LButton hotkey would make AutoHotkey
; install a low-level mouse hook that wakes on every mouse move - measured at
; ~1.6% of a core just sitting there. MOVESIZEEND also fires after the OS modal
; move loop has finished, which is precisely when repositioning is safe.
global DragHwnd := 0, DragL := 0, DragT := 0, DragR := 0, DragB := 0
global VelX := 0, VelY := 0, PrevX := 0, PrevY := 0
global CurrentDragAlpha := 255
; Not a "Fast" callback. Fast mode runs on top of whatever script thread the
; event interrupted, and this one is not trivial: it queries the window, starts
; an animation and arms a timer. Registering an animation from inside an
; arbitrary interruption point is what corrupted the scheduler's enumeration.
; The event is WINEVENT_OUTOFCONTEXT, so it arrives through our own message
; queue either way and nothing here needs fast-mode semantics.
; Keep the hook handles: without them the hooks can never be unhooked and the
; callbacks can never be freed. Bye() releases all four.
;
; Declared here, INSTALLED by InstallDragHooks() from Boot(). As top-level
; initialisers the two SetWinEventHook calls began delivering MOVESIZESTART and
; menu-popup events while thousands of later declarations had not run - and
; WinEvent queries the window, registers an animation and arms a timer.
global WinEventCb := 0, WinEventHook := 0
global MenuEventCb := 0, MenuEventHook := 0

InstallDragHooks() {
    global WinEventCb, WinEventHook, MenuEventCb, MenuEventHook
    WinEventCb := CallbackCreate(WinEvent, , 7)
    WinEventHook := DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
            "ptr", WinEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

    MenuEventCb := CallbackCreate(MenuEvent, , 7)
    MenuEventHook := DllCall("SetWinEventHook", "uint", 0x0006, "uint", 0x0006, "ptr", 0,
            "ptr", MenuEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")
}

MenuEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global ContextMenuAnimEnabled
    if (!ContextMenuAnimEnabled || !hwnd || idObject != 0 || idChild != 0)
        return
        
    ; Both queries need a catch, not a bare `try`. A failed WinGetClass leaves cls
    ; unset and a failed WinGetPos leaves w/h unset, and the next line reads them -
    ; outside the try, in a SetWinEventHook callback. Menu windows (#32768) are
    ; created and destroyed constantly, so losing the race here is routine and the
    ; result was an error dialog on a random right-click.
    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls != "#32768")
        return

    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    ; Through the pipeline, not WinSetTransparent/WinSetRegion directly.
    ; MenuAnimStep is a scheduler callback, and the scheduler's contract is that
    ; callbacks only QUEUE - a direct Win32 write from inside the produce phase
    ; skips the batching, the diffing and the priority arbitration, and rebuilds
    ; a GDI region for a menu that RS_LastRegion would have skipped.
    RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
    RS_Commit()

    animKey := "MenuAnim_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150

    MenuAnimStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd)) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        curH := Round(h * ease)
        if (curH > 0) {
            RS_SetRegion(hwnd, "0-0 w" w " h" curH, RS_PRI_ANIM)
            RS_SetAlpha(hwnd, 255, RS_PRI_ANIM)
        }
        return true
    }
    RegisterAnimation(animKey, MenuAnimStep)
}

WinEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global SnapEnabled, RestoreEnabled, ParallaxEnabled
    global DragHwnd, DragL, DragT, DragR, DragB, VelX, VelY, PrevX, PrevY
    global CurrentDragAlpha          ; assigned below - without this it is a local and the reset never lands
    if (idObject != 0 || idChild != 0)
        return
    ; ParallaxEnabled belongs here too: the drag-transparency effect is driven
    ; entirely from this hook, so leaving it out made it silently depend on
    ; snapping or position memory also being switched on.
    if (!SnapEnabled && !RestoreEnabled && !ParallaxEnabled)
        return
    if (event = 0x000A) {                    ; MOVESIZESTART
        if (DragHwnd != 0 && DragHwnd != hwnd) {
            CancelAnimation("SampleVelocity")
            global GhostWindows
            if (!GhostWindows.Has(DragHwnd))
                StartFadeBackAlpha(DragHwnd, CurrentDragAlpha)
        }
        DragHwnd := 0
        ; allowMax: see the note on IsSnappable. Windows un-maximizes the window
        ; as the drag begins, so by the time SampleVelocityStep first runs it is a
        ; normal window - but the event that STARTS the pipeline arrives before
        ; that, and gating on the strict form meant dragging a maximized window
        ; got no velocity sampling, no drag transparency and no glide at all.
        if !IsSnappable(hwnd, true)
            return
        if !GetRects(hwnd, &sL, &sT, &sR, &sB, &sx, &sy)
            return
        ; The user has taken the window. Nothing else may drive its position or
        ; its opacity until the drag ends.
        ;
        ; Region is deliberately NOT released, even though the hand-written list
        ; this replaces named Unroll_. Cancelling a region animation mid-flight
        ; strands the window clipped to a partial height, because only its
        ; terminal frame clears the region - and nothing short of the panic key
        ; or exit puts that back. Letting the unroll finish is self-healing and
        ; costs nothing: a drag does not touch the region, so the two do not
        ; fight. That the old list cancelled it was a latent bug, not a rule.
        Anim_Release(hwnd, "geom")
        Anim_Release(hwnd, "alpha")

        DragHwnd := hwnd, DragL := sL, DragT := sT, DragR := sR, DragB := sB
        VelX := 0, VelY := 0, PrevX := sL, PrevY := sT
        CurrentDragAlpha := 255
        RegisterAnimation("SampleVelocity", SampleVelocityStep)
        return
    }

    if (hwnd != DragHwnd)                    ; MOVESIZEEND
        return
    CancelAnimation("SampleVelocity")
    DragHwnd := 0
    ; Capture the start rect into the closure. It used to be read from the
    ; globals 50 ms later, so a second drag beginning inside that window
    ; overwrote them and this drag was measured against the wrong origin.
    sL := DragL, sT := DragT, sR := DragR, sB := DragB
    sAlpha := CurrentDragAlpha
    SetTimer(() => FinishDrag(hwnd, sL, sT, sR, sB, sAlpha), -50)    ; defer: FinishDrag enumerates windows
}

; The drag-transparency ramp, in one place. Both drag paths call it: the gain used
; to be written out longhand at each of them, which is exactly how they drifted
; apart before (see the note in AltDragMove).
;
; It is a ramp between two SPEEDS rather than a gain per px/s, because a gain
; cannot be calibrated by eye. The old form, 255 - speed * 0.06, returned 225/255
; at an ordinary 400 px/s drag - 88% opacity, which nobody can see - and reached
; the floor only past 3200 px/s, so an honest description of the feature was "does
; nothing unless you flick". Naming both ends makes "invisible at a normal drag
; speed" a value that can be read off the settings page instead of a constant
; buried on a 15 ms path.
;
; Returns the fraction as well as the alpha: the caller needs to know whether the
; ramp is engaged at all, which it used to infer from a magic "alpha < 250".
ParallaxAlpha(speed) {
    lo := Tune("parallaxFrom")
    hi := Tune("parallaxFull")
    if (hi <= lo)
        hi := lo + 1
    f := Clamp((speed - lo) / (hi - lo), 0, 1)
    return {alpha: Round(255 - f * (255 - TuneAlpha("parallaxMin"))), fade: f}
}

; SPI_GETDRAGFULLWINDOWS. Defaults to "on" when the query itself fails: assuming
; the dependency is met is the harmless guess, because the only cost of being
; wrong is that the effects do nothing, whereas assuming it is off would flip a
; system-wide setting on the strength of a failed read.
ReadDragFullWindows() {
    on := 1
    try {
        buf := Buffer(4, 0)
        if DllCall("SystemParametersInfoW", "uint", 0x26, "uint", 0, "ptr", buf, "uint", 0)
            on := NumGet(buf, 0, "int")
    }
    return on
}

; DragFullWindows is a hard functional dependency of every drag-driven effect, and
; the failure is completely silent: with it off Windows drags a hollow outline, so
; the window rect does not move until release, SampleVelocityStep measures zero
; speed on every frame, and parallax and the ice glide both do nothing at all.
; That was documented in CLAUDE.md and checked by Install.ps1, neither of which
; helps someone who turned the Windows setting off afterwards.
CheckDragFullWindows() {
    global ParallaxEnabled, GlideEnabled
    if (!ParallaxEnabled && !GlideEnabled)
        return
    if ReadDragFullWindows()
        return

    ; Turn it on rather than only complaining about it. SPIF_UPDATEINIFILE |
    ; SPIF_SENDCHANGE (3) persists the change and broadcasts WM_SETTINGCHANGE, so
    ; this is a real, system-wide edit to the user's machine and not a local
    ; override - hence the log line and the notification. Bye() deliberately does
    ; NOT put it back: the setting is a Windows default, the user is far more
    ; likely to have hit it by accident than to want outline dragging, and
    ; silently reverting it at exit would make the fix look intermittent.
    try DllCall("SystemParametersInfoW", "uint", 0x25, "uint", 1, "ptr", 0, "uint", 3)

    ; Confirm rather than assume. Group policy and some remote-desktop sessions
    ; refuse this, and the old code reported success either way.
    if ReadDragFullWindows() {
        WriteLog("DragFullWindows was off - enabled it so drag transparency and ice glide can work")
        Notify("Enabled 'Show window contents while dragging' (Parallax / Glide)")
        return
    }
    WriteLog("DragFullWindows is off and could not be enabled - drag transparency and ice glide cannot work")
    Notify("Windows is dragging window outlines only.`nTurn on Show window contents while dragging, or the drag effects do nothing.")
}

SampleVelocityStep(dt, now) {
    global DragHwnd, VelX, VelY, PrevX, PrevY, ParallaxEnabled, CurrentDragAlpha, FRAME_MS, DEBUG
    if !DragHwnd {
        return false
    }
    ; A window destroyed mid-drag never delivers MOVESIZEEND, so DragHwnd stays set
    ; and GetRects fails on every frame from then on. Returning true there held the
    ; 15 ms frame loop and timeBeginPeriod(1) open for the rest of the session.
    if !DllCall("IsWindow", "ptr", DragHwnd) {
        DragHwnd := 0
        return false
    }
    if !GetRects(DragHwnd, &L, &T, &R, &B, &x, &y)
        return true
    ; Velocity is pixels per SECOND, not pixels per frame.
    ;
    ; This function is handed dt and used to ignore it: the old EMA smoothed
    ; the raw per-frame displacement, so every constant downstream - the throw
    ; gain, the monitor-throw and tilt thresholds, the parallax opacity ramp,
    ; the group-break test - was silently calibrated to a 15 ms frame. The
    ; scheduler clamps dt to three frames but does not guarantee it, so under
    ; load the same hand motion reported up to 3x the velocity and the same
    ; flick threw the window three times as far. Nothing else about the drag
    ; was frame-rate dependent; this was.
    ;
    ; The smoothing constant is a time constant rather than a per-frame ratio
    ; for the same reason. tau = 30 ms reproduces the old 0.4 blend exactly at
    ; the nominal frame and holds that response when frames get heavy.
    if (dt <= 0)
        dt := FRAME_MS
    k := 1 - Exp(-dt / 30.0)
    VelX := VelX + (((L - PrevX) / dt * 1000) - VelX) * k
    VelY := VelY + (((T - PrevY) / dt * 1000) - VelY) * k
    vX := L - PrevX
    vY := T - PrevY
    PrevX := L, PrevY := T
    
    global MagneticGroupsEnabled, MagGroups
    if (MagneticGroupsEnabled && (vX != 0 || vY != 0) && MagGroups.Has(DragHwnd)) {
        ; vX/vY are still raw per-frame deltas here, so this threshold is
        ; converted rather than re-derived: 25 px per 15 ms frame is ~1650 px/s.
        if (Abs(vX) / dt * 1000 > 1650 || Abs(vY) / dt * 1000 > 1650) {
            UngroupWindow(DragHwnd)
        } else {
            ; Queued, not WinMove'd. This runs inside the produce phase of the
            ; frame loop, where the scheduler's contract says callbacks may only
            ; write through RS_*; a direct WinMove skipped the DeferWindowPos
            ; batching and, at DRAG priority, fought any animation still running
            ; on the towed window instead of overriding it cleanly.
            for other in MagGroups[DragHwnd] {
                if (other != DragHwnd && DllCall("IsWindow", "ptr", other)) {
                    try {
                        WinGetPos(&ox, &oy, &ow, &oh, other)
                        RS_SetPos(other, ox + vX, oy + vY, ow, oh, RS_PRI_DRAG)
                    }
                }
            }
        }
    }
    
    global GhostWindows
    if (ParallaxEnabled && !GhostWindows.Has(DragHwnd)) {
        speed := Sqrt(VelX * VelX + VelY * VelY)
        p := ParallaxAlpha(speed)

        ; dt-based, like the velocity EMA above it. The old 0.7/0.3 blend was the
        ; last frame-rate-dependent term left on this path: a ~45 ms lag at the
        ; nominal frame and three times that once frames get heavy, which on top of
        ; an already-weak ramp meant a short drag ended before the fade had gone
        ; anywhere at all.
        ka := 1 - Exp(-dt / 45.0)
        CurrentDragAlpha := CurrentDragAlpha + (p.alpha - CurrentDragAlpha) * ka

        ; Engaged, not "close enough to solid". The ramp itself says whether it
        ; wants this window dimmed; the old alpha < 250 test threw away the first
        ; five units of every fade and left the layer installed on the way out.
        if (p.fade > 0 || CurrentDragAlpha < 254) {
            ; "It does not fade" is not a diagnosable report on its own: the speed,
            ; the ramp and the composed alpha are all invisible from outside the
            ; process. With the debug log on, this says which of the three is wrong.
            ; Throttled, because this is a 15 ms path - WriteLog buffers in RAM but
            ; is not free.
            static lastLog := 0
            if (DEBUG && (now - lastLog > 250)) {
                lastLog := now
                WriteLog("drag speed=" Round(speed) " px/s fade=" Round(p.fade, 2)
                    . " alpha=" Round(CurrentDragAlpha) "/255")
            }
            RS_SetAlphaLayer(DragHwnd, "drag", CurrentDragAlpha / 255.0, RS_PRI_DRAG)
        } else {
            RS_ClearAlphaLayer(DragHwnd, "drag", RS_PRI_DRAG)
        }
    }
    
    global SmartGridEnabled, GridActive
    if (SmartGridEnabled && GetKeyState("Shift", "P")) {
        if (!GridActive)
            ShowSmartGrid()
        UpdateSmartGrid()
    } else if (GridActive) {
        HideSmartGrid()
    }
    
    return true
}

FinishDrag(hwnd, startL, startT, startR, startB, startA) {
    global MIN_DRAG, ParallaxEnabled
    if !DllCall("IsWindow", "ptr", hwnd)
        return

    global GridActive, GridHoverZone
    if (GridActive) {
        ; HideSmartGrid must run even if ApplyGridZone fails, or the zone overlays
        ; are stranded on screen with nothing left that can take them down.
        if (GridHoverZone > 0)
            try ApplyGridZone(hwnd, GridHoverZone)
        HideSmartGrid()
        global GhostWindows
        if (!GhostWindows.Has(hwnd))
            StartFadeBackAlpha(hwnd, startA)
        return
    }

    global GhostWindows
    if (!GhostWindows.Has(hwnd))
        StartFadeBackAlpha(hwnd, startA)

    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - startL) < MIN_DRAG && Abs(eT - startT) < MIN_DRAG
        && Abs(eR - startR) < MIN_DRAG && Abs(eB - startB) < MIN_DRAG)
        return
    minMax := 0
    try minMax := WinGetMinMax(hwnd)
    catch
        return
    if (minMax != 0) {                       ; Windows' own snap maximised it
        WriteLog("skip: window ended maximized")
        return
    }

    WriteLog(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
}

StartFadeBackAlpha(hwnd, startA) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (startA >= 254) {
        RS_ClearAlphaLayer(hwnd, "drag", RS_PRI_DRAG)
        RS_Commit()
        return
    }
    animKey := "FadeBack_" hwnd
    start := QPC()
    ms := 190
    FadeBackStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            ; Clear, not "solid": the window goes back to whatever opacity the
            ; user chose for it, which a hard 255 used to throw away silently.
            RS_ClearAlphaLayer(hwnd, "drag", RS_PRI_DRAG)
            return false
        }
        ; Ease out: the window should rush back to solid the instant you let go,
        ; then settle. A linear ramp made the release feel sluggish.
        e := 1 - (1 - t) * (1 - t)
        RS_SetAlphaLayer(hwnd, "drag", (startA + (255 - startA) * e) / 255.0, RS_PRI_DRAG)
        return true
    }
    Anim_Claim(hwnd, "alpha", animKey, FadeBackStep)
}

; ============================================================================
; Magnetic Window Groups
; ============================================================================
; This declaration was missing entirely. Every user of MagGroups declares it
; `global` and then calls .Has() on it, so with nothing ever assigning it AHK's
; default #Warn VarUnset popped a modal warning dialog on startup, and the first
; drag would have thrown on an unset variable. Grouping could never have worked.
global MagGroups := Map()

GroupWindows(h1, h2) {
    global MagGroups
    g1 := MagGroups.Has(h1) ? MagGroups[h1] : [h1]
    g2 := MagGroups.Has(h2) ? MagGroups[h2] : [h2]
    
    if (g1 = g2)
        return
        
    newGroup := []
    for h in g1
        newGroup.Push(h)
    for h in g2 {
        found := false
        for eh in newGroup
            if (eh = h)
                found := true
        if !found
            newGroup.Push(h)
    }
    
    for h in newGroup
        MagGroups[h] := newGroup
}

UngroupWindow(h) {
    global MagGroups
    if !MagGroups.Has(h)
        return
    grp := MagGroups[h]
    MagGroups.Delete(h)
    
    newGrp := []
    for eh in grp {
        if (eh != h)
            newGrp.Push(eh)
    }
    
    if (newGrp.Length == 1) {
        MagGroups.Delete(newGrp[1])
    } else {
        for eh in newGrp
            MagGroups[eh] := newGrp
    }
}
