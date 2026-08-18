; Window commands - what a keystroke does to the ACTIVE window.
;
; Function definitions and global initialisers only, no top-level statements.
; Place, tile, cycle, hop monitors, undo, maximize, set opacity, roll up, hide to
; tray, boss key. Every one of them is reached from a hotkey, the tray or the
; settings window by name, never re-implemented at the call site.
;
; EVERY FUNCTION HERE IS A ONE-SHOT PRODUCER: it queues through RS_SetPos and
; returns. The animation scheduler stops its timer as soon as nothing is
; animating, so each of these MUST call RS_Commit() itself or the queued move is
; simply never applied and the window does not budge.
;
; ApplyLayout() IS THE ONLY PLACE THAT KNOWS WHAT MAKES A KEYBOARD MOVE CORRECT.
; Add a layout action by computing a frame rect and handing it over - never by
; queueing RS_SetPos directly. It does four things nothing else does:
;
;   1. Calls RS_Commit(), because these are one-shot producers.
;   2. Converts frame space to WinMove space with GetRects() + WinGetPos(). The
;      two differ by the invisible DWM border, and WIDTHS need the conversion
;      too, not just origins.
;   3. Cancels whatever owns the window's "geom" channel first. A live glide
;      writes RS_SetPos at the same priority every frame and would overwrite the
;      queued move with no error at all.
;   4. Clears the roll-up region, because a rolled-up window is clipped to its
;      OLD width and resizing it without that leaves a torn window.
;
; ToggleMaximize is the deliberate exception. It uses WinMaximize/WinRestore and
; CANNOT gate on IsRestorable(), because that goes through IsSnappable(), which
; rejects maximized windows - the one window it exists to un-maximize.
;
; MorphMaximize runs AFTER the state change, not instead of it. RS_* has no
; concept of a maximize state, and a window that merely covers the work area is
; not maximized to the OS or to the app. So Windows performs the state change and
; only the rect is animated.
;
; Work areas are read live rather than cached: the work area changes when the
; taskbar auto-hides and that raises no WM_DISPLAYCHANGE, so a cached copy would
; be stale exactly when Smart Auto-Hide is on.

; =========================================================== Window layout ===========================================================
; Keyboard positioning. Every function in this section is a ONE-SHOT producer:
; it queues through RS_SetPos and returns. The animation scheduler stops its
; timer as soon as nothing is animating, so each of these MUST call RS_Commit()
; itself or the queued move is simply never applied and the window does not budge.

global LayoutUndo   := Map()      ; hwnd -> {x, y, w, h}, WinGetPos space
global SizeCycleIdx := Map()      ; hwnd -> {idx, l, t, r, b} last applied by CycleWindowSize

global SIZE_CYCLE := [0.50, 0.75, 0.90]

; Un-maximize before laying a window out, and do it BEFORE IsRestorable is
; consulted: that predicate goes through IsSnappable, which rejects maximized
; windows outright, so without this every layout key would be silently dead on
; exactly the windows most likely to need one. Windows' own maximize also wins
; over an explicit rect, so tiling one without restoring it first does nothing.
UnmaximizeFirst(hwnd) {
    try {
        if (WinGetMinMax(hwnd) != 1)        ; 1 = maximized
            return
        WinRestore(hwnd)
        ; Sleep, not a spin: the restore is carried out by the target window's
        ; own thread and everything downstream measures the rect it settles into.
        ; A busy wait would block every timer in this process, frame loop
        ; included - the same mistake that used to freeze SnapWindow.
        Sleep(60)
    }
}

; Move a window so its VISIBLE frame occupies (tx, ty, tw, th). Pass -1 for
; tw/th to keep the current size. Returns false if the window went away.
;
; Three things make this correct, and every one of them has cost debugging time
; somewhere else in this file:
;   - the DWM frame rect and the WinMove rect differ by the invisible resize
;     border, so the target has to be converted back the way SnapWindow does;
;   - a Glide or Bounce still registered on this window writes RS_SetPos at the
;     same priority every frame and would overwrite this one silently;
;   - a rolled-up window is clipped by a region measured against its old width,
;     so resizing it without clearing that region leaves a torn-looking window.
ApplyLayout(hwnd, tx, ty, tw := -1, th := -1) {
    global RolledUpWindows
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return false
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY)
        return false
    try WinGetPos(, , &winW, &winH, hwnd)
    catch
        return false
    if (winW = "" || winH = "")
        return false

    ; Whatever is driving this window, whether or not this function has heard
    ; of it. The hand-written list this replaces named three animations by name;
    ; ten write RS_Pos. Region as well, because the list named RollUp_ - and
    ; this function clears the roll-up region a few lines below.
    Anim_Release(hwnd, "geom")
    Anim_Release(hwnd, "region")

    if RolledUpWindows.Has(hwnd) {
        RolledUpWindows.Delete(hwnd)
        RS_SetRegion(hwnd, "", RS_PRI_USER)
    }

    RememberLayout(hwnd, winX, winY, winW, winH)

    ; Frame space -> WinMove space.
    destX := winX + (tx - fL)
    destY := winY + (ty - fT)
    destW := (tw < 0) ? -1 : tw + (winW - (fR - fL))
    destH := (th < 0) ? -1 : th + (winH - (fB - fT))

    RS_SetPos(hwnd, destX, destY, destW, destH, RS_PRI_USER)
    RS_Commit()                    ; one-shot producer: nothing else will flush
    return true
}

RememberLayout(hwnd, x, y, w, h) {
    global LayoutUndo
    LayoutUndo[hwnd] := {x: x, y: y, w: w, h: h}
}

; One level of undo per window - enough to take back a mis-aimed tile, which is
; the only thing this is for. A stack would need pruning rules of its own.
UndoLayout() {
    global LayoutUndo, SizeCycleIdx
    hwnd := WinExist("A")
    if !hwnd || !LayoutUndo.Has(hwnd) {
        Notify("Nothing to undo")
        return
    }
    r := LayoutUndo[hwnd]
    LayoutUndo.Delete(hwnd)
    if SizeCycleIdx.Has(hwnd)
        SizeCycleIdx.Delete(hwnd)
    if !DllCall("IsWindow", "ptr", hwnd)
        return

    Anim_Release(hwnd, "geom")
    ; Already in WinMove space - this is what WinGetPos reported before the move,
    ; so it must NOT go through the frame conversion a second time.
    RS_SetPos(hwnd, r.x, r.y, r.w, r.h, RS_PRI_USER)
    RS_Commit()
    Notify("Layout undone")
}

CenterWindow() {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return
    fw := fR - fL, fh := fB - fT
    if !WorkAreaAt(fL + fw // 2, fT + fh // 2, &wl, &wt, &wr, &wb)
        return
    ApplyLayout(hwnd, wl + ((wr - wl) - fw) // 2, wt + ((wb - wt) - fh) // 2)
}

; 50% -> 75% -> 90% of the work area, centred, then back to 50%.
CycleWindowSize() {
    global SizeCycleIdx, SIZE_CYCLE
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return

    ; Restart the cycle whenever the window is not where this function last put
    ; it. Without the check, dragging a window between two presses made the next
    ; press jump to a size with no relationship to what was on screen.
    idx := 0
    if SizeCycleIdx.Has(hwnd) {
        st := SizeCycleIdx[hwnd]
        if (Abs(st.l - fL) <= 2 && Abs(st.t - fT) <= 2
         && Abs(st.r - fR) <= 2 && Abs(st.b - fB) <= 2)
            idx := st.idx
    }
    idx := Mod(idx, SIZE_CYCLE.Length) + 1

    if !WorkAreaAt((fL + fR) // 2, (fT + fB) // 2, &wl, &wt, &wr, &wb)
        return
    frac := SIZE_CYCLE[idx]
    tw := Round((wr - wl) * frac), th := Round((wb - wt) * frac)
    tx := wl + ((wr - wl) - tw) // 2, ty := wt + ((wb - wt) - th) // 2

    if !ApplyLayout(hwnd, tx, ty, tw, th)
        return
    SizeCycleIdx[hwnd] := {idx: idx, l: tx, t: ty, r: tx + tw, b: ty + th}
    Notify("Window size: " Round(frac * 100) "%")
}

; The digit is the position of the key on the numeric keypad, which is the whole
; point of the gesture: 7 is the top-left quarter, 2 the bottom half, and so on.
TileWindow(cell) {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return
    if !WorkAreaAt((fL + fR) // 2, (fT + fB) // 2, &wl, &wt, &wr, &wb)
        return

    aw := wr - wl, ah := wb - wt
    hw := aw // 2, hh := ah // 2
    ; The far half takes the remainder, so an odd work-area width leaves no
    ; one-pixel seam between two tiled windows.
    rw := aw - hw, rh := ah - hh

    switch cell {
        case 7: tx := wl,      ty := wt,      tw := hw, th := hh
        case 8: tx := wl,      ty := wt,      tw := aw, th := hh
        case 9: tx := wl + hw, ty := wt,      tw := rw, th := hh
        case 4: tx := wl,      ty := wt,      tw := hw, th := ah
        case 5: tx := wl + rw // 2, ty := wt + rh // 2, tw := hw, th := hh
        case 6: tx := wl + hw, ty := wt,      tw := rw, th := ah
        case 1: tx := wl,      ty := wt + hh, tw := hw, th := rh
        case 2: tx := wl,      ty := wt + hh, tw := aw, th := rh
        case 3: tx := wl + hw, ty := wt + hh, tw := rw, th := rh
        default: return
    }
    ApplyLayout(hwnd, tx, ty, tw, th)
}

; Push the window to the next monitor, keeping its position and size relative to
; the work area - a half-width window stays half-width on a display of a
; different resolution instead of keeping its pixel count.
MoveToNextMonitor() {
    hwnd := WinExist("A")
    if !hwnd
        return
    UnmaximizeFirst(hwnd)
    if !IsRestorable(hwnd)
        return
    g := ScreenMetrics()
    if (g.mons.Length < 2) {
        Notify("Only one monitor")
        return
    }
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)
        return

    fw := fR - fL, fh := fB - fT
    cur := MonitorIndexAt(fL + fw // 2, fT + fh // 2)
    nxt := Mod(cur, g.mons.Length) + 1

    if !WorkAreaOf(cur, &sl, &st, &sr, &sb)
        return
    if !WorkAreaOf(nxt, &dl, &dt, &dr, &db)
        return
    sw := sr - sl, sh := sb - st
    dw := dr - dl, dh := db - dt
    if (sw <= 0 || sh <= 0)
        return

    tw := Round(fw * dw / sw), th := Round(fh * dh / sh)
    tx := dl + Round((fL - sl) * dw / sw)
    ty := dt + Round((fT - st) * dh / sh)

    ; Clamp last, so rounding can never push it off the destination work area.
    if (tw > dw)
        tw := dw
    if (th > dh)
        th := dh
    if (tx + tw > dr)
        tx := dr - tw
    if (ty + th > db)
        ty := db - th
    if (tx < dl)
        tx := dl
    if (ty < dt)
        ty := dt

    if ApplyLayout(hwnd, tx, ty, tw, th)
        Notify("Moved to monitor " nxt)
}

; IsRestorable is deliberately NOT the gate here: it goes through IsSnappable,
; which rejects maximized windows outright, so it can never see the one window
; this is meant to un-maximize. WinMaximize/WinRestore also stay outside the
; render pipeline because RS_* has no concept of a maximize state - it queues
; explicit rects, and the two would fight over the same window.
ToggleMaximize() {
    hwnd := WinExist("A")
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return
        if !(WinGetStyle(hwnd) & 0x10000)          ; WS_MAXIMIZEBOX
            return
        Anim_Release(hwnd, "geom")

        wasMax := (WinGetMinMax(hwnd) = 1)
        fromX := "", fromY := "", fromW := "", fromH := ""
        try WinGetPos(&fromX, &fromY, &fromW, &fromH, hwnd)

        if wasMax
            WinRestore(hwnd)
        else
            WinMaximize(hwnd)

        MorphMaximize(hwnd, fromX, fromY, fromW, fromH)
    }
}

; Grow the window out to its new rect instead of letting it jump.
;
; This is the one roadmap item with no implementation. It has to run AFTER the
; state change rather than instead of it, because WinMaximize/WinRestore own the
; maximize state and RS_* has no concept of one - queueing an explicit rect
; cannot make a window maximized, and a window that merely covers the work area
; is not the same thing to the OS or to the app.
;
; So: let Windows do the state change, read where it landed, put the window back
; where it started for one frame, and glide it to the destination. The window is
; genuinely maximized the whole time; only its rect is animated.
MorphMaximize(hwnd, fromX, fromY, fromW, fromH) {
    global GlideEnabled
    ; Inherits the user's existing preference rather than adding a setting: if
    ; ice glide is off, they have said they do not want windows sliding.
    if (!GlideEnabled || fromX = "" || fromW = "" || fromW < 1 || fromH < 1)
        return
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try WinGetPos(&toX, &toY, &toW, &toH, hwnd)
    catch
        return
    if (toX = "" || toW = "" || toW < 1 || toH < 1)
        return
    ; Nothing worth animating, and this also catches the case where the app
    ; refused the state change.
    if (Abs(toX - fromX) < 4 && Abs(toY - fromY) < 4
     && Abs(toW - fromW) < 4 && Abs(toH - fromH) < 4)
        return

    animKey := "Morph_" hwnd
    start := QPC()
    ms := 190
    lastX := -99999, lastY := -99999, lastW := -1, lastH := -1

    MorphStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, toX, toY, toW, toH, RS_PRI_ANIM)
            return false
        }
        ; Quintic out, the same curve the glide uses, so a window growing to full
        ; screen and a window sliding to an edge decelerate identically.
        e := 1 - (1 - t) ** 5
        nx := Round(fromX + (toX - fromX) * e)
        ny := Round(fromY + (toY - fromY) * e)
        nw := Round(fromW + (toW - fromW) * e)
        nh := Round(fromH + (toH - fromH) * e)
        if (nx != lastX || ny != lastY || nw != lastW || nh != lastH) {
            RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
            lastX := nx, lastY := ny, lastW := nw, lastH := nh
        }
        return true
    }

    ; Seed the first frame from the old rect and commit it now, so the window
    ; does not show one frame at its destination before the animation starts.
    RS_SetPos(hwnd, fromX, fromY, fromW, fromH, RS_PRI_ANIM)
    RS_Commit()
    Anim_Claim(hwnd, "geom", animKey, MorphStep)
}

global CustomTrans := Map()

ChangeTransparency(dir) {
    global CustomTrans, PendingTransMsg
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return

    current := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

    step := Tune("transStep")
    if (dir > 0)
        current += step
    else
        current -= step

    ; The floor is a real one: a window at alpha 0 is invisible, focused and
    ; still clickable, and the only way back is Shift+Alt+X on a window you can
    ; no longer see.
    floor := TuneAlpha("transMin")
    if (current > 255)
        current := 255
    if (current < floor)
        current := floor

    CustomTrans[hwnd] := current

    ; No hand-off to breathing any more. This used to write the chosen alpha into
    ; WinTargetAlpha/WinCurrentAlpha so breathing would not immediately fade the
    ; window back down - one module reaching into another's private state to
    ; hand-compose two opacities. RenderCore multiplies the base by the breathe
    ; factor now, so the two are independent by construction.
    if (current == 255) {
        RS_SetBaseAlpha(hwnd, 255, RS_PRI_USER)
        CustomTrans.Delete(hwnd)
        PendingTransMsg := "Transparency: OFF"
    } else {
        RS_SetBaseAlpha(hwnd, current, RS_PRI_USER)
        PendingTransMsg := "Opacity: " Round((current / 255) * 100) "%"
    }
    ; One-shot producer: nothing else is animating, so nothing else will flush.
    RS_Commit()
    ; One tray tip per gesture, not one per wheel notch - a single scroll used to
    ; queue a dozen notifications into the Action Center.
    SetTimer(FlushTransNotify, -400)
}

FlushTransNotify() {
    global PendingTransMsg
    if (PendingTransMsg != "") {
        Notify(PendingTransMsg)
        PendingTransMsg := ""
    }
}

; Back to fully opaque in one press.
;
; This clears the breathe layer as well as the user's own opacity, and that is
; deliberate: the key means "make this window solid NOW", so leaving it dim
; because it happens to be idle would read as the key having done nothing. The
; window starts breathing again on the next monitor tick, which is the same
; behaviour as before - it used to be achieved by writing 255 into breathing's
; two private maps from here.
ResetTransparency() {
    global CustomTrans, WinCurrentAlpha, WinTargetAlpha
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
    if CustomTrans.Has(hwnd)
        CustomTrans.Delete(hwnd)
    if WinCurrentAlpha.Has(hwnd)
        WinCurrentAlpha[hwnd] := 255
    if WinTargetAlpha.Has(hwnd)
        WinTargetAlpha[hwnd] := 255
    RS_SetBaseAlpha(hwnd, 255, RS_PRI_USER)
    RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_USER)
    RS_Commit()                    ; one-shot producer: nothing else will flush
    Notify("Transparency: OFF")
}

; The panic key. Every state this app can put a window into that is not obvious
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
    global BottomWindows, CustomTrans, PushedBackWindows, CurtainWindows, PrivacyBlurWindows
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
    ; breathe, ghost, drag or depth layer - which is precisely the state a panic
    ; key exists to clear, and the one the user cannot see the cause of.
    RS_ResetAllAlphaState(RS_PRI_USER)
    if PushedBackWindows.Count {
        n += PushedBackWindows.Count
        try RestoreFocusDepth()
    }
    if CurtainWindows.Count {
        n += CurtainWindows.Count
        try RestoreCurtain()
    }
    for hwnd, obj in PrivacyBlurWindows.Clone() {
        try RemovePrivacyBlur(hwnd)
        n += 1
    }
    try RestoreShatters()
    RS_Commit()                     ; one-shot producer: nothing else will flush

    SyncMediaCore()
    Notify(n ? "Restored " n " window(s)" : "Nothing to restore")
}

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

AltDragMove() {
    ; #MaxThreadsPerHotkey 2 lets a second Alt+LButton interrupt this one. Two
    ; loops driving the same window from different origin snapshots fight each
    ; other, so only one may run at a time.
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return

    ; Geometry only. See the MOVESIZESTART hook for why the region animation is
    ; left alone despite the old list naming Unroll_.
    Anim_Release(hwnd, "geom")

    try {
        if WinGetMinMax(hwnd) != 0
            return
    } catch
        return

    if !WinActive(hwnd)
        try WinActivate(hwnd)

    global ParallaxEnabled, GlideEnabled, SnapEnabled
    global VelX, VelY, GLIDE_THROW, GLIDE_MAX
    vX := 0, vY := 0
    ; Alt-drag hands VelX/VelY to SnapWindow, which now expects pixels per
    ; SECOND. This loop samples on a Sleep(10) cadence rather than on the frame
    ; clock, so it has to measure its own elapsed time; using the raw per-tick
    ; delta is what made an alt-drag throw a different distance from a title-bar
    ; drag of the same speed. Smoothed with the same 30 ms time constant, so
    ; the two paths now agree by construction rather than by coincidence.
    dragVX := 0.0, dragVY := 0.0
    lastSample := QPC()

    busy := true
    try {
        Loop {
            if !GetKeyState("LButton", "P") || !GetKeyState("Alt", "P")
                break
            if !DllCall("IsWindow", "ptr", hwnd)
                break
            MouseGetPos(&nX, &nY)
            sampleNow := QPC()
            sampleDt := sampleNow - lastSample
            if (sampleDt < 1)
                sampleDt := 1
            lastSample := sampleNow
            if (nX != mX || nY != mY) {
                vX := nX - mX
                vY := nY - mY
                k := 1 - Exp(-sampleDt / 30.0)
                dragVX += ((vX / sampleDt * 1000) - dragVX) * k
                dragVY += ((vY / sampleDt * 1000) - dragVY) * k

                global GhostWindows
                if (ParallaxEnabled && !GhostWindows.Has(hwnd)) {
                    ; Both drag paths share one ramp function now, so an alt-drag
                    ; and a title-bar drag of the same window at the same speed
                    ; agree by construction. Each used to write the floor and the
                    ; gain out longhand, which is how they drifted before - a
                    ; hard-coded 100 here against 60 there, then 3 against 0.06.
                    vel := Sqrt(dragVX**2 + dragVY**2)
                    RS_SetAlphaLayer(hwnd, "drag", ParallaxAlpha(vel).alpha / 255.0, RS_PRI_DRAG)
                }

                try WinGetPos(&wX, &wY,,, hwnd)
                catch
                    break
                wX += vX
                wY += vY
                mX := nX
                mY := nY
                RS_SetPos(hwnd, wX, wY, -1, -1, RS_PRI_DRAG)
                RS_Commit()
            } else {
                ; Standing still decays the measured speed toward zero rather
                ; than discarding it, so a pause mid-drag does not make the
                ; release read as a flick.
                vX := 0, vY := 0
                k := 1 - Exp(-sampleDt / 30.0)
                dragVX -= dragVX * k
                dragVY -= dragVY * k
                if (ParallaxEnabled && !GhostWindows.Has(hwnd)) {
                    RS_SetAlphaLayer(hwnd, "drag", 1.0, RS_PRI_DRAG)
                    ; AltDragMove is a Sleep(10) loop, not a registered animation,
                    ; so it is a one-shot producer and has to flush its own writes.
                    ; Only the branch above committed, so holding Alt+LButton still
                    ; left this write sitting in RS_Alpha and the window stuck at
                    ; its last committed transparency instead of going back solid.
                    RS_Commit()
                }
            }
            ; Sleep, not PreciseSleep: this yields, so the frame loop keeps
            ; running other animations instead of being starved by a spin.
            Sleep(10)
        }
    }
    busy := false

    if (ParallaxEnabled && !GhostWindows.Has(hwnd)) {
        RS_ClearAlphaLayer(hwnd, "drag", RS_PRI_DRAG)
        RS_Commit()
    }

    ; Hand off to the same release pipeline a title-bar drag uses. SnapWindow
    ; reads VelX/VelY to carry the throw forward and calls Glide itself, so
    ; there is nothing to schedule separately.
    VelX := dragVX, VelY := dragVY
    if (SnapEnabled) {
        if GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
            SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
    } else if (GlideEnabled && (Abs(dragVX) > 330 || Abs(dragVY) > 330)) {
        ; Snap off, glide on: throw it by hand, then keep it on screen. Same
        ; px/s unit and the same 0.18 gain as SnapWindow, so this fallback and
        ; the snap path cannot disagree about how far a flick carries.
        try {
            WinGetPos(&gx, &gy, &gw, &gh, hwnd)
            tx := gx + Clamp(Round(dragVX * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
            ty := gy + Clamp(Round(dragVY * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
            gR := tx + gw, gB := ty + gh
            KeepOnScreen(hwnd, &tx, &ty, &gR, &gB, dragVX, dragVY)
            Glide(hwnd, gx, gy, tx, ty)
        }
    }
    RememberPosition(hwnd)
}

AltDragResize() {
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &hwnd)
    if !hwnd || !IsRestorable(hwnd)
        return

    try {
        WinGetPos(&wX, &wY, &wW, &wH, hwnd)
        if WinGetMinMax(hwnd) != 0
            return
    } catch
        return


    if !WinActive(hwnd)
        try WinActivate(hwnd)
        
    leftDist := mX - wX
    rightDist := (wX + wW) - mX
    topDist := mY - wY
    bottomDist := (wY + wH) - mY
    
    resizeMask := 0
    if (leftDist < wW / 3)
        resizeMask |= 1
    else if (rightDist < wW / 3)
        resizeMask |= 2
        
    if (topDist < wH / 3)
        resizeMask |= 4
    else if (bottomDist < wH / 3)
        resizeMask |= 8
        
    if (resizeMask == 0)
        resizeMask := 10
        
    busy := true
    try {
        Loop {
            if !GetKeyState("RButton", "P") || !GetKeyState("Alt", "P")
                break
            if !DllCall("IsWindow", "ptr", hwnd)
                break
            MouseGetPos(&nX, &nY)
            dX := nX - mX
            dY := nY - mY
            if (dX != 0 || dY != 0) {
                newX := wX, newY := wY, newW := wW, newH := wH
                if (resizeMask & 1) {
                    newX += dX, newW -= dX
                } else if (resizeMask & 2) {
                    newW += dX
                }
                if (resizeMask & 4) {
                    newY += dY, newH -= dY
                } else if (resizeMask & 8) {
                    newH += dY
                }
                if (newW < 100) {
                    if (resizeMask & 1)
                        newX -= (100 - newW)
                    newW := 100
                }
                if (newH < 100) {
                    if (resizeMask & 4)
                        newY -= (100 - newH)
                    newH := 100
                }
                wX := newX, wY := newY, wW := newW, wH := newH
                mX := nX, mY := nY
                RS_SetPos(hwnd, wX, wY, wW, wH, RS_PRI_DRAG)
                RS_Commit()
            }
            Sleep(10)
        }
    }
    busy := false
}

global TrayIcons := Map()

TrayIconClick(wParam, lParam, msg, hwnd) {
    if (lParam == 0x0202) {
        if TrayIcons.Has(wParam)
            RestoreFromTray(wParam)
    }
}

; WM_GETICON, asked politely. A plain SendMessage to a foreign window blocks
; until that window's thread pumps messages - so a hung ("Not Responding") app
; froze this whole process, every timer and every hotkey with it, forever.
; SMTO_ABORTIFHUNG plus a short timeout costs us a default icon at worst.
AskWindowIcon(hwnd) {
    static ICON_SMALL2 := 2, ICON_BIG := 1, GCLP_HICON := -14
    for which in [ICON_SMALL2, ICON_BIG] {
        res := 0
        ok := DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x7F
            , "ptr", which, "ptr", 0, "uint", 2, "uint", 100, "ptr*", &res)
        if (ok && res)
            return res
    }
    ; Class icon needs no cooperation from the target thread at all.
    try {
        if (A_PtrSize == 8)
            return DllCall("GetClassLongPtrW", "ptr", hwnd, "int", GCLP_HICON, "ptr")
        return DllCall("GetClassLongW", "ptr", hwnd, "int", GCLP_HICON, "uint")
    }
    return 0
}

HideToTray(hwnd := 0) {
    global TrayMinimizeEnabled
    if (!TrayMinimizeEnabled)
        return
        
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
        
    title := "Hidden Window"
    try title := WinGetTitle(hwnd)
    if (title == "")
        title := "Hidden Window"

    hIcon := AskWindowIcon(hwnd)
    if !hIcon
        hIcon := DllCall("LoadIcon", "ptr", 0, "ptr", 32512, "ptr")


    cbSize := A_PtrSize == 8 ? 976 : 956
    nid := Buffer(cbSize, 0)
    NumPut("uint", cbSize, nid, 0)
    NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
    NumPut("uint", hwnd, nid, A_PtrSize == 8 ? 16 : 8)
    NumPut("uint", 0x7, nid, A_PtrSize == 8 ? 20 : 12)
    NumPut("uint", 0x1000, nid, A_PtrSize == 8 ? 24 : 16)
    NumPut("ptr", hIcon, nid, A_PtrSize == 8 ? 32 : 20)
    StrPut(SubStr(title, 1, 63), nid.Ptr + (A_PtrSize == 8 ? 40 : 24), "UTF-16")
    
    DllCall("shell32\Shell_NotifyIconW", "uint", 0, "ptr", nid)
    
    TrayIcons[hwnd] := true
    try WinHide(hwnd)
}

RestoreFromTray(hwnd) {
    if TrayIcons.Has(hwnd) {
        cbSize := A_PtrSize == 8 ? 976 : 956
        nid := Buffer(cbSize, 0)
        NumPut("uint", cbSize, nid, 0)
        NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
        NumPut("uint", hwnd, nid, A_PtrSize == 8 ? 16 : 8)
        
        DllCall("shell32\Shell_NotifyIconW", "uint", 2, "ptr", nid)
        TrayIcons.Delete(hwnd)
        
        try WinShow(hwnd)
        try WinActivate(hwnd)
    }
}

global BossKeyActive := false

global BossKeyWindows := []

global BossKeyMuteState := false

ToggleBossKey() {
    global BossKeyActive, BossKeyWindows, BossKeyMuteState, BossKeyEnabled
    ; Re-entry here is the most damaging of any toggle in the file: a second
    ; press during the WinGetList/WinHide loop would start a fresh BossKeyWindows
    ; array and the first pass's hidden windows would have no record left at all.
    static busy := false
    if busy
        return
    ; Only the HIDE direction is gated. Gating both meant that turning the feature
    ; off while it was active left every window on the desktop hidden with no way
    ; to get them back short of quitting - the one path that must always work is
    ; the one that undoes what we already did.
    if (!BossKeyEnabled && !BossKeyActive)
        return
    busy := true
    try {

    ; The privacy-blur overlays are owned by THIS process, so the ownPid filter
    ; below deliberately skips them - and WinHide on an owner does not hide owned
    ; windows either. They have to be hidden explicitly, or CheckPrivacyBlur sees
    ; "nothing is active", takes the inactive branch for every private window and
    ; paints an opaque rectangle onto the bare desktop at exactly the position and
    ; size of the window the user just hid.
    global PrivacyBlurWindows

    if (BossKeyActive) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        BossKeyWindows := []
        try SoundSetMute(BossKeyMuteState)
        BossKeyActive := false
    } else {
        for hwnd, obj in PrivacyBlurWindows {
            try DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)   ; SW_HIDE
            obj.active := false
        }
        try BossKeyMuteState := SoundGetMute()
        catch
            BossKeyMuteState := false
            
        try SoundSetMute(true)
        
        hwnds := WinGetList()
        BossKeyWindows := []
        ownPid := DllCall("GetCurrentProcessId", "uint")

        for hwnd in hwnds {
            cls := ""
            try cls := WinGetClass(hwnd)
            ; Shell_SecondaryTrayWnd is the taskbar on every non-primary monitor.
            ; Hiding it left those taskbars gone for good if this process died
            ; while Boss Key was active.
            if (cls == "Progman" || cls == "WorkerW"
                || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
                continue

            ; Our own overlays (active border, monitor dimmers, the OSDs, the
            ; focus vignette) are visible top-level windows too. Hiding them and
            ; showing them back later resurrects overlays whose feature may have
            ; been switched off in between.
            pid := 0
            try pid := WinGetPID(hwnd)
            if (pid == ownPid)
                continue

            BossKeyWindows.Push(hwnd)
            try WinHide(hwnd)
        }

        BossKeyActive := true
    }
    }
    busy := false
}

global PendingTransMsg := ""
