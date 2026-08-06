#Requires AutoHotkey v2.0
; ============================================================================
; RenderCore.ahk — Centralized render pipeline
; ============================================================================
; Every visual feature writes desired state through RS_Set*() functions.
; Nothing outside this file may call WinSetTransparent, SetWindowPos, WinMove,
; WinSetRegion, or WinSetExStyle directly.  RS_Flush() applies all pending
; changes exactly once per frame, batching position changes through
; BeginDeferWindowPos / DeferWindowPos / EndDeferWindowPos.
;
; Function definitions only — safe to #Include from test scripts.
; ============================================================================

; ----- priority constants (higher number wins) --------------------------------
global RS_PRI_AMBIENT  := 10   ; breathing, ghost proximity
global RS_PRI_ANIM     := 20   ; glide, bounce, pulse, fade, slide-in, seam
global RS_PRI_DRAG     := 30   ; parallax drag, alt-drag, grab-pan
global RS_PRI_USER     := 40   ; manual transparency wheel, explicit move

; ----- per-HWND render state --------------------------------------------------
; Maps keyed by HWND.  Each stores a plain object with the desired value and
; the priority of the writer so that RS_Flush can pick the winner.

global RS_Alpha      := Map()   ; hwnd → {value, pri, dirty}
global RS_Pos        := Map()   ; hwnd → {x, y, w, h, pri, dirty}
global RS_Region     := Map()   ; hwnd → {value, pri, dirty}
global RS_ZOrder     := Map()   ; hwnd → {insertAfter, flags, pri, dirty}
global RS_ExStyle    := Map()   ; hwnd → {add, remove, pri, dirty}

; ----- last-applied state (for diffing) ---------------------------------------
global RS_LastAlpha  := Map()   ; hwnd → last alpha written
global RS_LastPos    := Map()   ; hwnd → {x, y, w, h}
global RS_LastRegion := Map()   ; hwnd → last region string

; ----- stats (read by frame-budget logger) ------------------------------------
global RS_FlushCount   := 0     ; total frames flushed
global RS_LastFlushMs  := 0     ; ms spent in last RS_Flush call

; ==============================================================================
;  Public API — called by feature callbacks (state producers)
; ==============================================================================

; Queue a transparency change.  "Off" is stored as 256.
RS_SetAlpha(hwnd, alpha, pri := 20) {
    global RS_Alpha
    if !hwnd
        return
    ; Normalise "Off" to a sentinel the flush can detect.
    numAlpha := (alpha == "Off") ? 256 : Integer(alpha)

    if RS_Alpha.Has(hwnd) {
        entry := RS_Alpha[hwnd]
        if (pri >= entry.pri) {
            entry.value := numAlpha
            entry.pri   := pri
            entry.dirty := true
        }
    } else {
        RS_Alpha[hwnd] := {value: numAlpha, pri: pri, dirty: true}
    }
}

; Queue a position/size change.  Pass -1 for w or h to mean "don't change size"
; (maps to SWP_NOSIZE internally).
RS_SetPos(hwnd, x, y, w := -1, h := -1, pri := 20) {
    global RS_Pos
    if !hwnd
        return
    if RS_Pos.Has(hwnd) {
        entry := RS_Pos[hwnd]
        if (pri >= entry.pri) {
            entry.x     := x
            entry.y     := y
            entry.w     := w
            entry.h     := h
            entry.pri   := pri
            entry.dirty := true
        }
    } else {
        RS_Pos[hwnd] := {x: x, y: y, w: w, h: h, pri: pri, dirty: true}
    }
}

; Queue a region change.  Pass "" to clear the region.
RS_SetRegion(hwnd, regionStr, pri := 20) {
    global RS_Region
    if !hwnd
        return
    if RS_Region.Has(hwnd) {
        entry := RS_Region[hwnd]
        if (pri >= entry.pri) {
            entry.value := regionStr
            entry.pri   := pri
            entry.dirty := true
        }
    } else {
        RS_Region[hwnd] := {value: regionStr, pri: pri, dirty: true}
    }
}

; Queue a z-order change.  insertAfter is an HWND or a constant
; (0 = HWND_TOP, 1 = HWND_BOTTOM, -1 = HWND_TOPMOST, -2 = HWND_NOTOPMOST).
RS_SetZOrder(hwnd, insertAfter, flags := 0x0013, pri := 20) {
    global RS_ZOrder
    if !hwnd
        return
    if RS_ZOrder.Has(hwnd) {
        entry := RS_ZOrder[hwnd]
        if (pri >= entry.pri) {
            entry.insertAfter := insertAfter
            entry.flags       := flags
            entry.pri         := pri
            entry.dirty       := true
        }
    } else {
        RS_ZOrder[hwnd] := {insertAfter: insertAfter, flags: flags, pri: pri, dirty: true}
    }
}

; Queue an extended-style modification (bits to add / bits to remove).
RS_SetExStyle(hwnd, addBits, removeBits, pri := 20) {
    global RS_ExStyle
    if !hwnd
        return
    if RS_ExStyle.Has(hwnd) {
        entry := RS_ExStyle[hwnd]
        if (pri >= entry.pri) {
            entry.add    := addBits
            entry.remove := removeBits
            entry.pri    := pri
            entry.dirty  := true
        }
    } else {
        RS_ExStyle[hwnd] := {add: addBits, remove: removeBits, pri: pri, dirty: true}
    }
}

; ==============================================================================
;  Lifecycle helpers
; ==============================================================================

; Remove all tracked state for a destroyed window.
RS_RemoveHwnd(hwnd) {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_ExStyle
    global RS_LastAlpha, RS_LastPos, RS_LastRegion
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_ExStyle,
              RS_LastAlpha, RS_LastPos, RS_LastRegion] {
        if m.Has(hwnd)
            m.Delete(hwnd)
    }
}

; Full teardown on exit.
RS_Shutdown() {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_ExStyle
    global RS_LastAlpha, RS_LastPos, RS_LastRegion
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_ExStyle,
              RS_LastAlpha, RS_LastPos, RS_LastRegion] {
        m.Clear()
    }
}

; ==============================================================================
;  RS_Flush — the single render pass, called once per frame
; ==============================================================================
RS_Flush() {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_ExStyle
    global RS_LastAlpha, RS_LastPos, RS_LastRegion
    global RS_FlushCount, RS_LastFlushMs

    flushStart := QPC()
    RS_FlushCount++

    ; ---- 1. Batch position/size changes via DeferWindowPos ------------------
    posCount := 0
    for hwnd, entry in RS_Pos {
        if entry.dirty
            posCount++
    }

    if (posCount > 0) {
        hdwp := DllCall("BeginDeferWindowPos", "int", posCount, "ptr")
        if hdwp {
            for hwnd, entry in RS_Pos {
                if !entry.dirty
                    continue
                if !DllCall("IsWindow", "ptr", hwnd) {
                    entry.dirty := false
                    continue
                }

                ; Diff against last-applied to skip no-ops.
                if RS_LastPos.Has(hwnd) {
                    lp := RS_LastPos[hwnd]
                    if (entry.x == lp.x && entry.y == lp.y
                        && entry.w == lp.w && entry.h == lp.h) {
                        entry.dirty := false
                        continue
                    }
                }

                ; SWP flags: NOACTIVATE=0x0010, NOZORDER=0x0004
                flags := 0x0014
                xVal := entry.x, yVal := entry.y
                wVal := entry.w, hVal := entry.h

                if (wVal < 0 || hVal < 0) {
                    flags |= 0x0001   ; SWP_NOSIZE
                    wVal := 0, hVal := 0
                }

                result := DllCall("DeferWindowPos", "ptr", hdwp
                    , "ptr", hwnd, "ptr", 0
                    , "int", xVal, "int", yVal, "int", wVal, "int", hVal
                    , "uint", flags, "ptr")
                if result
                    hdwp := result

                ; Record what we applied.
                RS_LastPos[hwnd] := {x: entry.x, y: entry.y, w: entry.w, h: entry.h}
                entry.dirty := false
            }
            DllCall("EndDeferWindowPos", "ptr", hdwp)
        } else {
            ; Fallback: DeferWindowPos failed, apply individually.
            for hwnd, entry in RS_Pos {
                if !entry.dirty
                    continue
                if !DllCall("IsWindow", "ptr", hwnd) {
                    entry.dirty := false
                    continue
                }
                flags := 0x0014
                wVal := entry.w, hVal := entry.h
                if (wVal < 0 || hVal < 0) {
                    flags |= 0x0001
                    wVal := 0, hVal := 0
                }
                try DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
                    , "int", entry.x, "int", entry.y, "int", wVal, "int", hVal
                    , "uint", flags)
                RS_LastPos[hwnd] := {x: entry.x, y: entry.y, w: entry.w, h: entry.h}
                entry.dirty := false
            }
        }
    }

    ; ---- 2. Z-order changes (cannot be batched with position) ----------------
    for hwnd, entry in RS_ZOrder {
        if !entry.dirty
            continue
        if !DllCall("IsWindow", "ptr", hwnd) {
            entry.dirty := false
            continue
        }
        try DllCall("SetWindowPos", "ptr", hwnd, "ptr", entry.insertAfter
            , "int", 0, "int", 0, "int", 0, "int", 0, "uint", entry.flags)
        entry.dirty := false
    }

    ; ---- 3. Alpha / transparency changes -------------------------------------
    for hwnd, entry in RS_Alpha {
        if !entry.dirty
            continue
        if !DllCall("IsWindow", "ptr", hwnd) {
            entry.dirty := false
            continue
        }

        ; Diff: skip if value unchanged.
        if RS_LastAlpha.Has(hwnd) {
            if (RS_LastAlpha[hwnd] == entry.value) {
                entry.dirty := false
                continue
            }
        }

        try {
            if (entry.value >= 256)
                WinSetTransparent("Off", hwnd)
            else
                WinSetTransparent(entry.value, hwnd)
        }
        RS_LastAlpha[hwnd] := entry.value
        entry.dirty := false
    }

    ; ---- 4. Region changes ---------------------------------------------------
    for hwnd, entry in RS_Region {
        if !entry.dirty
            continue
        if !DllCall("IsWindow", "ptr", hwnd) {
            entry.dirty := false
            continue
        }

        if RS_LastRegion.Has(hwnd) {
            if (RS_LastRegion[hwnd] == entry.value) {
                entry.dirty := false
                continue
            }
        }

        try WinSetRegion(entry.value, hwnd)
        RS_LastRegion[hwnd] := entry.value
        entry.dirty := false
    }

    ; ---- 5. Extended style changes -------------------------------------------
    for hwnd, entry in RS_ExStyle {
        if !entry.dirty
            continue
        if !DllCall("IsWindow", "ptr", hwnd) {
            entry.dirty := false
            continue
        }
        try {
            cur := WinGetExStyle(hwnd)
            newStyle := (cur | entry.add) & ~entry.remove
            if (newStyle != cur)
                WinSetExStyle(newStyle, hwnd)
        }
        entry.dirty := false
    }

    ; ---- 6. Reset priorities for next frame ----------------------------------
    ; Every slot drops to 0 so that next frame's writers compete fresh.
    for hwnd, entry in RS_Alpha
        entry.pri := 0
    for hwnd, entry in RS_Pos
        entry.pri := 0
    for hwnd, entry in RS_Region
        entry.pri := 0
    for hwnd, entry in RS_ZOrder
        entry.pri := 0
    for hwnd, entry in RS_ExStyle
        entry.pri := 0

    RS_LastFlushMs := QPC() - flushStart
}

; ==============================================================================
;  RS_FlushFinal — exit-time cleanup: reset all windows to clean state
; ==============================================================================
RS_FlushFinal() {
    global RS_Alpha, RS_Region
    ; Set all tracked windows back to fully opaque.
    for hwnd, entry in RS_Alpha {
        if DllCall("IsWindow", "ptr", hwnd) {
            try WinSetTransparent("Off", hwnd)
        }
    }
    ; Clear all regions.
    for hwnd, entry in RS_Region {
        if (entry.value != "" && DllCall("IsWindow", "ptr", hwnd)) {
            try WinSetRegion("", hwnd)
        }
    }
    RS_Shutdown()
}
