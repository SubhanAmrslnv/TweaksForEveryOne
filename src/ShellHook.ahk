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

