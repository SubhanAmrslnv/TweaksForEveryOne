; Ambient dimming - the two features that fade a window nobody is looking at,
; and the MediaCore bridge that stops them fading one that is playing.
;
; Function definitions and global initialisers only, no top-level statements.
;
; OPACITY ON A FOREIGN WINDOW IS COMPOSED, NEVER ABSOLUTE. Several unrelated
; features can want to dim the same window at once, and RS_* priorities only
; arbitrate WITHIN one flush - across flushes an absolute write is simply
; last-writer-wins. So breathing installs a named modifier LAYER
; (RS_SetAlphaLayer / RS_ClearAlphaLayer) and never touches the base the user
; chose with Shift+Alt+Wheel. WinTargetAlpha/WinCurrentAlpha hold that layer s
; numerator, not an absolute opacity.
;
; Before that, set a window to 50%, click away and back, and Focus Depth wrote
; 210 and then "Off" - the 50% was gone while CustomTrans still claimed 128.
;
; HOIST ANY PER-WINDOW PREDICATE OUT OF A PER-WINDOW LOOP. MC_IsMediaHwnd costs
; 1.7 us per window per frame; MC_AnyMedia() is the O(1) "could anything match?"
; gate, so call it once per tick and && it.
;
; MediaCore's hold window is derived from BREATHE_IDLE_MS in SyncMediaCore, so
; the two can never be set into a dim/wake flicker.
;
; Collect-then-delete when removing entries from a Map you are iterating.
; Deleting the current item shifts the remainder under the enumerator index and
; silently skips the next one - BreathingAnimatorStep shows the pattern.

ToggleBreathing() {
    global BreathingEnabled, Win, C
    BreathingEnabled := !BreathingEnabled
    SyncTray(), SaveSettings()
    if (Win && WinExist("ahk_id " Win.Hwnd))
        try C["breath"].Value := BreathingEnabled
    Notify("Breathing windows " (BreathingEnabled ? "ON" : "OFF"))
    SyncBreathingTimers()
}

global WinTargetAlpha := Map()

global WinCurrentAlpha := Map()

global WinLastActive := Map()

; These used to be installed unconditionally and merely return early when the
; feature is off - but BreathingMonitor runs WinGetList() plus IsRestorable()
; (up to six window queries and a DWM call each) over every top-level window
; five times a second. That is exactly the polling the drag pipeline was
; designed to avoid, and it ran even for users who never turn breathing on.
SyncBreathingTimers() {
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive
    if (BreathingEnabled) {
        now := QPC()
        hwnds := WinGetList()
        for hwnd in hwnds {
            if IsRestorable(hwnd) {
                ; 255 = "this layer is not dimming anything", NOT "the window is
                ; opaque". These two maps hold the breathe LAYER's numerator now;
                ; the user's own opacity is a separate factor that RenderCore
                ; multiplies in, so breathing no longer has to know about it.
                WinLastActive[hwnd] := now
                WinCurrentAlpha[hwnd] := 255
                WinTargetAlpha[hwnd] := 255
            }
        }
        SetTimer(BreathingMonitorStep, 200)
        SyncMediaCore()
        return
    }
    SetTimer(BreathingMonitorStep, 0)
    CancelAnimation("BreathingAnimator")
    ; Hand every window its opacity back before we stop animating it, or a
    ; window dimmed at the moment of the toggle stays dim for good. The commit
    ; is the point: cancelling the animator was the last thing that would ever
    ; have flushed these writes, so without it they were never applied.
    for hwnd, alpha in WinCurrentAlpha {
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_AMBIENT)
    }
    RS_Commit()
    WinTargetAlpha.Clear(), WinCurrentAlpha.Clear(), WinLastActive.Clear()
    ; Breathing is a MediaCore consumer, so its state has to be re-published here
    ; and not by each caller.
    ;
    ; SyncBreathingTimers is on every path that changes breathing - startup,
    ; ApplyUi and ToggleBreathing - whereas SyncMediaCore was only reached from
    ; ApplyUi and, at startup, as a side effect of SyncDimmerTimer. So toggling
    ; breathing with Shift+Alt+E never told MediaCore: turning it ON while nothing
    ; else wanted MediaCore left the sweep stopped, and breathing then dimmed
    ; windows that were playing video - the exact thing MediaCore exists to
    ; prevent. Turning it OFF left the sweep running for nothing. Same pattern as
    ; SyncDimmerTimer, which already ends with this call.
    SyncMediaCore()
}

; Runs on a 200 ms timer, so a throw in here is not a dropped frame - AHK kills
; a timer whose callback throws, and breathing would then be dead for the rest of
; the session with the checkbox still saying it is on.
;
; Two hazards, both from the same source: ShellEvent's HSHELL_WINDOWDESTROYED
; branch deletes the closing window from WinLastActive, WinTargetAlpha and
; WinCurrentAlpha, and it runs on the message thread, which can interrupt this
; timer between any two lines.
;
;   - Enumerating WinLastActive directly meant that delete shifted the remainder
;     under the live enumerator and silently skipped a window. Iterate a snapshot
;     of the keys instead, the same shape RenderFrame uses.
;   - WinTargetAlpha[hwnd] and WinCurrentAlpha[hwnd] were indexed unguarded. The
;     window can vanish between the IsWindow check and either read, and a missing
;     key throws. Note the target is NOT necessarily written earlier in the same
;     iteration: the else branch only assigns once the idle threshold is passed.
BreathingMonitorStep() {
    global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha, GhostWindows
    if !BreathingEnabled
        return

    try {
        MouseGetPos(,, &mHwnd)
        aHwnd := WinExist("A")
        now := QPC()

        needsAnimation := false
        ; One O(1) check instead of a 1.7 us MC_IsMediaHwnd per tracked window. When
        ; nothing is playing - the usual case - MC_IsMediaHwnd would return false for
        ; every window anyway, so short-circuiting is behaviour-identical.
        anyMedia := MC_AnyMedia()
        dimAlpha := TuneAlpha("breatheAlpha")

        keys := []
        for hwnd, unused in WinLastActive
            keys.Push(hwnd)

        for hwnd in keys {
            if !WinLastActive.Has(hwnd)              ; closed since the snapshot
                continue
            if !DllCall("IsWindow", "ptr", hwnd)
                continue

            ; The ghost owns this window's opacity outright, so keep breathing's
            ; own state neutral for it. Without this the monitor kept recording a
            ; target the animator then refused to act on, so every 200 ms tick
            ; re-registered the animator, which retired again on the next frame -
            ; restarting the scheduler and timeBeginPeriod(1) five times a second
            ; for a window nothing was fading.
            if GhostWindows.Has(hwnd) {
                WinLastActive[hwnd] := now
                WinTargetAlpha[hwnd] := 255
                WinCurrentAlpha[hwnd] := 255
                continue
            }

            lastActive := WinLastActive[hwnd]

            ; No Min() against the user's opacity any more. These are layer
            ; factors and RenderCore multiplies them, so a window the user set to
            ; 50% and then left idle lands at 50% * 70%, and breathing can never
            ; brighten a window the user deliberately dimmed - which is the only
            ; thing that Min() was ever there to prevent.
            if (hwnd == aHwnd || hwnd == mHwnd || (anyMedia && MC_IsMediaHwnd(hwnd))) {
                WinLastActive[hwnd] := now
                WinTargetAlpha[hwnd] := 255
            } else if (now - lastActive > BREATHE_IDLE_MS) {
                WinTargetAlpha[hwnd] := dimAlpha
            }

            if (!WinTargetAlpha.Has(hwnd) || !WinCurrentAlpha.Has(hwnd))
                continue
            if (WinTargetAlpha[hwnd] != WinCurrentAlpha[hwnd])
                needsAnimation := true
        }

        if (needsAnimation)
            RegisterAnimation("BreathingAnimator", BreathingAnimatorStep)
    }
}

BreathingAnimatorStep(dt:=0, now:=0) {
    global BreathingEnabled, WinTargetAlpha, WinCurrentAlpha, WinLastActive, FRAME_MS
    global GhostWindows
    if !BreathingEnabled
        return false
    if (dt <= 0)
        dt := FRAME_MS
        
    activeFades := false
    dead := []
    ; Hoisted out of the loop: this runs every frame for every tracked window.
    anyMedia := MC_AnyMedia()
    For hwnd, target in WinTargetAlpha {
        ; Collect, do not delete: removing the current item shifts the rest down
        ; under the live enumerator index, which silently skips the next window.
        if !DllCall("IsWindow", "ptr", hwnd) {
            dead.Push(hwnd)
            continue
        }
        ; Same shell-hook race as BreathingMonitorStep: the destroy branch can
        ; delete this hwnd from WinCurrentAlpha between the IsWindow check above
        ; and the read below. That throw was caught by the scheduler, which then
        ; retired the whole animator mid-fade and left every dimmed window frozen
        ; part-way until the 200 ms monitor re-registered it.
        if !WinCurrentAlpha.Has(hwnd) {
            dead.Push(hwnd)
            continue
        }

        ; Breathing yields the whole window to the ghost, and this is now a
        ; PRODUCT choice rather than an ownership workaround: the two layers
        ; would compose cleanly, but ghost 0.30 x breathe 0.70 is alpha 54 - much
        ; darker than the ghost's own 76 - so an idle ghosted window would sink
        ; below the opacity the ghost settings ask for.
        ;
        ; Yielding means CLEARING, not just skipping. A window that was already
        ; dimmed when it became a ghost would otherwise keep its breathe layer
        ; forever - nothing else owns that name - and the ghost would sit at the
        ; product anyway, which is the exact outcome this skip exists to avoid.
        ; Resetting the tracked alpha alongside it keeps breathing's own state
        ; agreeing with the layer, so un-ghosting fades from solid rather than
        ; from a value the screen never had.
        if GhostWindows.Has(hwnd) {
            RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_AMBIENT)
            WinCurrentAlpha[hwnd] := 255
            continue
        }

        if (anyMedia && MC_IsMediaHwnd(hwnd)) {
            ; Track it as awake so we stop re-queueing on every frame for the
            ; whole time something is playing. Clearing is free once clear.
            WinCurrentAlpha[hwnd] := 255
            RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_AMBIENT)
            continue
        }

        current := WinCurrentAlpha[hwnd]
        if (current == target)
            continue

        activeFades := true

        ; Rates in alpha units per millisecond, not per frame. These are the old
        ; per-frame steps (25 waking, 2 sleeping) divided by the nominal frame, so
        ; the fade looks the same at 63 fps but now holds its wall-clock duration
        ; when frames get heavy instead of turning into slow motion.
        rate := (target == 255) ? (25 / FRAME_MS) : (2 / FRAME_MS)
        step := rate * dt
        if (step < 0.5)                ; never stall on a very short frame
            step := 0.5

        if (current < target)
            current := Min(current + step, target)
        else
            current := Max(current - step, target)

        WinCurrentAlpha[hwnd] := current

        try {
            ; Integer() before the compare: alpha is applied as an integer, so a
            ; fractional current must not re-queue the same visible value.
            iv := Integer(current + 0.5)
            if (iv >= 255)
                RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_AMBIENT)
            else
                RS_SetAlphaLayer(hwnd, "breathe", iv / 255.0, RS_PRI_AMBIENT)
        }
    }

    for hwnd in dead {
        WinTargetAlpha.Delete(hwnd)
        if WinCurrentAlpha.Has(hwnd)
            WinCurrentAlpha.Delete(hwnd)
        if WinLastActive.Has(hwnd)
            WinLastActive.Delete(hwnd)
        ; CustomTrans is cleaned up by the shell hook's destroy branch, which is
        ; also where RS_RemoveHwnd / MC_RemoveHwnd happen. Doing it here as well
        ; only duplicated that, so it is left to the one owner.
    }
    return activeFades
}

; ====== Multi-Monitor Focus Dimmer ======

SyncDimmerTimer() {
    global MultiMonitorDimmerEnabled, DimmerGuis
    if (MultiMonitorDimmerEnabled) {
        SetTimer(MonitorDimmerTickStep, 200)
    } else {
        SetTimer(MonitorDimmerTickStep, 0)
        for k, g in DimmerGuis {
            FadeGui(g, 0, 0, true)
        }
        DimmerGuis.Clear()
    }
    SyncMediaCore()
}

MonitorDimmerTickStep(dt:=0, now:=0) {
    global MultiMonitorDimmerEnabled, DimmerGuis
    
    if (!MultiMonitorDimmerEnabled)
        return
        
    try count := MonitorGetCount()
    catch
        return
        
    if (count < 2)
        return
        
    try {
        MouseGetPos(&mx, &my)
        activeMon := 1
        ; Exclusive on right/bottom, like MonitorIndexAt. Inclusive bounds make
        ; the shared edge belong to both monitors, so a cursor sitting exactly on
        ; the seam kept the neighbouring monitor un-dimmed.
        activeMon := MonitorIndexAt(mx, my)
        
        Loop count {
            if (A_Index == activeMon || MC_MediaOnMonitor(A_Index)) {
                if DimmerGuis.Has(A_Index) {
                    g := DimmerGuis[A_Index]
                    DimmerGuis.Delete(A_Index)
                    FadeGui(g, 0, 0, true)
                }
            } else {
                if !DimmerGuis.Has(A_Index) {
                    MonitorGet(A_Index, &L, &T, &R, &B)
                    g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20 +E0x8000000")
                    g.BackColor := "000000"
                    RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
                    RS_Commit()
                    g.Show("NoActivate x" L " y" T " w" (R-L) " h" (B-T))
                    DimmerGuis[A_Index] := g
                    FadeGui(g, TuneAlpha("dimmerAlpha"))
                }
            }
        }
    }
}

; ====== MediaCore Integration ======

SyncMediaCore() {
    global BreathingEnabled, MultiMonitorDimmerEnabled, ProximityGhostEnabled, ParallaxEnabled
    global MediaFallbackList, BREATHE_IDLE_MS
    wanted := BreathingEnabled || MultiMonitorDimmerEnabled || ProximityGhostEnabled || ParallaxEnabled
    MC_SetFallbackList(MediaFallbackList)
    ; Keep MediaCore's hold window derived from the breathing threshold rather
    ; than left at its default; MC_HoldMs explains why they must stay tied.
    MC_SetHoldMs(BREATHE_IDLE_MS)
    MC_SetWanted(wanted, MultiMonitorDimmerEnabled, QPC())
    if wanted
        SetTimer(MC_Tick, 250)
    else
        SetTimer(MC_Tick, 0)
}

; MediaCore takes the clock as a parameter so it stays include-safe (see its
; header).  SetTimer calls its callback with no arguments, so the clock is read
; here rather than there - a callback with required parameters fails outright
; with "Invalid callback function".
MC_Tick() {
    global SchedulerRunning
    ; Tell MediaCore when something is animating so its COM sweep stays out of
    ; the frame loop's way - see MC_SweepStep.
    MC_SweepStep(QPC(), SchedulerRunning)
    ; Piggyback the render-cache sweep on a timer that is already awake. Our own
    ; overlay windows raise no shell destroy notification, so without a periodic
    ; pass their entries would sit in the last-applied caches forever - and a
    ; recycled HWND would inherit them. Skip it mid-animation too; it walks two
    ; Maps and there is no hurry.
    if !SchedulerRunning
        RS_SweepDead()
}
