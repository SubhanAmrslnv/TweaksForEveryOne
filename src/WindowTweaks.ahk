#Requires AutoHotkey v2.0
#SingleInstance Force

; Window Tweaks - magnetic window snapping, inertial ice glide, window
; animations and ~40 power-user tweaks for Windows 11.
;
; Shift+Alt+W opens the settings window. docs\HOTKEYS.md is the source of truth
; for the key bindings; docs\GUIDE.md is the user guide.
;
; THIS FILE IS THE ENTRY POINT AND NOTHING ELSE: process directives, the
; #Include manifest, and one Boot() call. It holds no globals, no functions and
; no other top-level statement, and scripts\Check-Split.ps1 check 8 fails any
; that reappear.
;
; MANIFEST ORDER IS DOCUMENTATION, NOT SEMANTICS - Boot() is what made that
; true. AHK v2 runs all top-level code in file order as one auto-execute thread,
; so before Boot() existed a startup call could fire while declarations below it
; had not run. Now every declaration in the program has run before the last line
; of this file executes. Two orderings are still real:
;
;   FeatureFlags.ahk comes first. Hotkeys are live from load time and a #HotIf
;   expression is evaluated against those globals from the first keypress.
;
;   ProcessLifecycle.ahk comes last, so Boot() and Bye() sit next to the
;   manifest they drive.
;
; EVERY #Include LIVES HERE. A nested include would rebase relative paths, and
; the modules stay flat in src\ with no underscore in any filename - both
; installers glob src\*.ahk, and build\Setup.cs unflattens '_' to '\' when it
; extracts, so Window_Commands.ahk would install as Window\Commands.ahk and fail
; to load on end-user machines and nowhere else.

; ----- Infrastructure: no feature knowledge -----
#Include SnapCore.ahk
#Include RenderCore.ahk
#Include AnimationScheduler.ahk
#Include MediaCore.ahk

; ----- Substrate: settings, flags, logging -----
#Include FeatureFlags.ahk
#Include TuningRegistry.ahk
#Include DiagnosticsLog.ahk
#Include SettingsStore.ahk

; ----- Shared services -----
#Include MonitorGeometry.ahk
#Include OverlayGui.ahk

; ----- UI and input -----
#Include SettingsWindow.ahk
#Include FeatureToggles.ahk
#Include InputBindings.ahk

; ----- Features -----
#Include CmdWindowGeometry.ahk
#Include CmdTransparency.ahk
#Include CmdRestoreAll.ahk
#Include CmdRollUp.ahk
#Include CmdAltDrag.ahk
#Include CmdTrayMinimize.ahk
#Include DragPipeline.ahk
#Include DropPlacement.ahk
#Include WindowClassification.ahk
#Include PositionMemory.ahk
#Include ShellHook.ahk
#Include WindowOpenAnim.ahk
#Include AmbientDimming.ahk
#Include ScreenEdgeGestures.ahk
#Include AudioOsd.ahk
#Include OnDemandOverlays.ahk
#Include FocusEmphasis.ahk
#Include PinnedWindowModes.ahk
#Include MouseGestureFx.ahk
#Include ShellSurfaceWatcher.ahk
#Include TaskbarClock.ahk
#Include FxGravity.ahk
#Include FxCurtain.ahk
#Include FxCarousel.ahk
#Include FxBlackHole.ahk
#Include FxShatter.ahk

; ----- Bolt-on: also runs standalone, so it keeps its own config and GUI -----
#Include StealthPanic.ahk

; ----- Boot() and Bye(). Last, so it sits beside the manifest it drives -----
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

; MUST STAY THE LAST STATEMENT IN THIS FILE. Boot() is in ProcessLifecycle.ahk
; and runs the whole startup sequence in one place: settings, tray, the drag
; hooks, every OnMessage handler, OnExit(Bye), and each feature's Sync*. It is
; here rather than beside any of those functions because a startup call placed
; higher up fires while declarations below it have not run yet.
Boot()
