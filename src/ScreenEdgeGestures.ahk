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
