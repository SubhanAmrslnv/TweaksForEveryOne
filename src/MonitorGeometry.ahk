; Monitor geometry - which screen a point is on, and where its work area is.
;
; Function definitions and global initialisers only, no top-level statements.
;
; Two caching rules, and they differ on purpose:
;
; MONITOR RECTS ARE CACHED. MonitorGet/MonitorGetCount measured 2.9-3.2 us and
; are read on the 15 ms frame path, so ScreenMetrics() caches them along with the
; virtual-screen bounds. The cache is invalidated by WM_DISPLAYCHANGE, which
; Boot() wires to InvalidateScreenMetrics.
;
; WORK AREAS ARE NOT. WorkAreaOf/WorkAreaAt call MonitorGetWorkArea live, because
; the work area changes when the taskbar auto-hides and that raises no
; WM_DISPLAYCHANGE - a cached copy would be stale exactly when Smart Auto-Hide is
; on. These are hotkey-path calls, so the ~3 us is irrelevant.

; Which cached monitor contains (px, py)? A 1-based index into
; ScreenMetrics().mons, falling back to 1 for a point off every screen.
MonitorIndexAt(px, py) {
    g := ScreenMetrics()
    for i, m in g.mons {
        if (px >= m.l && px < m.r && py >= m.t && py < m.b)
            return i
    }
    ; Monitor 1 is NOT the primary - the enumeration order is whatever the OS
    ; hands back, and on plenty of setups the primary is 2 or 3. For a point that
    ; is off every screen the primary is the only defensible answer.
    try return MonitorGetPrimary()
    return 1
}

; Which monitor should a transient overlay appear on? The one holding the
; pointer, because that is where the user is looking, and the primary when the
; pointer is nowhere. Shared by both OSDs so they cannot disagree.
CursorMonitorIndex() {
    MouseGetPos(&mx, &my)
    return MonitorIndexAt(mx, my)
}

; Work area (monitor minus taskbar) of monitor `idx`.
; The monitor RECTS come from the ScreenMetrics cache, but the work area is read
; live every time on purpose: it changes whenever the taskbar auto-hides, and
; that raises no WM_DISPLAYCHANGE - so a cached copy would be stale exactly when
; Smart Auto-Hide is on. This is a hotkey path, not a per-frame one, and
; MonitorGetWorkArea costs ~3 us.
WorkAreaOf(idx, &wl, &wt, &wr, &wb) {
    try {
        MonitorGetWorkArea(idx, &wl, &wt, &wr, &wb)
        return true
    }
    try {
        MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
        return true
    }
    return false
}

WorkAreaAt(px, py, &wl, &wt, &wr, &wb) {
    return WorkAreaOf(MonitorIndexAt(px, py), &wl, &wt, &wr, &wb)
}

; Virtual-screen metrics, cached. This runs 50 times a second; four SysGet calls
; plus a monitor enumeration per tick bought nothing, because the answer only
; changes when the display configuration does - and WM_DISPLAYCHANGE tells us.
global ScreenGeom := ""

ScreenMetrics() {
    global ScreenGeom
    if !IsObject(ScreenGeom) {
        vLeft := SysGet(76), vTop := SysGet(77)
        vWidth := SysGet(78), vHeight := SysGet(79)
        mons := []
        try {
            loop MonitorGetCount() {
                MonitorGet(A_Index, &L, &T, &R, &B)
                mons.Push({l: L, t: T, r: R, b: B})
            }
        }
        ScreenGeom := {left: vLeft, top: vTop, width: vWidth, height: vHeight
                     , right: vLeft + vWidth, bottom: vTop + vHeight, mons: mons}
    }
    return ScreenGeom
}

; Boot() registers this for WM_DISPLAYCHANGE (0x007E).
InvalidateScreenMetrics(*) {
    global ScreenGeom, DimmerGuis, FocusModeEnabled, FocusBounds, FocusGuis
    ScreenGeom := ""

    ; Dropping the cache is not enough - the overlays SIZED from it are still on
    ; screen at the old geometry. After a resolution change or a monitor being
    ; plugged in, the dimmers covered the wrong rectangles and the focus vignette
    ; left a bright band down whatever the desktop had just gained.
    ;
    ; Dimmers are cheap to rebuild: drop them and let the 200 ms tick recreate
    ; them against the new layout on its next pass.
    for k, g in DimmerGuis
        try GuiDestroy(g)
    DimmerGuis.Clear()

    ; The focus overlays cannot be dropped - they ARE focus mode - so resize them
    ; in place and re-anchor the region maths to the new virtual screen.
    if (FocusModeEnabled && FocusGuis.Length) {
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        for layer in FocusGuis
            try RS_SetPos(layer.gui.Hwnd, vx, vy, vw, vh, RS_PRI_ANIM)
        RS_Commit()
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
    }
}
