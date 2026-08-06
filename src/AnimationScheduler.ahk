#Requires AutoHotkey v2.0
; ============================================================================
; AnimationScheduler.ahk - Single-timer animation multiplexer
; ============================================================================
; All visual effects register callbacks here instead of spawning their own
; timers.  RenderFrame() runs every ~16 ms and has two phases:
;
;   Phase 1 - Produce:  Call every animation callback.  Each callback MUST
;             write desired state through RS_Set*() in RenderCore.ahk.
;             Callbacks must NOT call WinSetTransparent, SetWindowPos,
;             WinSetRegion, WinMove, or any other Win32 rendering API.
;
;   Phase 2 - Render:   Call RS_Flush() exactly once.  This batches all
;             pending changes and applies them in a single pass.
;
; A callback returns true to stay registered, false to be removed.  When the
; last one goes, the timer stops - which is why one-shot producers outside this
; file have to call RS_Commit() themselves (see RenderCore.ahk's header).
;
; Concurrency: the produce loop iterates a snapshot of the keys, not the Map.
; Every other timer, every hotkey and the SetWinEventHook callback can interrupt
; this loop between lines, and several of them call RegisterAnimation() or
; CancelAnimation().  Mutating an AHK Map while a `for` enumerator is live over
; it shifts items under the enumerator index, which silently skips or repeats
; animations; iterating a snapshot is immune to that.
;
; Function definitions only.
; ============================================================================

global ActiveAnimations := Map()
global SchedulerLastTime := QPC()
global SchedulerRunning := false

; Frame budget stats.
global FrameProduceMs := 0
global FrameRenderMs  := 0
global FrameOverbudget := 0   ; count of frames where produce > 12 ms

; The frame period is 15, not 16, and that is not a rounding choice.
;
; Windows' clock tick is ~15.6 ms. A 15.6 ms deadline set from a 16 ms period is
; always *just* past the next tick, so the timer waits a whole extra tick and the
; cadence alternates 15.6 / 31.2 ms. Measured over 100 frames on an idle script:
;
;   period=16 -> mean 25.15 ms, jitter 7.59 ms, 39.8 fps, 59% of frames > 20 ms
;   period=15 -> mean 15.78 ms, jitter 0.30 ms, 63.4 fps, min 14.88, max 16.33
;
; A period at or below the tick means the deadline has always already passed, so
; it fires on every tick: a rock-steady 63 fps. Going lower (10, 8, 5) lands on
; the same tick but occasionally double-fires, which is wasted work - 15 is the
; sweet spot. timeBeginPeriod(1) is required for either (without it, period 16
; measured 26.26 ms with 8.17 ms jitter).
global FRAME_MS := 15

StartScheduler() {
    global SchedulerRunning, SchedulerLastTime, FRAME_MS
    if (!SchedulerRunning) {
        SchedulerRunning := true
        SchedulerLastTime := QPC()
        ; Request 1 ms timer resolution while animating.
        DllCall("winmm\timeBeginPeriod", "uint", 1)
        SetTimer(RenderFrame, FRAME_MS)
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
    global ActiveAnimations, SchedulerLastTime, FRAME_MS
    global FrameProduceMs, FrameRenderMs, FrameOverbudget

    now := QPC()
    ; dt is real elapsed milliseconds since the last frame, clamped.
    ;
    ; Animations that advance by a fixed amount per frame are frame-rate
    ; dependent: measured, a 26-frame fade took 659 ms instead of 416 ms once
    ; frames got heavy - it turns into slow motion under load instead of holding
    ; its wall-clock duration. Such animations must scale their step by dt.
    ;
    ; The upper clamp matters: after a long stall (a modal dialog, a hung app)
    ; an unclamped dt would teleport every rate-based animation to its end in one
    ; frame. Three frames' worth is enough to absorb ordinary hiccups.
    dt := now - SchedulerLastTime
    if (dt <= 0)
        dt := FRAME_MS
    else if (dt > FRAME_MS * 3)
        dt := FRAME_MS * 3
    SchedulerLastTime := now

    ; ---- Phase 1: Produce (run all animation callbacks) ----------------------
    produceStart := QPC()

    keys := []
    for key, unused in ActiveAnimations
        keys.Push(key)

    for key in keys {
        if !ActiveAnimations.Has(key)          ; cancelled since the snapshot
            continue
        anim := ActiveAnimations[key]
        try
            keepAlive := anim.Call(dt, now)
        catch
            keepAlive := false
        if keepAlive
            continue
        ; Only retire what we actually ran: a callback is allowed to re-register
        ; its own key (roll-up does exactly this), and that fresh registration
        ; must not be thrown away by the finishing one.
        if (ActiveAnimations.Has(key) && ActiveAnimations[key] == anim)
            ActiveAnimations.Delete(key)
    }

    FrameProduceMs := QPC() - produceStart
    if (FrameProduceMs > 12) {
        FrameOverbudget++
        OutputDebug("WARNING: Frame Produce took " FrameProduceMs " ms (Budget: 12ms)")
    }

    ; ---- Phase 2: Render (single batched flush) ------------------------------
    renderStart := QPC()
    RS_Flush()
    FrameRenderMs := QPC() - renderStart

    ; ---- Shut down when idle -------------------------------------------------
    if (ActiveAnimations.Count == 0)
        StopScheduler()
}

RegisterAnimation(key, callback) {
    global ActiveAnimations
    ActiveAnimations[key] := callback
    StartScheduler()
}

CancelAnimation(key) {
    global ActiveAnimations
    if ActiveAnimations.Has(key)
        ActiveAnimations.Delete(key)
}
