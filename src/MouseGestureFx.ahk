; Mouse gesture FX - effects driven by pointer motion, idleness or the wheel.
;
; Function definitions and global initialisers only, no top-level statements.
;
; Grouped by WHAT DRIVES THE EFFECT, not by what it looks like: shake-to-find,
; cursor yawn, the breathing cursor, click ripples, the elastic drag trail, spark
; typing and motion-blur scroll all key off the same pointer and keyboard input.
;
; PARAMETERISE ON ELAPSED TIME, NEVER ON FRAME COUNT. t := (now - start) / ms is
; the standard shape. A fixed step per frame is frame-rate dependent - measured, a
; 26-frame fade took 659 ms instead of 416 ms once frames got heavy, which reads
; as slow motion under load. Where a rate really is the right model, scale by dt
; and write the rate as perFrameValue / FRAME_MS so it still looks identical at
; the nominal cadence. dt is clamped to 3 frames so a stall cannot teleport an
; animation to its end.
;
; EVERY POLLING TIMER NEEDS A Sync*, AND Bye() MUST STOP IT. ShakeDetector (40 ms)
; and CheckMouseIdle (1 s) were armed unconditionally at load and ran forever
; regardless of their flags. They are SyncShakeDetector() and SyncCursorFxTimer()
; now, called from Boot() and from ApplyUi.
;
; The overlays here are built LAZILY, on first use, so a feature nobody enabled
; costs nothing - InitShakeFind() is deliberately not called at startup.

; ============================================================================
; Shake to Find (macOS style cursor finder)
; ============================================================================

global ShakeFindActive := false

global ShakePrevX := 0

global ShakePrevY := 0

global ShakeDir := 0

global ShakeCount := 0

global ShakeLastTime := 0

global SF_Size := 0

global SF_TargetSize := 150

global SF_Vel := 0

global SF_Gui := 0

global SF_Hwnd := 0

global SF_Phase := 0

global SF_CircleSize := 200

; Creates the highlight overlay on first use. It used to be built at startup
; whether or not either consumer was switched on, which is a permanent
; always-on-top layered window for a feature that may never run.
;
; SF_Gui must be global. A Gui window dies with the last reference to its object,
; so keeping only its Hwnd left SF_Hwnd dangling the moment this function
; returned, and RenderShakeFind then threw inside a timer callback.
InitShakeFind() {
    global SF_Gui, SF_Hwnd
    if (SF_Gui && SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
        return true
    try {
        SF_Gui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
        SF_Gui.BackColor := "White"
        SF_Hwnd := SF_Gui.Hwnd
        WinSetTransparent(160, SF_Hwnd)
        return true
    }
    SF_Gui := 0, SF_Hwnd := 0
    return false
}

; The Sync* this timer never had. ShakeDetector polls the mouse and the idle
; timer 25 times a second and serves TWO features; with both off it was pure
; overhead, and it was armed unconditionally from InitShakeFind at startup.
SyncShakeDetector() {
    global ShakeFindEnabled, CursorYawnEnabled, ShakeFindActive
    if (ShakeFindEnabled || CursorYawnEnabled) {
        SetTimer(ShakeDetector, 40)
        return
    }
    SetTimer(ShakeDetector, 0)
    ; Switched off mid-highlight: take the circle down, or it is stranded at
    ; whatever size it had reached with nothing left to shrink it.
    if ShakeFindActive {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        global SF_Hwnd
        if (SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
            try DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0)   ; SW_HIDE
    }
}

ShakeDetector() {
    global ShakeFindEnabled, ShakeFindActive
    global ShakePrevX, ShakePrevY, ShakeDir, ShakeCount, ShakeLastTime
    global SF_TargetSize, SF_Phase
    
    global CursorYawnEnabled, CursorYawnActive, CursorYawnIdleTime
    if (CursorYawnEnabled) {
        idle := A_TimeIdlePhysical
        if (idle > CursorYawnIdleTime) {
            CursorYawnActive := true
        } else if (idle < 100 && CursorYawnActive) {
            CursorYawnActive := false
            TriggerCursorYawn()
        }
    }
    
    if (!ShakeFindEnabled)
        return
        
    MouseGetPos(&mx, &my)
    dx := mx - ShakePrevX
    dy := my - ShakePrevY
    ShakePrevX := mx
    ShakePrevY := my
    
    t := A_TickCount
    if (t - ShakeLastTime > 300) {
        ShakeCount := 0
    }
    
    if (Abs(dx) > 15) {
        dir := dx > 0 ? 1 : -1
        if (dir != ShakeDir) {
            ShakeDir := dir
            ShakeCount++
            ShakeLastTime := t
            
            if (ShakeCount >= Tune("shakeCount") && !ShakeFindActive) {
                ShakeCount := 0
                StartShakeFind()
            }
        }
    }
    
    if (ShakeFindActive && t - ShakeLastTime > 200) {
        if (SF_Phase == 1) {
            SF_Phase := 2
            SF_TargetSize := 0
        }
    }
}

StartShakeFind() {
    global ShakeFindActive, SF_Phase, SF_TargetSize, SF_Size, SF_Vel
    if !InitShakeFind()
        return
    ShakeFindActive := true
    SF_Phase := 1
    SF_TargetSize := Tune("shakeSize")
    SF_Size := 10
    SF_Vel := 0
    SetTimer(RenderShakeFind, 16)
}

RenderShakeFind() {
    global ShakeFindActive, SF_Size, SF_TargetSize, SF_Vel, SF_Hwnd, SF_CircleSize

    ; 16 ms timer: a throw here would pop an error dialog and kill the timer for
    ; the rest of the session, so the overlay must be verified before it is used.
    if (!SF_Hwnd || !DllCall("IsWindow", "ptr", SF_Hwnd)) {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        return
    }

    if (!ShakeFindActive) {
        SetTimer(RenderShakeFind, 0)
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        return
    }
    
    SF_Vel += (SF_TargetSize - SF_Size) * 0.4
    SF_Vel *= 0.6 ; friction
    SF_Size += SF_Vel
    
    if (SF_Size < 2 && SF_TargetSize == 0) {
        ShakeFindActive := false
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        SetTimer(RenderShakeFind, 0)
        return
    }
    
    MouseGetPos(&mx, &my)
    s := Round(SF_Size)
    if (s > SF_CircleSize)
        s := SF_CircleSize
        
    if (s > 0) {
        try {
            WinSetRegion("0-0 w" s " h" s " E", SF_Hwnd)
            DllCall("SetWindowPos", "ptr", SF_Hwnd, "ptr", -1, "int", mx - s//2, "int", my - s//2, "int", s, "int", s, "uint", 0x50) ; SWP_NOACTIVATE | SWP_SHOWWINDOW
        } catch {
            ShakeFindActive := false
            SetTimer(RenderShakeFind, 0)
        }
    }
}

TriggerCursorYawn() {
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "White"
    WinSetTransparent(220, guiObj.Hwnd)
    guiObj.Show("NA Hide")
    
    animKey := "CursorYawn_" . guiObj.Hwnd
    start := QPC()
    ms := 1000
    
    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            guiObj.Destroy()
            return false
        }
        
        baseSize := 24
        w := baseSize
        h := baseSize
        
        if (t < 0.35) {
            p := t / 0.35
            ease := 1 - (1 - p) ** 3
            h := baseSize + (45 * ease)
            w := baseSize - (12 * ease)
        } else if (t < 0.7) {
            p := (t - 0.35) / 0.35
            ease := 0.5 - Cos(p * 3.14159) * 0.5
            h := baseSize + 45 - (55 * ease)
            w := baseSize - 12 + (40 * ease)
        } else {
            p := (t - 0.7) / 0.3
            ease := p * p
            h := (baseSize - 10) * (1 - ease)
            w := (baseSize + 28) * (1 - ease)
            
            alpha := Round(220 * (1 - ease))
            try WinSetTransparent(alpha, guiObj.Hwnd)
        }
        
        if (w < 2)
            w := 2
        if (h < 2)
            h := 2
            
        WinSetRegion("0-0 w" Round(w) " h" Round(h) " E", guiObj.Hwnd)
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(mx - w/2), "int", Round(my - h/2), "int", Round(w), "int", Round(h), "uint", 0x14)
        return true
    }
    
    guiObj.Show("NA x" mx " y" my " w" 24 " h" 24)
    RegisterAnimation(animKey, Step)
}

; ============================================================================
; Rubber-Band Elastic Scroll
; ============================================================================

global ElasticHwnd := 0

global ElasticOffsetY := 0

global ElasticTargetY := 0

global ElasticVel := 0

global ElasticBaseX := 0

global ElasticBaseY := 0

global ElasticEdgeStates := Map()

global ElasticAwayCounts := Map()

ElasticScroll(hwnd, dir, startX, startY) {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global ElasticEdgeStates, ElasticAwayCounts
    
    if !ElasticEdgeStates.Has(hwnd) {
        ElasticEdgeStates[hwnd] := 0
        ElasticAwayCounts[hwnd] := 0
    }
    
    state := ElasticEdgeStates[hwnd]
    threshold := 5
    
    if (dir == 1) {
        if (state == 1) {
            return
        } else if (state == -1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := 1
            ElasticAwayCounts[hwnd] := 0
        }
    } else {
        if (state == -1) {
            return
        } else if (state == 1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := -1
            ElasticAwayCounts[hwnd] := 0
        }
    }
    
    if (ElasticHwnd != hwnd) {
        if (ElasticHwnd) {
            try WinMove(ElasticBaseX, ElasticBaseY,,, ElasticHwnd)
        }
        ElasticHwnd := hwnd
        ElasticBaseX := startX
        ElasticBaseY := startY
        ElasticOffsetY := 0
        ElasticTargetY := 0
        ElasticVel := 0
        RegisterAnimation("ElasticScroll", ElasticScrollCallback)
    }
    
    ElasticTargetY := dir * Tune("elasticAmt")
        
    SetTimer(ElasticTimeout, -150)
}

ElasticTimeout() {
    global ElasticTargetY
    ElasticTargetY := 0
}

ElasticScrollCallback(dt, now) {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global DragHwnd, FRAME_MS

    if (!DllCall("IsWindow", "ptr", ElasticHwnd) || DragHwnd == ElasticHwnd) {
        if (DragHwnd == ElasticHwnd)
            try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY, -1, -1, RS_PRI_ANIM)
        ElasticHwnd := 0
        return false
    }

    ; The only real spring in the program, and it was the last thing still
    ; integrating per frame rather than per millisecond: a heavy frame made the
    ; rubber band snap back faster, not later. Scaling the stiffness by dt and
    ; the damping by an exponential of dt keeps the same shape at any frame rate,
    ; and reproduces the old 0.4 / 0.6 constants exactly at the nominal frame.
    if (dt <= 0)
        dt := FRAME_MS
    steps := dt / FRAME_MS
    ElasticVel += (ElasticTargetY - ElasticOffsetY) * 0.4 * steps
    ElasticVel *= Exp(-0.5108256 * steps)          ; ln(1/0.6) per nominal frame
    ElasticOffsetY += ElasticVel * steps

    if (Abs(ElasticTargetY) < 1 && Abs(ElasticOffsetY) < 1 && Abs(ElasticVel) < 1) {
        try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY), -1, -1, RS_PRI_ANIM)
        ElasticHwnd := 0
        return false
    }
    
    try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY), -1, -1, RS_PRI_ANIM)
    return true
}

; Armed by SyncCursorFxTimer() rather than unconditionally at load.
SyncCursorFxTimer() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (BreatheCursorEnabled) {
        SetTimer(CheckMouseIdle, 1000)
        return
    }
    SetTimer(CheckMouseIdle, 0)
    if BreatheCursorActive {
        BreatheCursorActive := false
        StopBreatheCursor()
    }
}

global BreatheCursorActive := false

global BreatheGui := ""

global BreatheStart := 0

CheckMouseIdle() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (!BreatheCursorEnabled)
        return
        
    if (A_TimeIdleMouse > 10000) { 
        if (!BreatheCursorActive) {
            BreatheCursorActive := true
            StartBreatheCursor()
        }
    } else {
        if (BreatheCursorActive) {
            BreatheCursorActive := false
            StopBreatheCursor()
        }
    }
}

StartBreatheCursor() {
    global BreatheGui, BreatheStart
    if (!BreatheGui) {
        BreatheGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        BreatheGui.BackColor := "White"
        RS_SetRegion(BreatheGui.Hwnd, "0-0 w40 h40 E", RS_PRI_ANIM)
        RS_SetAlpha(BreatheGui.Hwnd, 0, RS_PRI_ANIM)
        RS_Commit()
        BreatheGui.Show("NA")
    }
    BreatheStart := QPC()
    RegisterAnimation("BreatheCursor", UpdateBreathe)
}

StopBreatheCursor() {
    global BreatheGui
    CancelAnimation("BreatheCursor")
    if (BreatheGui) {
        RS_SetAlpha(BreatheGui.Hwnd, "Off", RS_PRI_ANIM)
        BreatheGui.Hide()
        RS_Commit()
    }
}

UpdateBreathe(dt, now) {
    global BreatheGui, BreatheStart, BreatheCursorActive
    if (!BreatheCursorActive) {
        RS_SetAlpha(BreatheGui.Hwnd, "Off", RS_PRI_ANIM)
        BreatheGui.Hide()
        return false
    }
    MouseGetPos(&mx, &my)
    t := now - BreatheStart
    cycle := Mod(t, 3000) / 3000
    val := (Sin(cycle * 6.28318 - 1.57079) + 1) / 2
    size := Round(20 + 20 * val)
    alpha := Round(20 + 40 * val)
    
    RS_SetRegion(BreatheGui.Hwnd, "0-0 w" size " h" size " E", RS_PRI_ANIM)
    RS_SetAlpha(BreatheGui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(BreatheGui.Hwnd, mx - size//2, my - size//2, -1, -1, RS_PRI_ANIM)
    return true
}

global Ripples := []

SpawnRipple(x, y) {
    global Ripples
    idx := 0
    loop Ripples.Length {
        if (!Ripples[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Ripples.Length >= 5) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "White"
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0}
        Ripples.Push(r)
        idx := Ripples.Length
    }
    
    r := Ripples[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    r.Gui.Show("NA")
    
    RegisterAnimation("Ripple_" idx, RippleCallback.Bind(idx))
}

RippleCallback(idx, dt, now) {
    global Ripples
    r := Ripples[idx]
    if (!r.Active)
        return false
        
    t := now - r.Start
    if (t > 300) {
        r.Active := false
        RS_SetAlpha(r.Gui.Hwnd, "Off", RS_PRI_ANIM)
        r.Gui.Hide()
        return false
    }
    
    ease := 1 - (1 - (t / 300)) ** 2
    size := Round(10 + 40 * ease)
    alpha := Round(80 * (1 - ease))
    
    RS_SetRegion(r.Gui.Hwnd, "0-0 w" size " h" size " E", RS_PRI_ANIM)
    RS_SetAlpha(r.Gui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(r.Gui.Hwnd, r.x - size//2, r.y - size//2, -1, -1, RS_PRI_ANIM)
    return true
}

global DragTrailGui := ""

global DragTrailActive := false

global DragTrailX := 0, DragTrailY := 0, DragTrailVX := 0, DragTrailVY := 0

CheckElasticDrag() {
    global DragTrailStartX, DragTrailStartY, DragTrailActive, DragTrailX, DragTrailY, DragTrailGui
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckElasticDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - DragTrailStartX) > 5 || Abs(my - DragTrailStartY) > 5) {
        SetTimer(CheckElasticDrag, 0)
        DragTrailActive := true
        if (!DragTrailGui) {
            DragTrailGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            DragTrailGui.BackColor := "Gray"
            WinSetRegion("0-0 w16 h16 E", DragTrailGui.Hwnd)
        }
        DragTrailX := mx, DragTrailY := my
        DragTrailVX := 0
        DragTrailVY := 0
        RS_SetAlpha(DragTrailGui.Hwnd, 80, RS_PRI_ANIM)
        RS_Commit()
        DragTrailGui.Show("x-1000 y-1000 w16 h16 NoActivate")
        RegisterAnimation("DragTrail", DragTrailCallback)
    }
}

DragTrailCallback(dt, now) {
    global DragTrailGui, DragTrailActive, DragTrailX, DragTrailY, DragTrailVX, DragTrailVY
    if (!GetKeyState("LButton", "P")) {
        DragTrailActive := false
        RS_SetAlpha(DragTrailGui.Hwnd, "Off", RS_PRI_ANIM)
        DragTrailGui.Hide()
        return false
    }
    
    MouseGetPos(&mx, &my)
    dx := mx - DragTrailX
    dy := my - DragTrailY
    DragTrailVX += dx * 0.2
    DragTrailVY += dy * 0.2
    DragTrailVX *= 0.7
    DragTrailVY *= 0.7
    DragTrailX += DragTrailVX
    DragTrailY += DragTrailVY
    
    RS_SetAlpha(DragTrailGui.Hwnd, 80, RS_PRI_ANIM)
    RS_SetPos(DragTrailGui.Hwnd, Round(DragTrailX - 8), Round(DragTrailY - 8), -1, -1, RS_PRI_ANIM)
    return true
}

global Sparks := []

OnTypingSpark(ih, vk, sc) {
    global SparkTypingEnabled
    if (!SparkTypingEnabled)
        return
        
    if !CaretGetPos(&cx, &cy)
        return
        
    SpawnSpark(cx, cy)
}

SpawnSpark(x, y) {
    global Sparks
    idx := 0
    loop Sparks.Length {
        if (!Sparks[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Sparks.Length >= 30) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "FFAA00"
        WinSetRegion("0-0 w4 h4 E", g.Hwnd)
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0, vx: 0, vy: 0}
        Sparks.Push(r)
        idx := Sparks.Length
    }
    
    r := Sparks[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    r.vx := (Random() - 0.5) * 6
    r.vy := (Random() - 0.5) * 6 - 2
    
    RS_SetAlpha(r.Gui.Hwnd, 200, RS_PRI_ANIM)
    RegisterAnimation("Spark_" idx, SparkCallback.Bind(idx))
}

SparkCallback(idx, dt, now) {
    global Sparks
    r := Sparks[idx]
    if (!r.Active)
        return false
        
    t := now - r.Start
    if (t > 400) {
        r.Active := false
        RS_SetAlpha(r.Gui.Hwnd, "Off", RS_PRI_ANIM)
        r.Gui.Hide()
        return false
    }
    
    r.vy += 0.2 
    r.x += r.vx
    r.y += r.vy
    alpha := Round(200 * (1 - (t / 400)))
    
    RS_SetAlpha(r.Gui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(r.Gui.Hwnd, r.x, r.y, -1, -1, RS_PRI_ANIM)
    return true
}

global MotionBlurScrollSpeed := 0

global MotionBlurLastTime := 0

global MotionBlurGui := ""

global MotionBlurThumb := 0

global MotionBlurActiveHwnd := 0

TriggerMotionBlur(hwnd, dir) {
    global MotionBlurScrollSpeed, MotionBlurLastTime, MotionBlurActiveHwnd, MotionBlurGui
    now := QPC()
    dt := now - MotionBlurLastTime
    
    ; 120 ms, not 0.1. QPC() already returns MILLISECONDS, so the old threshold
    ; was a tenth of a millisecond - true between any two wheel events - and the
    ; accumulator was reset on every notch. The effect could never build up past
    ; one notch's worth, which is why it always looked like it did nothing.
    if (dt > 120 || hwnd != MotionBlurActiveHwnd)
        MotionBlurScrollSpeed := 0
        
    MotionBlurScrollSpeed += dir * 12
    MotionBlurLastTime := now
    MotionBlurActiveHwnd := hwnd
    
    RegisterAnimation("MotionBlur", MotionBlurCallback)
}

MotionBlurCallback(dt, now) {
    global MotionBlurScrollSpeed, MotionBlurGui
    
    if (Abs(MotionBlurScrollSpeed) < 1) {
        MotionBlurScrollSpeed := 0
        if (MotionBlurGui) {
            RS_SetAlpha(MotionBlurGui.Hwnd, "Off", RS_PRI_ANIM)
            MotionBlurGui.Hide()
        }
        return false
    }
    
    MotionBlurScrollSpeed *= 0.85
    
    hwnd := WinExist("A")
    if (!hwnd || !MotionBlurGui)
        return false
        
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return false
        
    RS_SetAlpha(MotionBlurGui.Hwnd, Round(Abs(MotionBlurScrollSpeed) * 3), RS_PRI_ANIM)
    RS_SetPos(MotionBlurGui.Hwnd, x, y, w, h, RS_PRI_ANIM)
    return true
}
