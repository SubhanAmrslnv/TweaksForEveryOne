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
#Include DragPipeline.ahk
#Include DropPlacement.ahk
#Include WindowLifecycle.ahk
#Include AmbientDimming.ahk
#Include ScreenEdgeGestures.ahk
#Include AudioOsd.ahk
#Include OnDemandOverlays.ahk
#Include FocusEmphasis.ahk
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







































global PendingTransMsg := ""










; Boot() registers OnMessage(0x1000) for the icons this Map holds.













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


