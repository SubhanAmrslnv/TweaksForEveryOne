; Shell surface watcher - the ONE poll that watches Explorer's own surfaces.
;
; Function definitions and global initialisers only, no top-level statements.
;
; Smart auto-hide, the taskbar icon wave, the lightsaber seam glow, Start-menu
; blur and elastic toasts all need to know what the shell is doing right now, and
; none of them can be event-driven. They share CheckTaskbarAndUI on one 32 ms
; timer rather than each arming its own, because CheckToasts alone enumerates
; every top-level window with a title filter on each tick.
;
; A FEATURE THAT OWNS AN OVERLAY MUST TEAR IT DOWN WHEN ITS FLAG GOES FALSE, AND
; THE FLAG TEST BELONGS INSIDE THAT FUNCTION - which is why CheckTaskbarAndUI
; calls all four unconditionally. Gating the call site instead means switching
; the feature off stops the only code that could ever clean up: Start Menu Blur
; stranded a full-screen 170-alpha sheet over the desktop, and Lightsaber left a
; cyan bar welded to a window edge. RenderTaskbarWave had the right shape; the
; others were made to match it.
;
; A TIMER CALLBACK THAT THROWS POPS AN ERROR DIALOG AND KILLS THAT TIMER, so the
; feature is dead for the rest of the session. Every window query in here is
; inside try with an explicit fallback - IsMouseOverTaskbar() is the pattern.
;
; Smart auto-hide is the reason work areas are never cached: it changes the work
; area and that raises no WM_DISPLAYCHANGE.

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
            if (IsShellSurface(hwnd, cls))
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
    RS_UpdateDwmThumbnail(TaskbarWaveThumb, [0, 0, size, size], [srcX, srcY, srcW, srcH], 255, true, true)
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
