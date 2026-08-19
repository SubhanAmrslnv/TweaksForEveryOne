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

    ; Geometry AND alpha, exactly as the MOVESIZESTART hook does. See that hook
    ; for why the region animation is left alone despite the old list naming
    ; Unroll_.
    ;
    ; The alpha release is not optional. Releasing a title-bar drag starts a 190 ms
    ; FadeBack_<hwnd> on the "alpha" channel, and grabbing the same window with
    ; Alt+LButton inside that window left the fade running: two owners writing the
    ; "drag" layer at the same RS_PRI_DRAG, which is the one-owner-per-layer rule
    ; in RenderCore.ahk's header broken inside a single layer. The fade won the
    ; frames it produced last and then ended with RS_ClearAlphaLayer, wiping the
    ; alt-drag's own fade mid-drag.
    Anim_Release(hwnd, "geom")
    Anim_Release(hwnd, "alpha")

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

