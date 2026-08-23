; Shell surface watcher - the ONE poll that watches Explorer's own surfaces.
;
; Function definitions and global initialisers only, no top-level statements.
;
; Smart auto-hide, the taskbar icon wave and elastic toasts all need to know what
; the shell is doing right now, and none of them can be event-driven. They share
; CheckTaskbarAndUI on one 32 ms timer rather than each arming its own, because
; CheckToasts alone enumerates every top-level window with a title filter on each
; tick.
;
; A FEATURE THAT OWNS AN OVERLAY MUST TEAR IT DOWN WHEN ITS FLAG GOES FALSE, AND
; THE FLAG TEST BELONGS INSIDE THAT FUNCTION - which is why CheckTaskbarAndUI
; calls RenderTaskbarWave unconditionally. Gating the call site instead means
; switching the feature off stops the only code that could ever clean up, which
; used to strand a full-screen dimming sheet over the desktop and a glow welded
; to a window edge. Anything added here needs RenderTaskbarWave's shape.
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
    ; Toast Bounce along with this feature for the rest of the session.
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
    
    ; See the DWM_THUMBNAIL_PROPERTIES layout in RS_UpdateDwmThumbnail. rcSource IS
    ; written here, so DWM_TNP_RECTSOURCE (0x02) is correct.
    RS_UpdateDwmThumbnail(TaskbarWaveThumb, [0, 0, size, size], [srcX, srcY, srcW, srcH], 255, true, true)
}

global KnownToasts := Map()

CheckTaskbarAndUI() {
    global TaskbarWaveEnabled, ToastBounceEnabled
    
    ; Called unconditionally on purpose: it checks its own flag as its FIRST act
    ; and tears its overlay down when the flag is off. Gating it here instead is
    ; what stranded the taskbar magnifier on screen when its box was unchecked
    ; mid-effect.
    RenderTaskbarWave()

    ; Toast bounce holds no overlay of its own - it only animates shell windows -
    ; so there is nothing to clean up and it can stay gated.
    if (ToastBounceEnabled)
        CheckToasts()
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
            ; Taskbar Wave.
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
    global TaskbarWaveEnabled, ToastBounceEnabled
    wanted := TaskbarWaveEnabled || ToastBounceEnabled
    if (wanted) {
        SetTimer(CheckTaskbarAndUI, 32)
        return
    }
    CheckTaskbarAndUI()            ; final pass: every sub-check cleans up
    SetTimer(CheckTaskbarAndUI, 0)
}
