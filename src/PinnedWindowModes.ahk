; Pinned window modes - modes a user opts a SPECIFIC window into, and that must
; be released before this program exits.
;
; Function definitions and global initialisers only, no top-level statements.
; This module opens and closes a bare #HotIf around its one binding.
;
; PiP and proximity ghost are grouped because they share the property that
; matters: each leaves a foreign window in a state the user cannot undo by hand.
; That makes exit-time restoration mandatory, not polish, and it is why Bye()
; calls into both.
;
; Always-on-Bottom used to live here and was REMOVED, not switched off: it
; reparented a foreign window into Explorer's WorkerW with a cross-process
; SetParent, which Win32 does not really support - the window could not be
; alt-tabbed to, could not be moved normally, and died with the next Explorer
; restart. Do not reintroduce it.
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

    ; WM_MOUSEWHEEL / WM_MOUSEHWHEEL deliver screen coordinates in lParam,
    ; unlike other mouse messages which deliver client coordinates.
    isWheel := (msg == 0x020A || msg == 0x020E)
    if (isWheel) {
        pt := Buffer(8, 0)
        NumPut("int", x, "int", y, pt)
        if !DllCall("ScreenToClient", "ptr", hwnd, "ptr", pt)
            return 0
        x := NumGet(pt, 0, "int")
        y := NumGet(pt, 4, "int")
    }

    pw := 0, ph := 0, sw := 0, sh := 0
    try {
        WinGetClientPos(,, &pw, &ph, hwnd)
        WinGetClientPos(,, &sw, &sh, sourceHwnd)
    } catch
        return
        
    if (pw > 0 && ph > 0) {
        srcX := Round(x * (sw / pw))
        srcY := Round(y * (sh / ph))

        if (isWheel) {
            pt := Buffer(8, 0)
            NumPut("int", srcX, "int", srcY, pt)
            if !DllCall("ClientToScreen", "ptr", sourceHwnd, "ptr", pt)
                return 0
            srcX := NumGet(pt, 0, "int")
            srcY := NumGet(pt, 4, "int")
        }
        
        newLParam := ((srcY & 0xFFFF) << 16) | (srcX & 0xFFFF)
        try PostMessage(msg, wParam, newLParam,, "ahk_id " sourceHwnd)
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
    PipGui.OnEvent("Close", (*) => ClosePiP(srcHwnd))
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
        if (!DllCall("IsWindow", "ptr", srcHwnd) || !DllCall("IsWindow", "ptr", pipGui.Hwnd)) {
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
        RS_SetZOrder(hwnd, -1, 0x0013, RS_PRI_USER)
        RS_Commit()
    } catch {
        try WinSetExStyle("-0x20", hwnd)
        try RS_ClearAlphaLayer(hwnd, "ghost", RS_PRI_AMBIENT)
        try RS_Commit()
        return
    }

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
        if !(orig.exStyle & 0x20)
            WinSetExStyle("-0x20", hwnd)
        if !(orig.exStyle & 0x8)
            RS_SetZOrder(hwnd, -2, 0x0013, RS_PRI_USER)
        RS_Commit()
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
            origClickThrough := (info.exStyle & 0x20)
            
            if (dist < clickDist) {
                if (isClickThrough && !origClickThrough)
                    WinSetExStyle("-0x20", hwnd)
            } else if (dist > clickDist + 12) {
                if (!isClickThrough)
                    WinSetExStyle("+0x20", hwnd)
            }
        }
    }

    if IsObject(dead) {
        for hwnd in dead {
            ; Has(): RestoreAllWindows or ApplyUi can un-ghost it between the
            ; collect and here, and a throw in a timer kills the timer.
            if GhostWindows.Has(hwnd)
                GhostWindows.Delete(hwnd)
        }
        if (GhostWindows.Count == 0)
            SetTimer(GhostMonitorStep, 0)
    }

    ; A monitor timer, not an animation: nothing else flushes for it, so without
    ; this the proximity fade never reached the screen at all.
    RS_Commit()
}

#HotIf
