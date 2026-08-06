#Requires AutoHotkey v2.0
; ============================================================================
; RenderCore.ahk - Centralized render pipeline
; ============================================================================
; Every visual feature writes desired state through RS_Set*() functions.
; Nothing outside this file may call WinSetTransparent, SetWindowPos, WinMove,
; WinSetRegion or WinSetExStyle directly.
;
; Two kinds of producer, and they MUST be told apart:
;
;   Per-frame animators  - register with RegisterAnimation(); the scheduler
;                          calls RS_Flush() once per frame for them.  They only
;                          queue state.
;   One-shot commands    - a hotkey or a monitor that queues state and returns.
;                          These MUST call RS_Commit() themselves.
;
; That second rule is not optional.  The animation scheduler stops its timer as
; soon as nothing is animating, so a queued change with nobody to flush it is
; simply never applied - which silently killed snapping-without-glide, the
; transparency wheel, breathing restore and un-ghosting until this was
; documented here.
;
; Lifetime model: a queued entry is DELETED the moment it is applied, so the
; pending Maps only ever hold outstanding work.  That is what bounds their size
; (transient overlay windows do not raise shell destroy notifications, so
; nothing else would ever clean up after them) and what makes priority
; arbitration per-flush without a reset pass.
;
; Deliberately NOT cached: window positions.  A cache is only valid when the
; cache owns the state, and the user dragging a title bar changes a window's
; position behind this pipeline's back.  Caching last-requested positions made
; a second snap to the same edge a silent no-op.
;
; Function definitions only - safe to #Include from test scripts.
; ============================================================================

; ----- priority constants (higher number wins within one flush) ---------------
global RS_PRI_AMBIENT  := 10   ; breathing, ghost proximity
global RS_PRI_ANIM     := 20   ; glide, bounce, pulse, fade, slide-in, seam
global RS_PRI_DRAG     := 30   ; parallax drag, alt-drag, grab-pan
global RS_PRI_USER     := 40   ; manual transparency wheel, explicit move

; ----- pending state, keyed by HWND ------------------------------------------
; Presence in one of these Maps means "not applied yet".  RS_Flush empties them.
global RS_Alpha      := Map()   ; hwnd -> {value, pri}     value 256 = "Off"
global RS_Pos        := Map()   ; hwnd -> {x, y, w, h, pri}  w/h -1 = keep size
global RS_Region     := Map()   ; hwnd -> {value, pri}     "" = clear region
global RS_ZOrder     := Map()   ; hwnd -> {insertAfter, flags, pri}

; ----- last-applied state ----------------------------------------------------
; Only for the two attributes this pipeline effectively owns.  Both exist to
; avoid redundant calls that are individually expensive: WinSetTransparent
; adds/removes WS_EX_LAYERED and WinSetRegion rebuilds a GDI region, and either
; one repeated every frame is a visible redraw storm.  Pruned by RS_RemoveHwnd
; and by the periodic RS_SweepDead pass, so a recycled HWND cannot inherit a
; dead window's entry for long.
global RS_LastAlpha  := Map()   ; hwnd -> last alpha written
global RS_LastRegion := Map()   ; hwnd -> last region string written

; ----- stats ------------------------------------------------------------------
global RS_FlushCount   := 0     ; total flushes
global RS_LastFlushMs  := 0     ; ms spent in the last flush

; ==============================================================================
;  Public API - state producers
; ==============================================================================
; All four setters share one rule: a write at a priority below whatever already
; claimed this HWND during the current flush cycle is dropped; anything else
; overwrites.  Entries never survive a flush, so nothing has to reset priorities.

; Queue a transparency change.  Pass "Off" to remove transparency entirely.
RS_SetAlpha(hwnd, alpha, pri := 20) {
    global RS_Alpha
    if !hwnd
        return
    numAlpha := (alpha == "Off") ? 256 : Integer(alpha)
    if RS_Alpha.Has(hwnd) {
        entry := RS_Alpha[hwnd]
        if (pri < entry.pri)
            return
        entry.pri   := pri
        entry.value := numAlpha
        return
    }
    RS_Alpha[hwnd] := {value: numAlpha, pri: pri}
}

; Queue a position/size change.  Pass -1 for w or h to mean "don't change size"
; (maps to SWP_NOSIZE internally).
RS_SetPos(hwnd, x, y, w := -1, h := -1, pri := 20) {
    global RS_Pos
    if !hwnd
        return
    if RS_Pos.Has(hwnd) {
        entry := RS_Pos[hwnd]
        if (pri < entry.pri)
            return
        entry.pri := pri
        entry.x   := x
        entry.y   := y
        entry.w   := w
        entry.h   := h
        return
    }
    RS_Pos[hwnd] := {x: x, y: y, w: w, h: h, pri: pri}
}

; Queue a region change.  Pass "" to clear the region.
RS_SetRegion(hwnd, regionStr, pri := 20) {
    global RS_Region
    if !hwnd
        return
    if RS_Region.Has(hwnd) {
        entry := RS_Region[hwnd]
        if (pri < entry.pri)
            return
        entry.pri   := pri
        entry.value := regionStr
        return
    }
    RS_Region[hwnd] := {value: regionStr, pri: pri}
}

; Queue a z-order change.  insertAfter is an HWND or a constant
; (0 = HWND_TOP, 1 = HWND_BOTTOM, -1 = HWND_TOPMOST, -2 = HWND_NOTOPMOST).
RS_SetZOrder(hwnd, insertAfter, flags := 0x0013, pri := 20) {
    global RS_ZOrder
    if !hwnd
        return
    if RS_ZOrder.Has(hwnd) {
        entry := RS_ZOrder[hwnd]
        if (pri < entry.pri)
            return
        entry.pri         := pri
        entry.insertAfter := insertAfter
        entry.flags       := flags
        return
    }
    RS_ZOrder[hwnd] := {insertAfter: insertAfter, flags: flags, pri: pri}
}

; What alpha does this window actually have right now?
;
; Lets a fade start from where the window is rather than from a hard-coded value,
; which is what stops a reversed fade (an OSD revived mid-hide) from jumping. A
; pending write wins over the last applied one, since that is what the next flush
; will produce. 256 ("Off") reports as 255.
RS_CurrentAlpha(hwnd, defaultVal := 255) {
    global RS_Alpha, RS_LastAlpha
    v := ""
    if RS_Alpha.Has(hwnd)
        v := RS_Alpha[hwnd].value
    else if RS_LastAlpha.Has(hwnd)
        v := RS_LastAlpha[hwnd]
    if (v == "")
        return defaultVal
    return (v >= 256) ? 255 : v
}

; ==============================================================================
;  Lifecycle helpers
; ==============================================================================

; Forget everything about one window.  Call this whenever a window we touched
; is destroyed - both foreign windows (shell hook) and our own overlay GUIs,
; which raise no shell notification at all.
RS_RemoveHwnd(hwnd) {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion] {
        if m.Has(hwnd)
            m.Delete(hwnd)
    }
}

; Backstop for windows nobody told us about: drop cache entries whose window is
; gone.  Collect first, delete after - deleting during enumeration shifts the
; remaining items under the enumerator and skips one.
RS_SweepDead() {
    global RS_LastAlpha, RS_LastRegion
    for m in [RS_LastAlpha, RS_LastRegion] {
        dead := []
        for hwnd, unused in m {
            if !DllCall("IsWindow", "ptr", hwnd)
                dead.Push(hwnd)
        }
        for hwnd in dead
            m.Delete(hwnd)
    }
}

RS_Shutdown() {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion]
        m.Clear()
}

; ==============================================================================
;  RS_Commit - apply queued state now.  For one-shot producers (see header).
; ==============================================================================
RS_Commit() => RS_Flush()

; ==============================================================================
;  RS_Flush - the single render pass
; ==============================================================================
; Re-entrancy guard: this is called from the frame loop AND directly from timer
; and hotkey threads, any of which can interrupt the frame loop between lines.
; A nested call would clear pending work under the outer call's feet, so it
; instead asks the outer call to run one more pass before it returns.
RS_Flush() {
    global RS_FlushCount, RS_LastFlushMs
    static busy := false
    static again := false
    static sinceSweep := 0

    if busy {
        again := true
        return
    }

    busy := true
    flushStart := QPC()
    try {
        loop 4 {                       ; bounded: never spin on a pathological producer
            again := false
            RS_Apply()
            if !again
                break
        }
    }
    RS_FlushCount++
    if (++sinceSweep >= 600) {         ; ~10s of continuous animation
        sinceSweep := 0
        try RS_SweepDead()
    }
    RS_LastFlushMs := QPC() - flushStart
    busy := false
}

; One pass over the pending Maps.  Each Map is swapped out for an empty one
; before it is read, so a producer interrupting this pass queues into the fresh
; Map and its write is picked up by the next pass instead of being lost or
; corrupting an in-flight enumeration.
RS_Apply() {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion

    ; ---- 1. Position / size, batched through DeferWindowPos ------------------
    if RS_Pos.Count {
        pend := RS_Pos
        RS_Pos := Map()

        ; One shape for any number of windows. A single-window fast path that
        ; skipped this array was tried and measured: no difference. SetWindowPos
        ; on a real window costs ~260 us (it drives actual composition), which
        ; dwarfs the ~1 us of allocation, and the old path already skipped the
        ; DeferWindowPos batching for one window. Not worth two code paths
        ; through the hottest function in the program.
        list := []
        for hwnd, entry in pend {
            if !DllCall("IsWindow", "ptr", hwnd) {
                RS_RemoveHwnd(hwnd)
                continue
            }
            ; SWP_NOACTIVATE | SWP_NOZORDER
            flags := 0x0014
            wVal  := entry.w
            hVal  := entry.h
            if (wVal < 0 || hVal < 0) {
                flags |= 0x0001        ; SWP_NOSIZE
                wVal := 0, hVal := 0
            }
            list.Push({hwnd: hwnd, x: entry.x, y: entry.y, w: wVal, h: hVal, flags: flags})
        }

        ; Batching one window costs more than it saves.
        batched := false
        if (list.Length > 1) {
            hdwp := DllCall("BeginDeferWindowPos", "int", list.Length, "ptr")
            if hdwp {
                for it in list {
                    res := DllCall("DeferWindowPos", "ptr", hdwp
                        , "ptr", it.hwnd, "ptr", 0
                        , "int", it.x, "int", it.y, "int", it.w, "int", it.h
                        , "uint", it.flags, "ptr")
                    ; A failure frees the whole structure: the handle is dead,
                    ; nothing queued so far was applied, and EndDeferWindowPos
                    ; must not be called on it.
                    if !res {
                        hdwp := 0
                        break
                    }
                    hdwp := res
                }
                if hdwp {
                    DllCall("EndDeferWindowPos", "ptr", hdwp)
                    batched := true
                }
            }
        }
        if !batched {
            for it in list {
                try DllCall("SetWindowPos", "ptr", it.hwnd, "ptr", 0
                    , "int", it.x, "int", it.y, "int", it.w, "int", it.h
                    , "uint", it.flags)
            }
        }
    }

    ; ---- 2. Z-order (cannot ride along with position) ------------------------
    ; Never diffed: z-order changes under us constantly, so a cache would be
    ; wrong more often than right.
    if RS_ZOrder.Count {
        pend := RS_ZOrder
        RS_ZOrder := Map()
        for hwnd, entry in pend {
            if !DllCall("IsWindow", "ptr", hwnd) {
                RS_RemoveHwnd(hwnd)
                continue
            }
            try DllCall("SetWindowPos", "ptr", hwnd, "ptr", entry.insertAfter
                , "int", 0, "int", 0, "int", 0, "int", 0, "uint", entry.flags)
        }
    }

    ; ---- 3. Alpha -----------------------------------------------------------
    if RS_Alpha.Count {
        pend := RS_Alpha
        RS_Alpha := Map()
        for hwnd, entry in pend {
            if !DllCall("IsWindow", "ptr", hwnd) {
                RS_RemoveHwnd(hwnd)
                continue
            }
            if RS_LastAlpha.Has(hwnd) {
                if (RS_LastAlpha[hwnd] == entry.value)
                    continue
            } else if (entry.value >= 256) {
                ; "Off" on a window we never made transparent: recording it is
                ; enough.  Actually calling it would strip WS_EX_LAYERED from a
                ; window that never had it and force a redraw for nothing.
                RS_LastAlpha[hwnd] := entry.value
                continue
            }
            try {
                if (entry.value >= 256)
                    WinSetTransparent("Off", hwnd)
                else
                    WinSetTransparent(entry.value, hwnd)
            }
            RS_LastAlpha[hwnd] := entry.value
        }
    }

    ; ---- 4. Region ----------------------------------------------------------
    if RS_Region.Count {
        pend := RS_Region
        RS_Region := Map()
        for hwnd, entry in pend {
            if !DllCall("IsWindow", "ptr", hwnd) {
                RS_RemoveHwnd(hwnd)
                continue
            }
            if RS_LastRegion.Has(hwnd) {
                if (RS_LastRegion[hwnd] == entry.value)
                    continue
            } else if (entry.value == "") {
                RS_LastRegion[hwnd] := ""      ; clearing a region nobody set
                continue
            }
            try WinSetRegion(entry.value, hwnd)
            RS_LastRegion[hwnd] := entry.value
        }
    }
}
