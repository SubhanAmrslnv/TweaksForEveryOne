; Drop placement - where a released window lands, and how it travels there.
;
; Function definitions and global initialisers only, no top-level statements.
; DragPipeline.ahk hands off here from FinishDrag.
;
; TWO COORDINATE SPACES, AND CONFUSING THEM COSTS ~7 px ON EVERY SNAP. Snapping
; measures with DWMWA_EXTENDED_FRAME_BOUNDS; WinMove works in a space that
; differs by the invisible DWM border. GetRects() in SnapCore.ahk returns both,
; and SnapWindow converts back with destX := winX + (newL - L).
;
; SNAP REACH SCALES WITH RELEASE SPEED. A slow, deliberate move reaches less, so
; a window can be parked near an edge on purpose; a hard flick reaches further. A
; line the window is moving AWAY from is penalised, one it is already flush with
; wins ties, and once one axis grabs, the other is retried with CORNER_BOOST x
; the reach so corners pull harder.
;
; TWO ANIMATIONS MUST NEVER DRIVE THE SAME PROPERTY OF THE SAME WINDOW AT THE
; SAME PRIORITY. RS_* arbitration is per-flush and ties break by Map order, and
; AHK enumerates a Map SORTED BY KEY - so Bounce_<hwnd> was produced before
; Glide_<hwnd> and the glide overwrote every bounce frame. "Bouncy Snapping"
; never put a pixel on screen unless ice glide was off. Anything that should
; happen WHEN A WINDOW LANDS has to be scheduled for after the glide, which is
; what BounceOnLanding and the seam flash do - the flash used to hang in empty
; space at the destination for up to 650 ms before the window arrived.
;
; Glide is elapsed-time driven, never step-counted, and returns its duration in
; ms so the caller can schedule verification for after it lands. A fixed step per
; frame is frame-rate dependent: measured, a 26-frame fade took 659 ms instead of
; 416 ms once frames got heavy.
;
; Frames that would not change a pixel are skipped. SetWindowPos on a real window
; costs ~260 us and forces the target app to re-layout, so Glide, BounceStep and
; PulseStep all compare against the last applied integer rect first.
;
; A Gui object must outlive its animation: ShowSeamFlash creates one on every
; single snap, so pass the OBJECT into the closure and finish with Destroy().

SnapWindow(hwnd, L, T, R, B, winX, winY) {
    global SnapEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MAX, VelX, VelY
    
    global MonitorThrowEnabled
    if (MonitorThrowEnabled && (Abs(VelX) > 1000 || Abs(VelY) > 1000)) {
        if ThrowWindowToNextMonitor(hwnd, L, T, R - L, B - T, VelX, VelY)
            return
    }

    ; Carry the release speed forward, so a flick keeps travelling instead of
    ; stopping dead where you let go.
    tx := 0, ty := 0
    if GlideEnabled {
        ; 0.18 px of travel per px/s of release speed, which is the old
        ; "* 12 per px/frame" expressed in the new unit (12 * 0.015).
        tx := Clamp(Round(VelX * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
        ty := Clamp(Round(VelY * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
    }
    pL := L + tx, pT := T + ty, pR := R + tx, pB := B + ty
    KeepOnScreen(hwnd, &pL, &pT, &pR, &pB, tx, ty)

    if (SnapEnabled) {
        ; Reach scales with how fast the window was released.
        ;
        ; A fixed 30 px meant a slow, deliberate placement got exactly the same
        ; yank as a hard flick, so parking a window a few pixels off an edge on
        ; purpose was impossible without switching the feature off entirely.
        ; Slow now reaches less and fast reaches further, which is also what
        ; "momentum increases attraction" means physically. snapAdapt 0
        ; reproduces the old fixed behaviour exactly.
        spd   := Sqrt(VelX * VelX + VelY * VelY)
        adapt := Tune("snapAdapt")
        reach := SNAP_DISTANCE * (1 + adapt * (Min(spd, 900) / 900 * 2 - 1))
        if (reach < 1)
            reach := 1

        ; Direction of travel per axis, so a line the window is moving away
        ; from stops competing with the one it is heading for.
        dirX := (VelX > 0) ? 1 : ((VelX < 0) ? -1 : 0)
        dirY := (VelY > 0) ? 1 : ((VelY < 0) ? -1 : 0)

        ; Snap is judged from where the throw would land, not where you let go.
        CollectEdges(hwnd, pL, pT, pR, pB, &vLines, &hLines, NEIGHBOUR_PROX)
        if !ComputeSnap(pL, pT, pR, pB, vLines, hLines, Round(reach), &newL, &newT
                      , CORNER_BOOST, dirX, dirY, Tune("snapHyst"))
            newL := pL, newT := pT
    } else {
        newL := pL, newT := pT
    }

    if (newL = L && newT = T) {
        RememberPosition(hwnd)
        global MomentumTiltEnabled
        if (MomentumTiltEnabled && (Abs(VelX) > 200 || Abs(VelY) > 200))
            JelloBounce(hwnd, winX, winY, VelX, VelY)
        return
    }

    ; Frame space -> WinMove space; they differ by the invisible DWM border.
    destX := winX + (newL - L)
    destY := winY + (newT - T)

    ; Everything that should happen WHEN THE WINDOW LANDS is collected into one
    ; handler and handed to Glide, which invokes it from the frame where it puts
    ; the window down. It used to be two parallel SetTimer calls armed for
    ; "glideMs from now", which raced the glide's own last frame by a frame or two
    ; and - worse - still fired if a new drag had cancelled the glide in the
    ; meantime, bouncing a window the user had already grabbed again.
    ;
    ; Both effects were originally applied immediately, which is why neither
    ; worked: the bounce was overwritten by every glide frame (Map keys enumerate
    ; sorted, so "Bounce_" produced before "Glide_"), and the seam flash hung in
    ; empty space at the destination for up to 650 ms before the window arrived.
    ; W/H are hoisted out of the seam-flash guard on purpose: the magnetic-groups
    ; block further down reads them unconditionally, so with seam flash off and
    ; magnetic groups on they were UNSET. SnapWindow runs from FinishDrag's -50 ms
    ; one-shot, so that throw killed the tail of the drag pipeline - no glide, no
    ; VerifySnap, window left wherever the OS dropped it.
    W := R - L
    H := B - T

    global SeamFlashEnabled
    seams := []
    if (SeamFlashEnabled) {
        if (newL != pL) {
            for v in vLines {
                if (Abs(newL - v) < 2) {
                    seams.Push([newL - 1, newT, 3, H])
                    break
                }
                if (Abs(newL + W - v) < 2) {
                    seams.Push([newL + W - 1, newT, 3, H])
                    break
                }
            }
        }
        if (newT != pT) {
            for hLine in hLines {
                if (Abs(newT - hLine) < 2) {
                    seams.Push([newL, newT - 1, W, 3])
                    break
                }
                if (Abs(newT + H - hLine) < 2) {
                    seams.Push([newL, newT + H - 1, W, 3])
                    break
                }
            }
        }
    }
    
    global MagneticGroupsEnabled
    if (MagneticGroupsEnabled && (newL != pL || newT != pT)) {
        if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
            newR := newL + W
            newB := newT + H
            for other in WinGetList() {
                if (other = hwnd || !IsSnappable(other))
                    continue
                if (GetRects(other, &oL, &oT, &oRight, &oB, &ox, &oy)) {
                    touches := false
                    if ((Abs(newL - oRight) < 2 || Abs(newR - oL) < 2) && (newT < oB && newB > oT))
                        touches := true
                    else if ((Abs(newT - oB) < 2 || Abs(newB - oT) < 2) && (newL < oRight && newR > oL))
                        touches := true
                    
                    if (touches) {
                        GroupWindows(hwnd, other)
                    }
                }
            }
        }
    }

    ; Physics: if momentum carried us further than the snap allowed, we crashed
    ; into a wall.
    ; "The snap stopped us short of where the throw was heading" - which is the
    ; same subtraction whichever way we were travelling. This was written as two
    ; branches per axis computing the identical expression; the only thing the
    ; sign test contributed was excluding the case where the snap carried us
    ; FURTHER than the throw, which is not a crash.
    crashX := 0, crashY := 0
    if (Abs(VelX) > 100 && tx != 0 && Abs(newL - L) < Abs(tx))
        crashX := tx - (newL - L)
    if (Abs(VelY) > 100 && ty != 0 && Abs(newT - T) < Abs(ty))
        crashY := ty - (newT - T)

    landed := OnSnapLanded.Bind(hwnd, destX, destY, crashX, crashY, seams)

    glideMs := 0
    if GlideEnabled {
        ; The crash impulse is handed to Glide so the window can overshoot the
        ; edge it is landing against and spring back, rather than easing
        ; asymptotically into it and then being squashed by a separate
        ; animation afterwards.
        glideMs := Glide(hwnd, winX, winY, destX, destY, landed, crashX, crashY)
    } else {
        ; One-shot: no animation is running, so nothing else would ever flush
        ; this. Without the commit, snapping did nothing at all whenever ice
        ; glide was switched off.
        MoveFast(hwnd, destX, destY)
        RS_Commit()
        landed()
    }

    ; Verify asynchronously. This used to be two PreciseSleep(40) spins inline:
    ; PreciseSleep never pumps messages, so the 80 ms froze every timer in the
    ; process - including the frame loop that had just been armed to run the
    ; glide. Worse, the check then read the position before the glide had moved
    ; anything, so its "one retry" fired on almost every snap and queued a
    ; competing move at the same priority as the animation.
    WriteLog(Format("  settled at L={1} T={2}  (throw {3},{4})", newL, newT, tx, ty))
    SetTimer(VerifySnap.Bind(hwnd, newL, newT), -(Round(glideMs) + 60))
}

; The moment the window comes to rest: spark the seams it touched, then let it
; squish if it hit something hard. Called from Glide's final frame, or directly
; when there is no glide - never from a timer racing the animation.
;
; The size is read HERE rather than at drag end, because the window's own app may
; have resized it during the slide.
OnSnapLanded(hwnd, destX, destY, crashX, crashY, seams) {
    for s in seams
        ShowSeamFlash(s[1], s[2], s[3], s[4])

    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try {
        WinGetPos(, , &w, &h, hwnd)
        ; Unconditional, and deliberately outside the squash gate below: this is
        ; where the window came to rest, whether or not it hit anything hard
        ; enough to squash. Gating it on the impact was already wrong, and
        ; raising that gate would have widened the band of landings that were
        ; never recorded.
        RememberPosition(hwnd, destX, destY, w, h)

        ; Squash threshold raised from 4 to 12. The glide now overshoots the
        ; target and springs back on its own, so squashing the window as well
        ; reads as two separate things happening on one landing. The squash is
        ; kept for genuinely hard impacts, where it is the difference between
        ; "arrived" and "hit something".
        if (Abs(crashX) > 12 || Abs(crashY) > 12)
            BounceSqueeze(hwnd, destX, destY, w, h, crashX, crashY)
    }
}

; Some apps reposition themselves once more after a drag ends. Nudge them back,
; once - but never while our own glide is still flying the window, or we would be
; fighting the animation instead of the app.
VerifySnap(hwnd, newL, newT) {
    global ActiveAnimations
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if Anim_Owner(hwnd, "geom")
        return
    if !GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
        return
    if (vL = newL && vT = newT)
        return
    MoveFast(hwnd, vx + (newL - vL), vy + (newT - vT))
    RS_Commit()
    WriteLog(Format("  corrected L={1} T={2} -> L={3} T={4}", vL, vT, newL, newT))
}

; Slides a window and returns the animation length in ms (0 if it moved it
; immediately), so the caller can schedule its verification for after the landing.
;
; `onLanded` is invoked from the frame that puts the window down - and only then.
; It is deliberately NOT called if the window dies mid-slide, or if a new glide
; cancels this one, because in both cases the window never landed where this snap
; intended and anything keyed to the landing would be wrong.
; crashX/crashY are how far past the destination the throw was still heading when
; the snap stopped it. They are optional: a glide with nowhere to land (a monitor
; throw, a plain slide) passes nothing and gets the pure ease-out it always had.
Glide(hwnd, fromX, fromY, toX, toY, onLanded := "", crashX := 0, crashY := 0) {
    global GLIDE_MS
    dx := toX - fromX, dy := toY - fromY
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 2 || GLIDE_MS < 1) {
        MoveFast(hwnd, toX, toY)
        RS_Commit()
        if onLanded
            onLanded()
        return 0
    }

    ; The floor was 200 ms, which made a 20 px correction take as long as a
    ; 150 px slide and feel like the window was wading. Duration is dominated by
    ; distance now and the floor is only there to stop a two-frame animation.
    ms := Min(GLIDE_MS, 140 + dist * 0.9)
    if (ms < 140)
        ms := 140

    ; Overshoot, capped and signed by the impulse that produced it. The window
    ; passes the edge it is landing against and springs back, which is what
    ; "hitting something" looks like. Previously nothing overshot at all: the
    ; window eased asymptotically into its target and a separate animation
    ; squashed its width afterwards, so the impact was read as a size change
    ; rather than as motion.
    settle := Tune("glideSettle")
    ox := 0, oy := 0
    if (settle > 0) {
        if (crashX != 0)
            ox := Clamp(crashX * 0.35, -settle, settle)
        if (crashY != 0)
            oy := Clamp(crashY * 0.35, -settle, settle)
    }

    animKey := "Glide_" hwnd

    start := QPC()
    lastX := -99999, lastY := -99999

    GlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, toX, toY, -1, -1, RS_PRI_ANIM)
            if onLanded
                onLanded()
            return false
        }

        e := 1 - (1 - t) ** 5
        ; Exactly 0 at t=0 and t=1, so the terminal frame still writes the
        ; precise destination and onLanded still fires from the frame that puts
        ; the window down. t*(1-t)^3 peaks at t=0.25 with a value of 0.10547, so
        ; it is normalised by 1/0.10547 - without that the whole excursion would
        ; be a tenth of the configured pixels and invisible. The long tail after
        ; the peak is the settle.
        o := 9.4815 * t * (1 - t) ** 3
        nx := Round(fromX + dx * e + ox * o)
        ny := Round(fromY + dy * e + oy * o)

        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, -1, -1, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, GlideStep)
    return ms
}

JelloBounce(hwnd, destX, destY, vx, vy) {
    if (!DllCall("IsWindow", "ptr", hwnd))
        return
        
    try WinGetPos(,, &w, &h, hwnd)
    
    animKey := "Jello_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    
    ; vx/vy arrive in px/s now. 1.5 px of squash per px/frame is 0.0225 per px/s.
    sqX := Clamp(vx * 0.0225, -10, 10)
    sqY := Clamp(vy * 0.0225, -10, 10)
    
    JelloStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, destX, destY, w, h, RS_PRI_ANIM)
            return false
        }
        
        decay := Exp(-t * 5)
        osc := Sin(t * 15)
        
        curSqX := Round(sqX * decay * osc)
        curSqY := Round(sqY * decay * osc)
        
        curX := destX - Round(curSqX / 2)
        curY := destY - Round(curSqY / 2)
        curW := w + curSqX
        curH := h + curSqY
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, JelloStep)
}

BounceSqueeze(hwnd, X, Y, W, H, crashX, crashY) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    
    squeezeX := 0, squeezeY := 0
    moveX := 0, moveY := 0
    depth := Tune("animBounce")

    if (crashX > 4) {
        squeezeX := Min(crashX * 0.4, depth)
        moveX := squeezeX
    } else if (crashX < -4) {
        squeezeX := Min(-crashX * 0.4, depth)
        moveX := 0
    }

    if (crashY > 4) {
        squeezeY := Min(crashY * 0.4, depth)
        moveY := squeezeY
    } else if (crashY < -4) {
        squeezeY := Min(-crashY * 0.4, depth)
        moveY := 0
    }
    
    if (squeezeX == 0 && squeezeY == 0)
        return
        
    animKey := "Bounce_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animBounceMs")

    ; One smooth squish-and-release instead of four hard-coded stages at 16/32/48
    ; ms. The old version was three discrete jumps that assumed a frame was exactly
    ; 16 ms - it had no interpolation at all, and a late frame made it skip a stage
    ; or repeat one. sin(pi*t) rises from 0 to the full squeeze at the midpoint and
    ; returns to 0, so it starts and ends exactly at rest with no discontinuity.
    lastW := -1, lastH := -1, lastX := -1, lastY := -1
    BounceStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, X, Y, W, H, RS_PRI_ANIM)
            return false
        }

        e := Sin(3.14159265 * t)
        nx := Round(X + moveX * e)
        ny := Round(Y + moveY * e)
        nw := Round(W - squeezeX * e)
        nh := Round(H - squeezeY * e)
        ; Skip frames that would not change a pixel: SetWindowPos on a real window
        ; costs ~260 us and forces the app to re-layout.
        if (nx != lastX || ny != lastY || nw != lastW || nh != lastH) {
            RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
            lastX := nx, lastY := ny, lastW := nw, lastH := nh
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, BounceStep)
}

ThrowWindowToNextMonitor(hwnd, L, T, W, H, vx, vy) {
    monCount := MonitorGetCount()
    if (monCount < 2)
        return false
        
    cx := L + W/2
    cy := T + H/2
    
    ; Exclusive on the right and bottom, like MonitorIndexAt. Inclusive bounds
    ; make the shared edge between two monitors belong to both, so a window
    ; centred exactly there matched whichever came first in the enumeration.
    curMon := MonitorIndexAt(cx, cy)
    
    targetMon := 0
    bestDist := 999999
    
    loop monCount {
        if (A_Index == curMon)
            continue
            
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        mx := mL + (mR - mL)/2
        my := mT + (mB - mT)/2
        
        dx := mx - cx
        dy := my - cy
        
        dotProduct := (dx * vx) + (dy * vy)
        if (dotProduct > 0) {
            dist := Sqrt(dx*dx + dy*dy)
            if (dist < bestDist) {
                bestDist := dist
                targetMon := A_Index
            }
        }
    }
    
    if (!targetMon)
        return false
        
    ; Centre on the WORK AREA, not the whole monitor rect: centring on the full
    ; rect on a screen with a taskbar puts the bottom of the window underneath it.
    if !WorkAreaOf(targetMon, &mL, &mT, &mR, &mB)
        MonitorGet(targetMon, &mL, &mT, &mR, &mB)
    destX := mL + Round((mR - mL - W)/2)
    destY := mT + Round((mB - mT - H)/2)

    if !GetRects(hwnd, &curL, &curT, &curR, &curB, &curWinX, &curWinY)
        return false

    winDestX := curWinX + (destX - L)
    winDestY := curWinY + (destY - T)

    ; W and H arrive in FRAME space (SnapWindow passes R-L and B-T of the DWM
    ; extended frame bounds), but BounceSqueeze writes its w/h straight into
    ; RS_SetPos, which is WinMove space. Those differ by the invisible resize
    ; border, so handing the frame size over shrank the window by ~14px on every
    ; single monitor throw - and it never grew back, so repeated throws walked it
    ; smaller and smaller. The window's own rect IS the WinMove size, so read it
    ; rather than deriving it.
    bounceW := W, bounceH := H
    try WinGetPos(, , &bounceW, &bounceH, hwnd)

    Glide(hwnd, curWinX, curWinY, winDestX, winDestY, () => BounceSqueeze(hwnd, winDestX, winDestY, bounceW, bounceH, vx > 0 ? 10 : (vx < 0 ? -10 : 0), 0))
    return true
}

ShowSeamFlash(x, y, w, h) {
    if (w < 1)
        w := 1
    if (h < 1)
        h := 1

    flash := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "SeamFlash")
    flash.BackColor := "00E5FF"
    flash.MarginX := 0, flash.MarginY := 0
    flash.Show("x" x " y" y " w" w " h" h " NoActivate")

    ; Pass the Gui object, not just its handle. The animation outlives this
    ; function, and handing over only the HWND left nothing holding a reference
    ; to the object for those 192 ms.
    FadeSeam(flash, x, y, w, h)
}

FadeSeam(flashGui, x, y, w, h) {
    hwnd := flashGui.Hwnd
    animKey := "FadeSeam_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animSeamMs")   ; duration in ms; never derive this from a frame count

    SeamStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            ; Destroy, not WinClose: WinClose only posts WM_CLOSE and leaves the
            ; Gui alive. One of these is created on every single snap, so a
            ; leaked window here is a leak that grows all session.
            try flashGui.Destroy()
            RS_RemoveHwnd(hwnd)
            return false
        }

        ; (1-t)^2, not 1-t^2. The old curve was still at 75% brightness a third
        ; of the way through, which reads as a bar being drawn on the seam; this
        ; one is bright immediately and mostly gone by the midpoint, which reads
        ; as a spark where the two edges met.
        alpha := Round(255 * (1 - t) ** 2)

        if (w < h) {
            shrink := Round(h * t * 0.3)
            RS_SetPos(hwnd, x, y + shrink, w, h - shrink*2, RS_PRI_ANIM)
        } else {
            shrink := Round(w * t * 0.3)
            RS_SetPos(hwnd, x + shrink, y, w - shrink*2, h, RS_PRI_ANIM)
        }

        RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, SeamStep)
}

; Cheaper than WinMove per frame, and leaves z-order and focus alone mid-slide.
; Now delegates to the render pipeline for batched application.
MoveFast(hwnd, x, y) {
    RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_ANIM)
}

; A throw must not fling a window off into nowhere.
KeepOnScreen(hwnd, &L, &T, &R, &B, tx, ty) {
    w := R - L, h := B - T

    if (tx != 0 || ty != 0) {
        hmon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if (hmon) {
            monInfo := Buffer(40)
            NumPut("uint", 40, monInfo)
            if DllCall("GetMonitorInfo", "ptr", hmon, "ptr", monInfo) {
                wl := NumGet(monInfo, 20, "int")
                wt := NumGet(monInfo, 24, "int")
                wr := NumGet(monInfo, 28, "int")
                wb := NumGet(monInfo, 32, "int")
                L := Clamp(L, wl, wr - w)
                T := Clamp(T, wt, wb - h)
                R := L + w, B := T + h
                return
            }
        }
    }

    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    margin := 120
    L := Clamp(L, vx - w + margin, vx + vw - margin)
    T := Clamp(T, vy, vy + vh - margin)
    R := L + w, B := T + h
}

; ============================================================================
; Smart Tiling Grid
; ============================================================================
global GridActive := false
global GridHoverZone := 0
global SmartGridZones := []
global SmartGridGuis := []

ShowSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridActive, GridHoverZone
    
    MouseGetPos(&mx, &my)
    mon := MonitorIndexAt(mx, my)
    if !WorkAreaOf(mon, &wl, &wt, &wr, &wb)
        return
    w := wr - wl, h := wb - wt
    SmartGridZones := []
    if (w / h > 2.0) {
        cw := w // 3
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wl + cw*2, B: wb})
        SmartGridZones.Push({L: wl + cw*2, T: wt, R: wr, B: wb})
    } else {
        cw := w // 2, ch := h // 2
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wr, B: wt + ch})
        SmartGridZones.Push({L: wl + cw, T: wt + ch, R: wr, B: wb})
    }
    
    gap := Tune("gridGap")
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (SmartGridGuis.Length < A_Index) {
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            SmartGridGuis.Push(g)
        }
        g := SmartGridGuis[A_Index]
        g.BackColor := "111111"
        WinSetTransparent(100, g.Hwnd)
        
        gx := z.L + gap, gy := z.T + gap, gw := (z.R - z.L) - gap * 2, gh := (z.B - z.T) - gap * 2
        g.Show("x" gx " y" gy " w" gw " h" gh " NoActivate")
    }
    
    GridHoverZone := 0
    GridActive := true
}

UpdateSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridHoverZone
    
    MouseGetPos(&mx, &my)
    hovered := 0
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (mx >= z.L && mx <= z.R && my >= z.T && my <= z.B) {
            hovered := A_Index
            break
        }
    }
    
    if (hovered != GridHoverZone) {
        if (GridHoverZone > 0) {
            g := SmartGridGuis[GridHoverZone]
            g.BackColor := "111111"
            WinSetTransparent(100, g.Hwnd)
        }
        GridHoverZone := hovered
        if (hovered > 0) {
            g := SmartGridGuis[hovered]
            g.BackColor := "0078D7"
            WinSetTransparent(180, g.Hwnd)
        }
    }
}

HideSmartGrid() {
    global SmartGridGuis, GridActive, GridHoverZone
    for g in SmartGridGuis {
        g.Hide()
    }
    GridActive := false
    GridHoverZone := 0
}

ApplyGridZone(hwnd, zoneIndex) {
    global SmartGridZones
    if (zoneIndex < 1 || zoneIndex > SmartGridZones.Length)
        return
    z := SmartGridZones[zoneIndex]

    ; Unguarded, this throws when the window dies between FinishDrag's IsWindow
    ; check and here - which is a real race, because FinishDrag runs from a -50 ms
    ; one-shot. The throw killed the timer thread before HideSmartGrid() could
    ; run, stranding three dark zone overlays on screen until the app restarted.
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY)
        return
    frameW := fR - fL
    frameH := fB - fT
    try WinGetPos(,, &rawW, &rawH, hwnd)
    catch
        return
        
    diffW := rawW - frameW
    diffH := rawH - frameH
    diffX := fL - winX
    diffY := fT - winY
    
    finalX := z.L - diffX
    finalY := z.T - diffY
    finalW := (z.R - z.L) + diffW
    finalH := (z.B - z.T) + diffH
    
    gap := Tune("gridGap")
    destX := finalX + gap
    destY := finalY + gap
    destW := finalW - gap*2
    destH := finalH - gap*2
    
    try WinMove(destX, destY, destW, destH, hwnd)
    catch
        return
    RememberPosition(hwnd)

    global MomentumTiltEnabled
    if (MomentumTiltEnabled) {
        cpx := (z.L == 0) ? -15 : ((z.R >= A_ScreenWidth) ? 15 : 0)
        cpy := (z.T == 0) ? -15 : ((z.B >= A_ScreenHeight) ? 15 : 0)
        if (cpx != 0 || cpy != 0)
            BounceSqueeze(hwnd, destX, destY, destW, destH, cpx, cpy)
    }
}
