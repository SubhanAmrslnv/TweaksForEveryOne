; Window lifecycle - classify a window, remember where it was, put it back, and
; animate it in. Owns the shell hook.
;
; Function definitions and global initialisers only, no top-level statements.
; Boot() registers the SHELLHOOK and TaskbarCreated handlers and calls
; RegisterShellHook() as the very last thing it does, because ShellEvent is the
; widest-reaching callback in the program - created, destroyed, activated and
; minimised - so nothing may still be uninitialised when it starts delivering.
;
; NEW WINDOWS ARE DETECTED VIA RegisterShellHookWindow, NOT POLLING - AND THAT
; REGISTRATION DOES NOT SURVIVE AN EXPLORER RESTART. Explorer broadcasts
; TaskbarCreated when the shell comes back; handling it and re-registering is the
; only thing keeping position memory, the open animations, focus pulse, breathing
; seeding, fly-to-mouse minimize and per-window cleanup alive after an Explorer
; crash - or after this program's own "Restart Explorer" button.
;
; POSITION MEMORY IS KEYED ON exe + WINDOW CLASS, and excludes dialogs, owned
; windows, WS_EX_TOOLWINDOW, anything without WS_THICKFRAME, and Picture-in-
; Picture. Every Chrome popup shares a class with the main window.
;
; NOTHING KEYED TO INPUT MAY TOUCH THE DISK. window-positions.ini was written
; with four synchronous IniWrites (~771 us each) at the end of every drag AND
; again from OnSnapLanded. It is buffered in PendingPositions and flushed by a
; 900 ms one-shot. For the same reason RememberPosition does NOT call
; IsMainApplicationWindow, which reaches a WMI query through ClassifyWindowImpl -
; tens of milliseconds of blocking COM on the drag path. Classification belongs
; on the window-created path, where RestorePosition already does it.
;
; NEVER MAKE A FOREIGN WINDOW LAYERED SPECULATIVELY. WinSetTransparent forces
; WS_EX_LAYERED; on a GPU-composited or full-screen window that costs a
; redirection surface and can break exclusive full-screen presentation.
; WillAnimateOpen() is the single eligibility test, applied BEFORE hiding a new
; window rather than after - get that backwards and brand-new windows sit at
; alpha 0, invisible but focused and clickable.
;
; The per-HWND state Maps are pruned in the HSHELL_WINDOWDESTROYED branch of the
; shell hook. Anything keyed on hwnd anywhere in the program has to be pruned
; there too, or it leaks for the session.

global POS_FILE := A_ScriptDir "\window-positions.ini"

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

IsShellSurface(hwnd, cls := "") {
    if (cls == "")
        try cls := WinGetClass(hwnd)
        catch
            return false
    return (cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || cls == "Progman" || cls == "WorkerW")
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
