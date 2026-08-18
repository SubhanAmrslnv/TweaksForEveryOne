; Focus emphasis - the three ways this program says "look at THIS window".
;
; Function definitions and global initialisers only, no top-level statements.
; Cinema/focus mode blacks out everything else, the smart active border draws an
; accent outline, and focus depth pushes the others back for depth of field.
;
; A MONITOR IS A SetTimer, NEVER A RegisterAnimation. The active border was once
; registered as an animation whose callback always returned true, so
; ActiveAnimations was never empty, the scheduler never reached its idle
; shutdown, and simply enabling the border pinned the 15 ms frame loop AND
; timeBeginPeriod(1) for the whole session. If it polls rather than interpolates
; it is a timer - and then it must call RS_Commit() itself, because nothing else
; flushes for it.
;
; FOCUS DEPTH IS AN AMBIENT CUE, SO IT WRITES AT RS_PRI_ANIM. It used to write at
; RS_PRI_USER, out-ranking every glide, bounce and pulse on any window the user
; switched away from. Only RestoreFocusDepth stays USER, because that one IS an
; explicit command.
;
; Rates are scaled by dt, not applied per frame. The focus spotlight is a rate,
; so it is written as perFrameValue / FRAME_MS and still looks identical at the
; nominal cadence; dt is clamped to 3 frames so a stall cannot teleport it.
;
; A FEATURE THAT OWNS AN OVERLAY MUST TEAR IT DOWN WHEN ITS FLAG GOES FALSE, AND
; THE FLAG TEST BELONGS INSIDE THAT FUNCTION. Gating the call site instead means
; switching the feature off stops the only code that could ever clean up.

global FocusModeEnabled := false

global FocusGuis := []

global SpotlightTarget := {x: 0, y: 0, w: 0, h: 0}

global SpotlightCurrent := {x: 0, y: 0, w: 0, h: 0}

global FocusBounds := {x: 0, y: 0, w: 0, h: 0}

; Snapshotted when focus mode is entered rather than read per layer per frame:
; FocusAnimatorStep runs three layers at 63 fps, and the shape of the vignette
; must not change halfway through a session anyway.
global FocusFeather := 70, FocusRadius := 40

global FocusTargetHwnd := 0

ToggleFocusMode() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    global FocusFeather, FocusRadius
    ; Decide before flipping the flag. Flipping first and then bailing out left
    ; the flag saying "on" with no overlays, so the next press took the off
    ; branch and focus mode could never be entered again.
    if (!FocusModeEnabled && FocusGuis.Length)
        return
    FocusModeEnabled := !FocusModeEnabled

    if (FocusModeEnabled) {
        ; Three stacked layers whose relative weights make the falloff; the
        ; setting scales all three so the shape is preserved at any strength.
        FocusFeather := Tune("focusFeather")
        FocusRadius  := Tune("focusRadius")
        peak := TuneAlpha("focusAlpha")
        alphas := [Round(peak * 140 / 240), Round(peak * 200 / 240), peak]
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        
        loop 3 {
            g := Gui("-Caption -DPIScale +ToolWindow +E0x20", "FocusModeOverlay" A_Index)
            g.BackColor := "000000"
            g.MarginX := 0, g.MarginY := 0
            g.Show("x" vx " y" vy " w" vw " h" vh " NoActivate")
            RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
            FocusGuis.Push({gui: g, targetAlpha: alphas[A_Index], currentAlpha: 0})
        }
        
        FocusTargetHwnd := WinExist("A")
        placed := false
        if (FocusTargetHwnd && IsRestorable(FocusTargetHwnd)) {
            try {
                if (WinGetMinMax(FocusTargetHwnd) == 0) {
                    WinGetPos(&tx, &ty, &tw, &th, FocusTargetHwnd)
                    SpotlightCurrent := {x: tx, y: ty, w: tw, h: th}
                    SpotlightTarget := {x: tx, y: ty, w: tw, h: th}
                    placed := true
                }
            }
        }
        if (!placed) {
            SpotlightCurrent := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
            SpotlightTarget := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
        }
        
        ZOrderSpotlight()
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
        SetTimer(FocusMonitorStep, 50)
        Notify("Focus Mode ON")
    } else {
        CancelAnimation("FocusAnimator")
        SetTimer(FocusMonitorStep, 0)
        ; 'layer', not 'fg' - case-insensitive identifiers make 'fg' the global
        ; foreground colour FG.
        ; FadeGui destroys the layer itself when it reaches 0, which removes the
        ; old 300 ms fade / 350 ms destroy-timer race.
        ; Explicitly 300 ms rather than the shared Overlay fade. These are three
        ; stacked FULL-SCREEN vignette layers; at the ~110 ms a small overlay
        ; wants, the whole desktop snaps from dark to bright and reads as a
        ; flash. Duration here is a property of what is being faded, not a
        ; preference, so it is not a setting.
        for layer in FocusGuis
            FadeGui(layer.gui, 0, 300, true)
        FocusGuis := []
        Notify("Focus Mode OFF")
    }
}

ZOrderSpotlight() {
    global FocusGuis, FocusTargetHwnd
    if !FocusTargetHwnd || !DllCall("IsWindow", "ptr", FocusTargetHwnd)
        return
        
    isTopmost := 0
    try isTopmost := WinGetExStyle(FocusTargetHwnd) & 0x8
    prevHwnd := FocusTargetHwnd
    for layer in FocusGuis {
        if (isTopmost)
            WinSetExStyle("+0x8", layer.gui.Hwnd)
        else
            WinSetExStyle("-0x8", layer.gui.Hwnd)
        try RS_SetZOrder(layer.gui.Hwnd, prevHwnd, 0x0013, RS_PRI_ANIM)
        prevHwnd := layer.gui.Hwnd
    }
    ; Called from FocusMonitorStep on a focus change, which does not always
    ; register an animation - so commit rather than hoping someone else will.
    RS_Commit()
}

FocusMonitorStep() {
    global FocusModeEnabled, FocusTargetHwnd, SpotlightTarget
    if !FocusModeEnabled
        return
        
    hwnd := WinExist("A")
    if (hwnd != FocusTargetHwnd) {
        FocusTargetHwnd := hwnd
        ZOrderSpotlight()
    }
    
    if (hwnd && IsRestorable(hwnd) && WinGetMinMax(hwnd) == 0) {
        WinGetPos(&tx, &ty, &tw, &th, hwnd)
        newTarget := {x: tx, y: ty, w: tw, h: th}
    } else {
        MouseGetPos(&mx, &my)
        newTarget := {x: mx, y: my, w: 0, h: 0}
    }
    
    if (SpotlightTarget.x != newTarget.x || SpotlightTarget.y != newTarget.y || SpotlightTarget.w != newTarget.w || SpotlightTarget.h != newTarget.h) {
        SpotlightTarget := newTarget
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
    }
}

FocusAnimatorStep(dt:=0, now:=0) {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FRAME_MS
    global FocusFeather, FocusRadius
    if !FocusModeEnabled || !FocusGuis.Length
        return false
    if (dt <= 0)
        dt := FRAME_MS

    spot := SpotlightCurrent
    t    := SpotlightTarget

    ; Frame-rate-independent exponential smoothing.
    ;
    ; A flat 0.15 per frame meant the spotlight caught up in a fixed number of
    ; FRAMES, so it drifted lazily whenever frames were slow and snapped when they
    ; were fast. Compounding the per-frame retention over the real elapsed time
    ; gives the same feel at any frame rate: after dt ms, the remaining distance is
    ; 0.85^(dt/FRAME_MS).
    f := 1 - (0.85 ** (dt / FRAME_MS))
    spot.x += (t.x - spot.x) * f
    spot.y += (t.y - spot.y) * f
    spot.w += (t.w - spot.w) * f
    spot.h += (t.h - spot.h) * f

    finished := true
    if (Abs(spot.x - t.x) < 0.5 && Abs(spot.y - t.y) < 0.5 && Abs(spot.w - t.w) < 0.5 && Abs(spot.h - t.h) < 0.5) {
        spot.x := t.x
        spot.y := t.y
        spot.w := t.w
        spot.h := t.h
    } else {
        finished := false
    }

    hx := Round(spot.x - FocusBounds.x)
    hy := Round(spot.y - FocusBounds.y)
    hw := Round(spot.w)
    hh := Round(spot.h)

    for layer in FocusGuis {
        pad := (A_Index - 1) * FocusFeather

        px := hx - pad
        py := hy - pad
        pw := hw + pad*2
        ph := hh + pad*2

        region := "0-0 W" FocusBounds.w " H" FocusBounds.h

        if (pw > 0 && ph > 0) {
            region .= " " px "-" py " W" pw " H" ph " R" (FocusRadius + pad) "-" (FocusRadius + pad)
        }

        ; WinSetRegion rebuilds a GDI region, and this runs for three full-screen
        ; overlays every frame. RS_LastRegion already skips an identical string,
        ; but only if we do not build a different one for the same pixels - hence
        ; the integer rounding above rather than per-layer float maths.
        try RS_SetRegion(layer.gui.Hwnd, region, RS_PRI_ANIM)

        if (layer.currentAlpha != layer.targetAlpha) {
            finished := false
            ; Per-millisecond, matching the old 10-per-frame at the nominal rate.
            step := (10 / FRAME_MS) * dt
            if (step < 0.5)
                step := 0.5
            if (layer.currentAlpha < layer.targetAlpha)
                layer.currentAlpha := Min(layer.currentAlpha + step, layer.targetAlpha)
            else
                layer.currentAlpha := Max(layer.currentAlpha - step, layer.targetAlpha)

            try RS_SetAlpha(layer.gui.Hwnd, Integer(layer.currentAlpha + 0.5), RS_PRI_ANIM)
        }
    }
    return !finished
}

; ====== Smart Active Border ======

GetAccentColor() {
    color := 0
    blend := 0
    hr := DllCall("dwmapi\DwmGetColorizationColor", "UInt*", &color, "Int*", &blend)
    if (hr == 0)
        return Format("{:06X}", color & 0xFFFFFF)
    return "00D7FF" 
}

SyncActiveBorderTimer() {
    global ActiveBorderEnabled
    ; A 50 ms timer, not a registered animation.
    ;
    ; ActiveBorderMonitorStep is a MONITOR - it polls the active window and
    ; returns true unconditionally - so registering it meant ActiveAnimations was
    ; never empty, the scheduler never hit its "nothing is animating" shutdown,
    ; and enabling the border pinned the 15 ms frame loop AND timeBeginPeriod(1)
    ; on for the rest of the session. That is the same "do not put a countdown in
    ; the scheduler" mistake the OSD auto-hides were fixed for, and 50 ms is the
    ; cadence this feature was always documented as using.
    ;
    ; DrawActiveBorder calls RS_Commit() itself, which is what a one-shot
    ; producer outside the frame loop has to do.
    if (ActiveBorderEnabled)
        SetTimer(ActiveBorderMonitorStep, 50)
    else {
        SetTimer(ActiveBorderMonitorStep, 0)
        DestroyActiveBorder()
    }
}

ActiveBorderMonitorStep() {
    global ActiveBorderEnabled, LastBorderHwnd, LastBorderX, LastBorderY, LastBorderW, LastBorderH
    if (!ActiveBorderEnabled)
        return

    hwnd := WinExist("A")
    if (!hwnd) {
        HideActiveBorder()
        return
    }
    
    ; Guarded, like IsMouseOverTaskbar: this runs 20 times a second on whatever
    ; window happens to be active, and the active window can be destroyed between
    ; WinExist("A") and the next line. An uncaught throw here would pop an error
    ; dialog and kill the timer, taking the feature out for the whole session.
    cls := "", style := 0
    try {
        cls := WinGetClass(hwnd)
        style := WinGetStyle(hwnd)
    } catch {
        HideActiveBorder()
        return
    }

    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "AutoHotkeyGUI") {
        HideActiveBorder()
        return
    }

    if (!(style & 0x10000000) || (style & 0x01000000) || (style & 0x20000000)) { ; Not visible OR Maximized OR Minimized
        HideActiveBorder()
        return
    }


    ; Measure the window, never the render queue.
    ;
    ; This used to read a PENDING RS_Pos entry as if it were a position. Every
    ; move-only producer - Glide, MoveFast, the curtain, the toast bounce -
    ; queues w and h as -1 to mean SWP_NOSIZE, so W and H came back as -1, failed
    ; the "W < 50" sanity test below and hid the border. The result was that the
    ; border blinked out for the whole of every glide, snap, pulse and layout
    ; key: it disappeared exactly when the window was moving, which is when it
    ; was most visible that something was wrong.
    ;
    ; A queued rect is also a request, not a fact - it has not been applied yet,
    ; and a higher-priority write in the same flush can still replace it.
    {
        rect := Buffer(16, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rect, "uint", 16)
        if (hr == 0) {
            X := NumGet(rect, 0, "Int")
            Y := NumGet(rect, 4, "Int")
            R := NumGet(rect, 8, "Int")
            B := NumGet(rect, 12, "Int")
            W := R - X
            H := B - Y
        } else {
            try WinGetPos(&X, &Y, &W, &H, hwnd)
            catch {
                HideActiveBorder()
                return
            }
        }
    }
    
    if (W < 50 || H < 50) {
        HideActiveBorder()
        return
    }
    
    SizeChanged := (W != LastBorderW || H != LastBorderH)
    if (hwnd == LastBorderHwnd && X == LastBorderX && Y == LastBorderY && !SizeChanged)
        return
        
    LastBorderHwnd := hwnd
    LastBorderX := X, LastBorderY := Y, LastBorderW := W, LastBorderH := H
    
    DrawActiveBorder(X, Y, W, H, SizeChanged)
}

DrawActiveBorder(X, Y, W, H, SizeChanged:=true) {
    global ActiveBorderGui, ActiveBorderShown

    if (!ActiveBorderGui) {
        ActiveBorderGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
        ActiveBorderGui.BackColor := (BorderColor = "auto") ? GetAccentColor() : BorderColor
        ; Created hidden on purpose, so the region and position are in place
        ; before it is ever shown - otherwise it flashes as a 1px dot at 0,0.
        ActiveBorderGui.Show("NoActivate Hide x0 y0 w1 h1")
        ActiveBorderShown := false
        SizeChanged := true
    }

    t := Tune("borderThick")

    try {
        if SizeChanged {
            rect1 := "0-0 w" W " h" t
            rect2 := "0-" (H-t) " w" W " h" t
            rect3 := "0-" t " w" t " h" (H-2*t)
            rect4 := (W-t) "-" t " w" t " h" (H-2*t)
            RS_SetRegion(ActiveBorderGui.Hwnd, rect1 "  " rect2 "  " rect3 "  " rect4, RS_PRI_ANIM)
        }

        RS_SetPos(ActiveBorderGui.Hwnd, X, Y, W, H, RS_PRI_ANIM)
        RS_SetAlpha(ActiveBorderGui.Hwnd, TuneAlpha("borderAlpha"), RS_PRI_ANIM)
        RS_Commit()

        ; And then actually show it. Nothing did: the window was created with
        ; "Hide" and only ever received SetWindowPos (SWP_NOACTIVATE, no
        ; SWP_SHOWWINDOW) and WinSetTransparent, neither of which shows a hidden
        ; window - so the border was never visible at all.
        if !ActiveBorderShown {
            ActiveBorderGui.Show("NoActivate")
            ActiveBorderShown := true
        }
    }
}

; Transient hide, for when focus moves to a window that gets no border. Hides
; rather than destroys: this fires on every focus change, and destroying meant a
; fresh Gui (plus a permanent set of RenderCore map entries for the dead handle)
; every single time.
HideActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    if (ActiveBorderGui && ActiveBorderShown) {
        try ActiveBorderGui.Hide()
        ActiveBorderShown := false
    }
}

; Real teardown, for switching the feature off and for exit.
DestroyActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    ActiveBorderShown := false
    if (ActiveBorderGui) {
        hwnd := 0
        try hwnd := ActiveBorderGui.Hwnd
        try ActiveBorderGui.Destroy()
        ActiveBorderGui := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
    }
}

; ApplyUi (when the checkbox is cleared) and Bye() both call this. PushBackWindow
; pins a window at 98% size and alpha 210, and BringForwardWindow was the only
; reversal - reachable only from ApplyFocusDepth, which only runs while the
; feature is on. So turning Focus Depth off, or exiting, left every window the
; user had ever switched away from permanently shrunk and translucent.
RestoreFocusDepth() {
    global PushedBackWindows
    for hwnd, orig in PushedBackWindows.Clone() {
        try CancelAnimation("FocusDepth_" hwnd)
        if (DllCall("IsWindow", "ptr", hwnd)) {
            ; Same staleness rule as BringForwardWindow: only hand the geometry
            ; back if the window is still where we parked it. Anything else has
            ; moved it since, and its position is now more correct than ours.
            if FocusDepthAtPushedRect(hwnd, orig)
                try RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_USER)
            try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_USER)
        }
    }
    PushedBackWindows := Map()
}

; Is this window still sitting at the rect we pushed it back to?
;
; PushBackWindow captures the pre-shrink rect and BringForwardWindow restores to
; it. If a snap, a glide, a layout key or the app itself moved or resized the
; window while it was pushed back, restoring that captured rect teleports it to
; a position the user has not seen for minutes. Comparing against the rect we
; actually left it at is what tells the two cases apart.
FocusDepthAtPushedRect(hwnd, orig) {
    try WinGetPos(&cx, &cy, &cw, &ch, hwnd)
    catch
        return false
    if (cx = "" || cw = "")
        return false
    return (Abs(cx - orig.px) <= 2 && Abs(cy - orig.py) <= 2
         && Abs(cw - orig.pw) <= 2 && Abs(ch - orig.ph) <= 2)
}

ApplyFocusDepth(newActive) {
    global LastActiveHwnd, PushedBackWindows
    if (LastActiveHwnd && LastActiveHwnd != newActive && DllCall("IsWindow", "ptr", LastActiveHwnd)) {
        PushBackWindow(LastActiveHwnd)
    }
    if (newActive && DllCall("IsWindow", "ptr", newActive)) {
        BringForwardWindow(newActive)
    }
    LastActiveHwnd := newActive
}

; RS_PRI_ANIM, not RS_PRI_USER, throughout this pair.
;
; Focus Depth fires on every activation, so at USER priority it out-ranked the
; glide, the bounce and the pulse on whatever window you had just switched away
; from - the depth animation won every arbitration and the other effect silently
; produced nothing. It is an ambient depth cue, not a user command; ANIM is the
; band it belongs in, and RestoreFocusDepth keeps USER because that IS explicit.
PushBackWindow(hwnd) {
    global PushedBackWindows
    ; Never fight a motion that is already running. A glide, bounce or layout
    ; move owns this window's geometry, and activating another window mid-slide
    ; used to resize it out from under the animation.
    if Anim_Owner(hwnd, "geom")
        return
    ; A maximized window cannot be scaled down and put back sensibly - the OS
    ; owns its rect - so it gets the alpha cue only.
    try {
        if (WinGetMinMax(hwnd) != 0)
            return
    } catch
        return
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    ; The rect we will leave it at, computed once so the settle frame, the
    ; staleness test and the restore all agree on it.
    pw := Round(w * 0.98)
    ph := Round(h * 0.98)
    px := x + Round((w - pw) / 2)
    py := y + Round((h - ph) / 2)
    PushedBackWindows[hwnd] := {x: x, y: y, w: w, h: h, px: px, py: py, pw: pw, ph: ph}

    animKey := "FocusDepth_" hwnd
    start := QPC()
    ms := 150

    PushBackStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, px, py, pw, ph, RS_PRI_ANIM)
            try RS_SetAlphaLayer(hwnd, "depth", 210 / 255.0, RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        scale := 1.0 - (0.02 * ease)
        nw := Round(w * scale)
        nh := Round(h * scale)
        nx := x + Round((w - nw) / 2)
        ny := y + Round((h - nh) / 2)

        RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
        try RS_SetAlphaLayer(hwnd, "depth", (255 - (45 * ease)) / 255.0, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, PushBackStep)
}

BringForwardWindow(hwnd) {
    global PushedBackWindows
    if (!PushedBackWindows.Has(hwnd))
        return

    orig := PushedBackWindows[hwnd]
    PushedBackWindows.Delete(hwnd)

    animKey := "FocusDepth_" hwnd

    ; The window has been moved or resized since we pushed it back, so the rect
    ; we captured is stale and restoring it would teleport the window. Give the
    ; opacity back and leave the geometry to whoever owns it now.
    if !FocusDepthAtPushedRect(hwnd, orig) {
        CancelAnimation(animKey)
        try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_ANIM)
        RS_Commit()                    ; one-shot: no animation will flush this
        return
    }

    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    start := QPC()
    ms := 150

    BringForwardStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_ANIM)
            try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        curW := w + Round((orig.w - w) * ease)
        curH := h + Round((orig.h - h) * ease)
        curX := orig.x + Round((orig.w - curW) / 2)
        curY := orig.y + Round((orig.h - curH) / 2)

        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        try RS_SetAlphaLayer(hwnd, "depth", (210 + 45 * ease) / 255.0, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, BringForwardStep)
}
