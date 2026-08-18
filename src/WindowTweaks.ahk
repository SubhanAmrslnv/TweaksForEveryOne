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
#Include PinnedWindowModes.ahk
#Include MouseGestureFx.ahk
#Include ShellSurfaceWatcher.ahk
#Include TaskbarClock.ahk
#Include WindowSpectacleFx.ahk
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










































; Boot() registers the ten OnMessage handlers these functions need: WM_NCHITTEST,
; WM_NCMBUTTONDOWN and the eight mouse messages. Each one runs for every message
; of its kind that reaches ANY window this process owns, which is why every
; handler's first act is to test the hwnd against PipGuis and return unhandled.

































































; ============================================================================
; Mouse & Cursors FX
; ============================================================================














































































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


