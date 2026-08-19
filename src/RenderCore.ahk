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
; Alpha has two APIs and picking the wrong one is a silent bug:
;
;   RS_SetAlpha()        for windows WE created (overlay GUIs). One owner by
;                        construction, so an absolute value is the whole truth.
;   RS_SetAlphaLayer()   for FOREIGN windows, where breathing, the ghost, the
;   RS_SetBaseAlpha()    drag parallax, focus depth and the user's own wheel can
;                        all want to dim the same window. See the block above
;                        those functions for the layer names and their owners.
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

; ----- composed alpha, keyed by HWND -----------------------------------------
; PERSISTENT, unlike the four pending Maps above. One record per FOREIGN window
; that something is currently dimming:
;
;   baseAlpha  the user's explicit opacity, 0-255. Only the user sets this.
;   layers     named multiplicative modifiers, each 0.0 - 1.0.
;
; final = baseAlpha * product(layers).
;
; THE FIELD CANNOT BE CALLED `base`. In AHK v2 `base` is the prototype slot on
; every object, and an object literal honours it: `{base: 255, layers: Map()}`
; does not create a field, it tries to set the object's prototype to the integer
; 255 and throws `Error: Invalid base.` (verified on 2.0.26 in this repo).
;
; That threw on the ONE line that creates a record, so it fired the first time
; anything dimmed a given window - which is every window - and took the whole
; composed-alpha system with it: drag parallax, breathing, the proximity ghost,
; focus depth, the open animations, gravity close and the user's own
; Shift+Alt+Wheel all silently did nothing. It was invisible because the throw
; happened inside an animation callback, where the scheduler's bare `catch`
; retired the animation without a word (see AnimationScheduler.ahk) - the whole
; feature set was dead with an empty log and a clean parse.
;
; Clearing one layer therefore cannot destroy the base or any other layer, and
; that is the entire point. Before this existed every producer wrote an ABSOLUTE,
; so any producer that ended with "Off" - focus depth, the post-drag fade-back,
; un-ghosting - silently threw away the opacity the user had set with
; Shift+Alt+Wheel, and left CustomTrans claiming a value the screen did not have.
; Breathing had already grown two hand-written compositions to work around it.
;
; Bounded the same way the pending Maps are, just keyed on a different event: a
; record is DELETED the moment it goes neutral (baseAlpha 255, no layers), so this
; only ever holds windows that are currently non-default. RS_RemoveHwnd drops a
; record when a window dies and RS_SweepDead is the backstop, exactly as for
; RS_LastAlpha - without both, a recycled HWND inherits a stranger's opacity.
global RS_AlphaState := Map()   ; hwnd -> {baseAlpha, layers}

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
;  Public API - composed alpha, for FOREIGN windows
; ==============================================================================
; Use RS_SetAlpha for windows we created ourselves. Every overlay Gui in the
; program - OSDs, seam flash, spotlight, PiP, the active border, dimmers - has
; exactly one owner by construction and a lifetime shorter than the effect
; driving it, so composition there would be a Map lookup and a product for a
; value that could only ever have one contributor.
;
; Use the functions below for a window that belongs to another process, where
; several unrelated features can want to dim it at once.
;
; ONE OWNER PER LAYER NAME. The language cannot enforce this, so it is written
; down here:
;
;   "base"     the user's opacity        ChangeTransparency / ResetTransparency
;   "drag"     parallax while dragging   SampleVelocityStep / AltDragMove /
;                                        StartFadeBackAlpha
;   "ghost"    proximity ghost           ToggleGhostMode / GhostMonitorStep /
;                                        UnGhostWindow
;   "breathe"  idle background fade      BreathingAnimatorStep /
;                                        SyncBreathingTimers
;   "depth"    focus depth cue           PushBackWindow / BringForwardWindow /
;                                        RestoreFocusDepth
;   "open"     pre-hide of a new window  ShellEvent / RevealWindow /
;                                        UnrollWindow / GhostSlideIn /
;                                        PortalScaleIn
;   "gravity"  Alt+F4 drop stand-in      GravityClose / CheckGravityClose
;
; Two owners of one name reproduce the original oscillation bug inside a single
; layer, which is strictly harder to see than the one this replaced.

; The user's explicit opacity. Pass 255 or "Off" to mean "no user opacity".
; This is the only thing that sets base; every ambient effect uses a layer.
RS_SetBaseAlpha(hwnd, alpha, pri := 40) {
    global RS_AlphaState
    if !hwnd
        return
    numAlpha := (alpha == "Off") ? 255 : Integer(alpha)
    if (numAlpha > 255)
        numAlpha := 255
    if (numAlpha < 0)
        numAlpha := 0
    if RS_AlphaState.Has(hwnd) {
        rec := RS_AlphaState[hwnd]
        if (rec.baseAlpha == numAlpha)
            return
        rec.baseAlpha := numAlpha
    } else {
        if (numAlpha >= 255)
            return                     ; neutral, and no record to make neutral
        RS_AlphaState[hwnd] := {baseAlpha: numAlpha, layers: Map()}
    }
    RS_RecomposeAlpha(hwnd, pri)
    RS_PruneAlphaState(hwnd)
}

; Read the user's opacity back. 255 means "none set".
RS_BaseAlpha(hwnd) {
    global RS_AlphaState
    return RS_AlphaState.Has(hwnd) ? RS_AlphaState[hwnd].baseAlpha : 255
}

; Install or update one named modifier.
;
; A factor of 1.0 is NOT the same as clearing the layer. A layer present at 1.0
; keeps the window layered at full opacity rather than collapsing the record to
; "Off"; the proximity ghost depends on exactly that, because losing
; WS_EX_LAYERED would leave an opaque, click-through, always-on-top window with
; no visible cue that anything is wrong.
RS_SetAlphaLayer(hwnd, name, factor, pri := 20) {
    global RS_AlphaState
    if !hwnd
        return
    if (factor > 1.0)
        factor := 1.0
    if (factor < 0.0)
        factor := 0.0
    if RS_AlphaState.Has(hwnd) {
        rec := RS_AlphaState[hwnd]
        ; Cheap early-out: a ghost sitting still, or a breathe fade that has
        ; settled, re-asserts the same factor on every single frame.
        if (rec.layers.Has(name) && rec.layers[name] == factor)
            return
    } else {
        rec := {baseAlpha: 255, layers: Map()}
        RS_AlphaState[hwnd] := rec
    }
    rec.layers[name] := factor
    RS_RecomposeAlpha(hwnd, pri)
}

; Drop one modifier. Whatever else is dimming this window - the user's base, a
; different layer - is untouched. This is the call that fixes the defect class.
RS_ClearAlphaLayer(hwnd, name, pri := 20) {
    global RS_AlphaState
    if !hwnd || !RS_AlphaState.Has(hwnd)
        return
    rec := RS_AlphaState[hwnd]
    if !rec.layers.Has(name)
        return                         ; already clear: safe to call every frame
    rec.layers.Delete(name)
    RS_RecomposeAlpha(hwnd, pri)       ; emit BEFORE pruning - prune drops the record
    RS_PruneAlphaState(hwnd)
}

; Hand a window all of its opacity back: base AND every layer. For teardown -
; Bye() and the panic key - and nothing else. A feature must clear its own layer.
RS_ResetAlphaState(hwnd, pri := 40) {
    global RS_AlphaState
    if !hwnd || !RS_AlphaState.Has(hwnd)
        return
    RS_AlphaState.Delete(hwnd)
    ; The record is gone, so RS_RecomposeAlpha would early-return. Queue directly.
    RS_SetAlpha(hwnd, "Off", pri)
}

; Every window this pipeline is currently dimming, in one call.
;
; Snapshot the keys first: RS_ResetAlphaState deletes from the Map being walked,
; which shifts the remainder under the enumerator index and silently skips one -
; the same hazard RS_SweepDead and RenderFrame already document.
RS_ResetAllAlphaState(pri := 40) {
    global RS_AlphaState
    keys := []
    for hwnd, unused in RS_AlphaState
        keys.Push(hwnd)
    for hwnd in keys
        RS_ResetAlphaState(hwnd, pri)
}

; A record is neutral when nothing is dimming the window: full base, no layers.
; This is a STRUCTURAL test, not a numeric one, and that distinction is
; load-bearing - see the note in RS_RecomposeAlpha.
RS_IsNeutralAlpha(rec) => (rec.baseAlpha >= 255 && rec.layers.Count == 0)

RS_PruneAlphaState(hwnd) {
    global RS_AlphaState
    if (RS_AlphaState.Has(hwnd) && RS_IsNeutralAlpha(RS_AlphaState[hwnd]))
        RS_AlphaState.Delete(hwnd)
}

; Derive the committed value and queue it. The only place a composed final is
; computed, and it recomputes from source every time rather than accumulating,
; so repeated float products cannot drift.
;
; "Off" (256) strips WS_EX_LAYERED, which is a real saving, but it is emitted
; ONLY for a structurally neutral record - never merely because the arithmetic
; rounded up to 255. A ghosted window sits at proximity alpha 255 whenever the
; cursor is over it; collapsing that to "Off" would strip WS_EX_LAYERED and
; re-add it 40 times a second, and in between the window is opaque and
; click-through. ToggleGhostMode installs its layer at 1.0 for that reason.
;
; Priority handling: a composed value is the COMPLETE truth for this window, so
; it overwrites whatever is pending and keeps the strongest priority the entry
; has been given. Two composed writes in one flush always agree - both derive
; from this same record - and dropping the later one because it happened to
; carry a lower priority is what would strand a cleared layer: the clearing
; owner early-returns on the next frame because the layer is already gone, so
; nothing would ever re-queue it.
RS_RecomposeAlpha(hwnd, pri) {
    global RS_AlphaState, RS_Alpha
    if !RS_AlphaState.Has(hwnd)
        return
    rec := RS_AlphaState[hwnd]

    if RS_IsNeutralAlpha(rec) {
        iv := 256
    } else {
        v := rec.baseAlpha + 0.0
        for name, f in rec.layers
            v *= f
        iv := Integer(v + 0.5)
        if (iv > 255)
            iv := 255
        if (iv < 0)
            iv := 0
    }

    if RS_Alpha.Has(hwnd) {
        entry := RS_Alpha[hwnd]
        entry.value := iv
        if (pri > entry.pri)
            entry.pri := pri
        return
    }
    RS_Alpha[hwnd] := {value: iv, pri: pri}
}

; ==============================================================================
;  Lifecycle helpers
; ==============================================================================

; Forget everything about one window.  Call this whenever a window we touched
; is destroyed - both foreign windows (shell hook) and our own overlay GUIs,
; which raise no shell notification at all.
RS_RemoveHwnd(hwnd) {
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion, RS_AlphaState
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion, RS_AlphaState] {
        if m.Has(hwnd)
            m.Delete(hwnd)
    }
}

; Backstop for windows nobody told us about: drop cache entries whose window is
; gone.  Collect first, delete after - deleting during enumeration shifts the
; remaining items under the enumerator and skips one.
RS_SweepDead() {
    global RS_LastAlpha, RS_LastRegion, RS_AlphaState
    for m in [RS_LastAlpha, RS_LastRegion, RS_AlphaState] {
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
    global RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion, RS_AlphaState
    for m in [RS_Alpha, RS_Pos, RS_Region, RS_ZOrder, RS_LastAlpha, RS_LastRegion, RS_AlphaState]
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
            ; Record the value ONLY when the call actually landed. WinSetTransparent
            ; throws on a window this process may not touch - an elevated one, with
            ; AHK unelevated - and recording it anyway poisoned the cache: the diff
            ; above then skipped every later identical write, so drag parallax,
            ; breathing and the ghost silently never worked on that window again,
            ; with nothing logged and no way to tell from the outside.
            okAlpha := false
            try {
                if (entry.value >= 256)
                    WinSetTransparent("Off", hwnd)
                else
                    WinSetTransparent(entry.value, hwnd)
                okAlpha := true
            }
            if okAlpha
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

; Immediate mode - DWM thumbnails do not go through the flush cycle because they
; write to a DWM handle, not an HWND property.
RS_UpdateDwmThumbnail(thumbId, destRect := "", srcRect := "", alpha := "", visible := "", clientOnly := "") {
    props := Buffer(48, 0)
    flags := 0
    if (destRect != "") {
        flags |= 0x01 ; DWM_TNP_RECTDESTINATION
        NumPut("int", destRect[1], props, 4)
        NumPut("int", destRect[2], props, 8)
        NumPut("int", destRect[1] + destRect[3], props, 12)
        NumPut("int", destRect[2] + destRect[4], props, 16)
    }
    if (srcRect != "") {
        flags |= 0x02 ; DWM_TNP_RECTSOURCE
        NumPut("int", srcRect[1], props, 20)
        NumPut("int", srcRect[2], props, 24)
        NumPut("int", srcRect[1] + srcRect[3], props, 28)
        NumPut("int", srcRect[2] + srcRect[4], props, 32)
    }
    if (alpha != "") {
        flags |= 0x04 ; DWM_TNP_OPACITY
        NumPut("char", alpha, props, 36)
    }
    if (visible != "") {
        flags |= 0x08 ; DWM_TNP_VISIBLE
        NumPut("int", visible ? 1 : 0, props, 40)
    }
    if (clientOnly != "") {
        flags |= 0x10 ; DWM_TNP_SOURCECLIENTAREAONLY
        NumPut("int", clientOnly ? 1 : 0, props, 44)
    }
    if (flags) {
        NumPut("uint", flags, props, 0)
        DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", thumbId, "ptr", props)
    }
}
