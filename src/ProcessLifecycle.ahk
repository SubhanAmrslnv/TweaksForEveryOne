; Process lifecycle - the one ordered startup sequence.
;
; Function definitions only, no top-level statements. Everything this module
; exists for happens inside Boot(), which the entry file calls as its last line,
; after every #Include.
;
; WHY Boot() exists. AHK v2 runs all top-level code in file order as a single
; auto-execute thread, so a "global X := ..." further down the file has not run
; yet when an earlier top-level call fires. A call that arms a timer, builds a
; Gui, talks to COM or registers a hook can therefore read state that does not
; exist yet - or have the state it just wrote reset underneath it when execution
; reaches the declaration. Worse, several of those calls pump the message queue,
; so a shell event queued during startup got dispatched right there: a window
; closing at that moment reached ShellEvent's HSHELL_WINDOWDESTROYED cleanup and
; threw "This global variable has not been assigned a value" on
; PushedBackWindows, declared thousands of lines below where the hook had been
; registered. It reproduced on a fresh install (the setup window closes as the
; app starts) and almost never when running from src\ on a quiet desktop.
;
; The program used to work around that with a "deferred init" block pinned to
; the bottom of WindowTweaks.ahk, plus a rule about which four calls were allowed
; above it. Boot() removes the class instead of documenting it: it runs after
; every module's declarations have run, so nothing it calls can be clobbered and
; #Include order is documentation rather than semantics.
;
; scripts\Check-Split.ps1 check 8 enforces the other half of the rule - no
; module may carry a top-level call of its own.

Boot() {
    ; Reload() starts the new process before the old one exits, and the tray
    ; Restart item goes through Reload(). A second Boot() would stack every
    ; OnMessage handler and register OnExit(Bye) twice, so Bye would run twice.
    static done := false
    if done
        return
    done := true

    ; Settings first: every Sync* below branches on a flag this loads, and
    ; SyncTray/BuildTray read the values to set their tick marks.
    LoadSettings()
    RotateLog()
    SyncTray()
    BuildTray()
    WriteLog("=== Window Tweaks " VERSION " started ===")

    ; Tray icons injected by Minimize-to-Tray talk back through this one.
    OnMessage(0x1000, TrayIconClick)

    ; MOVESIZESTART/END and the menu-popup event. Kept out of a top-level
    ; initialiser so the hooks cannot start delivering before the state their
    ; callbacks read has been declared.
    InstallDragHooks()

    ; The shell tells us when a window is created, so there is no polling timer.
    OnMessage(DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint"), ShellEvent)
    ; Explorer broadcasts TaskbarCreated to every top-level window when the shell
    ; restarts, and the shell-hook registration does NOT survive that. Without
    ; re-registering, an Explorer crash - or this app's own "Restart Explorer"
    ; button - silently killed position memory, the open animations, focus pulse,
    ; breathing seeding, fly-to-mouse minimize and per-window cleanup for the rest
    ; of the session, with no error anywhere.
    OnMessage(DllCall("RegisterWindowMessage", "str", "TaskbarCreated", "uint"), TaskbarCreated)
    OnMessage(0x007E, InvalidateScreenMetrics)     ; WM_DISPLAYCHANGE

    ; Live Window PiP. These run for every message of their kind that reaches any
    ; window this process owns, which is why each handler's first act is to check
    ; the hwnd against PipGuis and return unhandled.
    OnMessage(0x0084, WM_NCHITTEST_PiP)
    OnMessage(0x00A7, PiP_NCMouseEvents) ; WM_NCMBUTTONDOWN
    OnMessage(0x0201, PiP_MouseEvents) ; LBUTTONDOWN
    OnMessage(0x0202, PiP_MouseEvents) ; LBUTTONUP
    OnMessage(0x0204, PiP_MouseEvents) ; RBUTTONDOWN
    OnMessage(0x0205, PiP_MouseEvents) ; RBUTTONUP
    OnMessage(0x0207, PiP_MouseEvents) ; MBUTTONDOWN
    OnMessage(0x0208, PiP_MouseEvents) ; MBUTTONUP
    OnMessage(0x020A, PiP_MouseEvents) ; MOUSEWHEEL
    OnMessage(0x0200, PiP_MouseEvents) ; MOUSEMOVE

    OnExit(Bye)

    ; Feature arming. Each Sync* starts or stops its own polling timer according
    ; to the flag LoadSettings() just read, so a feature nobody enabled costs
    ; nothing. InitShakeFind() and InitLightsaber() are deliberately NOT called:
    ; both build their overlay lazily on first use.
    SyncShakeDetector()
    SyncCursorFxTimer()
    SyncTaskbarUiTimer()
    SyncBreathingTimers()
    SyncDimmerTimer()
    SyncSmartTaskbar()
    SyncHotCornersTimer()
    SyncCursorWrapTimer()
    SyncActiveBorderTimer()
    SyncTextExpander()
    SyncCustomClockTimer()
    ; Not a Sync: a one-off probe of a Windows setting that the drag effects
    ; cannot work without. It only ever logs and notifies.
    CheckDragFullWindows()
    UpdateKeyboardHook()
    ; Last of all. ShellEvent is the widest-reaching callback in the program -
    ; window created, destroyed, activated and minimised - so nothing else may
    ; still be uninitialised when the shell starts delivering to it.
    RegisterShellHook()
}
