; Screen edge gestures - what happens when the pointer reaches a boundary.
;
; Function definitions only, no top-level statements. Both features are polling
; monitors, so each is a SetTimer with its own Sync*, and each MUST call
; RS_Commit() itself - a monitor is not a registered animation and nothing else
; flushes for it.
;
; INFINITE CURSOR WRAP IS AN INTENT MODEL, NOT A THRESHOLD TEST, and the shape
; matters because the outer edge of the desktop is somewhere the pointer lands
; constantly: a Back button, a close box, a scrollbar, the Start button. The
; original fired on any contact with the outermost pixel column, mid-drag
; included. Three gates, ALL of which must pass:
;
;   1. Approach speed at the moment of contact. Sampled from the tick BEFORE
;      contact - once Windows clamps the pointer at the edge its measured speed
;      is zero by definition, so it cannot be sampled after.
;   2. Dwell. Leaving the band resets the state, so a glance off the edge never
;      accumulates.
;   3. Cooldown since the last wrap, so one gesture cannot chain.
;
; Setting speed or delay to 0 disables that gate individually, which is how the
; old instant behaviour stays reachable.
;
; Two things are deliberately NOT settings: suppression while any mouse button is
; down or DragHwnd is set, because teleporting the cursor mid-drag is never
; wanted; and the landing inset, derived as tolerance + 8 so the destination can
; never re-arm the gate it just left.
;
; Hot corners uses the same dwell model for the same reason, so the two features
; feel like one design.
;
; A TIMER CALLBACK THAT THROWS POPS AN ERROR DIALOG AND KILLS THAT TIMER - the
; feature is then dead for the rest of the session. Every window query in a
; monitor goes inside try with an explicit fallback.

; ====== macOS Hot Corners ======

SyncHotCornersTimer() {
    global HotCornersEnabled
    if (HotCornersEnabled)
        SetTimer(HotCornersMonitorStep, 50)
    else
        SetTimer(HotCornersMonitorStep, 0)
}

SyncCursorWrapTimer() {
    global InfiniteWrapEnabled
    if (InfiniteWrapEnabled)
        SetTimer(CursorWrapMonitorStep, 20)
    else
        SetTimer(CursorWrapMonitorStep, 0)
}

; Teleport the cursor across the outer edges of the virtual desktop - but only
; when the user clearly meant it.
;
; The original was a single stateless test: "is x at the outermost pixel column?
; then jump". That fires on any contact whatsoever with the outer edge, and the
; outer edge is somewhere the pointer lands constantly - throwing it left to hit
; a Back button, a window's close box, a scrollbar, the Start button. Windows
; clamps the pointer at the edge, so a fast reach parks it there for several
; ticks and the jump was indistinguishable from a deliberate one. It also fired
; mid-drag, teleporting the cursor out from under a window being moved.
;
; Intent is inferred from three things, all of which must hold:
;
;   1. APPROACH SPEED at the moment of contact. A deliberate push arrives fast;
;      a pointer that drifted to the edge while the user read something does not.
;      Sampled from the tick before contact, because once the pointer is clamped
;      at the edge its measured speed is zero by definition.
;   2. DWELL. It must stay in the band for wrap.delay. Leaving resets the state,
;      so a glance off the edge never accumulates toward a wrap.
;   3. COOLDOWN since the last wrap, so one gesture cannot chain.
;
; Setting wrap.speed or wrap.delay to 0 disables that gate on its own, which is
; how the old instant behaviour stays reachable.
;
; Suppression while a mouse button is down is NOT configurable: teleporting the
; cursor mid-drag is never what anyone wants, and HotCornersMonitorStep already
; sets that precedent.
CursorWrapMonitorStep() {
    global InfiniteWrapEnabled, DragHwnd
    static lastX := 0, lastY := 0, lastAt := 0     ; previous sample, for speed
    static contactAt := 0                          ; when the current contact began
    static contactSide := 0                        ; -1 left, +1 right, 0 none
    static approachOk := false                     ; speed gate passed on contact
    static cooldownUntil := 0

    if (!InfiniteWrapEnabled)
        return

    now := A_TickCount
    MouseGetPos(&mx, &my)

    prevX := lastX, prevY := lastY, prevAt := lastAt
    lastX := mx, lastY := my, lastAt := now

    ; A drag is in progress: no wrapping, and no state either - releasing the
    ; button at the edge must not count as a completed dwell.
    if (DragHwnd || GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
        || GetKeyState("MButton", "P")) {
        contactSide := 0
        return
    }

    ; Interior dead edges first. A bridge moves the pointer, so the outer-wrap
    ; sample taken above is stale and this tick is over.
    if (CursorBridgeStep(now)) {
        contactSide := 0
        MouseGetPos(&lastX, &lastY)
        return
    }

    g := ScreenMetrics()
    tol := Tune("wrapTol")

    ; The rightmost addressable column is right-1, so the right band is measured
    ; from there. Getting this wrong by one is the difference between a band of
    ; `tol` pixels and one that can never be entered at all.
    side := 0
    if (mx <= g.left + tol)
        side := -1
    else if (mx >= g.right - 1 - tol)
        side := 1

    if (!side) {
        contactSide := 0
        return
    }
    if (now < cooldownUntil)
        return

    if (side != contactSide) {
        ; First tick of this contact. Judge the approach from the movement that
        ; brought us here.
        contactSide := side
        contactAt := now
        minSpeed := Tune("wrapSpeed")
        approachOk := (minSpeed <= 0)
        if (!approachOk && prevAt && now > prevAt) {
            dist := Sqrt((mx - prevX) ** 2 + (my - prevY) ** 2)
            approachOk := (dist * 1000 / (now - prevAt)) >= minSpeed
        }
        return
    }

    if (!approachOk)
        return
    if (now - contactAt < Tune("wrapDelay"))
        return

    ; Land clear of the band we just left, or the destination would satisfy the
    ; contact test immediately and the pointer would sit armed on the far edge.
    inset := tol + 8
    tx := (side < 0) ? (g.right - 1 - inset) : (g.left + inset)
    ty := my

    ; The virtual desktop is a bounding box, not a surface: with monitors of
    ; different heights or vertical offsets, (tx, ty) can land in a hole. Project
    ; onto the nearest monitor that spans tx. Bounds are exclusive on the right
    ; and bottom, matching MonitorIndexAt and MC_MonitorIndexForRect.
    inside := false
    for m in g.mons {
        if (tx >= m.l && tx < m.r && ty >= m.t && ty < m.b) {
            inside := true
            break
        }
    }
    if (!inside) {
        bestDy := 0, bestY := "", edgePad := 5
        for m in g.mons {
            if (tx < m.l || tx >= m.r)
                continue
            if (ty < m.t)
                dy := m.t - ty, projY := m.t + edgePad
            else if (ty >= m.b)
                dy := ty - m.b + 1, projY := m.b - 1 - edgePad
            else
                dy := 0, projY := ty
            if (bestY == "" || dy < bestDy)
                bestDy := dy, bestY := projY
        }
        ; No monitor spans tx at all - the arrangement has no surface on that
        ; side at this height. Refuse rather than teleport into nothing.
        if (bestY == "") {
            contactSide := 0
            return
        }
        ty := bestY
    }

    MouseMove(tx, ty, 0)
    cooldownUntil := now + Tune("wrapCool")
    contactSide := 0
    lastX := tx, lastY := ty
}

; ====== Dead-edge bridge ======
;
; THE ASYMMETRY THIS FIXES IS WINDOWS', NOT THE WRAP'S. Measured on the owner's
; desk: DISPLAY1 0,0 1920x1200 and DISPLAY2 1920,58 1920x1080. Every point of
; DISPLAY2's left edge has DISPLAY1 beside it, so right-to-left always crosses.
; DISPLAY1's right edge has NOTHING beside it for y < 58 and y >= 1138, and
; Windows clamps the pointer there - left-to-right only crossed if the hand
; happened to be inside the overlap. The wrap never helped: it only ever looks
; at the outer edges of the whole desktop.
;
; A dead edge is an edge band of the pointer's monitor where the pixel just
; beyond is on no monitor, but another monitor shares that edge LINE somewhere
; else. Reaching it while still moving toward it carries the pointer onto the
; nearest point of that neighbour. The rule is written once per axis and
; mirrored, reads real rects rather than monitor indices (enumeration order is
; not physical order), and so holds for any count, vertical stacks and negative
; coordinates alike.
;
; INTENT IS THE MOTION THAT ARRIVED, NOT SPEED AS A HURDLE. The dead strip on a
; maximised window's side is where its close box lives, and a pointer that
; decelerates onto a close box arrives at a crawl. wrap.bridgespeed (100 px/s)
; is far below any ordinary crossing, which is the point: the old complaint was
; having to move FAST. Sampled the tick before contact, because once Windows
; clamps the pointer its measured speed is zero.
;
; Measured and moved in PHYSICAL pixels under a per-monitor-v2 thread context -
; see PhysicalMonitorRects(). SetCursorPos rather than MouseMove for the same
; reason: MouseMove normalises through the process's system-DPI metrics.
;
; Returns true when it moved the pointer.
CursorBridgeStep(now) {
    static lastX := 0, lastY := 0, lastAt := 0, cooldownUntil := 0
    moved := false
    prevCtx := PerMonitorDpiBegin()
    try {
        pt := Buffer(8, 0)
        if !DllCall("GetCursorPos", "ptr", pt)
            return false
        mx := NumGet(pt, 0, "int"), my := NumGet(pt, 4, "int")
        px := lastX, py := lastY, pAt := lastAt
        lastX := mx, lastY := my, lastAt := now

        ; A sample older than a few ticks (the timer was paused by a drag, a
        ; button, Game Mode) describes some earlier gesture, not this one.
        if (!pAt || now <= pAt || now - pAt > 100 || now < cooldownUntil)
            return false

        mons := PhysicalMonitorRects()
        if (mons.Length < 2)
            return false
        cur := ""
        for m in mons {
            if (mx >= m.l && mx < m.r && my >= m.t && my < m.b) {
                cur := m
                break
            }
        }
        if !IsObject(cur)
            return false

        tol := Tune("wrapTol")
        minSpeed := Tune("wrapBridge")
        dt := now - pAt
        vx := (mx - px) * 1000 / dt, vy := (my - py) * 1000 / dt

        ; One table, four mirrored rows: which band, which way is "toward", and
        ; the pixel just past the edge. Bounds are exclusive on r/b.
        sides := [
            {inBand: mx >= cur.r - 1 - tol, v:  vx, ox: cur.r,     oy: my,        axis: "x", line: cur.r, dir:  1},
            {inBand: mx <= cur.l + tol,     v: -vx, ox: cur.l - 1, oy: my,        axis: "x", line: cur.l, dir: -1},
            {inBand: my >= cur.b - 1 - tol, v:  vy, ox: mx,        oy: cur.b,     axis: "y", line: cur.b, dir:  1},
            {inBand: my <= cur.t + tol,     v: -vy, ox: mx,        oy: cur.t - 1, axis: "y", line: cur.t, dir: -1}
        ]
        for s in sides {
            if (!s.inBand)
                continue
            ; Arrived moving toward it. With 0 any motion toward the edge counts,
            ; but a pointer simply resting there never does.
            if (s.v <= 0 || s.v < minSpeed)
                continue
            if (CursorPointOnAnyMonitor(mons, s.ox, s.oy))
                continue                     ; Windows crosses this one itself

            ; Nearest neighbour that shares this edge line and overlaps on the
            ; other axis. 1 px of slack absorbs rounding between scale factors.
            best := "", bestD := 0
            for m in mons {
                if (m == cur)
                    continue
                if (s.axis == "x") {
                    near := (s.dir > 0) ? m.l : m.r
                    if (Abs(near - s.line) > 1 || m.b <= cur.t || m.t >= cur.b)
                        continue
                    d := (my < m.t) ? m.t - my : (my >= m.b ? my - m.b + 1 : 0)
                } else {
                    near := (s.dir > 0) ? m.t : m.b
                    if (Abs(near - s.line) > 1 || m.r <= cur.l || m.l >= cur.r)
                        continue
                    d := (mx < m.l) ? m.l - mx : (mx >= m.r ? mx - m.r + 1 : 0)
                }
                if (!IsObject(best) || d < bestD)
                    best := m, bestD := d
            }
            if !IsObject(best)
                continue                     ; a true outer edge - the wrap's job

            ; Land clear of the neighbour's own edge band, at the closest point
            ; to where the pointer was heading.
            inset := tol + 2
            if (s.axis == "x") {
                tx := (s.dir > 0) ? best.l + inset : best.r - 1 - inset
                ty := Max(best.t + inset, Min(my, best.b - 1 - inset))
            } else {
                ty := (s.dir > 0) ? best.t + inset : best.b - 1 - inset
                tx := Max(best.l + inset, Min(mx, best.r - 1 - inset))
            }
            if DllCall("SetCursorPos", "int", tx, "int", ty) {
                lastX := tx, lastY := ty
                cooldownUntil := now + 150
                moved := true
            }
            break
        }
    } catch {
        ; A throw here would kill the wrap timer for the session.
        moved := false
    } finally {
        PerMonitorDpiEnd(prevCtx)
    }
    return moved
}

CursorPointOnAnyMonitor(mons, x, y) {
    for m in mons {
        if (x >= m.l && x < m.r && y >= m.t && y < m.b)
            return true
    }
    return false
}

HotCornersMonitorStep() {
    global HotCornersEnabled, HotCornerTL, HotCornerTR, HotCornerBL, HotCornerBR
    static LastCorner := "None", EnteredAt := 0, Fired := false

    if (!HotCornersEnabled)
        return

    try {
        if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P") || GetKeyState("MButton", "P"))
            return
            
        MouseGetPos(&mx, &my)

        g := ScreenMetrics()
        count := g.mons.Length
        activeMon := 1
        Loop count {
            m := g.mons[A_Index]
            L := m.l, T := m.t, R := m.r, B := m.b
            if (mx >= L && mx <= R - 1 && my >= T && my <= B - 1) {
                activeMon := A_Index
                break
            }
        }
        
        m := g.mons[activeMon]
        L := m.l, T := m.t, R := m.r, B := m.b

        currentCorner := "None"
        thresh := Tune("cornerSize")
        
        if (mx <= L + thresh && my <= T + thresh)
            currentCorner := "TL"
        else if (mx >= R - 1 - thresh && my <= T + thresh)
            currentCorner := "TR"
        else if (mx <= L + thresh && my >= B - 1 - thresh)
            currentCorner := "BL"
        else if (mx >= R - 1 - thresh && my >= B - 1 - thresh)
            currentCorner := "BR"
            
        ; Same dwell model as the cursor wrap, and for the same reason: a corner
        ; is where you throw the pointer to reach a close box or the Start
        ; button, so bare entry is not intent. EnteredAt is stamped on the first
        ; tick in a corner and the action waits for corners.delay; leaving resets
        ; it. Fired stops one dwell from re-firing every tick while the pointer
        ; stays parked there.
        if (currentCorner != LastCorner) {
            LastCorner := currentCorner
            EnteredAt := A_TickCount
            Fired := false
        }
        if (currentCorner == "None" || Fired)
            return
        if (A_TickCount - EnteredAt < Tune("cornerDelay"))
            return

        action := "None"
        if (currentCorner == "TL")
            action := HotCornerTL
        else if (currentCorner == "TR")
            action := HotCornerTR
        else if (currentCorner == "BL")
            action := HotCornerBL
        else if (currentCorner == "BR")
            action := HotCornerBR

        Fired := true
        if (action != "None")
            ExecuteHotCornerAction(action)
    }
}

ExecuteHotCornerAction(action) {
    if (action == "Task View")
        Send("#{Tab}")
    else if (action == "Show Desktop")
        Send("#d")
    else if (action == "Action Center")
        Send("#a")
    else if (action == "Start Menu")
        Send("{LWin}")
    else if (action == "Lock Screen")
        DllCall("user32\LockWorkStation")
    else if (action == "Mute Volume")
        Send("{Volume_Mute}")
}
