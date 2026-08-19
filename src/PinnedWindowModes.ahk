; Pinned window modes - modes a user opts a SPECIFIC window into, and that must
; be released before this program exits.
;
; Function definitions and global initialisers only, no top-level statements.
; This module opens and closes a bare #HotIf around its one binding.
;
; PiP, always-on-bottom, proximity ghost and privacy blur are grouped because
; they share the property that matters: each leaves a foreign window in a state
; the user cannot undo by hand. That makes exit-time restoration mandatory, not
; polish, and it is why Bye() calls into all four.
;
; SetParent ACROSS PROCESSES IS NOT REALLY SUPPORTED BY WIN32 and is not undone
; by anything except RestoreFromBottom(). A window left parented to WorkerW
; cannot be alt-tabbed to, cannot be moved normally, and dies with the next
; Explorer restart.
;
; ToggleGhostMode INSTALLS ITS ALPHA LAYER AT FACTOR 1.0 ON PURPOSE. "Off" (256,
; which strips WS_EX_LAYERED) may only be emitted for a STRUCTURALLY neutral
; record - base 255 and zero layers - never because the arithmetic rounded up to
; 255. A numeric rule would strip and re-add WS_EX_LAYERED 40 times a second
; while the cursor rests on a ghost, and in between the window is opaque,
; click-through and always-on-top with no visible cue.
;
; NEVER SendMessage TO A FOREIGN WINDOW WITHOUT A TIMEOUT. A window whose thread
; is not pumping ("Not Responding") never returns, freezing this whole process -
; every timer and every hotkey - with it. Use SendMessageTimeout with
; SMTO_ABORTIFHUNG.
;
; Each of these owns a per-hwnd Map, and every one of them is pruned in the
; HSHELL_WINDOWDESTROYED branch of the shell hook in WindowLifecycle.ahk.

; ====== Live Window PiP ======

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
    if (!cls || IsShellSurface(srcHwnd, cls))
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

    RS_UpdateDwmThumbnail(guiObj.ThumbId, [0, 0, width, height], "", alpha, true, true)
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
                RS_UpdateDwmThumbnail(pipGui.ThumbId, "", "", alpha)
            }
        }
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
    if (!cls || IsShellSurface(hwnd, cls))
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
    if (!cls || IsShellSurface(hwnd, cls))
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

; ----------------------------------------------------------------------------
; 8. Privacy Blur on Unfocus
; ----------------------------------------------------------------------------

#HotIf
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
