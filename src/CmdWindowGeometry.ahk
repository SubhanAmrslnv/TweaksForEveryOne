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

