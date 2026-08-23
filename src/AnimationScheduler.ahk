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
; Function definitions only. Also owns QPC(), the shared timebase every
; elapsed-time animation in the program is parameterised on.
; ============================================================================

global ActiveAnimations := Map()
global SchedulerLastTime := QPC()
global SchedulerRunning := false

; ----- per-window channel ownership -------------------------------------------
; A key is just a string, so nothing stopped two animations from driving the
; same property of the same window. RS_* arbitration is per-flush and ties at
; equal priority are broken by Map order - and AHK enumerates a Map sorted by
; key - so "Jello_" silently won over "Glide_" every frame.
;
; The old defence was a hand-written CancelAnimation list at each site that
; started a motion. There were five of them, they had drifted apart, and not one
; named Jello_ or Curtain_ - so grabbing a window during a
; 400 ms jello left the jello resizing it underneath the drag.
;
; A channel is a property class: at most one animation may own (window, channel)
; at a time, and claiming it cancels whoever held it. The five lists collapse to
; one Anim_Release(hwnd, "geom") each.
global ANIM_CHANNELS := ["geom", "alpha", "region"]
global AnimOwner     := Map()   ; hwnd "|" channel -> animation key
global AnimOwnerKey  := Map()   ; animation key    -> {hwnd, channel}

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

; Refuses to stop while work is queued.
;
; RenderFrame calls this after checking ActiveAnimations.Count == 0, and those
; two steps are not atomic: any of the 11 timers, every hotkey and the
; SetWinEventHook callback can interrupt in between and call RegisterAnimation.
; That call saw SchedulerRunning still true, so StartScheduler was a no-op, and
; then this ran and killed the timer - leaving a live animation registered with
; nothing to drive it until something else happened to register another one.
; Re-checking here closes the window from the other side.
;
; `force` is for Bye(), which has to stop the loop even though animations are
; still registered - it is about to undo all of them.
StopScheduler(force := false) {
    global SchedulerRunning, ActiveAnimations
    if (!force && ActiveAnimations.Count)
        return
    if (SchedulerRunning) {
        SetTimer(RenderFrame, 0)
        SchedulerRunning := false
        DllCall("winmm\timeEndPeriod", "uint", 1)
    }
}

RenderFrame() {
    global ActiveAnimations, SchedulerLastTime, FRAME_MS
    global FrameProduceMs, FrameRenderMs, FrameOverbudget

    ; Last time each animation key was reported as throwing. Bounded rather than
    ; pruned: keys are per-HWND ("Glide_12345"), so an unbounded Map would grow
    ; for the whole session. It only ever gains an entry when a callback actually
    ; throws, so in a healthy process it stays empty and the cap never fires.
    static lastThrow := Map()

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

    ; The whole body is inside the try, not just anim.Call. The snapshot above
    ; protects the ENUMERATION from concurrent mutation; it does not protect the
    ; LOOKUP. Every one of the timers, hotkeys and the SetWinEventHook callback
    ; listed in this file's header can interrupt between `Has(key)` and
    ; `ActiveAnimations[key]` and several of them call CancelAnimation - so that
    ; two-line gap could raise "key not found".
    ;
    ; That throw propagated out of RenderFrame, and the consequences were silent
    ; and total: AHK kills a timer whose callback throws, StopScheduler() below
    ; never ran, so SchedulerRunning stayed true and every later
    ; RegisterAnimation -> StartScheduler() became a no-op. No animation ran again
    ; for the rest of the session, and timeBeginPeriod(1) leaked until exit.
    for key in keys {
        try {
            if !ActiveAnimations.Has(key)          ; cancelled since the snapshot
                continue
            anim := ActiveAnimations[key]
            ; Swallowing the throw is right - one bad callback must not kill the
            ; frame timer and take every other animation with it - but swallowing
            ; it SILENTLY is what made "parallax does nothing" undiagnosable: a
            ; single throw inside SampleVelocityStep retires the drag pipeline for
            ; that whole drag, so parallax, velocity sampling and group towing all
            ; stop at once with nothing logged anywhere.
            ;
            ; Throttled per key, not globally: a callback that throws on every
            ; frame would otherwise put 65 lines a second into the log buffer, and
            ; a genuinely broken animation is exactly the case where the log has
            ; to stay readable. WriteLog buffers in RAM and is flushed by an idle
            ; one-shot, so this never touches the disk on the 15 ms path.
            try
                keepAlive := anim.Call(dt, now)
            catch as e {
                keepAlive := false
                if (!lastThrow.Has(key) || now - lastThrow[key] > 1000) {
                    if (lastThrow.Count > 64)
                        lastThrow.Clear()      ; bound it; worst case is one repeated line
                    lastThrow[key] := now
                    ; File/line/what, not just the message: "Invalid base." on its
                    ; own names neither the expression nor the module, and these
                    ; callbacks are closures several files away from here.
                    detail := ""
                    try detail := " at " e.What " " e.File ":" e.Line
                    WriteLog("animation '" key "' threw and was retired: " e.Message detail)
                }
            }
            if keepAlive
                continue
            ; Only retire what we actually ran: a callback is allowed to
            ; re-register its own key (roll-up does exactly this), and that fresh
            ; registration must not be thrown away by the finishing one.
            if (ActiveAnimations.Has(key) && ActiveAnimations[key] == anim) {
                ActiveAnimations.Delete(key)
                Anim_Forget(key)           ; an animation that ends releases its channel
            }
        }
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
    Anim_Forget(key)
}

; ==============================================================================
;  Channel ownership
; ==============================================================================

; Register `callback` under `key` and make it the sole owner of this window's
; channel, cancelling whoever held it. hwnd 0 falls back to a plain register, so
; screen-wide effects can use one call shape.
Anim_Claim(hwnd, channel, key, callback) {
    global AnimOwner, AnimOwnerKey
    if !hwnd {
        ; Still drop any slot this key used to own, or a screen-wide effect
        ; reusing a per-window key would leave that window's channel claimed by
        ; an animation that is no longer driving it.
        Anim_Forget(key)
        RegisterAnimation(key, callback)
        return
    }
    slot := hwnd "|" channel
    if (AnimOwner.Has(slot) && AnimOwner[slot] != key)
        CancelAnimation(AnimOwner[slot])   ; releases the slot through Anim_Forget
    Anim_Forget(key)                       ; this key may have owned another slot
    AnimOwner[slot]   := key
    AnimOwnerKey[key] := {hwnd: hwnd, channel: channel}
    RegisterAnimation(key, callback)
}

; The key currently driving this window's channel, or "" if nothing is.
Anim_Owner(hwnd, channel) {
    global AnimOwner
    if !hwnd
        return ""
    slot := hwnd "|" channel
    return AnimOwner.Has(slot) ? AnimOwner[slot] : ""
}

; Cancel whatever owns this window's channel. An empty channel means all of them,
; which is what a fresh drag or an explicit layout command wants.
Anim_Release(hwnd, channel := "") {
    global AnimOwner, ANIM_CHANNELS
    if !hwnd
        return
    if (channel != "") {
        slot := hwnd "|" channel
        if AnimOwner.Has(slot)
            CancelAnimation(AnimOwner[slot])
        return
    }
    for ch in ANIM_CHANNELS
        Anim_Release(hwnd, ch)
}

; Drop a key's ownership record. Called from CancelAnimation and from the
; scheduler's retirement branch, so an animation that ends of its own accord
; releases its channel without the feature having to remember to.
Anim_Forget(key) {
    global AnimOwner, AnimOwnerKey
    if !AnimOwnerKey.Has(key)
        return
    owned := AnimOwnerKey[key]
    AnimOwnerKey.Delete(key)
    slot := owned.hwnd "|" owned.channel
    ; Only release the slot if it still points at this key. A Claim that
    ; replaced us has already rewritten it, and stealing it back here would
    ; leave the new owner running unowned - the same identity guard the
    ; retirement branch in RenderFrame uses.
    if (AnimOwner.Has(slot) && AnimOwner[slot] == key)
        AnimOwner.Delete(slot)
}

QPC() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &count:=0)
    return count * 1000 / freq
}
