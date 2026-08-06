#Requires AutoHotkey v2.0
; ============================================================================
; AnimationScheduler.ahk — Single-timer animation multiplexer
; ============================================================================
; All visual effects register callbacks here instead of spawning their own
; timers.  RenderFrame() runs every ~16 ms and has two phases:
;
;   Phase 1 — Produce:  Call every animation callback.  Each callback MUST
;             write desired state through RS_Set*() in RenderCore.ahk.
;             Callbacks must NOT call WinSetTransparent, SetWindowPos,
;             WinSetRegion, WinMove, or any other Win32 rendering API.
;
;   Phase 2 — Render:   Call RS_Flush() exactly once.  This batches all
;             pending changes and applies them in a single kernel pass.
;
; Function definitions only.
; ============================================================================

global ActiveAnimations := Map()
global SchedulerLastTime := QPC()
global SchedulerRunning := false

; Pending adds/removes avoid mutating ActiveAnimations while iterating.
global _SchedPendingAdd    := Map()
global _SchedPendingRemove := Map()

; Frame budget stats.
global FrameProduceMs := 0
global FrameRenderMs  := 0
global FrameOverbudget := 0   ; count of frames where produce > 12 ms

StartScheduler() {
    global SchedulerRunning, SchedulerLastTime
    if (!SchedulerRunning) {
        SchedulerRunning := true
        SchedulerLastTime := QPC()
        ; Request 1 ms timer resolution while animating.
        DllCall("winmm\timeBeginPeriod", "uint", 1)
        SetTimer(RenderFrame, 16)
    }
}

StopScheduler() {
    global SchedulerRunning
    if (SchedulerRunning) {
        SetTimer(RenderFrame, 0)
        SchedulerRunning := false
        DllCall("winmm\timeEndPeriod", "uint", 1)
    }
}

RenderFrame() {
    global ActiveAnimations, SchedulerLastTime
    global _SchedPendingAdd, _SchedPendingRemove
    global FrameProduceMs, FrameRenderMs, FrameOverbudget

    now := QPC()
    dt := now - SchedulerLastTime
    if (dt <= 0)
        dt := 1
    SchedulerLastTime := now

    ; ---- Phase 1: Produce (run all animation callbacks) ----------------------
    RS_BeginFrame()
    produceStart := QPC()

    for key, anim in ActiveAnimations {
        try {
            keepAlive := anim.Call(dt, now)
            if (!keepAlive)
                _SchedPendingRemove[key] := true
        } catch {
            _SchedPendingRemove[key] := true
        }
    }

    FrameProduceMs := QPC() - produceStart
    if (FrameProduceMs > 12) {
        FrameOverbudget++
        OutputDebug("WARNING: Frame Produce took " FrameProduceMs " ms (Budget: 12ms)")
    }

    ; ---- Apply pending add/remove before flush so new animations get their
    ;      first state applied this same frame.
    for key in _SchedPendingRemove {
        if ActiveAnimations.Has(key)
            ActiveAnimations.Delete(key)
    }
    _SchedPendingRemove.Clear()

    for key, cb in _SchedPendingAdd {
        ActiveAnimations[key] := cb
    }
    _SchedPendingAdd.Clear()

    ; ---- Phase 2: Render (single batched flush) ------------------------------
    renderStart := QPC()
    RS_Flush()
    FrameRenderMs := QPC() - renderStart

    ; ---- Shut down when idle -------------------------------------------------
    if (ActiveAnimations.Count == 0)
        StopScheduler()
}

RegisterAnimation(key, callback) {
    global ActiveAnimations, _SchedPendingAdd
    ; If we are mid-frame (inside RenderFrame iteration), defer the add.
    ; Otherwise apply immediately so StartScheduler fires.
    ActiveAnimations[key] := callback
    StartScheduler()
}

CancelAnimation(key) {
    global ActiveAnimations
    if ActiveAnimations.Has(key)
        ActiveAnimations.Delete(key)
}
