#Requires AutoHotkey v2.0
#SingleInstance Force
#Include SnapCore.ahk
#Include RenderCore.ahk
#Include AnimationScheduler.ahk
#Include MediaCore.ahk
#Include FeatureFlags.ahk
#Include TuningRegistry.ahk
#Include DiagnosticsLog.ahk
#Include SettingsStore.ahk
#Include SettingsWindow.ahk
#Include FeatureToggles.ahk
#Include InputBindings.ahk
#Include WindowCommands.ahk
#Include MonitorGeometry.ahk
#Include OverlayGui.ahk
#Include StealthPanic.ahk
#Include ProcessLifecycle.ahk
Persistent
DetectHiddenWindows false
SetWinDelay -1
#MaxThreadsPerHotkey 2

; Every thread inherits this, and timer threads have no other way to get it.
; Without it the timers ran on the default coordinate mode while only a handful
; of hotkey bodies set Screen locally, so hot corners, the monitor dimmer and
; the fly-to-mouse minimize rect compared client-relative mouse coordinates
; against screen rectangles. Nothing here wants client coordinates.
CoordMode "Mouse", "Screen"

; Idle cost: no debug history buffers, no key history ring, below-normal
; priority so this never competes with the app you are actually using.
ListLines False
KeyHistory 0
ProcessSetPriority "BelowNormal"

; Window Tweaks - snapping, ice glide, always-on-top, position memory, taskbar.
; Shift+Alt+W opens the settings window. See GUIDE.md.


global POS_FILE := A_ScriptDir "\window-positions.ini"







; There is no startup code here any more. LoadSettings(), RotateLog(),
; SyncTray(), BuildTray() and the first WriteLog() all run from Boot() in
; ProcessLifecycle.ahk, which the last line of this file calls once every
; declaration in the program has run. scripts\Check-Split.ps1 check 8 fails any
; top-level call that reappears here.

; =========================================================== Settings ===========================================================



















; Written values, so an unchanged key is never written again.
;
; Measured: one IniWrite costs 771 us, and SaveSettings writes 45 keys - 34.6 ms
; of blocking disk I/O. It runs on every checkbox click, every debounced keystroke
; in the settings window, and every toggle hotkey, so Shift+Alt+S used to stall the
; whole process for 35 ms. A toggle changes exactly one key; writing only that one
; costs 0.8 ms, and SaveSettings() no longer writes at all - it queues.








; =========================================================== Start with Windows ===========================================================





















ForgetPositions() {
    global POS_FILE, PendingPositions
    try {
        SetTimer(WritePositions, 0)
        PendingPositions.Clear()     ; or the buffered ones rewrite the file
        if FileExist(POS_FILE)
            FileDelete(POS_FILE)
        Notify("Saved window positions cleared")
    }
}


















global PendingTransMsg := ""










; Boot() registers OnMessage(0x1000) for the icons this Map holds.







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
; Behind its flag rather than re-sending Alt+F4 from the body: with the
; feature off the key is simply not claimed, so Windows' own close runs and
; nothing sits in front of Alt+F4 at all.
#HotIf GravityCloseEnabled
$!F4::GravityClose()
#HotIf

GravityClose() {
    hwnd := WinExist("A")
    if !hwnd {
        Send("!{F4}")
        return
    }

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls == "" || cls == "AutoHotkeyGUI" || cls == "WorkerW"
        || cls == "Progman" || cls == "Shell_TrayWnd") {
        Send("!{F4}")
        return
    }

    ; Maximized and full-screen windows are where PrintWindow costs the most (a
    ; whole-screen bitmap) and where the effect reads as a glitch rather than an
    ; animation, so they close the normal way.
    try {
        if (WinGetMinMax(hwnd) != 0) {
            Send("!{F4}")
            return
        }
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        Send("!{F4}")
        return
    }
    if (w < 1 || h < 1) {
        Send("!{F4}")
        return
    }

    ; Capture window visual
    hbm := 0
    success := false
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    if hdcDest {
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
        if (hbm && hdcMem) {
            oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            ; PW_RENDERFULLCONTENT = 2
            success := DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
            DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
        }
        if hdcMem
            DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    }

    if !success {
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
        Send("!{F4}")
        return
    }

    ; Order matters: put the bitmap copy on screen FIRST, then hide the real
    ; window underneath it. Hiding first left a frame with neither visible - a
    ; black flash of whatever is behind the window, right at the start of the
    ; animation. The copy is pixel-identical and always-on-top, so covering the
    ; original before it disappears is seamless.
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "GravityCloseAnim")
    animGui.MarginX := 0, animGui.MarginY := 0
    pic := animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("x" x " y" y " w" w " h" h " NoActivate")

    try RS_SetAlphaLayer(hwnd, "gravity", 0.0, RS_PRI_ANIM)
    RS_Commit()

    startW := w, startH := h
    startX := x, startY := y

    animKey := "Gravity_" animGui.Hwnd
    start := QPC()
    ms := Tune("animGravityMs")
    ; Owns the bitmap and the GUI: whichever way this animation ends, both are
    ; released exactly once. The bitmap used to leak on every path except a clean
    ; finish - one 8 MB screen-compatible bitmap per Alt+F4.
    finished := false
    Cleanup() {
        if finished
            return
        finished := true
        gh := 0
        try gh := animGui.Hwnd
        try animGui.Destroy()
        if gh
            RS_RemoveHwnd(gh)      ; our own GUIs raise no shell destroy event
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
    }

    GravityStep(dt, now) {
        if !DllCall("IsWindow", "ptr", animGui.Hwnd) {
            Cleanup()
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            Cleanup()
            try PostMessage(0x0010, 0, 0, , hwnd) ; WM_CLOSE
            SetTimer(CheckGravityClose.Bind(hwnd), -400)
            return false
        }

        ; Falling under gravity is s = 1/2*a*t^2 - quadratic, not cubic. Cubic made
        ; the window hang almost still and then snap away at the end, which reads as
        ; a stutter rather than a drop. Quadratic is both correct and smoother.
        ease := t * t

        curW := Round(startW * (1 - ease * 0.95))
        curH := Round(startH * (1 - ease * 0.95))

        curX := Round(startX + (startW - curW) / 2)
        curY := Round(startY + ease * (startH * 0.8) + (startH - curH) / 2)

        try {
            animGui.Move(curX, curY, curW, curH)
            pic.Move(0, 0, curW, curH)

            if (t > 0.4) {
                alpha := Clamp(Round(255 * (1 - ((t - 0.4) / 0.6))), 0, 255)
                RS_SetAlpha(animGui.Hwnd, alpha, RS_PRI_ANIM)
            }
        }
        return true
    }

    RegisterAnimation(animKey, GravityStep)
}

; The window refused (or has not yet processed) WM_CLOSE - a "Save changes?"
; prompt, typically. Give it its opacity back, and actually commit: without the
; commit the window stayed at alpha 0, alive and focused but invisible.
CheckGravityClose(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try RS_ClearAlphaLayer(hwnd, "gravity", RS_PRI_ANIM)
    RS_Commit()
}

global FocusModeEnabled := false
global FocusGuis := []
global SpotlightTarget := {x: 0, y: 0, w: 0, h: 0}
global SpotlightCurrent := {x: 0, y: 0, w: 0, h: 0}
global FocusBounds := {x: 0, y: 0, w: 0, h: 0}
; Snapshotted when focus mode is entered rather than read per layer per frame:
; FocusAnimatorStep runs three layers at 63 fps, and the shape of the vignette
; must not change halfway through a session anyway.
global FocusFeather := 70, FocusRadius := 40
global FocusTargetHwnd := 0

ToggleFocusMode() {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FocusTargetHwnd
    global FocusFeather, FocusRadius
    ; Decide before flipping the flag. Flipping first and then bailing out left
    ; the flag saying "on" with no overlays, so the next press took the off
    ; branch and focus mode could never be entered again.
    if (!FocusModeEnabled && FocusGuis.Length)
        return
    FocusModeEnabled := !FocusModeEnabled

    if (FocusModeEnabled) {
        ; Three stacked layers whose relative weights make the falloff; the
        ; setting scales all three so the shape is preserved at any strength.
        FocusFeather := Tune("focusFeather")
        FocusRadius  := Tune("focusRadius")
        peak := TuneAlpha("focusAlpha")
        alphas := [Round(peak * 140 / 240), Round(peak * 200 / 240), peak]
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        FocusBounds := {x: vx, y: vy, w: vw, h: vh}
        
        loop 3 {
            g := Gui("-Caption -DPIScale +ToolWindow +E0x20", "FocusModeOverlay" A_Index)
            g.BackColor := "000000"
            g.MarginX := 0, g.MarginY := 0
            g.Show("x" vx " y" vy " w" vw " h" vh " NoActivate")
            RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
            FocusGuis.Push({gui: g, targetAlpha: alphas[A_Index], currentAlpha: 0})
        }
        
        FocusTargetHwnd := WinExist("A")
        placed := false
        if (FocusTargetHwnd && IsRestorable(FocusTargetHwnd)) {
            try {
                if (WinGetMinMax(FocusTargetHwnd) == 0) {
                    WinGetPos(&tx, &ty, &tw, &th, FocusTargetHwnd)
                    SpotlightCurrent := {x: tx, y: ty, w: tw, h: th}
                    SpotlightTarget := {x: tx, y: ty, w: tw, h: th}
                    placed := true
                }
            }
        }
        if (!placed) {
            SpotlightCurrent := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
            SpotlightTarget := {x: vx + vw/2, y: vy + vh/2, w: 0, h: 0}
        }
        
        ZOrderSpotlight()
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
        SetTimer(FocusMonitorStep, 50)
        Notify("Focus Mode ON")
    } else {
        CancelAnimation("FocusAnimator")
        SetTimer(FocusMonitorStep, 0)
        ; 'layer', not 'fg' - case-insensitive identifiers make 'fg' the global
        ; foreground colour FG.
        ; FadeGui destroys the layer itself when it reaches 0, which removes the
        ; old 300 ms fade / 350 ms destroy-timer race.
        ; Explicitly 300 ms rather than the shared Overlay fade. These are three
        ; stacked FULL-SCREEN vignette layers; at the ~110 ms a small overlay
        ; wants, the whole desktop snaps from dark to bright and reads as a
        ; flash. Duration here is a property of what is being faded, not a
        ; preference, so it is not a setting.
        for layer in FocusGuis
            FadeGui(layer.gui, 0, 300, true)
        FocusGuis := []
        Notify("Focus Mode OFF")
    }
}


ZOrderSpotlight() {
    global FocusGuis, FocusTargetHwnd
    if !FocusTargetHwnd || !DllCall("IsWindow", "ptr", FocusTargetHwnd)
        return
        
    isTopmost := 0
    try isTopmost := WinGetExStyle(FocusTargetHwnd) & 0x8
    prevHwnd := FocusTargetHwnd
    for layer in FocusGuis {
        if (isTopmost)
            WinSetExStyle("+0x8", layer.gui.Hwnd)
        else
            WinSetExStyle("-0x8", layer.gui.Hwnd)
        try RS_SetZOrder(layer.gui.Hwnd, prevHwnd, 0x0013, RS_PRI_ANIM)
        prevHwnd := layer.gui.Hwnd
    }
    ; Called from FocusMonitorStep on a focus change, which does not always
    ; register an animation - so commit rather than hoping someone else will.
    RS_Commit()
}

FocusMonitorStep() {
    global FocusModeEnabled, FocusTargetHwnd, SpotlightTarget
    if !FocusModeEnabled
        return
        
    hwnd := WinExist("A")
    if (hwnd != FocusTargetHwnd) {
        FocusTargetHwnd := hwnd
        ZOrderSpotlight()
    }
    
    if (hwnd && IsRestorable(hwnd) && WinGetMinMax(hwnd) == 0) {
        WinGetPos(&tx, &ty, &tw, &th, hwnd)
        newTarget := {x: tx, y: ty, w: tw, h: th}
    } else {
        MouseGetPos(&mx, &my)
        newTarget := {x: mx, y: my, w: 0, h: 0}
    }
    
    if (SpotlightTarget.x != newTarget.x || SpotlightTarget.y != newTarget.y || SpotlightTarget.w != newTarget.w || SpotlightTarget.h != newTarget.h) {
        SpotlightTarget := newTarget
        RegisterAnimation("FocusAnimator", FocusAnimatorStep)
    }
}

FocusAnimatorStep(dt:=0, now:=0) {
    global FocusModeEnabled, FocusGuis, SpotlightTarget, SpotlightCurrent, FocusBounds, FRAME_MS
    global FocusFeather, FocusRadius
    if !FocusModeEnabled || !FocusGuis.Length
        return false
    if (dt <= 0)
        dt := FRAME_MS

    spot := SpotlightCurrent
    t    := SpotlightTarget

    ; Frame-rate-independent exponential smoothing.
    ;
    ; A flat 0.15 per frame meant the spotlight caught up in a fixed number of
    ; FRAMES, so it drifted lazily whenever frames were slow and snapped when they
    ; were fast. Compounding the per-frame retention over the real elapsed time
    ; gives the same feel at any frame rate: after dt ms, the remaining distance is
    ; 0.85^(dt/FRAME_MS).
    f := 1 - (0.85 ** (dt / FRAME_MS))
    spot.x += (t.x - spot.x) * f
    spot.y += (t.y - spot.y) * f
    spot.w += (t.w - spot.w) * f
    spot.h += (t.h - spot.h) * f

    finished := true
    if (Abs(spot.x - t.x) < 0.5 && Abs(spot.y - t.y) < 0.5 && Abs(spot.w - t.w) < 0.5 && Abs(spot.h - t.h) < 0.5) {
        spot.x := t.x
        spot.y := t.y
        spot.w := t.w
        spot.h := t.h
    } else {
        finished := false
    }

    hx := Round(spot.x - FocusBounds.x)
    hy := Round(spot.y - FocusBounds.y)
    hw := Round(spot.w)
    hh := Round(spot.h)

    for layer in FocusGuis {
        pad := (A_Index - 1) * FocusFeather

        px := hx - pad
        py := hy - pad
        pw := hw + pad*2
        ph := hh + pad*2

        region := "0-0 W" FocusBounds.w " H" FocusBounds.h

        if (pw > 0 && ph > 0) {
            region .= " " px "-" py " W" pw " H" ph " R" (FocusRadius + pad) "-" (FocusRadius + pad)
        }

        ; WinSetRegion rebuilds a GDI region, and this runs for three full-screen
        ; overlays every frame. RS_LastRegion already skips an identical string,
        ; but only if we do not build a different one for the same pixels - hence
        ; the integer rounding above rather than per-layer float maths.
        try RS_SetRegion(layer.gui.Hwnd, region, RS_PRI_ANIM)

        if (layer.currentAlpha != layer.targetAlpha) {
            finished := false
            ; Per-millisecond, matching the old 10-per-frame at the nominal rate.
            step := (10 / FRAME_MS) * dt
            if (step < 0.5)
                step := 0.5
            if (layer.currentAlpha < layer.targetAlpha)
                layer.currentAlpha := Min(layer.currentAlpha + step, layer.targetAlpha)
            else
                layer.currentAlpha := Max(layer.currentAlpha - step, layer.targetAlpha)

            try RS_SetAlpha(layer.gui.Hwnd, Integer(layer.currentAlpha + 0.5), RS_PRI_ANIM)
        }
    }
    return !finished
}






; =========================================================== Drag detection ===========================================================
; The shell raises MOVESIZESTART / MOVESIZEEND around every window drag, so we
; hook those instead of the mouse. A ~LButton hotkey would make AutoHotkey
; install a low-level mouse hook that wakes on every mouse move - measured at
; ~1.6% of a core just sitting there. MOVESIZEEND also fires after the OS modal
; move loop has finished, which is precisely when repositioning is safe.
global DragHwnd := 0, DragL := 0, DragT := 0, DragR := 0, DragB := 0
global VelX := 0, VelY := 0, PrevX := 0, PrevY := 0
global CurrentDragAlpha := 255
; Not a "Fast" callback. Fast mode runs on top of whatever script thread the
; event interrupted, and this one is not trivial: it queries the window, starts
; an animation and arms a timer. Registering an animation from inside an
; arbitrary interruption point is what corrupted the scheduler's enumeration.
; The event is WINEVENT_OUTOFCONTEXT, so it arrives through our own message
; queue either way and nothing here needs fast-mode semantics.
; Keep the hook handles: without them the hooks can never be unhooked and the
; callbacks can never be freed. Bye() releases all four.
;
; Declared here, INSTALLED by InstallDragHooks() from Boot(). As top-level
; initialisers the two SetWinEventHook calls began delivering MOVESIZESTART and
; menu-popup events while thousands of later declarations had not run - and
; WinEvent queries the window, registers an animation and arms a timer.
global WinEventCb := 0, WinEventHook := 0
global MenuEventCb := 0, MenuEventHook := 0

InstallDragHooks() {
    global WinEventCb, WinEventHook, MenuEventCb, MenuEventHook
    WinEventCb := CallbackCreate(WinEvent, , 7)
    WinEventHook := DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
            "ptr", WinEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

    MenuEventCb := CallbackCreate(MenuEvent, , 7)
    MenuEventHook := DllCall("SetWinEventHook", "uint", 0x0006, "uint", 0x0006, "ptr", 0,
            "ptr", MenuEventCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")
}

MenuEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global ContextMenuAnimEnabled
    if (!ContextMenuAnimEnabled || !hwnd || idObject != 0 || idChild != 0)
        return
        
    ; Both queries need a catch, not a bare `try`. A failed WinGetClass leaves cls
    ; unset and a failed WinGetPos leaves w/h unset, and the next line reads them -
    ; outside the try, in a SetWinEventHook callback. Menu windows (#32768) are
    ; created and destroyed constantly, so losing the race here is routine and the
    ; result was an error dialog on a random right-click.
    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls != "#32768")
        return

    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    ; Through the pipeline, not WinSetTransparent/WinSetRegion directly.
    ; MenuAnimStep is a scheduler callback, and the scheduler's contract is that
    ; callbacks only QUEUE - a direct Win32 write from inside the produce phase
    ; skips the batching, the diffing and the priority arbitration, and rebuilds
    ; a GDI region for a menu that RS_LastRegion would have skipped.
    RS_SetAlpha(hwnd, 0, RS_PRI_ANIM)
    RS_Commit()

    animKey := "MenuAnim_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 150

    MenuAnimStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd)) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            RS_SetAlpha(hwnd, "Off", RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        curH := Round(h * ease)
        if (curH > 0) {
            RS_SetRegion(hwnd, "0-0 w" w " h" curH, RS_PRI_ANIM)
            RS_SetAlpha(hwnd, 255, RS_PRI_ANIM)
        }
        return true
    }
    RegisterAnimation(animKey, MenuAnimStep)
}

WinEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global SnapEnabled, RestoreEnabled, ParallaxEnabled
    global DragHwnd, DragL, DragT, DragR, DragB, VelX, VelY, PrevX, PrevY
    global CurrentDragAlpha          ; assigned below - without this it is a local and the reset never lands
    if (idObject != 0 || idChild != 0)
        return
    ; ParallaxEnabled belongs here too: the drag-transparency effect is driven
    ; entirely from this hook, so leaving it out made it silently depend on
    ; snapping or position memory also being switched on.
    if (!SnapEnabled && !RestoreEnabled && !ParallaxEnabled)
        return
    if (event = 0x000A) {                    ; MOVESIZESTART
        if (DragHwnd != 0 && DragHwnd != hwnd) {
            CancelAnimation("SampleVelocity")
            global GhostWindows
            if (!GhostWindows.Has(DragHwnd))
                StartFadeBackAlpha(DragHwnd, CurrentDragAlpha)
        }
        DragHwnd := 0
        ; allowMax: see the note on IsSnappable. Windows un-maximizes the window
        ; as the drag begins, so by the time SampleVelocityStep first runs it is a
        ; normal window - but the event that STARTS the pipeline arrives before
        ; that, and gating on the strict form meant dragging a maximized window
        ; got no velocity sampling, no drag transparency and no glide at all.
        if !IsSnappable(hwnd, true)
            return
        if !GetRects(hwnd, &sL, &sT, &sR, &sB, &sx, &sy)
            return
        ; The user has taken the window. Nothing else may drive its position or
        ; its opacity until the drag ends.
        ;
        ; Region is deliberately NOT released, even though the hand-written list
        ; this replaces named Unroll_. Cancelling a region animation mid-flight
        ; strands the window clipped to a partial height, because only its
        ; terminal frame clears the region - and nothing short of the panic key
        ; or exit puts that back. Letting the unroll finish is self-healing and
        ; costs nothing: a drag does not touch the region, so the two do not
        ; fight. That the old list cancelled it was a latent bug, not a rule.
        Anim_Release(hwnd, "geom")
        Anim_Release(hwnd, "alpha")

        DragHwnd := hwnd, DragL := sL, DragT := sT, DragR := sR, DragB := sB
        VelX := 0, VelY := 0, PrevX := sL, PrevY := sT
        CurrentDragAlpha := 255
        RegisterAnimation("SampleVelocity", SampleVelocityStep)
        return
    }

    if (hwnd != DragHwnd)                    ; MOVESIZEEND
        return
    CancelAnimation("SampleVelocity")
    DragHwnd := 0
    ; Capture the start rect into the closure. It used to be read from the
    ; globals 50 ms later, so a second drag beginning inside that window
    ; overwrote them and this drag was measured against the wrong origin.
    sL := DragL, sT := DragT, sR := DragR, sB := DragB
    sAlpha := CurrentDragAlpha
    SetTimer(() => FinishDrag(hwnd, sL, sT, sR, sB, sAlpha), -50)    ; defer: FinishDrag enumerates windows
}

; The drag-transparency ramp, in one place. Both drag paths call it: the gain used
; to be written out longhand at each of them, which is exactly how they drifted
; apart before (see the note in AltDragMove).
;
; It is a ramp between two SPEEDS rather than a gain per px/s, because a gain
; cannot be calibrated by eye. The old form, 255 - speed * 0.06, returned 225/255
; at an ordinary 400 px/s drag - 88% opacity, which nobody can see - and reached
; the floor only past 3200 px/s, so an honest description of the feature was "does
; nothing unless you flick". Naming both ends makes "invisible at a normal drag
; speed" a value that can be read off the settings page instead of a constant
; buried on a 15 ms path.
;
; Returns the fraction as well as the alpha: the caller needs to know whether the
; ramp is engaged at all, which it used to infer from a magic "alpha < 250".
ParallaxAlpha(speed) {
    lo := Tune("parallaxFrom")
    hi := Tune("parallaxFull")
    if (hi <= lo)
        hi := lo + 1
    f := Clamp((speed - lo) / (hi - lo), 0, 1)
    return {alpha: Round(255 - f * (255 - TuneAlpha("parallaxMin"))), fade: f}
}

; DragFullWindows is a hard functional dependency of every drag-driven effect, and
; the failure is completely silent: with it off Windows drags a hollow outline, so
; the window rect does not move until release, SampleVelocityStep measures zero
; speed on every frame, and parallax and the ice glide both do nothing at all.
; That was documented in CLAUDE.md and checked by Install.ps1, neither of which
; helps someone who turned the Windows setting off afterwards.
CheckDragFullWindows() {
    global ParallaxEnabled, GlideEnabled
    if (!ParallaxEnabled && !GlideEnabled)
        return
    on := 1
    try {
        buf := Buffer(4, 0)
        if DllCall("SystemParametersInfoW", "uint", 0x26, "uint", 0, "ptr", buf, "uint", 0)
            on := NumGet(buf, 0, "int")
    }
    if (on)
        return
    WriteLog("DragFullWindows is off - drag transparency and ice glide cannot work")
    Notify("Windows is dragging window outlines only.`nTurn on Show window contents while dragging, or the drag effects do nothing.")
}

SampleVelocityStep(dt, now) {
    global DragHwnd, VelX, VelY, PrevX, PrevY, ParallaxEnabled, CurrentDragAlpha, FRAME_MS, DEBUG
    if !DragHwnd {
        return false
    }
    ; A window destroyed mid-drag never delivers MOVESIZEEND, so DragHwnd stays set
    ; and GetRects fails on every frame from then on. Returning true there held the
    ; 15 ms frame loop and timeBeginPeriod(1) open for the rest of the session.
    if !DllCall("IsWindow", "ptr", DragHwnd) {
        DragHwnd := 0
        return false
    }
    if !GetRects(DragHwnd, &L, &T, &R, &B, &x, &y)
        return true
    ; Velocity is pixels per SECOND, not pixels per frame.
    ;
    ; This function is handed dt and used to ignore it: the old EMA smoothed
    ; the raw per-frame displacement, so every constant downstream - the throw
    ; gain, the monitor-throw and tilt thresholds, the parallax opacity ramp,
    ; the group-break test - was silently calibrated to a 15 ms frame. The
    ; scheduler clamps dt to three frames but does not guarantee it, so under
    ; load the same hand motion reported up to 3x the velocity and the same
    ; flick threw the window three times as far. Nothing else about the drag
    ; was frame-rate dependent; this was.
    ;
    ; The smoothing constant is a time constant rather than a per-frame ratio
    ; for the same reason. tau = 30 ms reproduces the old 0.4 blend exactly at
    ; the nominal frame and holds that response when frames get heavy.
    if (dt <= 0)
        dt := FRAME_MS
    k := 1 - Exp(-dt / 30.0)
    VelX := VelX + (((L - PrevX) / dt * 1000) - VelX) * k
    VelY := VelY + (((T - PrevY) / dt * 1000) - VelY) * k
    vX := L - PrevX
    vY := T - PrevY
    PrevX := L, PrevY := T
    
    global MagneticGroupsEnabled, MagGroups
    if (MagneticGroupsEnabled && (vX != 0 || vY != 0) && MagGroups.Has(DragHwnd)) {
        ; vX/vY are still raw per-frame deltas here, so this threshold is
        ; converted rather than re-derived: 25 px per 15 ms frame is ~1650 px/s.
        if (Abs(vX) / dt * 1000 > 1650 || Abs(vY) / dt * 1000 > 1650) {
            UngroupWindow(DragHwnd)
        } else {
            ; Queued, not WinMove'd. This runs inside the produce phase of the
            ; frame loop, where the scheduler's contract says callbacks may only
            ; write through RS_*; a direct WinMove skipped the DeferWindowPos
            ; batching and, at DRAG priority, fought any animation still running
            ; on the towed window instead of overriding it cleanly.
            for other in MagGroups[DragHwnd] {
                if (other != DragHwnd && DllCall("IsWindow", "ptr", other)) {
                    try {
                        WinGetPos(&ox, &oy, &ow, &oh, other)
                        RS_SetPos(other, ox + vX, oy + vY, ow, oh, RS_PRI_DRAG)
                    }
                }
            }
        }
    }
    
    global GhostWindows
    if (ParallaxEnabled && !GhostWindows.Has(DragHwnd)) {
        speed := Sqrt(VelX * VelX + VelY * VelY)
        p := ParallaxAlpha(speed)

        ; dt-based, like the velocity EMA above it. The old 0.7/0.3 blend was the
        ; last frame-rate-dependent term left on this path: a ~45 ms lag at the
        ; nominal frame and three times that once frames get heavy, which on top of
        ; an already-weak ramp meant a short drag ended before the fade had gone
        ; anywhere at all.
        ka := 1 - Exp(-dt / 45.0)
        CurrentDragAlpha := CurrentDragAlpha + (p.alpha - CurrentDragAlpha) * ka

        ; Engaged, not "close enough to solid". The ramp itself says whether it
        ; wants this window dimmed; the old alpha < 250 test threw away the first
        ; five units of every fade and left the layer installed on the way out.
        if (p.fade > 0 || CurrentDragAlpha < 254) {
            ; "It does not fade" is not a diagnosable report on its own: the speed,
            ; the ramp and the composed alpha are all invisible from outside the
            ; process. With the debug log on, this says which of the three is wrong.
            ; Throttled, because this is a 15 ms path - WriteLog buffers in RAM but
            ; is not free.
            static lastLog := 0
            if (DEBUG && (now - lastLog > 250)) {
                lastLog := now
                WriteLog("drag speed=" Round(speed) " px/s fade=" Round(p.fade, 2)
                    . " alpha=" Round(CurrentDragAlpha) "/255")
            }
            RS_SetAlphaLayer(DragHwnd, "drag", CurrentDragAlpha / 255.0, RS_PRI_DRAG)
        } else {
            RS_ClearAlphaLayer(DragHwnd, "drag", RS_PRI_DRAG)
        }
    }
    
    global SmartGridEnabled, GridActive
    if (SmartGridEnabled && GetKeyState("Shift", "P")) {
        if (!GridActive)
            ShowSmartGrid()
        UpdateSmartGrid()
    } else if (GridActive) {
        HideSmartGrid()
    }
    
    return true
}

FinishDrag(hwnd, startL, startT, startR, startB, startA) {
    global MIN_DRAG, ParallaxEnabled
    if !DllCall("IsWindow", "ptr", hwnd)
        return

    global GridActive, GridHoverZone
    if (GridActive) {
        ; HideSmartGrid must run even if ApplyGridZone fails, or the zone overlays
        ; are stranded on screen with nothing left that can take them down.
        if (GridHoverZone > 0)
            try ApplyGridZone(hwnd, GridHoverZone)
        HideSmartGrid()
        global GhostWindows
        if (!GhostWindows.Has(hwnd))
            StartFadeBackAlpha(hwnd, startA)
        return
    }

    global GhostWindows
    if (!GhostWindows.Has(hwnd))
        StartFadeBackAlpha(hwnd, startA)

    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - startL) < MIN_DRAG && Abs(eT - startT) < MIN_DRAG
        && Abs(eR - startR) < MIN_DRAG && Abs(eB - startB) < MIN_DRAG)
        return
    minMax := 0
    try minMax := WinGetMinMax(hwnd)
    catch
        return
    if (minMax != 0) {                       ; Windows' own snap maximised it
        WriteLog("skip: window ended maximized")
        return
    }

    WriteLog(Format("drag end hwnd={1} frame L={2} T={3} R={4} B={5}", hwnd, eL, eT, eR, eB))
    SnapWindow(hwnd, eL, eT, eR, eB, ex, ey)
}

StartFadeBackAlpha(hwnd, startA) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (startA >= 254) {
        RS_ClearAlphaLayer(hwnd, "drag", RS_PRI_DRAG)
        RS_Commit()
        return
    }
    animKey := "FadeBack_" hwnd
    start := QPC()
    ms := 190
    FadeBackStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        t := (now - start) / ms
        if (t >= 1) {
            ; Clear, not "solid": the window goes back to whatever opacity the
            ; user chose for it, which a hard 255 used to throw away silently.
            RS_ClearAlphaLayer(hwnd, "drag", RS_PRI_DRAG)
            return false
        }
        ; Ease out: the window should rush back to solid the instant you let go,
        ; then settle. A linear ramp made the release feel sluggish.
        e := 1 - (1 - t) * (1 - t)
        RS_SetAlphaLayer(hwnd, "drag", (startA + (255 - startA) * e) / 255.0, RS_PRI_DRAG)
        return true
    }
    Anim_Claim(hwnd, "alpha", animKey, FadeBackStep)
}

SnapWindow(hwnd, L, T, R, B, winX, winY) {
    global SnapEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global GlideEnabled, GLIDE_THROW, GLIDE_MAX, VelX, VelY
    
    global MonitorThrowEnabled
    if (MonitorThrowEnabled && (Abs(VelX) > 1000 || Abs(VelY) > 1000)) {
        if ThrowWindowToNextMonitor(hwnd, L, T, R - L, B - T, VelX, VelY)
            return
    }

    ; Carry the release speed forward, so a flick keeps travelling instead of
    ; stopping dead where you let go.
    tx := 0, ty := 0
    if GlideEnabled {
        ; 0.18 px of travel per px/s of release speed, which is the old
        ; "* 12 per px/frame" expressed in the new unit (12 * 0.015).
        tx := Clamp(Round(VelX * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
        ty := Clamp(Round(VelY * GLIDE_THROW * 0.18), -GLIDE_MAX, GLIDE_MAX)
    }
    pL := L + tx, pT := T + ty, pR := R + tx, pB := B + ty
    KeepOnScreen(hwnd, &pL, &pT, &pR, &pB, tx, ty)

    if (SnapEnabled) {
        ; Reach scales with how fast the window was released.
        ;
        ; A fixed 30 px meant a slow, deliberate placement got exactly the same
        ; yank as a hard flick, so parking a window a few pixels off an edge on
        ; purpose was impossible without switching the feature off entirely.
        ; Slow now reaches less and fast reaches further, which is also what
        ; "momentum increases attraction" means physically. snapAdapt 0
        ; reproduces the old fixed behaviour exactly.
        spd   := Sqrt(VelX * VelX + VelY * VelY)
        adapt := Tune("snapAdapt")
        reach := SNAP_DISTANCE * (1 + adapt * (Min(spd, 900) / 900 * 2 - 1))
        if (reach < 1)
            reach := 1

        ; Direction of travel per axis, so a line the window is moving away
        ; from stops competing with the one it is heading for.
        dirX := (VelX > 0) ? 1 : ((VelX < 0) ? -1 : 0)
        dirY := (VelY > 0) ? 1 : ((VelY < 0) ? -1 : 0)

        ; Snap is judged from where the throw would land, not where you let go.
        CollectEdges(hwnd, pL, pT, pR, pB, &vLines, &hLines, NEIGHBOUR_PROX)
        if !ComputeSnap(pL, pT, pR, pB, vLines, hLines, Round(reach), &newL, &newT
                      , CORNER_BOOST, dirX, dirY, Tune("snapHyst"))
            newL := pL, newT := pT
    } else {
        newL := pL, newT := pT
    }

    if (newL = L && newT = T) {
        RememberPosition(hwnd)
        global MomentumTiltEnabled
        if (MomentumTiltEnabled && (Abs(VelX) > 200 || Abs(VelY) > 200))
            JelloBounce(hwnd, winX, winY, VelX, VelY)
        return
    }

    ; Frame space -> WinMove space; they differ by the invisible DWM border.
    destX := winX + (newL - L)
    destY := winY + (newT - T)

    ; Everything that should happen WHEN THE WINDOW LANDS is collected into one
    ; handler and handed to Glide, which invokes it from the frame where it puts
    ; the window down. It used to be two parallel SetTimer calls armed for
    ; "glideMs from now", which raced the glide's own last frame by a frame or two
    ; and - worse - still fired if a new drag had cancelled the glide in the
    ; meantime, bouncing a window the user had already grabbed again.
    ;
    ; Both effects were originally applied immediately, which is why neither
    ; worked: the bounce was overwritten by every glide frame (Map keys enumerate
    ; sorted, so "Bounce_" produced before "Glide_"), and the seam flash hung in
    ; empty space at the destination for up to 650 ms before the window arrived.
    ; W/H are hoisted out of the seam-flash guard on purpose: the magnetic-groups
    ; block further down reads them unconditionally, so with seam flash off and
    ; magnetic groups on they were UNSET. SnapWindow runs from FinishDrag's -50 ms
    ; one-shot, so that throw killed the tail of the drag pipeline - no glide, no
    ; VerifySnap, window left wherever the OS dropped it.
    W := R - L
    H := B - T

    global SeamFlashEnabled
    seams := []
    if (SeamFlashEnabled) {
        if (newL != pL) {
            for v in vLines {
                if (Abs(newL - v) < 2) {
                    seams.Push([newL - 1, newT, 3, H])
                    break
                }
                if (Abs(newL + W - v) < 2) {
                    seams.Push([newL + W - 1, newT, 3, H])
                    break
                }
            }
        }
        if (newT != pT) {
            for hLine in hLines {
                if (Abs(newT - hLine) < 2) {
                    seams.Push([newL, newT - 1, W, 3])
                    break
                }
                if (Abs(newT + H - hLine) < 2) {
                    seams.Push([newL, newT + H - 1, W, 3])
                    break
                }
            }
        }
    }
    
    global MagneticGroupsEnabled
    if (MagneticGroupsEnabled && (newL != pL || newT != pT)) {
        if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
            newR := newL + W
            newB := newT + H
            for other in WinGetList() {
                if (other = hwnd || !IsSnappable(other))
                    continue
                if (GetRects(other, &oL, &oT, &oRight, &oB, &ox, &oy)) {
                    touches := false
                    if ((Abs(newL - oRight) < 2 || Abs(newR - oL) < 2) && (newT < oB && newB > oT))
                        touches := true
                    else if ((Abs(newT - oB) < 2 || Abs(newB - oT) < 2) && (newL < oRight && newR > oL))
                        touches := true
                    
                    if (touches) {
                        GroupWindows(hwnd, other)
                    }
                }
            }
        }
    }

    ; Physics: if momentum carried us further than the snap allowed, we crashed
    ; into a wall.
    ; "The snap stopped us short of where the throw was heading" - which is the
    ; same subtraction whichever way we were travelling. This was written as two
    ; branches per axis computing the identical expression; the only thing the
    ; sign test contributed was excluding the case where the snap carried us
    ; FURTHER than the throw, which is not a crash.
    crashX := 0, crashY := 0
    if (Abs(VelX) > 100 && tx != 0 && Abs(newL - L) < Abs(tx))
        crashX := tx - (newL - L)
    if (Abs(VelY) > 100 && ty != 0 && Abs(newT - T) < Abs(ty))
        crashY := ty - (newT - T)

    landed := OnSnapLanded.Bind(hwnd, destX, destY, crashX, crashY, seams)

    glideMs := 0
    if GlideEnabled {
        ; The crash impulse is handed to Glide so the window can overshoot the
        ; edge it is landing against and spring back, rather than easing
        ; asymptotically into it and then being squashed by a separate
        ; animation afterwards.
        glideMs := Glide(hwnd, winX, winY, destX, destY, landed, crashX, crashY)
    } else {
        ; One-shot: no animation is running, so nothing else would ever flush
        ; this. Without the commit, snapping did nothing at all whenever ice
        ; glide was switched off.
        MoveFast(hwnd, destX, destY)
        RS_Commit()
        landed()
    }

    ; Verify asynchronously. This used to be two PreciseSleep(40) spins inline:
    ; PreciseSleep never pumps messages, so the 80 ms froze every timer in the
    ; process - including the frame loop that had just been armed to run the
    ; glide. Worse, the check then read the position before the glide had moved
    ; anything, so its "one retry" fired on almost every snap and queued a
    ; competing move at the same priority as the animation.
    WriteLog(Format("  settled at L={1} T={2}  (throw {3},{4})", newL, newT, tx, ty))
    SetTimer(VerifySnap.Bind(hwnd, newL, newT), -(Round(glideMs) + 60))
}

; The moment the window comes to rest: spark the seams it touched, then let it
; squish if it hit something hard. Called from Glide's final frame, or directly
; when there is no glide - never from a timer racing the animation.
;
; The size is read HERE rather than at drag end, because the window's own app may
; have resized it during the slide.
OnSnapLanded(hwnd, destX, destY, crashX, crashY, seams) {
    for s in seams
        ShowSeamFlash(s[1], s[2], s[3], s[4])

    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try {
        WinGetPos(, , &w, &h, hwnd)
        ; Unconditional, and deliberately outside the squash gate below: this is
        ; where the window came to rest, whether or not it hit anything hard
        ; enough to squash. Gating it on the impact was already wrong, and
        ; raising that gate would have widened the band of landings that were
        ; never recorded.
        RememberPosition(hwnd, destX, destY, w, h)

        ; Squash threshold raised from 4 to 12. The glide now overshoots the
        ; target and springs back on its own, so squashing the window as well
        ; reads as two separate things happening on one landing. The squash is
        ; kept for genuinely hard impacts, where it is the difference between
        ; "arrived" and "hit something".
        if (Abs(crashX) > 12 || Abs(crashY) > 12)
            BounceSqueeze(hwnd, destX, destY, w, h, crashX, crashY)
    }
}

; Some apps reposition themselves once more after a drag ends. Nudge them back,
; once - but never while our own glide is still flying the window, or we would be
; fighting the animation instead of the app.
VerifySnap(hwnd, newL, newT) {
    global ActiveAnimations
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if Anim_Owner(hwnd, "geom")
        return
    if !GetRects(hwnd, &vL, &vT, &vR, &vB, &vx, &vy)
        return
    if (vL = newL && vT = newT)
        return
    MoveFast(hwnd, vx + (newL - vL), vy + (newT - vT))
    RS_Commit()
    WriteLog(Format("  corrected L={1} T={2} -> L={3} T={4}", vL, vT, newL, newT))
}

; Slides a window and returns the animation length in ms (0 if it moved it
; immediately), so the caller can schedule its verification for after the landing.
;
; `onLanded` is invoked from the frame that puts the window down - and only then.
; It is deliberately NOT called if the window dies mid-slide, or if a new glide
; cancels this one, because in both cases the window never landed where this snap
; intended and anything keyed to the landing would be wrong.
; crashX/crashY are how far past the destination the throw was still heading when
; the snap stopped it. They are optional: a glide with nowhere to land (a monitor
; throw, a plain slide) passes nothing and gets the pure ease-out it always had.
Glide(hwnd, fromX, fromY, toX, toY, onLanded := "", crashX := 0, crashY := 0) {
    global GLIDE_MS
    dx := toX - fromX, dy := toY - fromY
    dist := Sqrt(dx * dx + dy * dy)
    if (dist < 2 || GLIDE_MS < 1) {
        MoveFast(hwnd, toX, toY)
        RS_Commit()
        if onLanded
            onLanded()
        return 0
    }

    ; The floor was 200 ms, which made a 20 px correction take as long as a
    ; 150 px slide and feel like the window was wading. Duration is dominated by
    ; distance now and the floor is only there to stop a two-frame animation.
    ms := Min(GLIDE_MS, 140 + dist * 0.9)
    if (ms < 140)
        ms := 140

    ; Overshoot, capped and signed by the impulse that produced it. The window
    ; passes the edge it is landing against and springs back, which is what
    ; "hitting something" looks like. Previously nothing overshot at all: the
    ; window eased asymptotically into its target and a separate animation
    ; squashed its width afterwards, so the impact was read as a size change
    ; rather than as motion.
    settle := Tune("glideSettle")
    ox := 0, oy := 0
    if (settle > 0) {
        if (crashX != 0)
            ox := Clamp(crashX * 0.35, -settle, settle)
        if (crashY != 0)
            oy := Clamp(crashY * 0.35, -settle, settle)
    }

    animKey := "Glide_" hwnd

    start := QPC()
    lastX := -99999, lastY := -99999

    GlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, toX, toY, -1, -1, RS_PRI_ANIM)
            if onLanded
                onLanded()
            return false
        }

        e := 1 - (1 - t) ** 5
        ; Exactly 0 at t=0 and t=1, so the terminal frame still writes the
        ; precise destination and onLanded still fires from the frame that puts
        ; the window down. t*(1-t)^3 peaks at t=0.25 with a value of 0.10547, so
        ; it is normalised by 1/0.10547 - without that the whole excursion would
        ; be a tenth of the configured pixels and invisible. The long tail after
        ; the peak is the settle.
        o := 9.4815 * t * (1 - t) ** 3
        nx := Round(fromX + dx * e + ox * o)
        ny := Round(fromY + dy * e + oy * o)

        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, -1, -1, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, GlideStep)
    return ms
}

JelloBounce(hwnd, destX, destY, vx, vy) {
    if (!DllCall("IsWindow", "ptr", hwnd))
        return
        
    try WinGetPos(,, &w, &h, hwnd)
    
    animKey := "Jello_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    
    ; vx/vy arrive in px/s now. 1.5 px of squash per px/frame is 0.0225 per px/s.
    sqX := Clamp(vx * 0.0225, -10, 10)
    sqY := Clamp(vy * 0.0225, -10, 10)
    
    JelloStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, destX, destY, w, h, RS_PRI_ANIM)
            return false
        }
        
        decay := Exp(-t * 5)
        osc := Sin(t * 15)
        
        curSqX := Round(sqX * decay * osc)
        curSqY := Round(sqY * decay * osc)
        
        curX := destX - Round(curSqX / 2)
        curY := destY - Round(curSqY / 2)
        curW := w + curSqX
        curH := h + curSqY
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, JelloStep)
}

BounceSqueeze(hwnd, X, Y, W, H, crashX, crashY) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    
    squeezeX := 0, squeezeY := 0
    moveX := 0, moveY := 0
    depth := Tune("animBounce")

    if (crashX > 4) {
        squeezeX := Min(crashX * 0.4, depth)
        moveX := squeezeX
    } else if (crashX < -4) {
        squeezeX := Min(-crashX * 0.4, depth)
        moveX := 0
    }

    if (crashY > 4) {
        squeezeY := Min(crashY * 0.4, depth)
        moveY := squeezeY
    } else if (crashY < -4) {
        squeezeY := Min(-crashY * 0.4, depth)
        moveY := 0
    }
    
    if (squeezeX == 0 && squeezeY == 0)
        return
        
    animKey := "Bounce_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animBounceMs")

    ; One smooth squish-and-release instead of four hard-coded stages at 16/32/48
    ; ms. The old version was three discrete jumps that assumed a frame was exactly
    ; 16 ms - it had no interpolation at all, and a late frame made it skip a stage
    ; or repeat one. sin(pi*t) rises from 0 to the full squeeze at the midpoint and
    ; returns to 0, so it starts and ends exactly at rest with no discontinuity.
    lastW := -1, lastH := -1, lastX := -1, lastY := -1
    BounceStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, X, Y, W, H, RS_PRI_ANIM)
            return false
        }

        e := Sin(3.14159265 * t)
        nx := Round(X + moveX * e)
        ny := Round(Y + moveY * e)
        nw := Round(W - squeezeX * e)
        nh := Round(H - squeezeY * e)
        ; Skip frames that would not change a pixel: SetWindowPos on a real window
        ; costs ~260 us and forces the app to re-layout.
        if (nx != lastX || ny != lastY || nw != lastW || nh != lastH) {
            RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
            lastX := nx, lastY := ny, lastW := nw, lastH := nh
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, BounceStep)
}

ThrowWindowToNextMonitor(hwnd, L, T, W, H, vx, vy) {
    monCount := MonitorGetCount()
    if (monCount < 2)
        return false
        
    cx := L + W/2
    cy := T + H/2
    
    ; Exclusive on the right and bottom, like MonitorIndexAt. Inclusive bounds
    ; make the shared edge between two monitors belong to both, so a window
    ; centred exactly there matched whichever came first in the enumeration.
    curMon := MonitorIndexAt(cx, cy)
    
    targetMon := 0
    bestDist := 999999
    
    loop monCount {
        if (A_Index == curMon)
            continue
            
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        mx := mL + (mR - mL)/2
        my := mT + (mB - mT)/2
        
        dx := mx - cx
        dy := my - cy
        
        dotProduct := (dx * vx) + (dy * vy)
        if (dotProduct > 0) {
            dist := Sqrt(dx*dx + dy*dy)
            if (dist < bestDist) {
                bestDist := dist
                targetMon := A_Index
            }
        }
    }
    
    if (!targetMon)
        return false
        
    ; Centre on the WORK AREA, not the whole monitor rect: centring on the full
    ; rect on a screen with a taskbar puts the bottom of the window underneath it.
    if !WorkAreaOf(targetMon, &mL, &mT, &mR, &mB)
        MonitorGet(targetMon, &mL, &mT, &mR, &mB)
    destX := mL + Round((mR - mL - W)/2)
    destY := mT + Round((mB - mT - H)/2)

    if !GetRects(hwnd, &curL, &curT, &curR, &curB, &curWinX, &curWinY)
        return false

    winDestX := curWinX + (destX - L)
    winDestY := curWinY + (destY - T)

    ; W and H arrive in FRAME space (SnapWindow passes R-L and B-T of the DWM
    ; extended frame bounds), but BounceSqueeze writes its w/h straight into
    ; RS_SetPos, which is WinMove space. Those differ by the invisible resize
    ; border, so handing the frame size over shrank the window by ~14px on every
    ; single monitor throw - and it never grew back, so repeated throws walked it
    ; smaller and smaller. The window's own rect IS the WinMove size, so read it
    ; rather than deriving it.
    bounceW := W, bounceH := H
    try WinGetPos(, , &bounceW, &bounceH, hwnd)

    Glide(hwnd, curWinX, curWinY, winDestX, winDestY, () => BounceSqueeze(hwnd, winDestX, winDestY, bounceW, bounceH, vx > 0 ? 10 : (vx < 0 ? -10 : 0), 0))
    return true
}

ShowSeamFlash(x, y, w, h) {
    if (w < 1)
        w := 1
    if (h < 1)
        h := 1

    flash := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "SeamFlash")
    flash.BackColor := "00E5FF"
    flash.MarginX := 0, flash.MarginY := 0
    flash.Show("x" x " y" y " w" w " h" h " NoActivate")

    ; Pass the Gui object, not just its handle. The animation outlives this
    ; function, and handing over only the HWND left nothing holding a reference
    ; to the object for those 192 ms.
    FadeSeam(flash, x, y, w, h)
}

FadeSeam(flashGui, x, y, w, h) {
    hwnd := flashGui.Hwnd
    animKey := "FadeSeam_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animSeamMs")   ; duration in ms; never derive this from a frame count

    SeamStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            RS_RemoveHwnd(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            ; Destroy, not WinClose: WinClose only posts WM_CLOSE and leaves the
            ; Gui alive. One of these is created on every single snap, so a
            ; leaked window here is a leak that grows all session.
            try flashGui.Destroy()
            RS_RemoveHwnd(hwnd)
            return false
        }

        ; (1-t)^2, not 1-t^2. The old curve was still at 75% brightness a third
        ; of the way through, which reads as a bar being drawn on the seam; this
        ; one is bright immediately and mostly gone by the midpoint, which reads
        ; as a spark where the two edges met.
        alpha := Round(255 * (1 - t) ** 2)

        if (w < h) {
            shrink := Round(h * t * 0.3)
            RS_SetPos(hwnd, x, y + shrink, w, h - shrink*2, RS_PRI_ANIM)
        } else {
            shrink := Round(w * t * 0.3)
            RS_SetPos(hwnd, x + shrink, y, w - shrink*2, h, RS_PRI_ANIM)
        }

        RS_SetAlpha(hwnd, alpha, RS_PRI_ANIM)
        return true
    }
    RegisterAnimation(animKey, SeamStep)
}

; Cheaper than WinMove per frame, and leaves z-order and focus alone mid-slide.
; Now delegates to the render pipeline for batched application.
MoveFast(hwnd, x, y) {
    RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_ANIM)
}


; A throw must not fling a window off into nowhere.
KeepOnScreen(hwnd, &L, &T, &R, &B, tx, ty) {
    w := R - L, h := B - T

    if (tx != 0 || ty != 0) {
        hmon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        if (hmon) {
            monInfo := Buffer(40)
            NumPut("uint", 40, monInfo)
            if DllCall("GetMonitorInfo", "ptr", hmon, "ptr", monInfo) {
                wl := NumGet(monInfo, 20, "int")
                wt := NumGet(monInfo, 24, "int")
                wr := NumGet(monInfo, 28, "int")
                wb := NumGet(monInfo, 32, "int")
                L := Clamp(L, wl, wr - w)
                T := Clamp(T, wt, wb - h)
                R := L + w, B := T + h
                return
            }
        }
    }

    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    margin := 120
    L := Clamp(L, vx - w + margin, vx + vw - margin)
    T := Clamp(T, vy, vy + vh - margin)
    R := L + w, B := T + h
}

; =========================================================== Position memory ===========================================================
IsRestorable(hwnd) {
    if !IsSnappable(hwnd)
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")        ; GW_OWNER
        return false
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return false
            
        title := WinGetTitle(hwnd)
        if RegExMatch(title, "i)^(Picture.?in.?Picture|PiP|Картинка в картинке|Resim içinde resim|Şəkil içində şəkil)$")
            return false
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        ; Browser PiP windows (or popups) often don't have the standard title if localized, 
        ; but they are typically Always-On-Top (0x8) and lack a Maximize Box (0x10000).
        if ((exStyle & 0x8) && !(style & 0x10000)) {
            exe := WinGetProcessName(hwnd)
            if RegExMatch(exe, "i)^(chrome|msedge|firefox|brave|opera|vivaldi)\.exe$")
                return false
        }
            
        ; Every AutoHotkey GUI shares one class, so a single saved entry would
        ; drag every unrelated AHK window to the same spot.
        if (WinGetClass(hwnd) = "AutoHotkeyGUI")
            return false
        if (exStyle & 0x80)                                       ; WS_EX_TOOLWINDOW
            return false
        if !(style & 0x00040000)                                  ; WS_THICKFRAME
            return false
    } catch
        return false
    return true
}

WindowKey(hwnd) {
    try {
        exe := WinGetProcessName(hwnd)
        cls := WinGetClass(hwnd)
    } catch
        return ""
    return SubStr(RegExReplace(exe "_" cls, "[^A-Za-z0-9_]", ""), 1, 80)
}

global WindowCmdLineCache := Map()

GetProcessCommandLine(pid, hwnd) {
    global WindowCmdLineCache
    if WindowCmdLineCache.Has(hwnd)
        return WindowCmdLineCache[hwnd]

    ; The locator is built once. ComObjGet("winmgmts:") connects to the WMI
    ; service, and doing that per window made an already expensive query worse;
    ; this runs from HandleNewWindow's timer, so every millisecond is a stalled
    ; frame. Cached in a static, rebuilt if the service connection goes away.
    static wmi := ""
    cmdLine := ""
    try {
        if !wmi
            wmi := ComObjGet("winmgmts:")
        for proc in wmi.ExecQuery("Select CommandLine from Win32_Process where ProcessId=" pid) {
            cmdLine := proc.CommandLine
            break
        }
    } catch {
        wmi := ""
    }
    
    if DllCall("IsWindow", "ptr", hwnd)
        WindowCmdLineCache[hwnd] := cmdLine
        
    return cmdLine
}

IsMainApplicationWindow(hwnd) {
    return ClassifyWindowImpl(hwnd) == "Main"
}

ClassifyWindowImpl(hwnd) {
    try {
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            return "Transient"
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        if !(style & 0x00040000)
            return "Transient"
            
        if !(style & 0x10000000)
            return "Transient"
            
        if (style & 0x80000000)
            return "Transient"
            
        if (exStyle & 0x80)
            return "Transient"
            
        if IsCloaked(hwnd)
            return "Transient"

        title := WinGetTitle(hwnd)
        
        ; DISTINCTIVE phrases only.
        ;
        ; This list used to contain the bare words Settings, Options, Open,
        ; Print, About, Properties, Account, License, Loading, Progress, Trial,
        ; Welcome, Subscription and Wizard, matched anywhere in the title. Those
        ; are ordinary words in ordinary MAIN window titles - "Options - Mozilla
        ; Firefox", a VS Code "Settings" tab, any document named Account.xlsx -
        ; so position memory was silently switched off for a large slice of real
        ; windows, with nothing to tell the user why their app kept reopening in
        ; the wrong place.
        ;
        ; The generic single words are gone. What remains is multi-word or
        ; unambiguous. The structural tests above (owned window, no thick frame,
        ; tool window, cloaked) already reject most real dialogs, so this list
        ; only has to catch the ones that look structurally like a main window.
        static transientTitles := "i)\b(Getting Started|What's New|First Run|First Launch|Welcome Back"
            . "|Log In|Sign In|Two Factor|Security Check|Account Selection|Account Picker|User Selection|Profile Selection"
            . "|Chrome Profile Picker|Chrome Welcome|Chrome First Run|Chrome Sign In"
            . "|Edge Profile Picker|Edge Welcome|Edge First Run|Firefox Profile Manager|Brave Welcome|Opera Welcome|Arc Onboarding"
            . "|Configuration Wizard|Setup Wizard|InstallShield|MSI Installer|Inno Setup"
            . "|Downloading Update|Installing Update|Patch Installer|Version Upgrade"
            . "|Product Activation|License Activation|Subscription Activation"
            . "|Splash Screen|Boot Screen"
            . "|Profile Picker|User Picker|Folder Picker|File Picker|Color Picker|Font Picker|Emoji Picker|Device Picker|Printer Picker"
            . "|Settings Dialog|Message Box"
            . "|Permission Request|Allow Access|Administrator Prompt|Windows Security|Credential Dialog"
            . "|Visual Studio Installer|JetBrains Toolbox|Creative Cloud Installer|Office Installer|Epic Installer|Steam Installer|Riot Installer|EA Installer"
            . "|Steam Login|Discord Login|Slack Login|Teams Login|Zoom Login|Adobe Login|Epic Login|Battle\.net Login|Riot Login|Dropbox Login|OneDrive Login|Google Login|Apple Login"
            . "|Choose Profile|Save As|Choose Account|Choose Workspace|Workspace Picker|Device Setup|Connection Wizard)\b"
            
        if RegExMatch(title, transientTitles)
            return "Transient"

        pid := WinGetPID(hwnd)
        cmdLine := GetProcessCommandLine(pid, hwnd)
        static cmdLineArgs := "i)(--profile-picker|--first-run|--welcome|--setup|--installer|--install|--update|--updater|--repair|--activation|--login|--signin|--profile-manager)"
        
        if (cmdLine != "" && RegExMatch(cmdLine, cmdLineArgs))
            return "Transient"

    } catch {
        return "Transient"
    }

    return "Main"
}

; Pending position writes, keyed by window key. Same shape as SaveSettings ->
; WriteSettings, and for exactly the same measured reason: one IniWrite costs
; ~771 us, this wrote FOUR of them, and it runs at the end of every drag and
; again from OnSnapLanded - so ~3 ms of blocking disk I/O landed inside the drag
; pipeline, on the timer thread, stalling the frame loop that was mid-glide.
; Buffering makes it ~1 us; the flush happens 900 ms after the last drag.
global PendingPositions := Map()

RememberPosition(hwnd, forceX := "", forceY := "", forceW := "", forceH := "") {
    global RestoreEnabled, PendingPositions
    if (!RestoreEnabled || !IsRestorable(hwnd))
        return
    ; IsMainApplicationWindow is NOT consulted here any more. It reaches a WMI
    ; query (tens of milliseconds of blocking COM) through ClassifyWindowImpl,
    ; and this is an input path. The window was already classified when it was
    ; created - RestorePosition is the gate that matters - and a window we can
    ; snap is a window whose position is worth keeping.
    key := WindowKey(hwnd)
    if (key = "")
        return
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        if (forceX != "")
            x := forceX, y := forceY
        if (forceW != "")
            w := forceW, h := forceH
        if (w <= 0 || h <= 0)
            return
        PendingPositions[key] := {x: x, y: y, w: w, h: h}
        SetTimer(WritePositions, -900)
        WriteLog("  remembered " key " -> " x "," y " " w "x" h)
    }
}

; Bye() calls this directly: on the way out there is no idle for the one-shot.
WritePositions() {
    global PendingPositions, POS_FILE
    SetTimer(WritePositions, 0)
    if !PendingPositions.Count
        return
    pend := PendingPositions
    PendingPositions := Map()
    for key, r in pend {
        try {
            IniWrite(r.x, POS_FILE, key, "x")
            IniWrite(r.y, POS_FILE, key, "y")
            IniWrite(r.w, POS_FILE, key, "w")
            IniWrite(r.h, POS_FILE, key, "h")
        }
    }
}

; The shell tells us when a window is created, so there is no polling timer.
; Boot() registers both SHELLHOOK and TaskbarCreated, and calls
; RegisterShellHook() as the very last thing it does. Two reasons, both learned
; the hard way: ShellEvent is the widest-reaching callback in the program, so
; nothing may still be uninitialised when the shell starts delivering to it; and
; the registration does NOT survive an Explorer restart, so without the
; TaskbarCreated handler an Explorer crash - or this app's own "Restart Explorer"
; button - silently killed position memory, the open animations, focus pulse,
; breathing seeding, fly-to-mouse minimize and per-window cleanup for the rest of
; the session, with no error anywhere.

RegisterShellHook() {
    DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)
    return DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
}

TaskbarCreated(*) {
    ok := RegisterShellHook()
    WriteLog("explorer restarted - shell hook re-registered (" (ok ? "ok" : "FAILED") ")")
    ; The taskbar we recorded the auto-hide state of no longer exists.
    global SmartTaskbarEnabled, OriginalTaskbarState
    if (OriginalTaskbarState == -1)
        OriginalTaskbarState := GetTaskbarState()
    if SmartTaskbarEnabled
        SyncSmartTaskbar()
}

ShellEvent(wParam, lParam, *) {
    static HSHELL_WINDOWCREATED := 1
    static HSHELL_GETMINRECT := 5
    
    if ((wParam & 0x7FFF) = HSHELL_GETMINRECT) {
        global FlyMinimizeEnabled, BlackHoleMinimizeEnabled
        if (BlackHoleMinimizeEnabled) {
            hwndToMin := NumGet(lParam, 0, "ptr")
            TriggerBlackHoleMinimize(hwndToMin)
            rectOffset := A_PtrSize == 8 ? 8 : 4
            try WinGetPos(&wx, &wy, &ww, &wh, hwndToMin)
            if IsSet(wx) {
                cx := wx + ww//2
                cy := wy + wh//2
            } else {
                cx := Round(A_ScreenWidth / 2)
                cy := Round(A_ScreenHeight / 2)
            }
            NumPut("int", cx, lParam, rectOffset)
            NumPut("int", cy, lParam, rectOffset + 4)
            NumPut("int", cx, lParam, rectOffset + 8)
            NumPut("int", cy, lParam, rectOffset + 12)
            return 1
        } else if (FlyMinimizeEnabled) {
            MouseGetPos(&mx, &my)
            rectOffset := A_PtrSize == 8 ? 8 : 4
            NumPut("int", mx - 10, lParam, rectOffset)
            NumPut("int", my - 10, lParam, rectOffset + 4)
            NumPut("int", mx + 10, lParam, rectOffset + 8)
            NumPut("int", my + 10, lParam, rectOffset + 12)
            return 1
        }
    }
    
    if ((wParam & 0x7FFF) = 2) { ; HSHELL_WINDOWDESTROYED
        if (lParam) {
            global CustomTrans, RolledUpWindows, WinTargetAlpha, WinCurrentAlpha, WinLastActive, WindowCmdLineCache
            if WindowCmdLineCache.Has(lParam)
                WindowCmdLineCache.Delete(lParam)
            if CustomTrans.Has(lParam)
                CustomTrans.Delete(lParam)
            if RolledUpWindows.Has(lParam)
                RolledUpWindows.Delete(lParam)
            if WinTargetAlpha.Has(lParam)
                WinTargetAlpha.Delete(lParam)
            if WinCurrentAlpha.Has(lParam)
                WinCurrentAlpha.Delete(lParam)
            if WinLastActive.Has(lParam)
                WinLastActive.Delete(lParam)
            ; Focus Depth only ever removes the window being switched TO, so
            ; without this the map grows by one entry for every window the user
            ; has focused away from and never returned to, for the whole session.
            global PushedBackWindows
            if PushedBackWindows.Has(lParam)
                PushedBackWindows.Delete(lParam)
            ; Same reasoning for the two layout maps: nothing else ever removes
            ; from them, so without this they grow by one entry per window the
            ; user has ever tiled or resized, for the whole session.
            global LayoutUndo, SizeCycleIdx
            if LayoutUndo.Has(lParam)
                LayoutUndo.Delete(lParam)
            if SizeCycleIdx.Has(lParam)
                SizeCycleIdx.Delete(lParam)
            RS_RemoveHwnd(lParam)
            MC_RemoveHwnd(lParam)      ; MediaCore caches pid/exe per HWND forever otherwise
        }
    }

    if ((wParam & 0x7FFF) = 4) { ; HSHELL_WINDOWACTIVATED
        if (lParam) {
            if !BottomWindows.Has(lParam) {
                PulseWindow(lParam)
            }
            
            global FocusDepthEnabled
            if (FocusDepthEnabled) {
                ApplyFocusDepth(lParam)
            }
            
            global BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha
            if (BreathingEnabled && IsRestorable(lParam) && !WinLastActive.Has(lParam)) {
                ; 255 = "the breathe layer is dimming nothing yet". The user's
                ; own opacity is a separate factor and is not this map's business.
                WinLastActive[lParam] := QPC()
                WinCurrentAlpha[lParam] := 255
                WinTargetAlpha[lParam] := 255
            }
        }
    }

    if ((wParam & 0x7FFF) = HSHELL_WINDOWCREATED) {
        global OpenAnim, GhostHiddenWindows, BreathingEnabled, WinLastActive, WinCurrentAlpha, WinTargetAlpha
        hwnd := lParam
        if (BreathingEnabled && IsRestorable(hwnd)) {
            WinLastActive[hwnd] := QPC()
            WinCurrentAlpha[hwnd] := 255
            WinTargetAlpha[hwnd] := 255
        }
        
        ; Only hide a window we are definitely going to animate back.
        ;
        ; This used to hide every un-owned new top-level window and decide
        ; afterwards, in HandleNewWindow, whether to animate it - and the "no
        ; animation after all" branch was the one that queued the reveal without
        ; committing it. Anything not restorable (a dialog, a fixed-size window,
        ; a window that opens maximized, our own settings window) was therefore
        ; left at alpha 0: focused, clickable and completely invisible.
        ;
        ; It also forced WS_EX_LAYERED onto arbitrary foreign windows, which for
        ; a GPU-composited or full-screen one costs a redirection surface and can
        ; break exclusive full-screen presentation. Nothing we then chose not to
        ; animate should ever have paid that.
        if (OpenAnim != "None" && WillAnimateOpen(hwnd)) {
            try {
                RS_SetAlphaLayer(hwnd, "open", 0.0, RS_PRI_ANIM)
                RS_Commit()
                GhostHiddenWindows[hwnd] := true
            }
        }
        SetTimer(() => HandleNewWindow(hwnd), -250)
    }
}

; The one eligibility test, used both before hiding a new window and before
; animating it, so the two can never disagree.
WillAnimateOpen(hwnd) {
    if !hwnd
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")     ; GW_OWNER
        return false
    if !IsRestorable(hwnd)
        return false
    try {
        if (WinGetMinMax(hwnd) != 0)
            return false
    } catch
        return false
    return true
}

RestorePosition(hwnd) {
    global RestoreEnabled, POS_FILE
    if (!RestoreEnabled || !DllCall("IsWindow", "ptr", hwnd))
        return
    if (!IsRestorable(hwnd) || !IsMainApplicationWindow(hwnd))
        return
    key := WindowKey(hwnd)
    if (key = "")
        return
    ; All four must be present and numeric. RememberPosition writes them as four
    ; separate IniWrites inside one try, so a failure part-way leaves a section
    ; with x but no h - and Integer("") throws from this timer callback, which
    ; surfaces as an error dialog every time that app opens a window.
    x := IniRead(POS_FILE, key, "x", "")
    y := IniRead(POS_FILE, key, "y", "")
    w := IniRead(POS_FILE, key, "w", "")
    h := IniRead(POS_FILE, key, "h", "")
    if !(IsInteger(x) && IsInteger(y) && IsInteger(w) && IsInteger(h))
        return

    rx := Integer(x), ry := Integer(y), rw := Integer(w), rh := Integer(h)
    if (rw <= 0 || rh <= 0)          ; a zero-size WinMove would collapse the window
        return

    try {
        exe := WinGetProcessName(hwnd)
        cls := WinGetClass(hwnd)
        
        loop 20 {
            conflict := false
            for other in WinGetList("ahk_class " cls " ahk_exe " exe) {
                if (other = hwnd)
                    continue
                if !DllCall("IsWindowVisible", "ptr", other)
                    continue
                try {
                    WinGetPos(&ox, &oy, &ow, &oh, other)
                    if (Abs(ox - rx) < 5 && Abs(oy - ry) < 5) {
                        conflict := true
                        rx += 30
                        ry += 30
                        break
                    }
                }
            }
            if (!conflict)
                break
        }
    } catch {
    }

    ; Ensure it restores on-screen. Guarded: a monitor can be removed between the
    ; count and the query, and this runs from a timer.
    try {
        intersecting := false
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
            if (rx < wr && rx + rw > wl && ry < wb && ry + rh > wt) {
                intersecting := true
                break
            }
        }
        if (!intersecting) {
            MonitorGetWorkArea(1, &wl, &wt, &wr, &wb)
            if (rw > wr - wl)
                rw := wr - wl
            if (rh > wb - wt)
                rh := wb - wt
            rx := wl + 40
            ry := wt + 40
        }
    }


    try {
        RS_SetPos(hwnd, rx, ry, rw, rh, RS_PRI_USER)
        RS_Commit()
        WriteLog("restored " key " -> " rx "," ry " " rw "x" rh)
        return {x: rx, y: ry, w: rw, h: rh}
    }
}

global GhostHiddenWindows := Map()

HandleNewWindow(hwnd) {
    global OpenAnim, GhostHiddenWindows
    isHidden := GhostHiddenWindows.Has(hwnd)
    if isHidden
        GhostHiddenWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd) {
        RS_RemoveHwnd(hwnd)
        return
    }

    restoredRect := RestorePosition(hwnd)

    if !isHidden
        return

    ; Re-check: 250 ms is long enough for the window to have been maximized,
    ; closed or restyled since we hid it.
    if (OpenAnim != "None" && WillAnimateOpen(hwnd)) {
        if (OpenAnim == "Ghost Slide-In")
            GhostSlideIn(hwnd, restoredRect)
        else if (OpenAnim == "Portal Scale-In")
            PortalScaleIn(hwnd, restoredRect)
        else if (OpenAnim == "Window Unrolling")
            UnrollWindow(hwnd, restoredRect)
        ; Belt and braces: if the animation callback dies before its final
        ; "Off", this un-hides the window anyway. A window we made invisible
        ; must never be able to stay that way.
        SetTimer(RevealWindow.Bind(hwnd), -1200)
        return
    }

    RevealWindow(hwnd)
}

RevealWindow(hwnd) {
    global GhostWindows
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    ; The CustomTrans guard is gone: clearing the "open" layer cannot stomp an
    ; opacity the user asked for in the meantime, because the base is a separate
    ; factor. The ghost guard stays - a window that became a ghost while the open
    ; animation was pending is no longer this code's to reveal.
    if GhostWindows.Has(hwnd)
        return
    try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
    RS_Commit()
}

UnrollWindow(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    ; Reveal first, then clip: the region does the animating here, so the window
    ; must be opaque from the first frame.
    try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)

    animKey := "Unroll_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    UnrollStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            try RS_SetRegion(hwnd, "", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) * (1 - t)
        curH := Round(h * ease)
        if (curH < 1)
            curH := 1
            
        try RS_SetRegion(hwnd, "0-0 W" w " H" curH, RS_PRI_ANIM)
        return true
    }
    
    Anim_Claim(hwnd, "region", animKey, UnrollStep)
}

GhostSlideIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }


    startY := y + Tune("animOpenSlide")
    endY := y
    
    MoveFast(hwnd, x, startY)
    RS_Commit()
    
    animKey := "GhostSlideIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    GhostSlideStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            MoveFast(hwnd, x, endY)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            return false
        }
        
        ease := 1 - (1 - t) * (1 - t) ; ease-out
        curY := Round(startY + (endY - startY) * ease)
        MoveFast(hwnd, x, curY)
        
        try RS_SetAlphaLayer(hwnd, "open", ease, RS_PRI_ANIM)
        return true
    }
    
    Anim_Claim(hwnd, "geom", animKey, GhostSlideStep)
}

PortalScaleIn(hwnd, restoredRect := "") {
    if (IsObject(restoredRect) && restoredRect.HasOwnProp("w")) {
        x := restoredRect.x, y := restoredRect.y, w := restoredRect.w, h := restoredRect.h
    } else {
        try WinGetPos(&x, &y, &w, &h, hwnd)
        catch {
            RevealWindow(hwnd)
            return
        }
    }
    if (w = 0 || h = 0) {
        RevealWindow(hwnd)
        return
    }

    animKey := "PortalScaleIn_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := Tune("animOpenMs")
    
    cX := x + w / 2
    cY := y + h / 2
    
    try RS_SetAlphaLayer(hwnd, "open", 0.0, RS_PRI_ANIM)
    RS_SetPos(hwnd, Round(cX - (w * 0.8) / 2), Round(cY - (h * 0.8) / 2), Round(w * 0.8), Round(h * 0.8), RS_PRI_ANIM)
    RS_Commit()
    
    PortalScaleStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            try RS_ClearAlphaLayer(hwnd, "open", RS_PRI_ANIM)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        scale := 0.8 + 0.2 * ease
        
        curW := Round(w * scale)
        curH := Round(h * scale)
        curX := Round(cX - curW / 2)
        curY := Round(cY - curH / 2)
        
        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        
        try RS_SetAlphaLayer(hwnd, "open", (t > 0.4 ? 1.0 : (t / 0.4)), RS_PRI_ANIM)
        return true
    }
    
    Anim_Claim(hwnd, "geom", animKey, PortalScaleStep)
}

global PulsingWindows := Map()

PulseWindow(hwnd) {
    global PulseEnabled, PulsingWindows
    if (!PulseEnabled || !DllCall("IsWindow", "ptr", hwnd) || !IsRestorable(hwnd))
        return

    try {
        if (WinGetMinMax(hwnd) != 0) ; skip maximized/minimized
            return
    } catch
        return

    global ActiveAnimations
    ; Never pulse a window that is still being flown somewhere.
    ;
    ; Pulse_<hwnd> and Glide_<hwnd> both write RS_Pos[hwnd] at RS_PRI_ANIM, and
    ; equal priority means last-writer-wins within a flush. AHK enumerates a Map
    ; sorted by key, so "Pulse_" is produced after "Glide_" and won every frame -
    ; and worse, PulseStep captured x/y/w/h at activation, i.e. a MID-GLIDE
    ; position, then restored the window to it on its final frame. Activating a
    ; window mid-snap threw away the snap. Same guard idiom as VerifySnap.
    animKey := "Pulse_" hwnd
    if Anim_Owner(hwnd, "geom")
        return
    if PulsingWindows.Has(hwnd) {
        ; A callback dropped by the scheduler (it swallows exceptions) would
        ; leave this flag set forever and that window could never pulse again.
        if ActiveAnimations.Has(animKey)
            return
        PulsingWindows.Delete(hwnd)
    }

    PulsingWindows[hwnd] := true

    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        PulsingWindows.Delete(hwnd)
        return
    }

    ; The 12 px cap stays internal: it stops the pulse from throwing a
    ; full-screen window several centimetres, which is a property of the
    ; effect, not a preference.
    grow := Tune("animPulse") / 100
    pw := Min(Round(w * grow), 12)
    ph := Min(Round(h * grow), 12)

    start := QPC()
    ms := Tune("animPulseMs")

    ; Same story as the bounce: this was three hard-coded stages at 16/32/48 ms,
    ; which is 3 frames - not an animation so much as a flicker, and it assumed a
    ; frame was exactly 16 ms. sin(pi*t) over 190 ms grows out from the centre and
    ; settles back, which is the single "breath" a macOS focus cue gives you.
    lastX := -99999, lastY := -99999
    PulseStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            PulsingWindows.Delete(hwnd)
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, w, h, RS_PRI_ANIM)
            PulsingWindows.Delete(hwnd)
            return false
        }

        ; t**0.7 skews the half-sine so the window jumps out quickly and eases
        ; back slowly. A symmetric pulse spends as long growing as returning,
        ; which reads as a wobble rather than as "this window just took focus".
        e := Sin(3.14159265 * t ** 0.7)
        gx := Round(pw * e)
        gy := Round(ph * e)
        nx := x - gx, ny := y - gy
        if (nx != lastX || ny != lastY) {
            RS_SetPos(hwnd, nx, ny, w + gx * 2, h + gy * 2, RS_PRI_ANIM)
            lastX := nx, lastY := ny
        }
        return true
    }

    Anim_Claim(hwnd, "geom", animKey, PulseStep)
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

; ====== macOS Quick Look ======
IsTypingInExplorer() {
    try {
        ctrl := ControlGetClassNN(ControlGetFocus("A"))
        if (InStr(ctrl, "Edit") || InStr(ctrl, "Search") || InStr(ctrl, "Windows.UI.Core.CoreWindow"))
            return true
    }
    return false
}

GetSelectedExplorerFile() {
    try {
        hwnd := WinExist("A")
        for window in ComObject("Shell.Application").Windows {
            if (window.HWND == hwnd) {
                sel := window.Document.SelectedItems
                if (sel.Count > 0)
                    return sel.Item(0).Path
            }
        }
    }
    return ""
}

ToggleQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        CloseQuickLook()
        return true
    }
    path := GetSelectedExplorerFile()
    if (!path || !FileExist(path) || InStr(FileExist(path), "D"))
        return false 
        
    ; Build into a local and only publish it once there is something to show.
    ; Assigning QuickLookGui up front and then returning false for an unsupported
    ; extension left a created-but-never-shown window in the global, which made
    ; the next Space press take the "close it" branch and swallow the keystroke -
    ; so Space alternated between working and doing nothing.
    ext := StrLower(RegExReplace(path, ".*\.([^.]+)$", "$1"))
    if !(ext ~= "^(png|jpg|jpeg|gif|bmp|txt|md|ini|ahk|csv|log|json|xml|ps1|bat|cmd)$")
        return false

    g := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound +Border -DPIScale")
    g.BackColor := "111111"
    g.MarginX := 20
    g.MarginY := 20

    try {
        if (ext ~= "^(png|jpg|jpeg|gif|bmp)$")
            g.AddPicture("w-1 h-1", path)
        else
            g.AddEdit("w600 h400 ReadOnly Background111111 cWhite -E0x200", FileRead(path, "m4096"))
    } catch {
        try g.Destroy()
        return false
    }

    QuickLookGui := g
    RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
    RS_Commit()
    g.Show("NoActivate AutoSize Center")
    FadeGui(g, 255)
    SetTimer(CheckQuickLookFocusStep, 100)
    return true
}

CloseQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        SetTimer(CheckQuickLookFocusStep, 0)
        guiObj := QuickLookGui
        QuickLookGui := "" 
        FadeGui(guiObj, 0, 0, true)
    }
}

CheckQuickLookFocusStep() {
    global QuickLookGui
    if !QuickLookGui {
        SetTimer(CheckQuickLookFocusStep, 0)
        return
    }

    ahwnd := WinExist("A")
    ; WinGetClass(0) throws, and an uncaught throw in a timer thread pops an
    ; error dialog and kills the timer. There is routinely no active window at
    ; all - during a desktop switch, or on the lock screen.
    cls := ""
    if ahwnd
        try cls := WinGetClass(ahwnd)
    if (ahwnd != QuickLookGui.Hwnd && cls != "CabinetWClass")
        CloseQuickLook()
}

; ====== Smart Auto-Hide Taskbar ======
global SmartTaskbarLastState := -1

SyncSmartTaskbar() {
    global SmartTaskbarEnabled, SmartTaskbarLastState
    ; Reset the remembered state on every toggle. As a `static` inside the monitor
    ; it survived being switched off and on again, so the first evaluation after a
    ; re-enable could match the stale value and skip applying anything.
    SmartTaskbarLastState := -1
    if (SmartTaskbarEnabled)
        SetTimer(SmartTaskbarMonitorStep, 200)
    else
        SetTimer(SmartTaskbarMonitorStep, 0)
}

SmartTaskbarMonitorStep() {
    global SmartTaskbarEnabled, SmartTaskbarLastState

    if !SmartTaskbarEnabled
        return
        
    try {
        tbHwnd := WinExist("ahk_class Shell_TrayWnd")
        if !tbHwnd
            return
            
        ; Get taskbar height
        WinGetPos(,, &tw, &th, tbHwnd)
        if (th < 10)
            th := 48 ; Fallback
            
        ; The primary monitor, not enumeration index 1 - Shell_TrayWnd is the
        ; PRIMARY taskbar, and on many setups those are different screens, which
        ; made every window test below compare against the wrong rectangle.
        MonitorGet(MonitorGetPrimary(), &ML, &MT, &MR, &MB)
        tbActiveTop := MB - th
        
        shouldHide := false
        hwnds := WinGetList()
        for hwnd in hwnds {
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
            ; Read the window state ONCE. It was queried again below for the
            ; maximized test - two cross-process calls per window, five times a
            ; second, for one piece of information.
            mm := WinGetMinMax(hwnd)
            if (mm == -1) ; Minimized
                continue
                
            cls := WinGetClass(hwnd)
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
                continue
                
            if (WinGetExStyle(hwnd) & 0x80) ; WS_EX_TOOLWINDOW
                continue
                
            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            if (ww == 0 || wh == 0)
                continue
                
            ; Check if on primary monitor
            if (wx >= MR || wx + ww <= ML || wy >= MB || wy + wh <= MT)
                continue
                
            if (mm == 1 || wy + wh > tbActiveTop) {
                shouldHide := true
                break
            }
        }
        
        if (shouldHide != SmartTaskbarLastState) {
            SetTaskbarAutoHide(shouldHide)
            SmartTaskbarLastState := shouldHide
        }
    }
}

GetTaskbarState() {
    try {
        cbSize := A_PtrSize == 8 ? 48 : 36
        abd := Buffer(cbSize, 0)
        NumPut("uint", cbSize, abd, 0)
        hwnd := WinExist("ahk_class Shell_TrayWnd")
        if !hwnd
            return -1
        NumPut("ptr", hwnd, abd, A_PtrSize == 8 ? 8 : 4)
        return DllCall("Shell32\SHAppBarMessage", "uint", 4, "ptr", abd)
    }
    return -1
}

SetTaskbarAutoHide(hide) {
    try {
        cbSize := A_PtrSize == 8 ? 48 : 36
        abd := Buffer(cbSize, 0)
        NumPut("uint", cbSize, abd, 0)
        hwnd := WinExist("ahk_class Shell_TrayWnd")
        if !hwnd
            return
        NumPut("ptr", hwnd, abd, A_PtrSize == 8 ? 8 : 4)
        NumPut("ptr", hide ? 1 : 2, abd, A_PtrSize == 8 ? 40 : 32)
        DllCall("Shell32\SHAppBarMessage", "uint", 10, "ptr", abd)
    }
}

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

; ====== Premium Volume OSD ======
ChangeVolumeOSD(dir) {
    try {
        stepPct := Tune("osdStep")
        SoundSetVolume((dir > 0 ? "+" : "-") stepPct)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

ToggleMuteOSD() {
    try {
        SoundSetMute(-1)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

GetVolumeOSDPos(&x, &visibleY, &hiddenY) {
    ; Not monitor 1: that is an enumeration index, not the primary, and the OSD
    ; answers a scroll over a taskbar that may be on any screen.
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    
    dpiScale := 1.0
    try {
        rect := Buffer(16)
        NumPut("Int", WL, "Int", WT, "Int", WR, "Int", WB, rect)
        if hMonitor := DllCall("MonitorFromRect", "Ptr", rect, "UInt", 2, "Ptr") {
            DllCall("Shcore\GetDpiForMonitor", "Ptr", hMonitor, "Int", 0, "UInt*", &dpiX:=0, "UInt*", &dpiY:=0)
            if dpiY
                dpiScale := dpiY / 96.0
        }
    }
    
    x := WL + (WR - WL - 280) // 2
    margin := Round(75 * dpiScale)
    visibleY := WB - 64 - margin
    hiddenY := WB + 10
}

ShowVolumeOSD(vol, isMuted) {
    global OsdGui, OsdHiding

    if (OsdGui) {
        ; Reuse the window even if it is mid-fade-out. Previously HideVolumeOSD
        ; cleared OsdGui immediately, so a notch during the 100 ms fade built a
        ; SECOND OSD on top of the one still fading - two semi-transparent copies
        ; at the same coordinates, which reads as a flicker. The shared fade key
        ; cancels the outgoing fade, and OsdFadeIn brings this one back.
        UpdateOSD(vol, isMuted)
        ; UpdateOSD destroys the window and clears OsdGui if any of its controls
        ; have gone. Everything below dereferences it, and NotchAnim's argument
        ; is evaluated OUTSIDE any try - so on that path an ordinary wheel notch
        ; over the taskbar popped an error dialog. Re-check, and rebuild on the
        ; next notch instead.
        if (!OsdGui)
            return
        try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
        if OsdHiding {
            OsdHiding := false
            ; Explicit fallback rather than a bare `try`: a failed WinGetPos leaves
            ; cy UNSET and NotchAnim reads it. The parked position is the right
            ; default - that is where a hidden OSD sits.
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            cy := hiddenY
            try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
            NotchAnim(OsdGui.Hwnd, cy, visibleY, true)
        }
    } else {
        try {
            OsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale")
            OsdGui.BackColor := "181818"
            OsdGui.SetFont("s24 cWhite", "Segoe UI Emoji")
            OsdGui.AddText("vIcon x15 y12 w40 h40 BackgroundTrans Center", GetSpeakerIcon(vol, isMuted))
            
            OsdGui.SetFont("s10 cWhite bold", "Segoe UI")
            pctStr := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
            OsdGui.AddText("vPct x55 y21 w50 h24 BackgroundTrans Right", pctStr)
            
            OsdGui.AddText("x115 y29 w150 h6 Background333333")
            w := Max(1, Round(150 * (vol / 100)))
            OsdGui.AddText("vBar x115 y29 w" w " h6 BackgroundFFFFFF")

            RS_SetAlpha(OsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()
            
            OsdGui.Show("NoActivate w280 h64")
            try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
            RS_SetRegion(OsdGui.Hwnd, "0-0 w280 h64 r20-20", RS_PRI_ANIM)
            
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            OsdGui.Move(x, y)
            
            NotchAnim(OsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; A plain one-shot, re-armed on every notch, so it hides 1.5 s after the LAST
    ; scroll. This was an entry in the animation scheduler, which meant 95 frames
    ; of the 15 ms loop - holding timeBeginPeriod(1) and running a full produce +
    ; flush pass - purely to compare two numbers. Nothing was animating.
    SetTimer(HideVolumeOSD, -Tune("osdHide"))
}

UpdateOSD(vol, isMuted) {
    global OsdGui
    OsdGui["Icon"].Text := GetSpeakerIcon(vol, isMuted)
    OsdGui["Pct"].Text := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
    w := Max(1, Round(150 * (vol / 100)))
    OsdGui["Bar"].Move(,, w)
    try {
        if (isMuted)
            OsdGui["Bar"].Opt("Background555555")
        else
            OsdGui["Bar"].Opt("BackgroundFFFFFF")
    }
    OsdGui["Bar"].Redraw()
}

GetSpeakerIcon(vol, isMuted) {
    if (isMuted || vol == 0)
        return "🔇"
    if (vol < 30)
        return "🔈"
    if (vol < 70)
        return "🔉"
    return "🔊"
}

HideVolumeOSD() {
    global OsdGui, OsdHiding
    if (!OsdGui)
        return
    OsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetVolumeOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
    NotchAnim(OsdGui.Hwnd, cy, hiddenY, false, ClearVolumeOSD)
}

ClearVolumeOSD() {
    global OsdGui, OsdHiding
    OsdGui := ""
    OsdHiding := false
}

; ====== Live Window PiP ======
; Boot() registers the ten OnMessage handlers these functions need: WM_NCHITTEST,
; WM_NCMBUTTONDOWN and the eight mouse messages. Each one runs for every message
; of its kind that reaches ANY window this process owns, which is why every
; handler's first act is to test the hwnd against PipGuis and return unhandled.


WM_NCHITTEST_PiP(wParam, lParam, msg, hwnd) {
    global PipGuis
    ; Runs for every WM_NCHITTEST on every window this process owns, which is
    ; every mouse move over the settings window and all the overlays. Bail out
    ; before touching anything when there are no PiP windows at all.
    if !PipGuis.Count
        return
    for src, pip in PipGuis {
        if (pip.Hwnd == hwnd) {
            x := lParam << 48 >> 48
            y := lParam << 32 >> 48
            if !WinGetPosSafe(hwnd, &winX, &winY, &winW, &winH)
                return
            if (x < winX + 5 || x > winX + winW - 5 || y < winY + 5 || y > winY + winH - 5)
                return
            if (pip.HasProp("Interactive") && pip.Interactive)
                return 1 ; HTCLIENT
            return 2 ; HTCAPTION
        }
    }
}

PiP_NCMouseEvents(wParam, lParam, msg, hwnd) {
    global PipGuis
    if (msg == 0x00A7 && wParam == 2) { ; WM_NCMBUTTONDOWN on HTCAPTION
        for src, pip in PipGuis {
            if (pip.Hwnd == hwnd) {
                pip.Interactive := true
                pip.Opt("+Border +Caption")
                pip.Title := "PiP (Interactive) - MClick to exit"
                return 0
            }
        }
    }
}

PiP_MouseEvents(wParam, lParam, msg, hwnd) {
    global PipGuis
    isPip := false
    sourceHwnd := 0
    guiObj := 0
    for src, pip in PipGuis {
        if (pip.Hwnd == hwnd) {
            isPip := true
            sourceHwnd := src
            guiObj := pip
            break
        }
    }
    if !isPip
        return
        
    if (msg == 0x0207) { ; WM_MBUTTONDOWN
        guiObj.Interactive := false
        guiObj.Opt("-Caption -Border")
        guiObj.Title := ""
        return 0
    }
    
    if (!guiObj.HasProp("Interactive") || !guiObj.Interactive)
        return
        
    x := lParam << 48 >> 48
    y := lParam << 32 >> 48
    
    WinGetClientPos(,, &pw, &ph, hwnd)
    try WinGetClientPos(,, &sw, &sh, sourceHwnd)
    catch
        return
        
    if (pw > 0 && ph > 0) {
        srcX := Round(x * (sw / pw))
        srcY := Round(y * (sh / ph))
        
        newLParam := (srcY << 16) | (srcX & 0xFFFF)
        PostMessage(msg, wParam, newLParam,, "ahk_id " sourceHwnd)
    }
    
    if (msg != 0x0200)
        return 0
}

WinGetPosSafe(hwnd, &x, &y, &w, &h) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        return true
    }
    return false
}

; One place that tears a PiP down, so the thumbnail handle, the window and the
; map entry can never get out of step.
ClosePiP(srcHwnd) {
    global PipGuis
    if !PipGuis.Has(srcHwnd)
        return
    pip := PipGuis[srcHwnd]
    PipGuis.Delete(srcHwnd)
    hwnd := 0
    try hwnd := pip.Hwnd
    try DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", pip.ThumbId)
    try pip.Destroy()
    if hwnd
        RS_RemoveHwnd(hwnd)
}

TogglePiP() {
    global PipGuis

    srcHwnd := WinExist("A")
    if !srcHwnd
        return

    cls := ""
    try cls := WinGetClass(srcHwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd")
        return

    ; Shift+Alt+P while a PiP thumbnail itself is focused closes that thumbnail.
    for s, pip in PipGuis {
        if (pip.Hwnd == srcHwnd) {
            ClosePiP(s)
            return
        }
    }

    if PipGuis.Has(srcHwnd) {
        ClosePiP(srcHwnd)
        return
    }

    ; -DPIScale like every other overlay: without it Gui.Show scales the
    ; requested w/h by the system DPI, so a PiP asked for 320x180 came out
    ; half as big again on a 150% display and no longer matched its source.
    PipGui := Gui("-Caption +ToolWindow +AlwaysOnTop +Resize +Border -DPIScale")
    PipGui.BackColor := "000000"

    sw := 0, sh := 0
    try WinGetClientPos(,, &sw, &sh, srcHwnd)
    if (sw > 0 && sh > 0) {
        ph := 200
        pw := Round(ph * (sw / sh))
    } else {
        pw := 320, ph := 180
    }


    PipGui.Show("w" pw " h" ph " NoActivate")
    
    thumbId := 0
    hr := DllCall("dwmapi\DwmRegisterThumbnail", "ptr", PipGui.Hwnd, "ptr", srcHwnd, "ptr*", &thumbId)
    if (hr != 0) {
        PipGui.Destroy()
        return
    }
    
    PipGui.ThumbId := thumbId
    PipGui.SourceHwnd := srcHwnd
    PipGuis[srcHwnd] := PipGui
    
    PipGui.OnEvent("Size", PipGuiResize)
    PipGui.OnEvent("ContextMenu", PipGuiContextMenu)
    PipGuiResize(PipGui, 0, pw, ph)
    SetTimer(PiPMonitorStep, 100)
}

PipGuiResize(guiObj, minMax, width, height) {
    if !guiObj.HasProp("ThumbId")
        return
        
    alpha := 255
    try {
        a := WinGetTransparent(guiObj.Hwnd)
        if (a != "")
            alpha := a
    }

    props := Buffer(48, 0)
    NumPut("UInt", 0x1D, props, 0) ; 0x19 | 0x04 = 0x1D
    NumPut("Int", 0, props, 4)
    NumPut("Int", 0, props, 8)
    NumPut("Int", width, props, 12)
    NumPut("Int", height, props, 16)
    NumPut("UChar", alpha, props, 36)
    NumPut("Int", 1, props, 40)
    NumPut("Int", 1, props, 44)
    DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", guiObj.ThumbId, "ptr", props)
}

PipGuiContextMenu(guiObj, *) {
    ; Went through PipGuis.Delete() directly, which throws if PiPMonitorStep had
    ; already removed the entry because the source window closed.
    try ClosePiP(guiObj.SourceHwnd)
}

PiPMonitorStep() {
    global PipGuis
    if (PipGuis.Count == 0) {
        SetTimer(PiPMonitorStep, 0)
        return
    }

    for srcHwnd, pipGui in PipGuis.Clone() {
        if !DllCall("IsWindow", "ptr", srcHwnd) {
            ClosePiP(srcHwnd)
            continue
        }
        
        try {
            alpha := WinGetTransparent(pipGui.Hwnd)
            if (alpha == "")
                alpha := 255
            if (!pipGui.HasProp("LastAlpha") || pipGui.LastAlpha != alpha) {
                pipGui.LastAlpha := alpha
                props := Buffer(48, 0)
                NumPut("UInt", 0x04, props, 0)
                NumPut("UChar", alpha, props, 36)
                DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", pipGui.ThumbId, "ptr", props)
            }
        }
    }
}

; ====== Global Mic Kill-Switch ======
ToggleDefaultMic() {
    try {
        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        pDevice := 0
        ComCall(4, IMMDeviceEnumerator, "UInt", 1, "UInt", 0, "Ptr*", &pDevice)
        if !pDevice
            return -1
            
        IID_IAudioEndpointVolume := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", IID_IAudioEndpointVolume)
        
        pAudioEndpointVolume := 0
        ComCall(3, pDevice, "Ptr", IID_IAudioEndpointVolume, "UInt", 23, "Ptr", 0, "Ptr*", &pAudioEndpointVolume)
        ObjRelease(pDevice)
        if !pAudioEndpointVolume
            return -1
            
        muted := 0
        ComCall(15, pAudioEndpointVolume, "Int*", &muted)
        
        newMuted := !muted
        ComCall(14, pAudioEndpointVolume, "Int", newMuted, "Ptr", 0)
        
        ObjRelease(pAudioEndpointVolume)
        return newMuted
    }
    return -1
}

ShowMicOSD(isMuted) {
    global MicOsdGui, MicOsdHiding

    if (MicOsdGui) {
        UpdateMicOSD(isMuted)
        if MicOsdHiding {           ; revive it rather than stacking a second one
            MicOsdHiding := false
            try FadeGui(MicOsdGui, TuneAlpha("osdAlpha"))
        }
    } else {
        try {
            MicOsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale")
            
            if (isMuted) {
                MicOsdGui.BackColor := "8B0000" 
                txt := "🎙️ Mic Muted"
            } else {
                MicOsdGui.BackColor := "006400" 
                txt := "🎙️ Mic Active"
            }
            
            MicOsdGui.SetFont("s20 cWhite bold", "Segoe UI")
            MicOsdGui.AddText("vText x0 y15 w240 h40 BackgroundTrans Center", txt)

            RS_SetAlpha(MicOsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()
            
            MicOsdGui.Show("NoActivate w240 h70")
            RS_SetRegion(MicOsdGui.Hwnd, "0-0 w240 h70 r20-20", RS_PRI_ANIM)
            
            GetMicOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            MicOsdGui.Move(x, y)
            
            NotchAnim(MicOsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; Plain one-shot, same reasoning as the volume OSD: this was 127 frames of the
    ; animation loop spent comparing a deadline.
    SetTimer(HideMicOSD, -Tune("osdHide"))
}

UpdateMicOSD(isMuted) {
    global MicOsdGui
    if (isMuted) {
        MicOsdGui.BackColor := "8B0000"
        MicOsdGui["Text"].Text := "🎙️ Mic Muted"
    } else {
        MicOsdGui.BackColor := "006400"
        MicOsdGui["Text"].Text := "🎙️ Mic Active"
    }
}

HideMicOSD() {
    global MicOsdGui, MicOsdHiding
    if (!MicOsdGui)
        return
    MicOsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetMicOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, MicOsdGui.Hwnd)
    NotchAnim(MicOsdGui.Hwnd, cy, hiddenY, false, ClearMicOSD)
}

; Mirrors GetVolumeOSDPos so the two OSDs pick their monitor the same way. The
; mic OSD keeps its top-of-screen notch placement; only the monitor choice moved.
GetMicOSDPos(&x, &visibleY, &hiddenY) {
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    x := WL + (WR - WL - 240) // 2
    visibleY := WT + 10
    hiddenY := WT - 70
}

ClearMicOSD() {
    global MicOsdGui, MicOsdHiding
    MicOsdGui := ""
    MicOsdHiding := false
}

; ====== Quick Spotlight Launcher ======
ToggleSpotlight() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    
    if (SpotlightGui) {
        hwnd := 0
        try hwnd := SpotlightGui.Hwnd
        try SpotlightGui.Destroy()
        SpotlightGui := "", SpotlightInput := "", SpotlightResult := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
        return
    }


    SpotlightGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    SpotlightGui.BackColor := "202020" 
    
    SpotlightGui.SetFont("s24 cWhite", "Segoe UI")
    SpotlightInput := SpotlightGui.AddEdit("x20 y20 w600 h45 -VScroll -E0x200 Background202020 cWhite")
    
    SpotlightGui.SetFont("s14 cAAAAAA", "Segoe UI")
    SpotlightResult := SpotlightGui.AddText("x20 y85 w600 h35", "Type to search, calculate, or run...")
    
    SpotlightInput.OnEvent("Change", SpotlightOnChange)
    
    activeMon := MonitorGetPrimary()
    MonitorGet(activeMon, &L, &T, &R, &B)
    w := 640, h := 140
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 3 
    
    ; Round the corners and set the opacity BEFORE showing it. Doing it after Show
    ; meant one frame of a hard-edged, fully opaque grey rectangle before the
    ; region and alpha landed - a visible flash on every launch. The dimmer and the
    ; OSDs already did it in this order; this one did not.
    RS_SetRegion(SpotlightGui.Hwnd, "0-0 w640 h140 r20-20", RS_PRI_ANIM)
    RS_SetAlpha(SpotlightGui.Hwnd, 240, RS_PRI_ANIM)
    RS_Commit()
    SpotlightGui.Show("x" x " y" y " w" w " h" h)
}

SpotlightOnChange(ctrl, *) {
    global SpotlightResult
    text := Trim(ctrl.Value)
    if (text = "") {
        SpotlightResult.Text := "Type to search, calculate, or run..."
        return
    }

    ; A fresh MSHTML document per keystroke is not cheap, but it is only reached
    ; for arithmetic-looking input and a reused document has to be open()ed and
    ; close()d to be re-writable - which fails silently inside this try and would
    ; take the calculator with it. Left as it is on purpose.
    ; The character class is the guard: only digits, whitespace, brackets and the
    ; four operators ever reach eval, so nothing can escape arithmetic.
    if RegExMatch(text, "^[\d\+\-\*\/\.\(\)\s]+$") && RegExMatch(text, "\d") {
        try {
            doc := ComObject("htmlfile")
            doc.write("<body><script>document.write(eval('" text "'));</script></body>")
            ans := doc.body.innerText
            if (ans != "") {
                SpotlightResult.Text := "= " ans
                return
            }
        }
    }


    if FileExist(text) {
        SpotlightResult.Text := "Open path: " text
        return
    }
    
    SpotlightResult.Text := "Run: " text
}

SpotlightExecute() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    text := Trim(SpotlightInput.Value)
    if (text = "")
        return
        
    resText := SpotlightResult.Text
    
    if (SubStr(resText, 1, 2) == "= ") {
        A_Clipboard := LTrim(resText, "= ")
        ToggleSpotlight()
        return
    }
    
    ToggleSpotlight()
    try {
        Run(text)
    } catch {
        q := StrReplace(text, " ", "+")
        try Run("https://www.google.com/search?q=" q)
    }
}

; ====== Smart Active Border ======
GetAccentColor() {
    color := 0
    blend := 0
    hr := DllCall("dwmapi\DwmGetColorizationColor", "UInt*", &color, "Int*", &blend)
    if (hr == 0)
        return Format("{:06X}", color & 0xFFFFFF)
    return "00D7FF" 
}

SyncActiveBorderTimer() {
    global ActiveBorderEnabled
    ; A 50 ms timer, not a registered animation.
    ;
    ; ActiveBorderMonitorStep is a MONITOR - it polls the active window and
    ; returns true unconditionally - so registering it meant ActiveAnimations was
    ; never empty, the scheduler never hit its "nothing is animating" shutdown,
    ; and enabling the border pinned the 15 ms frame loop AND timeBeginPeriod(1)
    ; on for the rest of the session. That is the same "do not put a countdown in
    ; the scheduler" mistake the OSD auto-hides were fixed for, and 50 ms is the
    ; cadence this feature was always documented as using.
    ;
    ; DrawActiveBorder calls RS_Commit() itself, which is what a one-shot
    ; producer outside the frame loop has to do.
    if (ActiveBorderEnabled)
        SetTimer(ActiveBorderMonitorStep, 50)
    else {
        SetTimer(ActiveBorderMonitorStep, 0)
        DestroyActiveBorder()
    }
}

ActiveBorderMonitorStep() {
    global ActiveBorderEnabled, LastBorderHwnd, LastBorderX, LastBorderY, LastBorderW, LastBorderH
    if (!ActiveBorderEnabled)
        return

    hwnd := WinExist("A")
    if (!hwnd) {
        HideActiveBorder()
        return
    }
    
    ; Guarded, like IsMouseOverTaskbar: this runs 20 times a second on whatever
    ; window happens to be active, and the active window can be destroyed between
    ; WinExist("A") and the next line. An uncaught throw here would pop an error
    ; dialog and kill the timer, taking the feature out for the whole session.
    cls := "", style := 0
    try {
        cls := WinGetClass(hwnd)
        style := WinGetStyle(hwnd)
    } catch {
        HideActiveBorder()
        return
    }

    if (cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "AutoHotkeyGUI") {
        HideActiveBorder()
        return
    }

    if (!(style & 0x10000000) || (style & 0x01000000) || (style & 0x20000000)) { ; Not visible OR Maximized OR Minimized
        HideActiveBorder()
        return
    }


    ; Measure the window, never the render queue.
    ;
    ; This used to read a PENDING RS_Pos entry as if it were a position. Every
    ; move-only producer - Glide, MoveFast, the curtain, the toast bounce -
    ; queues w and h as -1 to mean SWP_NOSIZE, so W and H came back as -1, failed
    ; the "W < 50" sanity test below and hid the border. The result was that the
    ; border blinked out for the whole of every glide, snap, pulse and layout
    ; key: it disappeared exactly when the window was moving, which is when it
    ; was most visible that something was wrong.
    ;
    ; A queued rect is also a request, not a fact - it has not been applied yet,
    ; and a higher-priority write in the same flush can still replace it.
    {
        rect := Buffer(16, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rect, "uint", 16)
        if (hr == 0) {
            X := NumGet(rect, 0, "Int")
            Y := NumGet(rect, 4, "Int")
            R := NumGet(rect, 8, "Int")
            B := NumGet(rect, 12, "Int")
            W := R - X
            H := B - Y
        } else {
            try WinGetPos(&X, &Y, &W, &H, hwnd)
            catch {
                HideActiveBorder()
                return
            }
        }
    }
    
    if (W < 50 || H < 50) {
        HideActiveBorder()
        return
    }
    
    SizeChanged := (W != LastBorderW || H != LastBorderH)
    if (hwnd == LastBorderHwnd && X == LastBorderX && Y == LastBorderY && !SizeChanged)
        return
        
    LastBorderHwnd := hwnd
    LastBorderX := X, LastBorderY := Y, LastBorderW := W, LastBorderH := H
    
    DrawActiveBorder(X, Y, W, H, SizeChanged)
}

DrawActiveBorder(X, Y, W, H, SizeChanged:=true) {
    global ActiveBorderGui, ActiveBorderShown

    if (!ActiveBorderGui) {
        ActiveBorderGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale +E0x20")
        ActiveBorderGui.BackColor := (BorderColor = "auto") ? GetAccentColor() : BorderColor
        ; Created hidden on purpose, so the region and position are in place
        ; before it is ever shown - otherwise it flashes as a 1px dot at 0,0.
        ActiveBorderGui.Show("NoActivate Hide x0 y0 w1 h1")
        ActiveBorderShown := false
        SizeChanged := true
    }

    t := Tune("borderThick")

    try {
        if SizeChanged {
            rect1 := "0-0 w" W " h" t
            rect2 := "0-" (H-t) " w" W " h" t
            rect3 := "0-" t " w" t " h" (H-2*t)
            rect4 := (W-t) "-" t " w" t " h" (H-2*t)
            RS_SetRegion(ActiveBorderGui.Hwnd, rect1 "  " rect2 "  " rect3 "  " rect4, RS_PRI_ANIM)
        }

        RS_SetPos(ActiveBorderGui.Hwnd, X, Y, W, H, RS_PRI_ANIM)
        RS_SetAlpha(ActiveBorderGui.Hwnd, TuneAlpha("borderAlpha"), RS_PRI_ANIM)
        RS_Commit()

        ; And then actually show it. Nothing did: the window was created with
        ; "Hide" and only ever received SetWindowPos (SWP_NOACTIVATE, no
        ; SWP_SHOWWINDOW) and WinSetTransparent, neither of which shows a hidden
        ; window - so the border was never visible at all.
        if !ActiveBorderShown {
            ActiveBorderGui.Show("NoActivate")
            ActiveBorderShown := true
        }
    }
}

; Transient hide, for when focus moves to a window that gets no border. Hides
; rather than destroys: this fires on every focus change, and destroying meant a
; fresh Gui (plus a permanent set of RenderCore map entries for the dead handle)
; every single time.
HideActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    if (ActiveBorderGui && ActiveBorderShown) {
        try ActiveBorderGui.Hide()
        ActiveBorderShown := false
    }
}

; Real teardown, for switching the feature off and for exit.
DestroyActiveBorder() {
    global ActiveBorderGui, ActiveBorderShown, LastBorderHwnd
    LastBorderHwnd := 0
    ActiveBorderShown := false
    if (ActiveBorderGui) {
        hwnd := 0
        try hwnd := ActiveBorderGui.Hwnd
        try ActiveBorderGui.Destroy()
        ActiveBorderGui := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
    }
}

; ====== Always on Bottom (Desktop Widget) ======
GetDesktopHwnd() {
    desktopHwnd := WinExist("ahk_class Progman")
    hwnds := WinGetList("ahk_class WorkerW")
    for w in hwnds {
        if DllCall("FindWindowEx", "ptr", w, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0) {
            desktopHwnd := w
            break
        }
    }
    return desktopHwnd
}

ToggleAlwaysOnBottom() {
    global BottomWindows
    ; Deliberately NOT guarded with a `static busy` flag.
    ; #MaxThreadsPerHotkey 2 does let a second press interrupt this one, but
    ; every exit below is an early `return` - and AHK v2 has no `finally`, so a
    ; guard would have to be cleared on each of a dozen paths. Miss one and the
    ; flag latches true and the hotkey is dead for the rest of the session,
    ; which is far worse than the race: re-entry here re-runs the same branch
    ; and writes the same Map entry twice, which is idempotent.

    hwnd := WinExist("A")
    if !hwnd
        return

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return

    if BottomWindows.Has(hwnd) {
        RestoreFromBottom(hwnd)
        return
    }

    desktop := GetDesktopHwnd()
    if !desktop
        return

    X := "", Y := "", W := "", H := ""
    try WinGetPos(&X, &Y, &W, &H, hwnd)

    ; No GetParent() here on purpose. For a window without WS_CHILD - which is
    ; every window this hotkey accepts - Win32 GetParent returns the OWNER, not
    ; the parent. Recording that and handing it back to SetParent on restore
    ; turned an owned top-level window into a CHILD of its owner: clipped to the
    ; owner's client area, not alt-tabbable, and impossible to move back out.
    ; A top-level window's parent is the desktop, so restore passes 0.
    ;
    ; The return value must also be checked BEFORE we record anything: SetParent
    ; fails across integrity levels and for some shell/UWP windows, and on failure
    ; the window used to be listed as pinned anyway and then teleported by the
    ; ScreenToClient conversion below.
    if !DllCall("SetParent", "ptr", hwnd, "ptr", desktop, "ptr") {
        Notify("Cannot pin this window to the desktop")
        return
    }

    ; Record the screen rect: reparenting is undone at exit, and the window has to
    ; go back to where it was on screen, not to client coordinates of a desktop it
    ; is no longer a child of.
    BottomWindows[hwnd] := {x: X, y: Y, w: W, h: H}

    if (X != "") {
        pt := Buffer(8)
        NumPut("Int", X, pt, 0)
        NumPut("Int", Y, pt, 4)
        DllCall("ScreenToClient", "ptr", desktop, "ptr", pt)
        nX := NumGet(pt, 0, "Int")
        nY := NumGet(pt, 4, "Int")

        RS_SetPos(hwnd, nX, nY, W, H, RS_PRI_USER)
        RS_Commit()
    }
}

; Put a desktop-pinned window back where it came from. Shared by the hotkey and
; by Bye(), because a window left parented to WorkerW cannot be alt-tabbed to,
; cannot be moved normally, and dies with the next Explorer restart.
RestoreFromBottom(hwnd) {
    global BottomWindows
    if !BottomWindows.Has(hwnd)
        return
    info := BottomWindows[hwnd]
    BottomWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd)
        return

    ; Where it is now, so a widget the user dragged around stays put. GetWindowRect
    ; reports screen coordinates even for a child window, so this is still valid
    ; while it is parented to the desktop. The pinning-time rect is the fallback.
    x := info.x, y := info.y, w := info.w, h := info.h
    try WinGetPos(&x, &y, &w, &h, hwnd)

    ; 0 = the desktop, i.e. back to being a real top-level window. See the note in
    ; ToggleAlwaysOnBottom for why the old GetParent() handle was wrong.
    DllCall("SetParent", "ptr", hwnd, "ptr", 0, "ptr")

    if (x != "")
        RS_SetPos(hwnd, x, y, w, h, RS_PRI_USER)
    RS_SetZOrder(hwnd, 0, 0x0013, RS_PRI_USER)      ; HWND_TOP
    RS_Commit()
}


; ====== Proximity Ghost Window ======
GetDistToRect(px, py, rx, ry, rw, rh) {
    cx := Max(Min(px, rx + rw), rx)
    cy := Max(Min(py, ry + rh), ry)
    return Sqrt((px - cx)**2 + (py - cy)**2)
}

ToggleGhostMode() {
    global GhostWindows
    ; Deliberately NOT guarded with a `static busy` flag.
    ; #MaxThreadsPerHotkey 2 does let a second press interrupt this one, but
    ; every exit below is an early `return` - and AHK v2 has no `finally`, so a
    ; guard would have to be cleared on each of a dozen paths. Miss one and the
    ; flag latches true and the hotkey is dead for the rest of the session,
    ; which is far worse than the race: re-entry here re-runs the same branch
    ; and writes the same Map entry twice, which is idempotent.

    hwnd := WinExist("A")
    if !hwnd
        return

    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls = "" || cls = "WorkerW" || cls = "Progman" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return

    if GhostWindows.Has(hwnd) {
        UnGhostWindow(hwnd)
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitorStep, 0)
        SyncMediaCore()
        return
    }

    exStyle := 0
    try exStyle := WinGetExStyle(hwnd)
    catch
        return

    ; A window that is already click-through is not one we can take over: we
    ; would have no way to tell our change from its own. Previously this fell
    ; through and still forced always-on-top, leaving the window topmost with
    ; nothing recorded and no way to undo it.
    if (exStyle & 0x20)
        return

    try {
        WinSetExStyle("+0x20", hwnd)          ; WS_EX_TRANSPARENT
        ; Through the pipeline, not WinSetTransparent(255) directly: this still
        ; forces WS_EX_LAYERED on, but it also records 255 in RS_LastAlpha. A
        ; direct call left the cache stale, so the very first proximity write
        ; could be dropped as "already applied" and the window sat opaque until
        ; the mouse moved far enough to ask for a different value.
        ;
        ; A layer at factor 1.0 rather than a cleared layer, for the same
        ; reason: the mere presence of "ghost" keeps the record non-neutral, so
        ; the composed value can never collapse to "Off" and strip
        ; WS_EX_LAYERED back off while the cursor is sitting on the window.
        RS_SetAlphaLayer(hwnd, "ghost", 1.0, RS_PRI_AMBIENT)
        RS_Commit()
        WinSetAlwaysOnTop(1, hwnd)
    } catch
        return

    GhostWindows[hwnd] := {exStyle: exStyle}
    if (GhostWindows.Count == 1)
        SetTimer(GhostMonitorStep, 25)
    SyncMediaCore()
}

; Undo everything ToggleGhostMode did. Shared with Bye(), because a ghost left
; behind is a permanently click-through, always-on-top, semi-transparent window
; that the user has no way to recover without restarting the app.
UnGhostWindow(hwnd) {
    global GhostWindows
    if !GhostWindows.Has(hwnd)
        return
    orig := GhostWindows[hwnd]
    GhostWindows.Delete(hwnd)

    if !DllCall("IsWindow", "ptr", hwnd)
        return

    try {
        ; Clearing the layer, not forcing "Off": a window the user had also set
        ; to 50% with the wheel goes back to 50%, not to fully opaque.
        RS_ClearAlphaLayer(hwnd, "ghost", RS_PRI_AMBIENT)
        RS_Commit()                            ; nothing else will flush this
        if !(orig.exStyle & 0x20)
            WinSetExStyle("-0x20", hwnd)
        if !(orig.exStyle & 0x8)
            WinSetAlwaysOnTop(0, hwnd)
    }
}

GhostMonitorStep() {
    global GhostWindows

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)

    maxDist := Tune("ghostRange") + 0.0     ; float: it divides below
    minAlpha := TuneAlpha("ghostAlpha")
    maxAlpha := 255
    clickDist := Tune("ghostClick")
    anyMedia := MC_AnyMedia()          ; hoisted: this runs 40 times a second

    ; Clone() only when something actually died; the common case is that nothing
    ; has, and this timer runs 40 times a second.
    dead := ""
    for hwnd, info in GhostWindows {
        if !DllCall("IsWindow", "ptr", hwnd) {
            if !IsObject(dead)
                dead := []
            dead.Push(hwnd)
            continue
        }

        try {
            WinGetPos(&X, &Y, &W, &H, hwnd)
            dist := GetDistToRect(mx, my, X, Y, W, H)

            if (dist == 0 || (anyMedia && MC_IsMediaHwnd(hwnd)))
                targetAlpha := maxAlpha
            else if (dist >= maxDist)
                targetAlpha := minAlpha
            else {
                ratio := 1.0 - (dist / maxDist)
                targetAlpha := minAlpha + Integer(ratio * (maxAlpha - minAlpha))
            }
            
            ; Queue only. The single commit after the loop applies every ghost
            ; in one batched pass; committing in here meant one full flush per
            ; ghosted window, 40 times a second.
            if (!info.HasProp("lastAlpha") || info.lastAlpha != targetAlpha) {
                RS_SetAlphaLayer(hwnd, "ghost", targetAlpha / 255.0, RS_PRI_AMBIENT)
                info.lastAlpha := targetAlpha
            }

            ; Read the real style rather than caching it: WinGetExStyle costs
            ; 0.28 us, and reading it back is what makes this self-correcting if
            ; the window changes its own styles. Not worth caching.
            ;
            ; Hysteresis, not a bare threshold: a cursor resting near the
            ; boundary crosses it on the sub-pixel jitter of an ordinary hand,
            ; and each crossing rewrote WS_EX_TRANSPARENT 40 times a second -
            ; so the window flickered between clickable and not.
            isClickThrough := (WinGetExStyle(hwnd) & 0x20)
            if (dist < clickDist) {
                if (isClickThrough)
                    WinSetExStyle("-0x20", hwnd)
            } else if (dist > clickDist + 12) {
                if (!isClickThrough)
                    WinSetExStyle("+0x20", hwnd)
            }
        }
    }

    if IsObject(dead) {
        for hwnd in dead
            GhostWindows.Delete(hwnd)
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitorStep, 0)
    }

    ; A monitor timer, not an animation: nothing else flushes for it, so without
    ; this the proximity fade never reached the screen at all.
    RS_Commit()
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

QPC() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &count:=0)
    return count * 1000 / freq
}

; ============================================================================
; Shake to Find (macOS style cursor finder)
; ============================================================================
global ShakeFindActive := false
global ShakePrevX := 0
global ShakePrevY := 0
global ShakeDir := 0
global ShakeCount := 0
global ShakeLastTime := 0

global SF_Size := 0
global SF_TargetSize := 150
global SF_Vel := 0
global SF_Gui := 0
global SF_Hwnd := 0
global SF_Phase := 0
global SF_CircleSize := 200

; Creates the highlight overlay on first use. It used to be built at startup
; whether or not either consumer was switched on, which is a permanent
; always-on-top layered window for a feature that may never run.
;
; SF_Gui must be global. A Gui window dies with the last reference to its object,
; so keeping only its Hwnd left SF_Hwnd dangling the moment this function
; returned, and RenderShakeFind then threw inside a timer callback.
InitShakeFind() {
    global SF_Gui, SF_Hwnd
    if (SF_Gui && SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
        return true
    try {
        SF_Gui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
        SF_Gui.BackColor := "White"
        SF_Hwnd := SF_Gui.Hwnd
        WinSetTransparent(160, SF_Hwnd)
        return true
    }
    SF_Gui := 0, SF_Hwnd := 0
    return false
}

; The Sync* this timer never had. ShakeDetector polls the mouse and the idle
; timer 25 times a second and serves TWO features; with both off it was pure
; overhead, and it was armed unconditionally from InitShakeFind at startup.
SyncShakeDetector() {
    global ShakeFindEnabled, CursorYawnEnabled, ShakeFindActive
    if (ShakeFindEnabled || CursorYawnEnabled) {
        SetTimer(ShakeDetector, 40)
        return
    }
    SetTimer(ShakeDetector, 0)
    ; Switched off mid-highlight: take the circle down, or it is stranded at
    ; whatever size it had reached with nothing left to shrink it.
    if ShakeFindActive {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        global SF_Hwnd
        if (SF_Hwnd && DllCall("IsWindow", "ptr", SF_Hwnd))
            try DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0)   ; SW_HIDE
    }
}

ShakeDetector() {
    global ShakeFindEnabled, ShakeFindActive
    global ShakePrevX, ShakePrevY, ShakeDir, ShakeCount, ShakeLastTime
    global SF_TargetSize, SF_Phase
    
    global CursorYawnEnabled, CursorYawnActive, CursorYawnIdleTime
    if (CursorYawnEnabled) {
        idle := A_TimeIdlePhysical
        if (idle > CursorYawnIdleTime) {
            CursorYawnActive := true
        } else if (idle < 100 && CursorYawnActive) {
            CursorYawnActive := false
            TriggerCursorYawn()
        }
    }
    
    if (!ShakeFindEnabled)
        return
        
    MouseGetPos(&mx, &my)
    dx := mx - ShakePrevX
    dy := my - ShakePrevY
    ShakePrevX := mx
    ShakePrevY := my
    
    t := A_TickCount
    if (t - ShakeLastTime > 300) {
        ShakeCount := 0
    }
    
    if (Abs(dx) > 15) {
        dir := dx > 0 ? 1 : -1
        if (dir != ShakeDir) {
            ShakeDir := dir
            ShakeCount++
            ShakeLastTime := t
            
            if (ShakeCount >= Tune("shakeCount") && !ShakeFindActive) {
                ShakeCount := 0
                StartShakeFind()
            }
        }
    }
    
    if (ShakeFindActive && t - ShakeLastTime > 200) {
        if (SF_Phase == 1) {
            SF_Phase := 2
            SF_TargetSize := 0
        }
    }
}

StartShakeFind() {
    global ShakeFindActive, SF_Phase, SF_TargetSize, SF_Size, SF_Vel
    if !InitShakeFind()
        return
    ShakeFindActive := true
    SF_Phase := 1
    SF_TargetSize := Tune("shakeSize")
    SF_Size := 10
    SF_Vel := 0
    SetTimer(RenderShakeFind, 16)
}

RenderShakeFind() {
    global ShakeFindActive, SF_Size, SF_TargetSize, SF_Vel, SF_Hwnd, SF_CircleSize

    ; 16 ms timer: a throw here would pop an error dialog and kill the timer for
    ; the rest of the session, so the overlay must be verified before it is used.
    if (!SF_Hwnd || !DllCall("IsWindow", "ptr", SF_Hwnd)) {
        ShakeFindActive := false
        SetTimer(RenderShakeFind, 0)
        return
    }

    if (!ShakeFindActive) {
        SetTimer(RenderShakeFind, 0)
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        return
    }
    
    SF_Vel += (SF_TargetSize - SF_Size) * 0.4
    SF_Vel *= 0.6 ; friction
    SF_Size += SF_Vel
    
    if (SF_Size < 2 && SF_TargetSize == 0) {
        ShakeFindActive := false
        DllCall("ShowWindow", "ptr", SF_Hwnd, "int", 0) ; SW_HIDE
        SetTimer(RenderShakeFind, 0)
        return
    }
    
    MouseGetPos(&mx, &my)
    s := Round(SF_Size)
    if (s > SF_CircleSize)
        s := SF_CircleSize
        
    if (s > 0) {
        try {
            WinSetRegion("0-0 w" s " h" s " E", SF_Hwnd)
            DllCall("SetWindowPos", "ptr", SF_Hwnd, "ptr", -1, "int", mx - s//2, "int", my - s//2, "int", s, "int", s, "uint", 0x50) ; SWP_NOACTIVATE | SWP_SHOWWINDOW
        } catch {
            ShakeFindActive := false
            SetTimer(RenderShakeFind, 0)
        }
    }
}

TriggerCursorYawn() {
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "White"
    WinSetTransparent(220, guiObj.Hwnd)
    guiObj.Show("NA Hide")
    
    animKey := "CursorYawn_" . guiObj.Hwnd
    start := QPC()
    ms := 1000
    
    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            guiObj.Destroy()
            return false
        }
        
        baseSize := 24
        w := baseSize
        h := baseSize
        
        if (t < 0.35) {
            p := t / 0.35
            ease := 1 - (1 - p) ** 3
            h := baseSize + (45 * ease)
            w := baseSize - (12 * ease)
        } else if (t < 0.7) {
            p := (t - 0.35) / 0.35
            ease := 0.5 - Cos(p * 3.14159) * 0.5
            h := baseSize + 45 - (55 * ease)
            w := baseSize - 12 + (40 * ease)
        } else {
            p := (t - 0.7) / 0.3
            ease := p * p
            h := (baseSize - 10) * (1 - ease)
            w := (baseSize + 28) * (1 - ease)
            
            alpha := Round(220 * (1 - ease))
            try WinSetTransparent(alpha, guiObj.Hwnd)
        }
        
        if (w < 2)
            w := 2
        if (h < 2)
            h := 2
            
        WinSetRegion("0-0 w" Round(w) " h" Round(h) " E", guiObj.Hwnd)
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(mx - w/2), "int", Round(my - h/2), "int", Round(w), "int", Round(h), "uint", 0x14)
        return true
    }
    
    guiObj.Show("NA x" mx " y" my " w" 24 " h" 24)
    RegisterAnimation(animKey, Step)
}

; ============================================================================
; Magnetic Window Groups
; ============================================================================
; This declaration was missing entirely. Every user of MagGroups declares it
; `global` and then calls .Has() on it, so with nothing ever assigning it AHK's
; default #Warn VarUnset popped a modal warning dialog on startup, and the first
; drag would have thrown on an unset variable. Grouping could never have worked.
global MagGroups := Map()

GroupWindows(h1, h2) {
    global MagGroups
    g1 := MagGroups.Has(h1) ? MagGroups[h1] : [h1]
    g2 := MagGroups.Has(h2) ? MagGroups[h2] : [h2]
    
    if (g1 = g2)
        return
        
    newGroup := []
    for h in g1
        newGroup.Push(h)
    for h in g2 {
        found := false
        for eh in newGroup
            if (eh = h)
                found := true
        if !found
            newGroup.Push(h)
    }
    
    for h in newGroup
        MagGroups[h] := newGroup
}

UngroupWindow(h) {
    global MagGroups
    if !MagGroups.Has(h)
        return
    grp := MagGroups[h]
    MagGroups.Delete(h)
    
    newGrp := []
    for eh in grp {
        if (eh != h)
            newGrp.Push(eh)
    }
    
    if (newGrp.Length == 1) {
        MagGroups.Delete(newGrp[1])
    } else {
        for eh in newGrp
            MagGroups[eh] := newGrp
    }
}

; ============================================================================
; Rubber-Band Elastic Scroll
; ============================================================================
global ElasticHwnd := 0
global ElasticOffsetY := 0
global ElasticTargetY := 0
global ElasticVel := 0
global ElasticBaseX := 0
global ElasticBaseY := 0
global ElasticEdgeStates := Map()
global ElasticAwayCounts := Map()

ElasticScroll(hwnd, dir, startX, startY) {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global ElasticEdgeStates, ElasticAwayCounts
    
    if !ElasticEdgeStates.Has(hwnd) {
        ElasticEdgeStates[hwnd] := 0
        ElasticAwayCounts[hwnd] := 0
    }
    
    state := ElasticEdgeStates[hwnd]
    threshold := 5
    
    if (dir == 1) {
        if (state == 1) {
            return
        } else if (state == -1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := 1
            ElasticAwayCounts[hwnd] := 0
        }
    } else {
        if (state == -1) {
            return
        } else if (state == 1) {
            ElasticAwayCounts[hwnd] += 1
            if (ElasticAwayCounts[hwnd] >= threshold) {
                ElasticEdgeStates[hwnd] := 0
                ElasticAwayCounts[hwnd] := 0
            }
            return
        } else {
            ElasticEdgeStates[hwnd] := -1
            ElasticAwayCounts[hwnd] := 0
        }
    }
    
    if (ElasticHwnd != hwnd) {
        if (ElasticHwnd) {
            try WinMove(ElasticBaseX, ElasticBaseY,,, ElasticHwnd)
        }
        ElasticHwnd := hwnd
        ElasticBaseX := startX
        ElasticBaseY := startY
        ElasticOffsetY := 0
        ElasticTargetY := 0
        ElasticVel := 0
        RegisterAnimation("ElasticScroll", ElasticScrollCallback)
    }
    
    ElasticTargetY := dir * Tune("elasticAmt")
        
    SetTimer(ElasticTimeout, -150)
}

ElasticTimeout() {
    global ElasticTargetY
    ElasticTargetY := 0
}

ElasticScrollCallback(dt, now) {
    global ElasticHwnd, ElasticOffsetY, ElasticTargetY, ElasticVel, ElasticBaseX, ElasticBaseY
    global DragHwnd, FRAME_MS

    if (!DllCall("IsWindow", "ptr", ElasticHwnd) || DragHwnd == ElasticHwnd) {
        if (DragHwnd == ElasticHwnd)
            try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY, -1, -1, RS_PRI_ANIM)
        ElasticHwnd := 0
        return false
    }

    ; The only real spring in the program, and it was the last thing still
    ; integrating per frame rather than per millisecond: a heavy frame made the
    ; rubber band snap back faster, not later. Scaling the stiffness by dt and
    ; the damping by an exponential of dt keeps the same shape at any frame rate,
    ; and reproduces the old 0.4 / 0.6 constants exactly at the nominal frame.
    if (dt <= 0)
        dt := FRAME_MS
    steps := dt / FRAME_MS
    ElasticVel += (ElasticTargetY - ElasticOffsetY) * 0.4 * steps
    ElasticVel *= Exp(-0.5108256 * steps)          ; ln(1/0.6) per nominal frame
    ElasticOffsetY += ElasticVel * steps

    if (Abs(ElasticTargetY) < 1 && Abs(ElasticOffsetY) < 1 && Abs(ElasticVel) < 1) {
        try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY), -1, -1, RS_PRI_ANIM)
        ElasticHwnd := 0
        return false
    }
    
    try RS_SetPos(ElasticHwnd, ElasticBaseX, ElasticBaseY + Round(ElasticOffsetY), -1, -1, RS_PRI_ANIM)
    return true
}

; ============================================================================
; Text Selection Magnifier
; ============================================================================
global MagActive := false
global MagHostGui := ""
global MagFrameGui := ""
global MagChildHwnd := 0
global MagFailed := false
global MagStartX := 0, MagStartY := 0

; Returns false if the magnifier is not usable on this machine. Every step is
; checked: MagInitialize can fail outright, and the whole thing is inside a try
; because it runs from a mouse-drag timer where a throw is an error dialog.
;
; MagFailed latches, so a machine without a working Magnification.dll pays the
; failed init exactly once instead of on every text drag.
InitMag() {
    global MagHostGui, MagFrameGui, MagChildHwnd, MagFailed

    if MagFailed
        return false
    try {
        if !DllCall("LoadLibrary", "str", "Magnification.dll", "ptr")
            throw Error("Magnification.dll")
        if !DllCall("Magnification\MagInitialize")
            throw Error("MagInitialize")

        MagFrameGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        MagFrameGui.BackColor := "2A2A2A"
        WinSetRegion("0-0 w144 h144 E", MagFrameGui.Hwnd)

        ; WS_EX_LAYERED (0x80000) is REQUIRED on the host of a magnifier control -
        ; the API documents it, and without it the control has no surface to
        ; present into, which is why this effect had never actually shown a loupe.
        MagHostGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x80000")
        WinSetRegion("0-0 w140 h140 E", MagHostGui.Hwnd)

        MagChildHwnd := DllCall("CreateWindowEx", "uint", 0
            , "str", "Magnifier"
            , "str", "MagnifierWindow"
            , "uint", 0x50000000 ; WS_CHILD | WS_VISIBLE
            , "int", 0, "int", 0, "int", 140, "int", 140
            , "ptr", MagHostGui.Hwnd, "ptr", 0, "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "ptr", 0, "ptr")
        if !MagChildHwnd
            throw Error("CreateWindowEx Magnifier")

        Transform := Buffer(36, 0)
        NumPut("float", 2.0, Transform, 0)
        NumPut("float", 2.0, Transform, 16)
        NumPut("float", 1.0, Transform, 32)
        DllCall("Magnification\MagSetWindowTransform", "ptr", MagChildHwnd, "ptr", Transform)
        return true
    } catch as e {
        MagFailed := true
        MagChildHwnd := 0
        try MagFrameGui.Destroy()
        try MagHostGui.Destroy()
        MagFrameGui := "", MagHostGui := ""
        WriteLog("magnifier unavailable - " e.Message)
        return false
    }
}

; Returns whether the loupe is actually on screen. The caller MUST honour it:
; arming UpdateMag regardless is what turned a missing Magnification.dll into an
; error dialog on every text drag, because UpdateMag then dereferenced
; MagFrameGui.Hwnd on an empty string, outside any try, from a 16 ms timer.
ShowMag(mx, my) {
    global MagHostGui, MagFrameGui, MagChildHwnd
    if (!MagChildHwnd && !InitMag())
        return false
    if (!MagFrameGui || !MagHostGui)
        return false
    try {
        MagFrameGui.Show("x-1000 y-1000 w144 h144 NoActivate")
        MagHostGui.Show("x-1000 y-1000 w140 h140 NoActivate")
        return true
    }
    return false
}

HideMag() {
    global MagHostGui, MagFrameGui
    if (MagHostGui) {
        MagHostGui.Hide()
        MagFrameGui.Hide()
    }
}

CheckMagDrag() {
    global MagStartX, MagStartY, MagActive
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckMagDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - MagStartX) > 5 || Abs(my - MagStartY) > 5) {
        SetTimer(CheckMagDrag, 0)
        if ShowMag(mx, my) {
            MagActive := true
            RegisterAnimation("MagLoupe", MagCallback)
        }
    }
}

MagCallback(dt, now) {
    global MagActive, MagChildHwnd, MagHostGui, MagFrameGui
    if (!GetKeyState("LButton", "P")) {
        MagActive := false
        HideMag()
        return false
    }

    if (!MagChildHwnd || !MagFrameGui || !MagHostGui) {
        MagActive := false
        return false
    }

    try {
        MouseGetPos(&mx, &my)
        SourceRect := Buffer(16, 0)
        NumPut("int", mx - 35, SourceRect, 0)
        NumPut("int", my - 35, SourceRect, 4)
        NumPut("int", mx + 35, SourceRect, 8)
        NumPut("int", my + 35, SourceRect, 12)
        DllCall("Magnification\MagSetWindowSource", "ptr", MagChildHwnd, "ptr", SourceRect)
        
        RS_SetPos(MagFrameGui.Hwnd, mx - 72, my - 162, -1, -1, RS_PRI_ANIM)
        RS_SetPos(MagHostGui.Hwnd, mx - 70, my - 160, -1, -1, RS_PRI_ANIM)
    }
    return true
}

; ============================================================================
; Smart Tiling Grid
; ============================================================================
global GridActive := false
global GridHoverZone := 0
global SmartGridZones := []
global SmartGridGuis := []

ShowSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridActive, GridHoverZone
    
    MouseGetPos(&mx, &my)
    mon := MonitorIndexAt(mx, my)
    if !WorkAreaOf(mon, &wl, &wt, &wr, &wb)
        return
    w := wr - wl, h := wb - wt
    SmartGridZones := []
    if (w / h > 2.0) {
        cw := w // 3
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wl + cw*2, B: wb})
        SmartGridZones.Push({L: wl + cw*2, T: wt, R: wr, B: wb})
    } else {
        cw := w // 2, ch := h // 2
        SmartGridZones.Push({L: wl, T: wt, R: wl + cw, B: wb})
        SmartGridZones.Push({L: wl + cw, T: wt, R: wr, B: wt + ch})
        SmartGridZones.Push({L: wl + cw, T: wt + ch, R: wr, B: wb})
    }
    
    gap := Tune("gridGap")
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (SmartGridGuis.Length < A_Index) {
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            SmartGridGuis.Push(g)
        }
        g := SmartGridGuis[A_Index]
        g.BackColor := "111111"
        WinSetTransparent(100, g.Hwnd)
        
        gx := z.L + gap, gy := z.T + gap, gw := (z.R - z.L) - gap * 2, gh := (z.B - z.T) - gap * 2
        g.Show("x" gx " y" gy " w" gw " h" gh " NoActivate")
    }
    
    GridHoverZone := 0
    GridActive := true
}

UpdateSmartGrid() {
    global SmartGridZones, SmartGridGuis, GridHoverZone
    
    MouseGetPos(&mx, &my)
    hovered := 0
    loop SmartGridZones.Length {
        z := SmartGridZones[A_Index]
        if (mx >= z.L && mx <= z.R && my >= z.T && my <= z.B) {
            hovered := A_Index
            break
        }
    }
    
    if (hovered != GridHoverZone) {
        if (GridHoverZone > 0) {
            g := SmartGridGuis[GridHoverZone]
            g.BackColor := "111111"
            WinSetTransparent(100, g.Hwnd)
        }
        GridHoverZone := hovered
        if (hovered > 0) {
            g := SmartGridGuis[hovered]
            g.BackColor := "0078D7"
            WinSetTransparent(180, g.Hwnd)
        }
    }
}

HideSmartGrid() {
    global SmartGridGuis, GridActive, GridHoverZone
    for g in SmartGridGuis {
        g.Hide()
    }
    GridActive := false
    GridHoverZone := 0
}

ApplyGridZone(hwnd, zoneIndex) {
    global SmartGridZones
    if (zoneIndex < 1 || zoneIndex > SmartGridZones.Length)
        return
    z := SmartGridZones[zoneIndex]

    ; Unguarded, this throws when the window dies between FinishDrag's IsWindow
    ; check and here - which is a real race, because FinishDrag runs from a -50 ms
    ; one-shot. The throw killed the timer thread before HideSmartGrid() could
    ; run, stranding three dark zone overlays on screen until the app restarted.
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY)
        return
    frameW := fR - fL
    frameH := fB - fT
    try WinGetPos(,, &rawW, &rawH, hwnd)
    catch
        return
        
    diffW := rawW - frameW
    diffH := rawH - frameH
    diffX := fL - winX
    diffY := fT - winY
    
    finalX := z.L - diffX
    finalY := z.T - diffY
    finalW := (z.R - z.L) + diffW
    finalH := (z.B - z.T) + diffH
    
    gap := Tune("gridGap")
    destX := finalX + gap
    destY := finalY + gap
    destW := finalW - gap*2
    destH := finalH - gap*2
    
    try WinMove(destX, destY, destW, destH, hwnd)
    catch
        return
    RememberPosition(hwnd)

    global MomentumTiltEnabled
    if (MomentumTiltEnabled) {
        cpx := (z.L == 0) ? -15 : ((z.R >= A_ScreenWidth) ? 15 : 0)
        cpy := (z.T == 0) ? -15 : ((z.B >= A_ScreenHeight) ? 15 : 0)
        if (cpx != 0 || cpy != 0)
            BounceSqueeze(hwnd, destX, destY, destW, destH, cpx, cpy)
    }
}

; ============================================================================
; Mouse & Cursors FX
; ============================================================================

; Armed by SyncCursorFxTimer() rather than unconditionally at load.
SyncCursorFxTimer() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (BreatheCursorEnabled) {
        SetTimer(CheckMouseIdle, 1000)
        return
    }
    SetTimer(CheckMouseIdle, 0)
    if BreatheCursorActive {
        BreatheCursorActive := false
        StopBreatheCursor()
    }
}

global BreatheCursorActive := false
global BreatheGui := ""
global BreatheStart := 0

CheckMouseIdle() {
    global BreatheCursorEnabled, BreatheCursorActive
    if (!BreatheCursorEnabled)
        return
        
    if (A_TimeIdleMouse > 10000) { 
        if (!BreatheCursorActive) {
            BreatheCursorActive := true
            StartBreatheCursor()
        }
    } else {
        if (BreatheCursorActive) {
            BreatheCursorActive := false
            StopBreatheCursor()
        }
    }
}

StartBreatheCursor() {
    global BreatheGui, BreatheStart
    if (!BreatheGui) {
        BreatheGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        BreatheGui.BackColor := "White"
        RS_SetRegion(BreatheGui.Hwnd, "0-0 w40 h40 E", RS_PRI_ANIM)
        RS_SetAlpha(BreatheGui.Hwnd, 0, RS_PRI_ANIM)
        RS_Commit()
        BreatheGui.Show("NA")
    }
    BreatheStart := QPC()
    RegisterAnimation("BreatheCursor", UpdateBreathe)
}

StopBreatheCursor() {
    global BreatheGui
    CancelAnimation("BreatheCursor")
    if (BreatheGui) {
        RS_SetAlpha(BreatheGui.Hwnd, "Off", RS_PRI_ANIM)
        BreatheGui.Hide()
        RS_Commit()
    }
}

UpdateBreathe(dt, now) {
    global BreatheGui, BreatheStart, BreatheCursorActive
    if (!BreatheCursorActive) {
        RS_SetAlpha(BreatheGui.Hwnd, "Off", RS_PRI_ANIM)
        BreatheGui.Hide()
        return false
    }
    MouseGetPos(&mx, &my)
    t := now - BreatheStart
    cycle := Mod(t, 3000) / 3000
    val := (Sin(cycle * 6.28318 - 1.57079) + 1) / 2
    size := Round(20 + 20 * val)
    alpha := Round(20 + 40 * val)
    
    RS_SetRegion(BreatheGui.Hwnd, "0-0 w" size " h" size " E", RS_PRI_ANIM)
    RS_SetAlpha(BreatheGui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(BreatheGui.Hwnd, mx - size//2, my - size//2, -1, -1, RS_PRI_ANIM)
    return true
}

global Ripples := []
SpawnRipple(x, y) {
    global Ripples
    idx := 0
    loop Ripples.Length {
        if (!Ripples[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Ripples.Length >= 5) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "White"
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0}
        Ripples.Push(r)
        idx := Ripples.Length
    }
    
    r := Ripples[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    r.Gui.Show("NA")
    
    RegisterAnimation("Ripple_" idx, RippleCallback.Bind(idx))
}

RippleCallback(idx, dt, now) {
    global Ripples
    r := Ripples[idx]
    if (!r.Active)
        return false
        
    t := now - r.Start
    if (t > 300) {
        r.Active := false
        RS_SetAlpha(r.Gui.Hwnd, "Off", RS_PRI_ANIM)
        r.Gui.Hide()
        return false
    }
    
    ease := 1 - (1 - (t / 300)) ** 2
    size := Round(10 + 40 * ease)
    alpha := Round(80 * (1 - ease))
    
    RS_SetRegion(r.Gui.Hwnd, "0-0 w" size " h" size " E", RS_PRI_ANIM)
    RS_SetAlpha(r.Gui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(r.Gui.Hwnd, r.x - size//2, r.y - size//2, -1, -1, RS_PRI_ANIM)
    return true
}

global DragTrailGui := ""
global DragTrailActive := false
global DragTrailX := 0, DragTrailY := 0, DragTrailVX := 0, DragTrailVY := 0

CheckElasticDrag() {
    global DragTrailStartX, DragTrailStartY, DragTrailActive, DragTrailX, DragTrailY, DragTrailGui
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckElasticDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - DragTrailStartX) > 5 || Abs(my - DragTrailStartY) > 5) {
        SetTimer(CheckElasticDrag, 0)
        DragTrailActive := true
        if (!DragTrailGui) {
            DragTrailGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            DragTrailGui.BackColor := "Gray"
            WinSetRegion("0-0 w16 h16 E", DragTrailGui.Hwnd)
        }
        DragTrailX := mx, DragTrailY := my
        DragTrailVX := 0
        DragTrailVY := 0
        RS_SetAlpha(DragTrailGui.Hwnd, 80, RS_PRI_ANIM)
        RS_Commit()
        DragTrailGui.Show("x-1000 y-1000 w16 h16 NoActivate")
        RegisterAnimation("DragTrail", DragTrailCallback)
    }
}

DragTrailCallback(dt, now) {
    global DragTrailGui, DragTrailActive, DragTrailX, DragTrailY, DragTrailVX, DragTrailVY
    if (!GetKeyState("LButton", "P")) {
        DragTrailActive := false
        RS_SetAlpha(DragTrailGui.Hwnd, "Off", RS_PRI_ANIM)
        DragTrailGui.Hide()
        return false
    }
    
    MouseGetPos(&mx, &my)
    dx := mx - DragTrailX
    dy := my - DragTrailY
    DragTrailVX += dx * 0.2
    DragTrailVY += dy * 0.2
    DragTrailVX *= 0.7
    DragTrailVY *= 0.7
    DragTrailX += DragTrailVX
    DragTrailY += DragTrailVY
    
    RS_SetAlpha(DragTrailGui.Hwnd, 80, RS_PRI_ANIM)
    RS_SetPos(DragTrailGui.Hwnd, Round(DragTrailX - 8), Round(DragTrailY - 8), -1, -1, RS_PRI_ANIM)
    return true
}

; ApplyUi (when the checkbox is cleared) and Bye() both call this. PushBackWindow
; pins a window at 98% size and alpha 210, and BringForwardWindow was the only
; reversal - reachable only from ApplyFocusDepth, which only runs while the
; feature is on. So turning Focus Depth off, or exiting, left every window the
; user had ever switched away from permanently shrunk and translucent.
RestoreFocusDepth() {
    global PushedBackWindows
    for hwnd, orig in PushedBackWindows.Clone() {
        try CancelAnimation("FocusDepth_" hwnd)
        if (DllCall("IsWindow", "ptr", hwnd)) {
            ; Same staleness rule as BringForwardWindow: only hand the geometry
            ; back if the window is still where we parked it. Anything else has
            ; moved it since, and its position is now more correct than ours.
            if FocusDepthAtPushedRect(hwnd, orig)
                try RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_USER)
            try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_USER)
        }
    }
    PushedBackWindows := Map()
}

; Is this window still sitting at the rect we pushed it back to?
;
; PushBackWindow captures the pre-shrink rect and BringForwardWindow restores to
; it. If a snap, a glide, a layout key or the app itself moved or resized the
; window while it was pushed back, restoring that captured rect teleports it to
; a position the user has not seen for minutes. Comparing against the rect we
; actually left it at is what tells the two cases apart.
FocusDepthAtPushedRect(hwnd, orig) {
    try WinGetPos(&cx, &cy, &cw, &ch, hwnd)
    catch
        return false
    if (cx = "" || cw = "")
        return false
    return (Abs(cx - orig.px) <= 2 && Abs(cy - orig.py) <= 2
         && Abs(cw - orig.pw) <= 2 && Abs(ch - orig.ph) <= 2)
}

ApplyFocusDepth(newActive) {
    global LastActiveHwnd, PushedBackWindows
    if (LastActiveHwnd && LastActiveHwnd != newActive && DllCall("IsWindow", "ptr", LastActiveHwnd)) {
        PushBackWindow(LastActiveHwnd)
    }
    if (newActive && DllCall("IsWindow", "ptr", newActive)) {
        BringForwardWindow(newActive)
    }
    LastActiveHwnd := newActive
}

; RS_PRI_ANIM, not RS_PRI_USER, throughout this pair.
;
; Focus Depth fires on every activation, so at USER priority it out-ranked the
; glide, the bounce and the pulse on whatever window you had just switched away
; from - the depth animation won every arbitration and the other effect silently
; produced nothing. It is an ambient depth cue, not a user command; ANIM is the
; band it belongs in, and RestoreFocusDepth keeps USER because that IS explicit.
PushBackWindow(hwnd) {
    global PushedBackWindows
    ; Never fight a motion that is already running. A glide, bounce or layout
    ; move owns this window's geometry, and activating another window mid-slide
    ; used to resize it out from under the animation.
    if Anim_Owner(hwnd, "geom")
        return
    ; A maximized window cannot be scaled down and put back sensibly - the OS
    ; owns its rect - so it gets the alpha cue only.
    try {
        if (WinGetMinMax(hwnd) != 0)
            return
    } catch
        return
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    ; The rect we will leave it at, computed once so the settle frame, the
    ; staleness test and the restore all agree on it.
    pw := Round(w * 0.98)
    ph := Round(h * 0.98)
    px := x + Round((w - pw) / 2)
    py := y + Round((h - ph) / 2)
    PushedBackWindows[hwnd] := {x: x, y: y, w: w, h: h, px: px, py: py, pw: pw, ph: ph}

    animKey := "FocusDepth_" hwnd
    start := QPC()
    ms := 150

    PushBackStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, px, py, pw, ph, RS_PRI_ANIM)
            try RS_SetAlphaLayer(hwnd, "depth", 210 / 255.0, RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        scale := 1.0 - (0.02 * ease)
        nw := Round(w * scale)
        nh := Round(h * scale)
        nx := x + Round((w - nw) / 2)
        ny := y + Round((h - nh) / 2)

        RS_SetPos(hwnd, nx, ny, nw, nh, RS_PRI_ANIM)
        try RS_SetAlphaLayer(hwnd, "depth", (255 - (45 * ease)) / 255.0, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, PushBackStep)
}

BringForwardWindow(hwnd) {
    global PushedBackWindows
    if (!PushedBackWindows.Has(hwnd))
        return

    orig := PushedBackWindows[hwnd]
    PushedBackWindows.Delete(hwnd)

    animKey := "FocusDepth_" hwnd

    ; The window has been moved or resized since we pushed it back, so the rect
    ; we captured is stale and restoring it would teleport the window. Give the
    ; opacity back and leave the geometry to whoever owns it now.
    if !FocusDepthAtPushedRect(hwnd, orig) {
        CancelAnimation(animKey)
        try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_ANIM)
        RS_Commit()                    ; one-shot: no animation will flush this
        return
    }

    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return
    if (w = 0 || h = 0)
        return

    start := QPC()
    ms := 150

    BringForwardStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, orig.x, orig.y, orig.w, orig.h, RS_PRI_ANIM)
            try RS_ClearAlphaLayer(hwnd, "depth", RS_PRI_ANIM)
            return false
        }

        ease := 1 - (1 - t) ** 2
        curW := w + Round((orig.w - w) * ease)
        curH := h + Round((orig.h - h) * ease)
        curX := orig.x + Round((orig.w - curW) / 2)
        curY := orig.y + Round((orig.h - curH) / 2)

        RS_SetPos(hwnd, curX, curY, curW, curH, RS_PRI_ANIM)
        try RS_SetAlphaLayer(hwnd, "depth", (210 + 45 * ease) / 255.0, RS_PRI_ANIM)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, BringForwardStep)
}






global Sparks := []
OnTypingSpark(ih, vk, sc) {
    global SparkTypingEnabled
    if (!SparkTypingEnabled)
        return
        
    if !CaretGetPos(&cx, &cy)
        return
        
    SpawnSpark(cx, cy)
}

SpawnSpark(x, y) {
    global Sparks
    idx := 0
    loop Sparks.Length {
        if (!Sparks[A_Index].Active) {
            idx := A_Index
            break
        }
    }
    if (!idx) {
        if (Sparks.Length >= 30) 
            return
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        g.BackColor := "FFAA00"
        WinSetRegion("0-0 w4 h4 E", g.Hwnd)
        r := {Gui: g, Active: false, Start: 0, x: 0, y: 0, vx: 0, vy: 0}
        Sparks.Push(r)
        idx := Sparks.Length
    }
    
    r := Sparks[idx]
    r.Active := true
    r.Start := QPC()
    r.x := x
    r.y := y
    r.vx := (Random() - 0.5) * 6
    r.vy := (Random() - 0.5) * 6 - 2
    
    RS_SetAlpha(r.Gui.Hwnd, 200, RS_PRI_ANIM)
    RegisterAnimation("Spark_" idx, SparkCallback.Bind(idx))
}

SparkCallback(idx, dt, now) {
    global Sparks
    r := Sparks[idx]
    if (!r.Active)
        return false
        
    t := now - r.Start
    if (t > 400) {
        r.Active := false
        RS_SetAlpha(r.Gui.Hwnd, "Off", RS_PRI_ANIM)
        r.Gui.Hide()
        return false
    }
    
    r.vy += 0.2 
    r.x += r.vx
    r.y += r.vy
    alpha := Round(200 * (1 - (t / 400)))
    
    RS_SetAlpha(r.Gui.Hwnd, alpha, RS_PRI_ANIM)
    RS_SetPos(r.Gui.Hwnd, r.x, r.y, -1, -1, RS_PRI_ANIM)
    return true
}

; Gated in the hotkey criteria rather than re-sending #d from the body. With the
; feature off the key is simply not claimed, so Windows' own show-desktop runs -
; CLAUDE.md lists Win+D as deliberately not touched.
#HotIf CurtainDropEnabled
#!d:: {
    global CurtainDropped, CurtainWindows

    if (CurtainDropped) {
        CurtainDropped := false
        for hwnd, rect in CurtainWindows {
            if DllCall("IsWindow", "ptr", hwnd) {
                CurtainBounceUp(hwnd, rect.x, rect.y, rect.w, rect.h)
            }
        }
        CurtainWindows := Map()
    } else {
        CurtainDropped := true
        CurtainWindows := Map()
        
        for hwnd in WinGetList() {
            if !IsSnappable(hwnd)
                continue
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
                
            try WinGetPos(&x, &y, &w, &h, hwnd)
            catch
                continue
                
            if (w == 0 || h == 0)
                continue
                
            CurtainWindows[hwnd] := {x: x, y: y, w: w, h: h}
            CurtainDropDown(hwnd, x, y, w, h)
        }
    }
}
#HotIf

; Bye() calls this. CurtainWindows is the ONLY record of where these windows came
; from, and dropping them parks every one of them below the screen - so exiting
; while the curtain is down used to leave the whole desktop off-screen with
; nothing anywhere that could put it back.
RestoreCurtain() {
    global CurtainDropped, CurtainWindows
    for hwnd, rect in CurtainWindows {
        if DllCall("IsWindow", "ptr", hwnd) {
            try CancelAnimation("Curtain_" hwnd)
            try RS_SetPos(hwnd, rect.x, rect.y, rect.w, rect.h, RS_PRI_USER)
        }
    }
    CurtainWindows := Map()
    CurtainDropped := false
}

CurtainDropDown(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 250
    destY := A_ScreenHeight + 50
    
    DropStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        
        ease := t ** 3
        curY := Round(y + (destY - y) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, DropStep)
}

CurtainBounceUp(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    startY := A_ScreenHeight + 50
    
    UpStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_USER)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        curY := Round(startY + (y - startY) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, UpStep)
}

#HotIf CarouselAltTabEnabled && !CarouselActive
*!Tab:: {
    global CarouselActive, CarouselWindows, CarouselIndex, Thumbnails, CarouselAngleOffset, CarouselGui
    CarouselActive := true
    CarouselWindows := []
    Thumbnails := []
    CarouselIndex := 1
    CarouselAngleOffset := 0
    
    for hwnd in WinGetList() {
        if !IsSnappable(hwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        CarouselWindows.Push(hwnd)
    }
    if CarouselWindows.Length == 0 {
        CarouselActive := false
        Send("!{Tab}")
        return
    }
    
    CarouselGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    CarouselGui.BackColor := "111111"
    CarouselGui.Show("w" A_ScreenWidth " h" A_ScreenHeight " x0 y0")
    RS_SetAlpha(CarouselGui.Hwnd, 220, RS_PRI_USER)
    RS_Commit()
    for hwnd in CarouselWindows {
        thumbId := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", CarouselGui.Hwnd, "ptr", hwnd, "ptr*", &thumbId)
        Thumbnails.Push(thumbId)
    }
    RegisterAnimation("Carousel", CarouselCallback)
}
#HotIf

#HotIf CarouselActive
*!Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex++
    if (CarouselIndex > CarouselWindows.Length)
        CarouselIndex := 1
    CarouselAngleOffset += 1
}
*!+Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex--
    if (CarouselIndex < 1)
        CarouselIndex := CarouselWindows.Length
    CarouselAngleOffset -= 1
}
; Both Alt keys, plus Escape. The opening hotkey is *!Tab, which fires on either
; Alt - so closing on LAlt alone meant that opening the carousel with RAlt left a
; full-screen AlwaysOnTop window up, a 16 ms timer running, and #HotIf
; CarouselActive swallowing !Tab and !+Tab. Alt+Tab itself was then dead and the
; only way out was Task Manager.
~LAlt up::CloseCarousel(true)
~RAlt up::CloseCarousel(true)
~Esc::CloseCarousel(false)
#HotIf

CloseCarousel(activateChoice) {
    global CarouselActive, CarouselGui, CarouselWindows, CarouselIndex, Thumbnails
    if (!CarouselActive)
        return
    CarouselActive := false
    CancelAnimation("Carousel")

    for thumbId in Thumbnails {
        try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", thumbId)
    }
    Thumbnails := []

    ; The chosen window can close while the carousel is open, and the index can
    ; be stale if the list was rebuilt - neither may throw out of a hotkey.
    hwnd := 0
    if (CarouselIndex >= 1 && CarouselIndex <= CarouselWindows.Length)
        hwnd := CarouselWindows[CarouselIndex]

    if (CarouselGui) {
        try RS_RemoveHwnd(CarouselGui.Hwnd)
        try CarouselGui.Destroy()
    }
    CarouselGui := ""

    if (activateChoice && hwnd && DllCall("IsWindow", "ptr", hwnd))
        try WinActivate(hwnd)
}

CarouselCallback(dt, now) {
    global CarouselGui, CarouselWindows, Thumbnails, CarouselIndex, CarouselAngleOffset, CarouselActive
    if (!CarouselActive)
        return false
        
    if (CarouselAngleOffset > 0)
        CarouselAngleOffset *= 0.8
    else if (CarouselAngleOffset < 0)
        CarouselAngleOffset *= 0.8
        
    if (Abs(CarouselAngleOffset) < 0.05)
        CarouselAngleOffset := 0
        
    num := CarouselWindows.Length
    centerX := A_ScreenWidth / 2
    centerY := A_ScreenHeight / 2
    radiusX := A_ScreenWidth * 0.3
    radiusY := A_ScreenHeight * 0.1
    
    PI := 3.141592653589793
    angleStep := (2 * PI) / num
    
    loop num {
        idx := A_Index
        dist := idx - CarouselIndex
        if (dist > num / 2)
            dist -= num
        else if (dist < -num / 2)
            dist += num
            
        angle := (dist + CarouselAngleOffset) * angleStep + (PI / 2)
        
        x := centerX + Cos(angle) * radiusX
        y := centerY + Sin(angle) * radiusY
        scale := 0.5 + (Sin(angle) + 1) * 0.25
        
        w := Round(400 * scale)
        h := Round(250 * scale)
        px := Round(x - w/2)
        py := Round(y - h/2)
        
        props := Buffer(48, 0)
        NumPut("uint", 0x01 | 0x08, props, 0) 
        NumPut("int", px, props, 4)
        NumPut("int", py, props, 8)
        NumPut("int", px + w, props, 12)
        NumPut("int", py + h, props, 16)
        NumPut("uint", (idx == CarouselIndex) ? 255 : Round(100 * scale), props, 32) 
        
        DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", Thumbnails[idx], "ptr", props)
    }
    return true
}

global MotionBlurScrollSpeed := 0
global MotionBlurLastTime := 0
global MotionBlurGui := ""
global MotionBlurThumb := 0
global MotionBlurActiveHwnd := 0

TriggerMotionBlur(hwnd, dir) {
    global MotionBlurScrollSpeed, MotionBlurLastTime, MotionBlurActiveHwnd, MotionBlurGui
    now := QPC()
    dt := now - MotionBlurLastTime
    
    ; 120 ms, not 0.1. QPC() already returns MILLISECONDS, so the old threshold
    ; was a tenth of a millisecond - true between any two wheel events - and the
    ; accumulator was reset on every notch. The effect could never build up past
    ; one notch's worth, which is why it always looked like it did nothing.
    if (dt > 120 || hwnd != MotionBlurActiveHwnd)
        MotionBlurScrollSpeed := 0
        
    MotionBlurScrollSpeed += dir * 12
    MotionBlurLastTime := now
    MotionBlurActiveHwnd := hwnd
    
    RegisterAnimation("MotionBlur", MotionBlurCallback)
}

MotionBlurCallback(dt, now) {
    global MotionBlurScrollSpeed, MotionBlurGui
    
    if (Abs(MotionBlurScrollSpeed) < 1) {
        MotionBlurScrollSpeed := 0
        if (MotionBlurGui) {
            RS_SetAlpha(MotionBlurGui.Hwnd, "Off", RS_PRI_ANIM)
            MotionBlurGui.Hide()
        }
        return false
    }
    
    MotionBlurScrollSpeed *= 0.85
    
    hwnd := WinExist("A")
    if (!hwnd || !MotionBlurGui)
        return false
        
    try WinGetPos(&x, &y, &w, &h, hwnd)
    catch
        return false
        
    RS_SetAlpha(MotionBlurGui.Hwnd, Round(Abs(MotionBlurScrollSpeed) * 3), RS_PRI_ANIM)
    RS_SetPos(MotionBlurGui.Hwnd, x, y, w, h, RS_PRI_ANIM)
    return true
}

global TaskbarWaveGui := ""
global TaskbarWaveThumb := 0

RenderTaskbarWave() {
    global TaskbarWaveGui, TaskbarWaveThumb, TaskbarWaveEnabled

    ; The flag check is INSIDE the teardown condition, not above it. It used to
    ; return first, which meant unchecking the box while the mouse was over the
    ; taskbar skipped the only cleanup path there is - leaving a 100 px
    ; AlwaysOnTop window stuck on screen, unreachable, until the app restarted.
    if (!TaskbarWaveEnabled || !IsMouseOverTaskbar()) {
        if (TaskbarWaveGui) {
            try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", TaskbarWaveThumb)
            try RS_RemoveHwnd(TaskbarWaveGui.Hwnd)
            try TaskbarWaveGui.Destroy()
            TaskbarWaveGui := ""
            TaskbarWaveThumb := 0
        }
        return
    }

    MouseGetPos(&mx, &my)
    hwnd := WinExist("ahk_class Shell_TrayWnd")
    if (!hwnd)
        return
        
    ; A bare `try` leaves tx/ty UNSET on failure and srcX/srcY below read them.
    ; This runs on the 32 ms CheckTaskbarAndUI timer, so that throw would kill
    ; Start Menu Blur, Toast Bounce, Lightsaber Seam and Privacy Blur along with
    ; this feature for the rest of the session.
    try WinGetPos(&tx, &ty, &tw, &th, hwnd)
    catch
        return

    if (!TaskbarWaveGui) {
        TaskbarWaveGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        TaskbarWaveGui.BackColor := "000000"
        TaskbarWaveThumb := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", TaskbarWaveGui.Hwnd, "ptr", hwnd, "ptr*", &TaskbarWaveThumb)
        WinSetTransColor("000000 255", TaskbarWaveGui.Hwnd) 
        WinSetRegion("0-0 w100 h100 E", TaskbarWaveGui.Hwnd) 
        TaskbarWaveGui.Show("NA x0 y0 w100 h100 Hide")
    }
    
    size := 100
    zoom := 1.3
    
    srcX := Round(mx - tx - (size / zoom / 2))
    srcY := Round(my - ty - (size / zoom / 2))
    srcW := Round(size / zoom)
    srcH := Round(size / zoom)
    
    destX := Round(mx - size / 2)
    destY := Round(my - size / 2)
    
    DllCall("SetWindowPos", "ptr", TaskbarWaveGui.Hwnd, "ptr", -1, "int", destX, "int", destY, "int", size, "int", size, "uint", 0x10 | 0x40)
    
    ; See the struct layout note in UpdateCarousel. rcSource IS written here, so
    ; DWM_TNP_RECTSOURCE (0x02) is correct.
    props := Buffer(48, 0)
    NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
    NumPut("int", 0, props, 4)
    NumPut("int", 0, props, 8)
    NumPut("int", size, props, 12)
    NumPut("int", size, props, 16)

    NumPut("int", srcX, props, 20)
    NumPut("int", srcY, props, 24)
    NumPut("int", srcX + srcW, props, 28)
    NumPut("int", srcY + srcH, props, 32)

    NumPut("char", 255, props, 36)
    NumPut("int", 1, props, 40)

    DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", TaskbarWaveThumb, "ptr", props)
}

global StartMenuBlurGui := ""
global KnownToasts := Map()

CheckTaskbarAndUI() {
    global TaskbarWaveEnabled, StartMenuBlurEnabled, ToastBounceEnabled, LightsaberSeamEnabled
    
    ; Called unconditionally on purpose. Each of these checks its own flag as its
    ; FIRST act and tears its overlay down when the flag is off; gating them here
    ; instead is what stranded the taskbar magnifier, the Start-menu blur and the
    ; lightsaber glow on screen when their box was unchecked mid-effect.
    RenderTaskbarWave()
    CheckStartMenu()
    CheckLightsaber()
    CheckPrivacyBlur()

    ; Toast bounce holds no overlay of its own - it only animates shell windows -
    ; so there is nothing to clean up and it can stay gated.
    if (ToastBounceEnabled)
        CheckToasts()
}

global LS_Gui := 0
global LS_Active := false
global LS_Hwnd := 0
global LS_Alpha := 0
global LS_Progress := 0

; Built on first use rather than at startup, so a disabled feature owns no
; window. Returns false if the overlay could not be created, which is the only
; thing CheckLightsaber needs to know.
InitLightsaber() {
    global LS_Gui, LS_Hwnd
    if (LS_Gui && LS_Hwnd && DllCall("IsWindow", "ptr", LS_Hwnd))
        return true
    try {
        LS_Gui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        LS_Gui.BackColor := "00FFFF"
        LS_Hwnd := LS_Gui.Hwnd
        WinSetTransparent(0, LS_Hwnd)
        return true
    }
    LS_Gui := 0, LS_Hwnd := 0
    return false
}

; The enabled test lives INSIDE this function, not at the CheckTaskbarAndUI call
; site, for the same reason RenderTaskbarWave's does: unchecking the box while the
; glow is lit used to stop the only code that could ever take it down, leaving a
; cyan bar welded across a window edge until the app restarted.
CheckLightsaber() {
    global LS_Active, LS_Hwnd, LS_Alpha, LS_Progress, LS_Gui, LightsaberSeamEnabled

    if (!LightsaberSeamEnabled) {
        if (LS_Active || LS_Alpha > 0) {
            LS_Active := false
            LS_Alpha := 0
            try DllCall("ShowWindow", "ptr", LS_Hwnd, "int", 0)   ; SW_HIDE
        }
        return
    }

    MouseGetPos(&mx, &my, &mHwnd)
    cursor := A_Cursor

    if ((cursor == "SizeWE" || cursor == "SizeNS") && mHwnd) {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, mHwnd)
            
            isEdge := false
            edgeX := wx
            edgeY := wy
            edgeW := 3
            edgeH := 3
            
            if (cursor == "SizeWE") {
                isLeftEdge := Abs(mx - wx) < 20
                isRightEdge := Abs(mx - (wx + ww)) < 20
                if (isLeftEdge || isRightEdge) {
                    isEdge := true
                    edgeX := isLeftEdge ? wx - 1 : wx + ww - 2
                    edgeY := wy
                    edgeW := 3
                    edgeH := wh
                }
            } else if (cursor == "SizeNS") {
                isTopEdge := Abs(my - wy) < 20
                isBottomEdge := Abs(my - (wy + wh)) < 20
                if (isTopEdge || isBottomEdge) {
                    isEdge := true
                    edgeX := wx
                    edgeY := isTopEdge ? wy - 1 : wy + wh - 2
                    edgeW := ww
                    edgeH := 3
                }
            }
            
            if (isEdge) {
                if (!LS_Active) {
                    if !InitLightsaber()
                        return
                    LS_Active := true
                    LS_Progress := 0
                    if (cursor == "SizeWE")
                        LS_Gui.Show("NA x" edgeX " y" my " w" edgeW " h2")
                    else
                        LS_Gui.Show("NA x" mx " y" edgeY " w2 h" edgeH)
                }
                
                if (LS_Progress < 1) {
                    LS_Progress += 0.12 
                    if (LS_Progress > 1)
                        LS_Progress := 1
                }
                
                ease := 1 - (1 - LS_Progress) ** 3 
                
                curY := my - (my - edgeY) * ease
                curH := 2 + (edgeH - 2) * ease
                
                curX := mx - (mx - edgeX) * ease
                curW := 2 + (edgeW - 2) * ease
                
                if (cursor == "SizeWE") {
                    DllCall("SetWindowPos", "ptr", LS_Hwnd, "ptr", -1, "int", edgeX, "int", Round(curY), "int", edgeW, "int", Round(curH), "uint", 0x14 | 0x40)
                } else {
                    DllCall("SetWindowPos", "ptr", LS_Hwnd, "ptr", -1, "int", Round(curX), "int", edgeY, "int", Round(curW), "int", edgeH, "uint", 0x14 | 0x40)
                }
                
                if (LS_Alpha < 180) {
                    LS_Alpha += 25
                    if (LS_Alpha > 180)
                        LS_Alpha := 180
                    WinSetTransparent(LS_Alpha, LS_Hwnd)
                }
                return
            }
        }
    }
    
    if (LS_Active) {
        if (LS_Alpha > 0) {
            LS_Alpha -= 25
            if (LS_Alpha <= 0) {
                LS_Alpha := 0
                LS_Active := false
                DllCall("ShowWindow", "ptr", LS_Hwnd, "int", 0) 
            } else {
                WinSetTransparent(LS_Alpha, LS_Hwnd)
            }
        }
    }
}

; Same shape, and this one is worse when it goes wrong: the stranded overlay is a
; full-screen 170-alpha black sheet, so switching the feature off while the Start
; menu was open used to leave the whole desktop dimmed until restart.
CheckStartMenu() {
    global StartMenuBlurGui, StartMenuBlurEnabled

    if (!StartMenuBlurEnabled) {
        if (StartMenuBlurGui) {
            FadeGui(StartMenuBlurGui, 0, 0, true)
            StartMenuBlurGui := ""
        }
        return
    }

    startHwnd := WinExist("Start ahk_class Windows.UI.Core.CoreWindow")
    if (!startHwnd)
        startHwnd := WinExist("Start ahk_class Windows.UI.Composition.DesktopWindowContentBridge")
        
    isVisible := false
    if (startHwnd && DllCall("IsWindowVisible", "ptr", startHwnd)) {
        isVisible := true
    }
    
    if (isVisible && !StartMenuBlurGui) {
        StartMenuBlurGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        StartMenuBlurGui.BackColor := "000000"
        StartMenuBlurGui.Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
        RS_SetPos(StartMenuBlurGui.Hwnd, 0, 0, A_ScreenWidth, A_ScreenHeight, RS_PRI_USER)
        RS_SetZOrder(StartMenuBlurGui.Hwnd, startHwnd, 0x13, RS_PRI_USER)
        RS_Commit() 
        FadeGui(StartMenuBlurGui, 170)
        
        ; Runs on a 32 ms timer, so a throw here would pop an error dialog and
        ; kill the timer - taking Taskbar Wave, Toast Bounce, Lightsaber Seam and
        ; Privacy Blur down with it. A bare `try` leaves sx/sy UNSET when the
        ; query fails, and the next line reads them.
        try WinGetPos(&sx, &sy, &sw, &sh, startHwnd)
        catch
            return
        RS_SetPos(startHwnd, sx, sy + 50, -1, -1, RS_PRI_USER)
        AnimStartMenuSlide(startHwnd, sx, sy + 50, sy)
    } else if (!isVisible && StartMenuBlurGui) {
        FadeGui(StartMenuBlurGui, 0, 0, true)
        StartMenuBlurGui := ""
    }
}

; x is a real coordinate, not a placeholder. RS_SetPos treats a negative value as
; SWP_NOSIZE for w/h ONLY - x and y are stored verbatim - so passing -1 as x here
; slammed the Start menu to x = -1 on every frame and it slid down the left edge
; of the screen instead of up from the taskbar.
AnimStartMenuSlide(hwnd, x, startY, destY) {
    animKey := "StartSlide"
    CancelAnimation(animKey)
    start := QPC()
    ms := 300

    SlideStep(dt, now) {
        if (!DllCall("IsWindowVisible", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        ease := 1 - (1 - t) ** 3
        curY := Round(startY + (destY - startY) * ease)
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, SlideStep)
}

CheckToasts() {
    global KnownToasts
    list := WinGetList("New notification ahk_class Windows.UI.Core.CoreWindow")
    for hwnd in list {
        if (!KnownToasts.Has(hwnd)) {
            KnownToasts[hwnd] := true
            ; Runs on a 32 ms timer and enumerates shell toast windows, which
            ; ShellExperienceHost creates and destroys constantly - so the window
            ; dying between WinGetList above and WinGetPos here is routine, not
            ; exotic. A bare `try` leaves x/y/w/h UNSET and the next line reads w,
            ; which throws OUTSIDE the try and kills this timer - and with it
            ; Taskbar Wave, Start Menu Blur, Lightsaber Seam and Privacy Blur.
            try WinGetPos(&x, &y, &w, &h, hwnd)
            catch
                continue
            if (w > 0) {
                AnimToastBounce(hwnd, x + 350, x, y)
            }
        }
    }
    
    for hwnd in KnownToasts.Clone() {
        if (!DllCall("IsWindow", "ptr", hwnd))
            KnownToasts.Delete(hwnd)
    }
}

; y is a real coordinate. RS_SetPos treats a negative value as SWP_NOSIZE for w/h
; ONLY - x and y are stored verbatim - so passing -1 as y here slammed every toast
; to y = -1 and they flew across the top of the screen instead of bouncing in at
; their own height.
AnimToastBounce(hwnd, startX, destX, y) {
    animKey := "Toast_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 500

    BounceStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, destX, y, -1, -1, RS_PRI_USER)
            return false
        }
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        curX := Round(startX + (destX - startX) * ease)
        RS_SetPos(hwnd, curX, y, -1, -1, RS_PRI_USER)
        return true
    }
    RegisterAnimation(animKey, BounceStep)
}

; The largest idle cost in the program had no Sync* at all: this was armed
; unconditionally at load and ran ~31 times a second forever, and four of its
; five consumers default ON. CheckToasts alone enumerates every top-level window
; with a title filter on each tick.
;
; One tick is still needed after the last consumer is switched off, so each
; sub-check can tear its overlay down - hence the deferred stop rather than an
; immediate one.
SyncTaskbarUiTimer() {
    global TaskbarWaveEnabled, StartMenuBlurEnabled, ToastBounceEnabled
    global LightsaberSeamEnabled, PrivacyBlurEnabled, PrivacyBlurWindows
    ; PrivacyBlur counts only while something is actually marked private -
    ; the flag alone gives the poll nothing to do. AddPrivacyBlur and
    ; RemovePrivacyBlur call back in here when that changes.
    wanted := TaskbarWaveEnabled || StartMenuBlurEnabled || ToastBounceEnabled
            || LightsaberSeamEnabled || (PrivacyBlurEnabled && PrivacyBlurWindows.Count > 0)
    if (wanted) {
        SetTimer(CheckTaskbarAndUI, 32)
        return
    }
    CheckTaskbarAndUI()            ; final pass: every sub-check cleans up
    SetTimer(CheckTaskbarAndUI, 0)
}

; ----------------------------------------------------------------------------
; Custom Taskbar Clock
; ----------------------------------------------------------------------------
; A time / date / temperature block on the taskbar, and ONE rule shapes all of it:
; it may never intersect TrayNotifyWnd.
;
; The first version did. It was 110 px wide, anchored on TrayClockWClass and grown
; leftward, so it covered the native clock and the Control Center button. That read
; as a corrupted tray - the notification icon looked like it had moved, the spacing
; was wrong, and a failed weather lookup printed "no data" where the time belongs.
; Nothing in Explorer had changed; it was all covered, not moved.
;
; So it sits entirely to the LEFT of the tray, in the strip the task buttons have
; not used, it is sized to its own content, and if the tray cannot be located it
; does not draw at all - because then there is no way to prove it is not sitting on
; top of something. Windows keeps drawing its own clock, date and tray icons,
; untouched, to the right of it.
global CustomClockGui := 0
global CustomClockTimeText := 0
global CustomClockTempText := 0
global CustomClockReq := 0        ; held so the async request is not collected mid-flight
global WeatherReqAt := 0
global CustomClockBuiltFor := ""  ; theme, font and column widths the Gui was built for
global CustomClockRect := ""      ; last rect actually queued, so unchanged ticks cost nothing

; Padding around and between the two columns.
global CLOCK_GAP := 6

SyncCustomClockTimer() {
    global CustomClockEnabled, LastWeatherFetch, CustomClockWeather, WeatherNextMs
    global WeatherWarnedFor, GeoFor, ClockWarnedNoCity
    if (CustomClockEnabled) {
        ; Re-arming forces an immediate fetch, which is also how a changed location
        ; or unit takes effect: ApplyUi calls this after reading the controls. GeoFor
        ; is reset with it, so a new city is geocoded again instead of reusing the
        ; coordinates of the old one.
        LastWeatherFetch := 0
        WeatherNextMs := 900000
        CustomClockWeather := ""
        WeatherWarnedFor := "-"
        ClockWarnedNoCity := false
        GeoFor := "-"
        SetTimer(UpdateCustomClock, 250)
        UpdateCustomClock()
    } else {
        SetTimer(UpdateCustomClock, 0)
        HideCustomClock()
    }
}

HideCustomClock() {
    global CustomClockGui, CustomClockTimeText, CustomClockTempText
    global CustomClockBuiltFor, CustomClockRect
    if (CustomClockGui) {
        ; Mandatory, not tidiness: a -Caption +ToolWindow overlay raises no shell
        ; destroy notification, so nothing else would ever prune its RS_* entries.
        try RS_RemoveHwnd(CustomClockGui.Hwnd)
        try CustomClockGui.Destroy()
    }
    CustomClockGui := 0
    ; These referenced controls of the destroyed Gui. Left dangling, the next tick
    ; wrote .Value into a dead control and threw - inside a timer callback.
    CustomClockTimeText := 0
    CustomClockTempText := 0
    CustomClockBuiltFor := ""
    CustomClockRect := ""
}

; Where the block's right edge goes, resolved from LIVE window geometry by class
; name. There is no coordinate anywhere in this feature.
;
; Two anchors, and the difference is a real trade-off rather than an internal
; detail, which is why it is a setting:
;
;   "Clock"    - the left edge of TrayClockWClass. Adjacent to the native clock, so
;                the block reads as part of the tray. It therefore sits ON TOP of
;                whatever is immediately left of the clock, which on this shell is
;                the Control Center button.
;   "TrayEdge" - the left edge of TrayNotifyWnd, i.e. left of EVERY tray element.
;                Covers nothing at all. The cost is distance: TrayNotifyWnd is the
;                whole notification area and its width moves with the icon count -
;                measured 343, 391, 415 and 511 px in one session - so the block
;                drifts, and at 511 px it is 480 px away from the clock and reads
;                as floating in the middle of the taskbar rather than integrated.
;
; Returns 0 when the requested element cannot be found AND neither can the
; fallback, and the caller then draws nothing rather than guessing a position.
ResolveClockAnchor(tbHwnd) {
    global ClockAnchor
    ; Ordered: the requested anchor first, then the safe one. A shell without a
    ; TrayClockWClass - the stock Win11 XAML taskbar has none - falls through to
    ; the tray edge instead of losing the feature.
    order := (ClockAnchor == "TrayEdge")
        ? ["TrayNotifyWnd"]
        : ["TrayClockWClass", "TrayNotifyWnd"]
    for cls in order {
        h := FindTrayElement(tbHwnd, cls)
        if (h) {
            WinGetPos(&ex, &ey, &ew, &eh, "ahk_id " h)
            if (ew > 0)
                return ex
        }
    }
    return 0
}

; Shell_TrayWnd -> TrayNotifyWnd -> the element. The clock is a GRANDCHILD of the
; tray, so a direct-child search finds only TrayNotifyWnd itself; both levels are
; tried. Never throws: an absent element is a normal outcome on the XAML shell.
FindTrayElement(tbHwnd, cls) {
    try {
        if (cls == "TrayNotifyWnd") {
            h := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0, "str", cls, "ptr", 0, "ptr")
            return (h && DllCall("IsWindowVisible", "ptr", h)) ? h : 0
        }
        notify := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0
            , "str", "TrayNotifyWnd", "ptr", 0, "ptr")
        if (notify) {
            h := DllCall("FindWindowExW", "ptr", notify, "ptr", 0, "str", cls, "ptr", 0, "ptr")
            if (h && DllCall("IsWindowVisible", "ptr", h))
                return h
        }
        h := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0, "str", cls, "ptr", 0, "ptr")
        if (h && DllCall("IsWindowVisible", "ptr", h))
            return h
    }
    return 0
}

; The taskbar follows the SYSTEM theme. AppsUseLightTheme - the key the settings
; window reads - is a different setting and gets this backwards for anyone running
; a mixed theme, which is a supported combination in Windows 11.
IsTaskbarDark() {
    v := 0
    try v := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        , "SystemUsesLightTheme", 0)
    return (v = 0)
}

; open-meteo reports a WMO weather code. This maps it to one glyph.
;
; Built with Chr() rather than written as a literal so the .ahk source stays pure
; ASCII - AutoHotkey reads a BOM-less file in the system codepage, so a literal
; would arrive as mojibake on a machine with a different one. All of these are in
; the BMP on purpose: they live in Segoe UI Symbol, which font fallback finds. The
; astral-plane weather emoji need Segoe UI Emoji and come out as tofu in a plain
; Static control.
WeatherIcon(code) {
    if (code = 0)
        return Chr(0x2600)                      ; clear
    if (code = 1 || code = 2)
        return Chr(0x26C5)                      ; mainly clear / partly cloudy
    if (code >= 95)
        return Chr(0x26C8)                      ; thunderstorm
    if ((code >= 71 && code <= 77) || code = 85 || code = 86)
        return Chr(0x2744)                      ; snow
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
        return Chr(0x2614)                      ; drizzle / rain / showers
    return Chr(0x2601)                          ; overcast, fog, anything else
}


; The colour of the taskbar itself, so the block can be painted to disappear into
; it. Returns "" when it cannot be read, and the caller then keeps its theme-derived
; default rather than guessing.
;
; The sample point is deliberately to the LEFT of the block: sampling under the
; block would read the block's own pixels once it exists.
SampleTaskbarColor(tx, ty, th, blockX) {
    px := blockX - 12
    if (px < tx + 2)
        px := tx + 2
    try {
        CoordMode("Pixel", "Screen")
        c := PixelGetColor(px, ty + th // 2)
        if (c != "")
            return Format("{:06X}", c & 0xFFFFFF)
    }
    return ""
}


; One line, with the whole body behind a try, because this is a SetTimer callback:
; a throw here pops an error dialog and kills the timer for the rest of the session.
; That is not hypothetical - the version this replaces called
; ControlGetHwnd("TrayClockWClass", ...) with a bare class name, which is not a
; valid ClassNN, and AHK throws TargetError rather than returning 0. It died on its
; first tick, every time, so the feature had never once drawn anything.
UpdateCustomClock() {
    try UpdateCustomClockImpl()
}

PaintCustomClock() {
    global CustomClockTimeText, CustomClockTempText, CustomClockWeather, CustomClockWind
    if (CustomClockTimeText)
        try CustomClockTimeText.Value := FormatTime(, "HH:mm") "`n" FormatTime(, "dd.MM.yyyy")
    ; "--" rather than blank: an empty column is indistinguishable from a column
    ; that was never created, which is the confusion this feature already caused
    ; once. A placeholder says "this part is here and has nothing to show yet".
    if (CustomClockTempText) {
        ; "--" rather than blank: an empty column is indistinguishable from a column
        ; that was never created, which is the confusion this feature already caused
        ; once. A placeholder says "this part is here and has nothing to show yet".
        info := (CustomClockWeather == "") ? "--" : CustomClockWeather
        ; Gated on the temperature, not on the wind, so a failure that clears the
        ; reading cannot leave a stale wind line behind on its own.
        if (CustomClockWeather != "" && CustomClockWind != "")
            info .= "`n" CustomClockWind
        try CustomClockTempText.Value := info
    }
}

UpdateCustomClockImpl() {
    global CustomClockGui, CustomClockTimeText, CustomClockTempText
    global CustomClockBuiltFor, CustomClockRect, CLOCK_GAP
    global CustomClockWeather, LastWeatherFetch, WeatherNextMs, ClockWeatherEnabled, ClockAnchor

    ; Read the network first, so the fetch keeps its own schedule regardless of
    ; whether anything gets drawn this tick.
    PollWeather()
    if (LastWeatherFetch == 0 || (A_TickCount - LastWeatherFetch > WeatherNextMs))
        FetchWeather()

    tbHwnd := WinExist("ahk_class Shell_TrayWnd")
    ; The visibility test is the one that matters most: a full-screen app hides the
    ; taskbar, and an AlwaysOnTop overlay would otherwise sit on top of the game.
    if (!tbHwnd || !DllCall("IsWindowVisible", "ptr", tbHwnd)) {
        HideCustomClock()
        return
    }

    WinGetPos(&tx, &ty, &tw, &th, "ahk_id " tbHwnd)
    if (tw < 200 || th < 12) {
        HideCustomClock()
        return
    }

    ; Auto-hidden: Windows parks the bar two pixels inside its own monitor rather
    ; than moving it off-screen. This used to compare against A_ScreenHeight, which
    ; is the PRIMARY monitor - wrong the moment the taskbar is on a different one.
    monB := A_ScreenHeight, monR := A_ScreenWidth
    try {
        sm := ScreenMetrics()
        m := sm.mons[MonitorIndexAt(tx + tw // 2, ty + th // 2)]
        monB := m.b, monR := m.r
    }
    if (ty >= monB - 2 || tx >= monR - 2) {
        HideCustomClock()
        return
    }

    anchorLeft := ResolveClockAnchor(tbHwnd)
    if (!anchorLeft) {
        ; Nothing to measure against, so no way to prove we are not covering
        ; something. Draw nothing rather than guess.
        HideCustomClock()
        return
    }

    ; Widths from the font, not from a setting. The content is known - five glyphs
    ; of time over ten of date, at most six of temperature - so a width control
    ; could only ever be used to make it wrong. Segoe UI digits run about 0.6 em and
    ; em is about 4/3 of the point size at 96 dpi, which is what makes this follow
    ; the text size and the DPI instead of assuming either.
    fpt := Integer(Tune("clockFont"))
    glyph := fpt * 4 / 3 * 0.6
    dateW := Ceil(glyph * 10) + CLOCK_GAP
    ; The temperature column exists whenever the feature is on. Only its VALUE is
    ; conditional: it reads "--" until a location produces a reading. Sizing the
    ; column to zero when there was no reading yet is what made a feature that was
    ; merely unconfigured look like a feature that was broken.
    tempW := ClockWeatherEnabled ? Ceil(glyph * 9) + CLOCK_GAP : 0
    boxW := CLOCK_GAP + tempW + dateW + CLOCK_GAP
    x := anchorLeft - CLOCK_GAP - boxW
    if (x < tx) {
        HideCustomClock()
        return
    }

    ; Two stacked lines, centred vertically by hand: the taskbar can be 30 px or
    ; 48 px tall and nothing here may assume which.
    lineH := Ceil(fpt * 4 / 3 * 1.35)
    textY := (th - 2 * lineH) // 2
    if (textY < 0)
        textY := 0

    ; The block is painted in the TASKBAR'S OWN COLOUR, so the panel disappears and
    ; only the text reads. This replaces colour-key transparency, which fringed: a
    ; keyed background needs every background pixel to be exactly the key colour,
    ; but antialiased and ClearType glyph edges BLEND with it, those blended pixels
    ; are not the key any more, so they survive the keying and every character ends
    ; up haloed in the key colour. Magenta text edges, measured on screen.
    ;
    ; Sampling works here because the taskbar is one flat colour - measured 0x202020
    ; at x = 200, 600, 1000, 1200, 1300 and 1400, including over inactive task
    ; buttons - so there is no gradient to mismatch against.
    bgColor := IsTaskbarDark() ? "202020" : "F3F3F3"

    ; Colours, font, chrome and the column split are all fixed at creation, so a
    ; change to any of them rebuilds rather than restyles: Gui.SetFont only affects
    ; controls added after it, and a control cannot be resized into existence.
    stamp := bgColor "|" fpt "|" tempW "|" dateW "|" th
    if (CustomClockGui && CustomClockBuiltFor != stamp)
        HideCustomClock()

    if (!CustomClockGui) {
        dark := IsTaskbarDark()
        CustomClockGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 -DPIScale")
        CustomClockGui.MarginX := 0
        CustomClockGui.MarginY := 0
        ; Refined by one sample of the real bar, taken from a point LEFT of where the
        ; block goes so it can never sample itself. Only at creation: the taskbar
        ; colour does not change while the block sits on it, and a theme change
        ; rebuilds through the stamp anyway.
        sampled := SampleTaskbarColor(tx, ty, th, x)
        if (sampled != "")
            bgColor := sampled
        CustomClockGui.BackColor := bgColor
        CustomClockGui.SetFont("s" fpt " c" (dark ? "FFFFFF" : "1A1A1A") " q5", "Segoe UI")
        ; A WM_CLOSE arriving at a caption-less, click-through overlay is never a
        ; user closing a window. It is a process-wide close request - taskkill,
        ; Install.ps1's StopRunning, a Windows shutdown - that walked the process's
        ; top-level windows, found this one before the script's own hidden main
        ; window, and stopped there. Measured: with the block on screen the app
        ; NEVER exited and Bye() never ran, so a graceful close silently lost every
        ; setting and left the overlay behind. It is the first permanently visible
        ; overlay in the program, which is why nothing hit this before.
        CustomClockGui.OnEvent("Close", (*) => ExitApp())
        if (tempW) {
            ; Two lines, like the clock beside it: the condition glyph with the
            ; temperature, and the wind under it.
            CustomClockTempText := CustomClockGui.Add("Text"
                , "x" CLOCK_GAP " y" textY " w" (tempW - CLOCK_GAP)
                . " h" (2 * lineH) " Center", "")
        } else {
            CustomClockTempText := 0
        }
        CustomClockTimeText := CustomClockGui.Add("Text"
            , "x" (CLOCK_GAP + tempW) " y" textY " w" (dateW - CLOCK_GAP)
            . " h" (2 * lineH) " Center", "")
        CustomClockBuiltFor := stamp
        ; Text before Show: showing first costs one frame of an unpainted rectangle
        ; sitting on the taskbar.
        PaintCustomClock()
        CustomClockGui.Show("NA x" x " y" ty " w" boxW " h" th)
    }

    ; A one-shot producer: nothing else flushes for it, so it commits itself.
    ;
    ; The rect is diffed first. RenderCore deliberately does not cache positions -
    ; the user can move a window behind its back - but this window is ours alone, so
    ; the cache is valid here, and it is what lets the tick run at 250 ms for
    ; nothing. It has to be that fast because the anchor MOVES: one new tray icon
    ; shifted TrayNotifyWnd 24 px and left the block overlapping the tray until the
    ; next tick.
    rect := x "," ty "," boxW "," th
    if (rect != CustomClockRect) {
        RS_SetPos(CustomClockGui.Hwnd, x, ty, boxW, th, RS_PRI_AMBIENT)
        CustomClockRect := rect
    }
    ; Z-order is re-asserted every tick regardless: the taskbar is topmost too and
    ; comes to the front whenever it is clicked. On our own window that is one
    ; SetWindowPos with NOMOVE | NOSIZE, nothing like the 260 us a real move costs
    ; on a foreign window.
    RS_SetZOrder(CustomClockGui.Hwnd, -1, 0x0013, RS_PRI_AMBIENT)
    RS_Commit()

    PaintCustomClock()
}

ClockUrlPart(s) {
    ; CleanClockLocation has already reduced this to [A-Za-z0-9 ,.+-], so these
    ; three are the whole encoding problem. Nothing that could change the shape of
    ; the query - & = ? % / - can reach here.
    s := StrReplace(s, "+", "%2B")
    s := StrReplace(s, ",", "%2C")
    return StrReplace(s, " ", "+")
}

ForecastUrl() {
    global GeoLat, GeoLon, ClockUnits
    u := "https://api.open-meteo.com/v1/forecast"
        . "?current=temperature_2m,weather_code,wind_speed_10m"
        . "&latitude=" GeoLat "&longitude=" GeoLon

    ; Fahrenheit implies the rest of the imperial set, so the wind comes back in mph
    ; rather than km/h and the label below follows it.
    if (ClockUnits == "Fahrenheit")
        u .= "&temperature_unit=fahrenheit&wind_speed_unit=mph"
    return u
}

; WinHttp rather than Msxml2.XMLHTTP, and that is not a preference.
;
; Measured on this build: MSXML (3.0 and 6.0) returns status 200 with an EMPTY
; responseText for an application/json body - it will not decode a content type it
; does not consider text - so every reading came back blank. WinHttpRequest returns
; the body. It is opened async and polled with WaitForResponse(0), which returns
; immediately, so nothing on this path blocks; a bare WaitForResponse() would block
; the frame loop and every timer in the process.
StartWeatherRequest(stage, url) {
    global CustomClockReq, WeatherReqAt, WeatherStage
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        ; resolve, connect, send, receive - in ms. Async still needs these, or a
        ; dead route keeps the object alive until the process exits.
        req.SetTimeouts(4000, 8000, 8000, 12000)
        req.Open("GET", url, true)
        req.Send()
        CustomClockReq := req
        WeatherStage := stage
        WeatherReqAt := A_TickCount
        return
    }
    CustomClockReq := 0
    WeatherStage := ""
    WeatherFailed("the request could not be started")
}

; Two requests, because open-meteo takes coordinates rather than a place name: the
; geocoder resolves the city once and the result is cached for as long as the
; setting does not change, so the steady state is one request every 15 minutes.
;
; This replaced wttr.in, which was not dependable enough to build on: it answers
; 200 with its HTML landing page instead of an error status whenever it will not
; serve a reading, it did that for /Baku while answering /Berlin in plain text, it
; did it for ?format=%t on its own, and after roughly twenty requests in a few
; minutes it did it for everything - and then began timing out entirely. Every one
; of those is indistinguishable from success at the HTTP level.
FetchWeather() {
    global CustomClockReq, LastWeatherFetch, ClockLocation, GeoFor, CustomClockWeather
    global ClockWeatherEnabled, ClockWarnedNoCity
    if (CustomClockReq)
        return                        ; one in flight is enough
    ; Stamp the attempt BEFORE sending, or a slow endpoint would be re-requested on
    ; every tick. The interval itself is set by the outcome - see WeatherFailed and
    ; the success path in PollWeather - so this only records that we tried.
    LastWeatherFetch := A_TickCount
    ; No city, no network. The time and the date need nothing, so the block still
    ; draws - the temperature column simply is not there until a location is typed.
    ; This is also what makes the feature safe to default ON: out of the box it
    ; makes no outbound request whatsoever.
    ; Switched off, or no city: no request at all. The block still draws - the time
    ; and the date need nothing - and the temperature column shows "--". This is
    ; also what keeps the feature safe to default ON: out of the box it makes no
    ; outbound call whatsoever, and the egress begins only once a city is typed.
    if (!ClockWeatherEnabled) {
        CustomClockWeather := ""
        return
    }
    if (ClockLocation == "") {
        CustomClockWeather := ""
        ; Said once per session, and only because the column is visibly showing
        ; "--": the user can see something is missing, so tell them what fills it.
        if (!ClockWarnedNoCity) {
            ClockWarnedNoCity := true
            Notify("Taskbar clock: set a Location in Shift+Alt+W, Taskbar Clock`nto show the temperature.")
        }
        return
    }
    if (GeoFor != ClockLocation)
        StartWeatherRequest("geo", "https://geocoding-api.open-meteo.com/v1/search"
            . "?count=1&language=en&format=json&name=" ClockUrlPart(ClockLocation))
    else
        StartWeatherRequest("now", ForecastUrl())
}

; Polled from the clock tick rather than driven by an event handler. A handler is
; one more thing that has to work for the feature to work at all, and with MSXML it
; also forced the request object to be released from inside its own callback, while
; the library was still on the stack. The tick is already running, so this costs
; nothing and cannot fail in a way that is invisible.
PollWeather() {
    global CustomClockReq, WeatherStage, WeatherReqAt, CustomClockWeather
    global WeatherNextMs, WeatherFailMs, ClockLocation, ClockUnits
    global GeoFor, GeoLat, GeoLon, CustomClockWind
    if !CustomClockReq
        return
    ready := false
    try ready := CustomClockReq.WaitForResponse(0)
    catch {
        CustomClockReq := 0, WeatherStage := ""
        WeatherFailed("the connection failed")
        return
    }
    if (!ready) {
        if (A_TickCount - WeatherReqAt > 20000) {
            CustomClockReq := 0, WeatherStage := ""
            WeatherFailed("the request timed out")
        }
        return
    }
    status := 0, body := ""
    try status := CustomClockReq.Status
    try body := CustomClockReq.ResponseText
    stage := WeatherStage
    CustomClockReq := 0, WeatherStage := ""
    if (status != 200) {
        WeatherFailed("the server answered " status)
        return
    }

    if (stage == "geo") {
        ; results[0] first, so the first latitude/longitude in the body is the match.
        ; An unknown name comes back as 200 with {"generationtime_ms":...} and no
        ; results at all, which is why this is a parse failure rather than a status.
        if (!RegExMatch(body, '"latitude"\s*:\s*(-?[0-9.]+)', &mLa)
            || !RegExMatch(body, '"longitude"\s*:\s*(-?[0-9.]+)', &mLo)) {
            WeatherFailed("that place name was not found")
            return
        }
        GeoLat := mLa[1], GeoLon := mLo[1], GeoFor := ClockLocation
        StartWeatherRequest("now", ForecastUrl())     ; straight on to the reading
        return
    }

    ; The forecast body carries temperature_2m twice: once in current_units as the
    ; STRING "C, and once in current as the number. Requiring a digit right after
    ; the colon is what picks the second one.
    if !RegExMatch(body, '"temperature_2m"\s*:\s*(-?[0-9.]+)', &mT) {
        WeatherFailed("no temperature in the reply")
        return
    }
    n := Round(Number(mT[1]))
    ; Chr(176) rather than a literal degree sign, for the same ASCII-source reason
    ; as WeatherIcon.
    unit := (ClockUnits == "Fahrenheit") ? "F" : "C"
    temp := (n > 0 ? "+" : "") n Chr(176) unit

    ; The condition glyph and the wind are additive: a reply that omits either still
    ; produces a reading, because the temperature is the part that must be there.
    icon := ""
    if RegExMatch(body, '"weather_code"\s*:\s*([0-9]+)', &mC)
        icon := WeatherIcon(Integer(mC[1])) " "
    CustomClockWeather := icon temp

    CustomClockWind := ""
    if RegExMatch(body, '"wind_speed_10m"\s*:\s*(-?[0-9.]+)', &mW)
        CustomClockWind := Round(Number(mW[1])) (ClockUnits == "Fahrenheit" ? " mph" : " km/h")

    WeatherFailMs := 0
    WeatherNextMs := 900000
}

; Failure never reaches the taskbar: the block hides instead. It is said once per
; location in the log, and once in a tray tip when the user typed the location
; themselves, because "that city name does not work" is something only they can fix.
WeatherFailed(why) {
    global CustomClockWeather, ClockLocation, WeatherWarnedFor
    global WeatherNextMs, WeatherFailMs
    ; Back OFF rather than retrying at a fixed minute. The likeliest reason for a
    ; refusal is a rate limit at the far end - twenty wttr.in requests in a few
    ; minutes was enough to trip one, measured - and a fixed retry keeps you there.
    WeatherFailMs := Min(Max(WeatherFailMs * 3, 60000), 900000)
    WeatherNextMs := WeatherFailMs
    CustomClockWeather := ""
    key := ClockLocation == "" ? "(unset)" : ClockLocation
    if (WeatherWarnedFor == key)
        return
    WeatherWarnedFor := key
    WriteLog("Taskbar temperature: " why " (location: " key ")")
    Notify(ClockLocation == ""
        ? "Taskbar temperature needs a city.`nSet one in Shift+Alt+W, General."
        : "No temperature for " ClockLocation ".`n" why ".")
}

; ----------------------------------------------------------------------------
; 5. Black Hole Delete
; ----------------------------------------------------------------------------
global ActiveDeleteGuis := Map()

#HotIf BlackHoleDeleteEnabled && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class WorkerW") || WinActive("ahk_class Progman")) && A_Cursor != "IBeam"
~Delete:: {
    hwnd := WinExist("A")
    TriggerBlackHoleDelete(hwnd)
}
#HotIf

TriggerBlackHoleDelete(hwnd) {
    global ActiveDeleteGuis
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "EEFFFF"
    
    thumb := 0
    DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
    
    size := 140
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    srcX := mx - wx - (size/2)
    srcY := my - wy - (size/2)
    
    guiObj.Show("NA x" (mx - size/2) " y" (my - size/2) " w" size " h" size)
    WinSetTransColor("EEFFFF", guiObj.Hwnd)
    
    animKey := "DeleteHole_" . guiObj.Hwnd
    start := QPC()
    ms := 600
    
    startX := mx - size/2
    startY := my - size/2
    
    prim := MonitorGetPrimary()
    MonitorGet(prim, &mL, &mT, &mR, &mB)
    destX := mL + 40
    destY := mT + 40
    
    distX := Abs(destX - startX)
    distY := Abs(destY - startY)
    
    ActiveDeleteGuis[animKey] := {gui: guiObj, thumb: thumb}
    
    Step(dt, now) {
        if (!ActiveDeleteGuis.Has(animKey))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            CleanDeleteGui(animKey)
            return false
        }
        
        ease := t * t * t 
        
        curX := startX + (destX - startX) * ease
        curY := startY + (destY - startY) * ease
        
        if (distX > distY) {
            curW := Round(size * (1 + ease * 2)) 
            curH := Round(size * (1 - ease * 0.8)) 
        } else {
            curW := Round(size * (1 - ease * 0.8)) 
            curH := Round(size * (1 + ease * 2)) 
        }
        
        scaleDown := 1 - ease
        curW := Round(curW * scaleDown)
        curH := Round(curH * scaleDown)
        
        if (curW < 1)
            curW := 1
        if (curH < 1)
            curH := 1
            
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", curW, "int", curH, "uint", 0x14) 
        
        ; See the struct layout note in UpdateCarousel.
        props := Buffer(48, 0)
        NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
        NumPut("int", 0, props, 4)
        NumPut("int", 0, props, 8)
        NumPut("int", curW, props, 12)
        NumPut("int", curH, props, 16)

        NumPut("int", Round(srcX), props, 20)
        NumPut("int", Round(srcY), props, 24)
        NumPut("int", Round(srcX + size), props, 28)
        NumPut("int", Round(srcY + size), props, 32)

        alpha := Round(255 * (1 - ease))
        NumPut("char", alpha, props, 36)
        NumPut("int", 1, props, 40)

        DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", props)
        return true
    }
    RegisterAnimation(animKey, Step)
}

CleanDeleteGui(animKey) {
    global ActiveDeleteGuis
    if (ActiveDeleteGuis.Has(animKey)) {
        obj := ActiveDeleteGuis[animKey]
        DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", obj.thumb)
        obj.gui.Destroy()
        ActiveDeleteGuis.Delete(animKey)
    }
}

; ----------------------------------------------------------------------------
; 6. Shatter to Close & Black Hole Minimize
; ----------------------------------------------------------------------------
TriggerBlackHoleMinimize(hwnd) {
    if !hwnd
        return
    try {
        if (WinGetMinMax(hwnd) != 0)
            return ; Don't animate maximized windows to save performance
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        return
    }
    if (w < 1 || h < 1)
        return
        
    hbm := 0
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    if hdcDest {
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
        if (hbm && hdcMem) {
            oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
            DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
        }
        if hdcMem
            DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    }
    if !hbm
        return
        
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
    animGui.MarginX := 0, animGui.MarginY := 0
    animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("NA x" x " y" y " w" w " h" h)
    
    animKey := "MinHole_" . animGui.Hwnd
    start := QPC()
    ms := 300
    
    startX := x
    startY := y
    destX := Round(A_ScreenWidth / 2)
    destY := Round(A_ScreenHeight)
    
    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            animGui.Destroy()
            DllCall("DeleteObject", "ptr", hbm)
            return false
        }
        
        ease := t * t * t 
        
        curX := startX + (destX - startX - w/2) * ease
        curY := startY + (destY - startY - h/2) * ease
        
        scaleDown := 1 - ease
        curW := Round(w * scaleDown)
        curH := Round(h * scaleDown)
        
        if (curW < 1)
            curW := 1
        if (curH < 1)
            curH := 1
            
        DllCall("SetWindowPos", "ptr", animGui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", curW, "int", curH, "uint", 0x14)
        
        WinSetTransparent(Round(255 * scaleDown), animGui.Hwnd)
        return true
    }
    RegisterAnimation(animKey, Step)
}

#HotIf ShatterEnabled
+!F4:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        TriggerShatterClose(hwnd)
    }
}
#HotIf

TriggerShatterClose(hwnd) {
    global ActiveShatters
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    gridX := 4
    gridY := 4
    pieceW := ww / gridX
    pieceH := wh / gridY
    
    shards := []
    
    loop gridX {
        col := A_Index
        loop gridY {
            row := A_Index
            
            guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            guiObj.BackColor := "EEFFFF"
            WinSetTransColor("EEFFFF", guiObj.Hwnd)
            
            thumb := 0
            DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
            
            srcX := (col - 1) * pieceW
            srcY := (row - 1) * pieceH
            
            cx := wx + srcX + pieceW/2
            cy := wy + srcY + pieceH/2
            
            winCx := wx + ww/2
            winCy := wy + wh/2
            
            vx := (cx - winCx) * (Random(15, 40) / 100) 
            vy := (cy - winCy) * (Random(15, 40) / 100) - Random(5, 20) 
            
            spinW := Random(1, 8) * 0.1
            spinH := Random(1, 8) * 0.1
            
            shards.Push({gui: guiObj, thumb: thumb, x: wx + srcX, y: wy + srcY, w: pieceW, h: pieceH, srcX: srcX, srcY: srcY, vx: vx, vy: vy, spinW: spinW, spinH: spinH})
        }
    }
    
    animKey := "Shatter_" . hwnd

    ; Every other animation producer in this file cancels its own key before
    ; re-registering. Without it a second Shift+Alt+F4 on the same window
    ; overwrote the map entry and orphaned the first batch of 16 Guis and 16 DWM
    ; thumbnails, with nothing left holding a reference that could free them.
    CancelAnimation(animKey)
    CleanShatter(animKey)

    ; The real window is parked far off-screen so only the shards are visible.
    ; wx/wy go into the map BEFORE that happens: this is the only record of where
    ; it belongs, and Bye() needs it to put the window back if we exit mid-flight.
    ActiveShatters[animKey] := {shards: shards, hwnd: hwnd, x: wx, y: wy}

    RS_SetPos(hwnd, -19999, wy, -1, -1, RS_PRI_USER)

    start := QPC()
    ms := 1000

    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            CleanShatter(animKey)
            if (DllCall("IsWindow", "ptr", hwnd)) {
                try RS_SetPos(hwnd, wx, wy, -1, -1, RS_PRI_USER)
                try WinClose(hwnd)
            }
            return false
        }
        
        alpha := Round(255 * (1 - (t ** 2))) 
        
        for s in shards {
            s.vy += 1.2 ; Gravity
            s.x += s.vx
            s.y += s.vy
            
            curW := s.w * Abs(Cos(t * 15 * s.spinW))
            curH := s.h * Abs(Cos(t * 15 * s.spinH))
            
            if (curW < 1)
                curW := 1
            if (curH < 1)
                curH := 1
                
            curX := s.x + (s.w - curW)/2
            curY := s.y + (s.h - curH)/2
            
            DllCall("SetWindowPos", "ptr", s.gui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", Round(curW), "int", Round(curH), "uint", 0x14 | 0x40) 
            
            ; See the struct layout note in UpdateCarousel.
            props := Buffer(48, 0)
            NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, props, 0)
            NumPut("int", 0, props, 4)
            NumPut("int", 0, props, 8)
            NumPut("int", Round(curW), props, 12)
            NumPut("int", Round(curH), props, 16)

            NumPut("int", Round(s.srcX), props, 20)
            NumPut("int", Round(s.srcY), props, 24)
            NumPut("int", Round(s.srcX + s.w), props, 28)
            NumPut("int", Round(s.srcY + s.h), props, 32)

            NumPut("char", alpha, props, 36)
            NumPut("int", 1, props, 40)

            DllCall("Dwmapi\DwmUpdateThumbnailProperties", "ptr", s.thumb, "ptr", props)
        }
        return true
    }
    
    RegisterAnimation(animKey, Step)
}

CleanShatter(animKey) {
    global ActiveShatters
    if (ActiveShatters.Has(animKey)) {
        obj := ActiveShatters[animKey]
        for s in obj.shards {
            DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", s.thumb)
            s.gui.Destroy()
        }
        ActiveShatters.Delete(animKey)
    }
}

; Bye() calls this. TriggerShatterClose parks the real window at x = -19999 and
; the ONLY thing that ever moves it back is the animation's final frame - which
; never arrives if the callback throws (the scheduler silently deregisters it) or
; if we exit mid-flight. The window was then alive, invisible and unrecoverable.
RestoreShatters() {
    global ActiveShatters
    for animKey, obj in ActiveShatters.Clone() {
        if (DllCall("IsWindow", "ptr", obj.hwnd))
            try RS_SetPos(obj.hwnd, obj.x, obj.y, -1, -1, RS_PRI_USER)
        try CancelAnimation(animKey)
        try CleanShatter(animKey)
    }
}

; ----------------------------------------------------------------------------
; 8. Privacy Blur on Unfocus
; ----------------------------------------------------------------------------

#HotIf PrivacyBlurEnabled
#!b:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        if (PrivacyBlurWindows.Has(hwnd)) {
            RemovePrivacyBlur(hwnd)
        } else {
            AddPrivacyBlur(hwnd)
        }
    }
}
#HotIf

AddPrivacyBlur(hwnd) {
    global PrivacyBlurWindows
    if (PrivacyBlurWindows.Has(hwnd))
        return
        
    guiObj := Gui("-Caption +ToolWindow -DPIScale +E0x20")
    guiObj.Opt("+Owner" hwnd)
    guiObj.BackColor := "222222"
    WinSetTransparent(0, guiObj.Hwnd)
    guiObj.Show("NA Hide")
    
    accent := Buffer(16, 0)
    NumPut("int", 3, accent, 0) 
    NumPut("int", 2, accent, 4) 
    NumPut("int", 0x88222222, accent, 8) 
    NumPut("int", 0, accent, 12) 
    
    data := Buffer(24, 0)
    NumPut("int", 19, data, 0) 
    NumPut("ptr", accent.Ptr, data, A_PtrSize)
    NumPut("int", 16, data, A_PtrSize + A_PtrSize)
    
    DllCall("user32\SetWindowCompositionAttribute", "ptr", guiObj.Hwnd, "ptr", data)
    
    PrivacyBlurWindows[hwnd] := {gui: guiObj, active: false}
    ; The first private window is what makes the 32 ms poll necessary.
    SyncTaskbarUiTimer()
}

RemovePrivacyBlur(hwnd) {
    global PrivacyBlurWindows
    if (PrivacyBlurWindows.Has(hwnd)) {
        try PrivacyBlurWindows[hwnd].gui.Destroy()
        PrivacyBlurWindows.Delete(hwnd)
        SyncTaskbarUiTimer()      ; the last one lets the poll stop
    }
}

CheckPrivacyBlur() {
    global PrivacyBlurWindows, PrivacyBlurEnabled, BossKeyActive
    ; Switched off: take the frosted sheets down. Returning early instead left an
    ; opaque overlay welded over every window that had been marked private, with
    ; the feature that owns it disabled and no way to reach it - the same failure
    ; as the Start-menu blur and the lightsaber glow.
    if (!PrivacyBlurEnabled) {
        for hwnd, obj in PrivacyBlurWindows {
            if obj.active {
                obj.active := false
                try CancelAnimation("BlurFade_" obj.gui.Hwnd)
                try DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)   ; SW_HIDE
            }
        }
        return
    }

    ; With every window hidden nothing is active, so every private window would
    ; take the inactive branch below and get SWP_SHOWWINDOW plus a fade to opaque
    ; - drawing the shape of what the user just hid onto the empty desktop.
    if (BossKeyActive)
        return

    activeHwnd := WinExist("A")

    ; Collect, then delete. Deleting the current item shifts the remainder under
    ; the live enumerator index and silently skips the next private window - the
    ; documented Map rule that MC_Expire and BreathingAnimatorStep already follow.
    dead := []
    for hwnd, obj in PrivacyBlurWindows {
        if (!DllCall("IsWindow", "ptr", hwnd)) {
            try obj.gui.Destroy()
            dead.Push(hwnd)
            continue
        }
        
        isActive := (hwnd == activeHwnd)
        
        if (isActive) {
            if (obj.active) {
                obj.active := false
                
                animKey := "BlurFade_" . obj.gui.Hwnd
                start := QPC()
                ms := 200
                Step(dt, now) {
                    t := (now - start) / ms
                    if (t >= 1) {
                        DllCall("ShowWindow", "ptr", obj.gui.Hwnd, "int", 0)
                        return false
                    }
                    WinSetTransparent(Round(255 * (1 - (t**2))), obj.gui.Hwnd)
                    return true
                }
                RegisterAnimation(animKey, Step)
            }
        } else {
            try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            catch
                continue
                
            if (!obj.active) {
                obj.active := true
                DllCall("SetWindowPos", "ptr", obj.gui.Hwnd, "ptr", -1, "int", wx, "int", wy, "int", ww, "int", wh, "uint", 0x14 | 0x40) 
                
                animKey := "BlurFade_" . obj.gui.Hwnd
                start := QPC()
                ms := 300
                StepOut(dt, now) {
                    t := (now - start) / ms
                    if (t >= 1) {
                        WinSetTransparent(255, obj.gui.Hwnd)
                        return false
                    }
                    WinSetTransparent(Round(255 * (t**3)), obj.gui.Hwnd)
                    return true
                }
                RegisterAnimation(animKey, StepOut)
            } else {
                DllCall("SetWindowPos", "ptr", obj.gui.Hwnd, "ptr", -1, "int", wx, "int", wy, "int", ww, "int", wh, "uint", 0x14)
            }
        }
    }

    for hwnd in dead
        PrivacyBlurWindows.Delete(hwnd)
}

; ============================================================================
; Startup - MUST stay the last statement in this file
; ============================================================================
; One call. Boot() lives in ProcessLifecycle.ahk and runs the whole startup
; sequence in one place: settings, tray, the drag hooks, every OnMessage handler,
; OnExit(Bye), and each feature's Sync*. It has to be here rather than beside any
; of those functions because AHK v2 runs all top-level code in file order, so a
; startup call placed higher up fires while declarations below it have not run
; yet - see the ProcessLifecycle.ahk header for the two bugs that produced.
Boot()


