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
; crash or a user-initiated Explorer restart.
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
; A window can leave the shell's task list while its HWND is still live.
; EVENT_OBJECT_DESTROY also reaches windows that were hidden before they closed.

global WindowDestroyCb := 0, WindowDestroyHook := 0

InstallWindowDestroyHook() {
    global WindowDestroyCb, WindowDestroyHook
    WindowDestroyCb := CallbackCreate(WindowDestroyEvent, , 7)
    WindowDestroyHook := DllCall("SetWinEventHook", "uint", 0x8001, "uint", 0x8001, "ptr", 0
        , "ptr", WindowDestroyCb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")
}

RemoveWindowDestroyHook() {
    global WindowDestroyCb, WindowDestroyHook
    if WindowDestroyHook
        DllCall("UnhookWinEvent", "ptr", WindowDestroyHook)
    if WindowDestroyCb
        CallbackFree(WindowDestroyCb)
    WindowDestroyHook := 0, WindowDestroyCb := 0
}

WindowDestroyEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global TrayIcons, CurtainWindows, RolledUpWindows, RollDownPending, UnrollPending
    if (!hwnd || idObject != 0 || idChild != 0)
        return
    if !DllCall("IsWindow", "ptr", hwnd) {
        ForgetDestroyedWindow(hwnd)
    } else if (TrayIcons.Has(hwnd) || CurtainWindows.Has(hwnd) || RolledUpWindows.Has(hwnd)
        || RollDownPending.Has(hwnd) || UnrollPending.Has(hwnd)) {
        SetTimer(ForgetDestroyedWindow.Bind(hwnd), -100)
    }
}

ForgetDestroyedWindow(hwnd) {
    global CustomTrans, RolledUpWindows, RollDownPending, WinTargetAlpha, WinCurrentAlpha, WinLastActive
    global WindowCmdLineCache, LayoutUndo, SizeCycleIdx, ElasticEdgeStates, ElasticAwayCounts
    global PendingOpen, OpenAnimated, GhostHiddenWindows, UnrollPending, CurtainWindows, TrayIcons
    if DllCall("IsWindow", "ptr", hwnd)
        return
    for state in [WindowCmdLineCache, CustomTrans, RolledUpWindows, RollDownPending
        , WinTargetAlpha, WinCurrentAlpha, WinLastActive, LayoutUndo, SizeCycleIdx
        , ElasticEdgeStates, ElasticAwayCounts, PendingOpen, OpenAnimated, GhostHiddenWindows
        , UnrollPending, CurtainWindows] {
        if state.Has(hwnd)
            state.Delete(hwnd)
    }
    if TrayIcons.Has(hwnd)
        try RemoveTrayIcon(hwnd)
    Anim_Release(hwnd)
    RS_RemoveHwnd(hwnd)
    MC_RemoveHwnd(hwnd)
}

RegisterShellHook() {
    DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)
    return DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
}

TaskbarCreated(*) {
    ok := RegisterShellHook()
    try ReAddAllTrayIcons()
    WriteLog("explorer restarted - shell hook re-registered (" (ok ? "ok" : "FAILED") ")")
}

ShellEvent(wParam, lParam, *) {
    static HSHELL_WINDOWCREATED := 1
    static HSHELL_GETMINRECT := 5
    
    if ((wParam & 0x7FFF) = HSHELL_GETMINRECT) {
        if (!lParam)
            return
        global FlyMinimizeEnabled, BlackHoleMinimizeEnabled
        if (BlackHoleMinimizeEnabled) {
            static bhCount := 0
            static lastBhTime := 0
            t := A_TickCount
            if (t - lastBhTime > 500) {
                bhCount := 0
            }
            bhCount++
            lastBhTime := t
            
            hwndToMin := NumGet(lParam, 0, "ptr")
            if (bhCount <= 3) {
                TriggerBlackHoleMinimize(hwndToMin)
            }
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
    
    if ((wParam & 0x7FFF) = 2 && lParam) { ; HSHELL_WINDOWDESTROYED
        ; Let a real destruction finish before checking the HWND. WinHide can
        ; send the same shell notification while the window remains restorable.
        SetTimer(ForgetDestroyedWindow.Bind(lParam), -100)
        return
    }

    if ((wParam & 0x7FFF) = 4) { ; HSHELL_WINDOWACTIVATED
        if (lParam) {
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
        ;
        ; A window that is still DWM-cloaked here is not on screen yet and cannot
        ; be judged; it is parked until EVENT_OBJECT_UNCLOAKED (WindowOpenAnim).
        if (OpenAnim != "None") {
            if OpenAnimWantsUncloak(hwnd)
                OpenAnimPend(hwnd)
            else if OpenAnimHide(hwnd)
                GhostHiddenWindows[hwnd] := true
        }
        ; A hidden window starts animating almost at once - it is invisible
        ; until then, and the 250 ms this used to wait read as "the window
        ; appeared, vanished, then slid in". A window we did not hide keeps the
        ; longer settle, which only feeds position memory.
        SetTimer(() => HandleNewWindow(hwnd), GhostHiddenWindows.Has(hwnd) ? -60 : -250)
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

    StartOpenAnimation(hwnd, restoredRect)
}

