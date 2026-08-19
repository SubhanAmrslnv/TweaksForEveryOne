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

global PendingPositions := Map()

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

