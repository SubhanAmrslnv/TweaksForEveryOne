; StealthPanic.ahk - Triple ESC Stealth Panic Mode Engine

#Include "StealthPanicConfig.ahk"
global StealthPanicIniPath := A_ScriptDir "\StealthPanic.ini"

StealthSafeInt(val, def, minVal := 0) {
    s := Trim(String(val))
    if (s == "" || !IsNumber(s))
        return def
    n := Integer(Number(s))
    return (n < minVal) ? def : n
}

global StealthPanicEnabled := IniRead(StealthPanicIniPath, "stealth", "enabled", "1") == "1"
global StealthPanicTimeout := StealthSafeInt(IniRead(StealthPanicIniPath, "stealth", "timeout", "600"), 600, 100)
global StealthLaunchSafeApps := IniRead(StealthPanicIniPath, "stealth", "launchapps", "1") == "1"
global StealthSafeAppList := StealthPanicConfig_ReadAppList(StealthPanicIniPath)
global StealthLaunchDelay := StealthSafeInt(IniRead(StealthPanicIniPath, "stealth", "delay", "500"), 500, 0)
global StealthRestoreWorkspace := IniRead(StealthPanicIniPath, "stealth", "restore", "1") == "1"
global StealthMuteAudio := IniRead(StealthPanicIniPath, "stealth", "muteaudio", "1") == "1"
global StealthMuteMic := IniRead(StealthPanicIniPath, "stealth", "mutemic", "1") == "1"
global StealthSuspendAnimations := IniRead(StealthPanicIniPath, "stealth", "suspendanim", "1") == "1"
global StealthSuspendOverlays := IniRead(StealthPanicIniPath, "stealth", "suspendover", "1") == "1"
global StealthSuspendBackground := IniRead(StealthPanicIniPath, "stealth", "suspendbg", "1") == "1"

global StealthPanicActive := false
global StealthHiddenWindows := []
global StealthOriginalMic := false
global StealthSuspendedFeatures := Map()
; When panic was entered, so WriteSettings() can unwind it and Game Mode in the
; right order when both overlays are active at once.
global StealthEnteredTick := 0

global StealthEscCount := 0
global StealthEscTimer := 0
global StealthEscHeld := false
global StealthEscBusy := false

global STEALTH_RELOAD_MSG := DllCall("RegisterWindowMessage", "str", "TFE_StealthPanic_ReloadConfig", "uint")
OnMessage(STEALTH_RELOAD_MSG, StealthOnConfigMessage)

StealthOnConfigMessage(*) {
    global StealthPanicActive
    if (!StealthPanicActive)
        StealthPanicRefreshSettings()
}

StealthHotkeyAllowed() {
    global StealthPanicEnabled, GameModeActive
    return StealthPanicEnabled && !(IsSet(GameModeActive) && GameModeActive)
}

#HotIf StealthHotkeyAllowed()
~Esc:: {
    global StealthEscCount, StealthEscTimer, StealthPanicTimeout, StealthEscHeld, StealthEscBusy
    if (StealthEscHeld || StealthEscBusy)
        return
    StealthEscHeld := true
    StealthEscCount++
    if (StealthEscCount == 1) {
        StealthEscTimer := A_TickCount
        SetTimer(ResetStealthEsc, -StealthPanicTimeout)
    } else if (StealthEscCount == 3) {
        elapsed := A_TickCount - StealthEscTimer
        if (elapsed <= StealthPanicTimeout) {
            SetTimer(ResetStealthEsc, 0)
            StealthEscCount := 0
            StealthEscBusy := true
            try ToggleStealthPanic()
            finally StealthEscBusy := false
        } else {
            ; Reset if time window expired
            StealthEscCount := 1
            StealthEscTimer := A_TickCount
            SetTimer(ResetStealthEsc, -StealthPanicTimeout)
        }
    }
}
#HotIf

~Esc up:: {
    global StealthEscHeld := false
}

ResetStealthEsc() {
    global StealthEscCount := 0
}

ToggleStealthPanic() {
    global StealthPanicActive
    if (StealthPanicActive) {
        RestoreStealthPanic()
        return
    }
    StealthPanicRefreshSettings()
    EnterStealthPanic()
}

; Re-read the settings on the way IN, and only on the way in.
;
; The settings GUI is a separate process, so the copy loaded into these globals
; at startup is stale the moment the user saves - and the reload message the GUI
; posts only ever reaches the standalone runner, never the engine hosted inside
; Window Tweaks. Reloading Window Tweaks instead is not an option: Bye() un-hides
; every window, drops the tray icons and cancels every animation.
;
; Deliberately NOT on the way out. StealthMuteMic decides whether the captured
; microphone state is handed back. Turning it off in memory while panic is
; active would strand the mic muted.
;
; Cost is roughly ten IniRead calls at ~64 us each plus one small file read, on a
; path that only runs on an actual triple-ESC. Nowhere near an input hot path.
StealthPanicRefreshSettings() {
    global StealthPanicIniPath, StealthPanicEnabled, StealthPanicTimeout, StealthLaunchSafeApps
    global StealthSafeAppList, StealthLaunchDelay, StealthRestoreWorkspace
    global StealthMuteAudio, StealthMuteMic
    global StealthSuspendAnimations, StealthSuspendOverlays, StealthSuspendBackground

    ; Every read falls back to the value already in memory, so a locked or
    ; half-written ini leaves the engine on its last known-good settings instead
    ; of silently resetting it to the shipped defaults.
    try StealthPanicEnabled := IniRead(StealthPanicIniPath, "stealth", "enabled", StealthPanicEnabled ? "1" : "0") == "1"
    try StealthPanicTimeout := StealthSafeInt(IniRead(StealthPanicIniPath, "stealth", "timeout", StealthPanicTimeout), StealthPanicTimeout, 100)
    try StealthLaunchSafeApps := IniRead(StealthPanicIniPath, "stealth", "launchapps", StealthLaunchSafeApps ? "1" : "0") == "1"
    try StealthLaunchDelay := StealthSafeInt(IniRead(StealthPanicIniPath, "stealth", "delay", StealthLaunchDelay), StealthLaunchDelay, 0)
    try StealthRestoreWorkspace := IniRead(StealthPanicIniPath, "stealth", "restore", StealthRestoreWorkspace ? "1" : "0") == "1"
    try StealthMuteAudio := IniRead(StealthPanicIniPath, "stealth", "muteaudio", StealthMuteAudio ? "1" : "0") == "1"
    try StealthMuteMic := IniRead(StealthPanicIniPath, "stealth", "mutemic", StealthMuteMic ? "1" : "0") == "1"
    try StealthSuspendAnimations := IniRead(StealthPanicIniPath, "stealth", "suspendanim", StealthSuspendAnimations ? "1" : "0") == "1"
    try StealthSuspendOverlays := IniRead(StealthPanicIniPath, "stealth", "suspendover", StealthSuspendOverlays ? "1" : "0") == "1"
    try StealthSuspendBackground := IniRead(StealthPanicIniPath, "stealth", "suspendbg", StealthSuspendBackground ? "1" : "0") == "1"

    ; A hand-edited 0 here would make the triple-ESC window impossible to hit and
    ; leave the feature unreachable with no way to tell why.
    if (!IsNumber(StealthPanicTimeout) || StealthPanicTimeout < 100)
        StealthPanicTimeout := 600
    if (!IsNumber(StealthLaunchDelay) || StealthLaunchDelay < 0)
        StealthLaunchDelay := 0

    ; ReadAppList never throws. An empty result is far more likely to be a
    ; transient read failure than a deliberate "launch nothing", and the user can
    ; express that properly by unchecking "Launch safe applications".
    fresh := StealthPanicConfig_ReadAppList(StealthPanicIniPath)
    if (fresh != "")
        StealthSafeAppList := fresh
}

; Call a function that may not exist in this build.
;
; StealthPanic.ahk is #Included into WindowTweaks.ahk in the hosted case and run
; on its own in the standalone case, so every Sync* below genuinely does not
; exist half the time. A direct call to a missing function is a LOAD-time error
; that no try can catch - measured. %name% is resolved when the line runs, and
; its failure is an ordinary catchable Error.
StealthCall(fnName, args*) {
    try {
        fn := %fnName%
        if (fn is Func) {
            fn(args*)
            return true
        }
    }
    return false
}

; Start or stop the things the suspended flags actually drive.
;
; Flipping a feature flag without calling its Sync* leaves the feature's timer
; running and its overlay on screen while the flag claims it is off - CLAUDE.md
; documents that exact failure mode, and panic mode is the worst possible place
; for it, since the entire point is that nothing of the previous workspace shows.
;
; Each Sync* reads its own flag and starts or stops accordingly, so the same call
; list serves both the suspend and the restore direction.
StealthSyncFeatures() {
    global ProximityGhostEnabled, LivePipEnabled, GhostWindows, PipGuis

    ; Ghost and PiP hold per-window state that no Sync* releases, so they get the
    ; same explicit teardown ApplyUi performs when their box is unchecked.
    if (IsSet(ProximityGhostEnabled) && !ProximityGhostEnabled && IsSet(GhostWindows)) {
        for hwnd, info in GhostWindows.Clone()
            StealthCall("UnGhostWindow", hwnd)
        try SetTimer(%"GhostMonitorStep"%, 0)
    }
    if (IsSet(LivePipEnabled) && !LivePipEnabled && IsSet(PipGuis)) {
        for src, pip in PipGuis.Clone()
            StealthCall("ClosePiP", src)
    }

    StealthCall("SyncBreathingTimers")
    StealthCall("SyncCursorFxTimer")
    StealthCall("UpdateKeyboardHook")
    StealthCall("SyncMediaCore")
}

StealthIsShellSurface(hwnd, cls) {
    try {
        fn := %"IsShellSurface"%
        if (fn is Func)
            return fn(hwnd, cls)
    }
    static shellClasses := Map(
        "Shell_TrayWnd", true,
        "Shell_SecondaryTrayWnd", true,
        "Progman", true,
        "WorkerW", true,
        "Windows.UI.Core.CoreWindow", true,
        "XamlExplorerHostIslandWindow", true,
        "TopLevelWindowForOverflowXamlIsland", true,
        "ApplicationFrameInputSinkWindow", true,
        "ForegroundStaging", true,
        "TaskListThumbnailWnd", true,
        "MultitaskingViewFrame", true,
        "NotifyIconOverflowWindow", true
    )
    return shellClasses.Has(cls)
}

StealthIsCloaked(hwnd) {
    try {
        fn := %"IsCloaked"%
        if (fn is Func)
            return fn(hwnd)
    }
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return cloaked != 0
}

StealthGetMicMute() {
    try {
        fn := %"GetDefaultMicMute"%
        if (fn is Func) {
            st := fn()
            if (st == 0 || st == 1)
                return (st == 1)
        }
    }
    try return (SoundGetMute(, "Microphone") == 1)
    return false
}

StealthSetMicMute(state) {
    try {
        fn := %"SetDefaultMicMute"%
        if (fn is Func) {
            if fn(state ? true : false)
                return true
        }
    }
    try {
        SoundSetMute(state ? 1 : 0, , "Microphone")
        return true
    }
    return false
}

; Boss Key and Stealth Panic can overlap. The first owner saves the speaker
; state and the last owner restores it, regardless of which mode ends first.
; This also runs in standalone Stealth, where it has only one caller.
PanicSetSpeakerMute(owner, active) {
    static owners := Map(), originalMute := false
    prevCritical := Critical("On")
    try {
        if (active) {
            if (!owners.Count) {
                try originalMute := SoundGetMute()
                catch
                    originalMute := false
            }
            owners[owner] := true
            try SoundSetMute(true)
        } else if (owners.Has(owner)) {
            owners.Delete(owner)
            if (!owners.Count)
                try SoundSetMute(originalMute)
        }
    } finally Critical(prevCritical)
}

EnterStealthPanic() {
    global StealthEnteredTick
    global StealthPanicActive, StealthHiddenWindows, StealthOriginalMic
    global StealthMuteAudio, StealthMuteMic, StealthLaunchSafeApps, StealthLaunchDelay

    if (StealthPanicActive)
        return
    
    StealthPanicActive := true
    StealthEnteredTick := A_TickCount
    kept := []
    seen := Map()
    for hwnd in StealthHiddenWindows {
        if (DllCall("IsWindow", "ptr", hwnd) && !seen.Has(hwnd)) {
            kept.Push(hwnd)
            seen[hwnd] := true
        }
    }
    StealthHiddenWindows := kept
    
    ; 1. Hide windows
    ownPid := DllCall("GetCurrentProcessId", "uint")
    hwnds := WinGetList()
    for hwnd in hwnds {
        if (!StealthPanicActive)
            return
        cls := ""
        try cls := WinGetClass(hwnd)
        if (!cls || StealthIsShellSurface(hwnd, cls) || StealthIsCloaked(hwnd))
            continue
        pid := 0
        try pid := WinGetPID(hwnd)
        if (pid == ownPid)
            continue
        
        if !seen.Has(hwnd) {
            StealthHiddenWindows.Push(hwnd)
            seen[hwnd] := true
        }
        try WinHide(hwnd)
    }

    if (!StealthPanicActive)
        return
    
    ; 2. Mute audio
    if (StealthMuteAudio) {
        PanicSetSpeakerMute("Stealth", true)
        
        ; Stop any playing media if appropriate
        if (IsSet(MC_AnyMedia)) {
            if (MC_AnyMedia())
                try Send("{Media_Stop}")
        } else {
            try Send("{Media_Stop}")
        }
    }
    
    ; 3. Mute Mic
    if (StealthMuteMic) {
        StealthOriginalMic := StealthGetMicMute()
        StealthSetMicMute(true)
    }
    
    ; 4. Suspend features
    SuspendStealthFeatures()
    
    ; 5. Launch Safe Workspace
    if (StealthPanicActive && StealthLaunchSafeApps)
        SetTimer(LaunchSafeApps, -Max(1, StealthLaunchDelay))
}

RestoreStealthPanic() {
    global StealthPanicActive, StealthHiddenWindows, StealthOriginalMic
    global StealthRestoreWorkspace, StealthMuteMic

    if (!StealthPanicActive)
        return
        
    StealthPanicActive := false
    SetTimer(LaunchSafeApps, 0)
    
    if (StealthRestoreWorkspace) {
        for hwnd in StealthHiddenWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        StealthHiddenWindows := []
    }
    
    PanicSetSpeakerMute("Stealth", false)
    
    if (StealthMuteMic) {
        StealthSetMicMute(StealthOriginalMic)
    }
    
    RestoreStealthFeatures()
}

SuspendStealthFeatures() {
    global StealthSuspendedFeatures
    StealthSuspendedFeatures.Clear()
    
    global StealthSuspendAnimations, StealthSuspendOverlays, StealthSuspendBackground
    
    ; In standalone mode, WindowTweaks variables might not exist
    ; So we check using IsSet
    global OpenAnim, ContextMenuAnimEnabled, RippleClickEnabled
    global ProximityGhostEnabled, LivePipEnabled
    global SpotlightEnabled, BreathingEnabled, CursorYawnEnabled
    global GameModeActive, GameModeSuspendedFeatures

    gmActive := IsSet(GameModeActive) && GameModeActive && IsSet(GameModeSuspendedFeatures)
    RealVal(key, curVal) => (gmActive && GameModeSuspendedFeatures.Has(key)) ? GameModeSuspendedFeatures[key] : curVal
    
    if (StealthSuspendAnimations) {
        if IsSet(OpenAnim) {
            StealthSuspendedFeatures["OpenAnim"] := RealVal("OpenAnim", OpenAnim)
            OpenAnim := "None"
        }
        if IsSet(ContextMenuAnimEnabled) {
            StealthSuspendedFeatures["ContextMenuAnimEnabled"] := RealVal("ContextMenuAnimEnabled", ContextMenuAnimEnabled)
            ContextMenuAnimEnabled := false
        }
        if IsSet(RippleClickEnabled) {
            StealthSuspendedFeatures["RippleClickEnabled"] := RealVal("RippleClickEnabled", RippleClickEnabled)
            RippleClickEnabled := false
        }
    }
    if (StealthSuspendOverlays) {
        if IsSet(ProximityGhostEnabled) {
            StealthSuspendedFeatures["ProximityGhostEnabled"] := RealVal("ProximityGhostEnabled", ProximityGhostEnabled)
            ProximityGhostEnabled := false
        }
        if IsSet(LivePipEnabled) {
            StealthSuspendedFeatures["LivePipEnabled"] := RealVal("LivePipEnabled", LivePipEnabled)
            LivePipEnabled := false
        }
    }
    if (StealthSuspendBackground) {
        if IsSet(SpotlightEnabled) {
            StealthSuspendedFeatures["SpotlightEnabled"] := RealVal("SpotlightEnabled", SpotlightEnabled)
            SpotlightEnabled := false
        }
        if IsSet(BreathingEnabled) {
            StealthSuspendedFeatures["BreathingEnabled"] := RealVal("BreathingEnabled", BreathingEnabled)
            BreathingEnabled := false
        }
        if IsSet(CursorYawnEnabled) {
            StealthSuspendedFeatures["CursorYawnEnabled"] := RealVal("CursorYawnEnabled", CursorYawnEnabled)
            CursorYawnEnabled := false
        }
    }

    ; The flags above are only half the job - without this the timers keep
    ; running and the overlays stay on screen.
    StealthSyncFeatures()
}

RestoreStealthFeatures() {
    global StealthSuspendedFeatures
    StealthApplyFeatureValues(StealthSuspendedFeatures)
    StealthSuspendedFeatures.Clear()

    ; Same call list as the suspend direction: each Sync* reads the flag it was
    ; just handed back and restarts whatever that flag owns.
    StealthSyncFeatures()
}

; Writes each key of `values` back into the global flag of the same name. The one
; place that knows the suspended names, so the restore path, the exit path and
; the persistence bracket cannot drift apart. IsSet guards keep it safe standalone.
StealthApplyFeatureValues(values) {
    global OpenAnim, ContextMenuAnimEnabled, RippleClickEnabled
    global ProximityGhostEnabled, LivePipEnabled
    global SpotlightEnabled, BreathingEnabled, CursorYawnEnabled

    for key, val in values {
        if (key == "OpenAnim" && IsSet(OpenAnim))
            OpenAnim := val
        if (key == "ContextMenuAnimEnabled" && IsSet(ContextMenuAnimEnabled))
            ContextMenuAnimEnabled := val
        if (key == "RippleClickEnabled" && IsSet(RippleClickEnabled))
            RippleClickEnabled := val
        if (key == "ProximityGhostEnabled" && IsSet(ProximityGhostEnabled))
            ProximityGhostEnabled := val
        if (key == "LivePipEnabled" && IsSet(LivePipEnabled))
            LivePipEnabled := val
        if (key == "SpotlightEnabled" && IsSet(SpotlightEnabled))
            SpotlightEnabled := val
        if (key == "BreathingEnabled" && IsSet(BreathingEnabled))
            BreathingEnabled := val
        if (key == "CursorYawnEnabled" && IsSet(CursorYawnEnabled))
            CursorYawnEnabled := val
    }
}

; ====== Persistence bracket ======
;
; Stealth Panic suspends features in memory exactly the way Game Mode does, and
; WriteSettings() persists whatever the globals hold - so an exit, reload or any
; SaveSettings() while panic was active wrote OpenAnim=None, ripple/ghost/PiP/
; spotlight/breathing/yawn = 0 to settings.ini, and they stayed off for good.
; WriteSettings() brackets itself with this pair, same contract as
; GameModeUnsuspendForWrite()/GameModeResuspend(): no Sync* calls, because the
; real values are only back for the duration of the write.
StealthUnsuspendForWrite() {
    global StealthPanicActive, StealthSuspendedFeatures
    if (!StealthPanicActive || !StealthSuspendedFeatures.Count)
        return false
    StealthApplyFeatureValues(StealthSuspendedFeatures)
    return true
}

; Settings-window edits made during panic become the held values; see
; OverlaysAdoptEdits() in SettingsStore.ahk. Assume-global for the dynamic
; %name% read, hence the sp prefix on its scratch variables.
StealthAdoptEdits(resuspend := true) {
    global
    if (!StealthPanicActive)
        return
    for spKey in StealthSuspendedFeatures.Clone() {
        if IsSet(%spKey%)
            StealthSuspendedFeatures[spKey] := %spKey%
    }
    if (resuspend)
        StealthResuspend()
}

StealthResuspend() {
    global StealthPanicActive, StealthSuspendedFeatures
    if (!StealthPanicActive)
        return
    suppressed := Map()
    for key in StealthSuspendedFeatures
        suppressed[key] := (key == "OpenAnim") ? "None" : false
    StealthApplyFeatureValues(suppressed)
}

global StealthAppCache := Map()

LaunchSafeApps() {
    global StealthPanicActive, StealthSafeAppList
    if (!StealthPanicActive)
        return
    ; Next to the program, like every other file it writes. It used to go to
    ; %APPDATA%, outside the program folder, where no uninstaller removed it.
    logPath := A_ScriptDir "\StealthPanic_Launch.log"
    try FileDelete(logPath)
    
    LogLaunch(msg) {
        try FileAppend(A_Now " - " msg "`n", logPath)
    }
    
    LogLaunch("--- Starting Safe Workspace Launch ---")
    
    Loop Parse, StealthSafeAppList, "`n", "`r" {
        if (!StealthPanicActive)
            return
        appInput := Trim(A_LoopField)
        if (appInput == "")
            continue
            
        LogLaunch("`nParsing command: " appInput)
        appStr := DerefEnv(appInput)
        LogLaunch("Expanded environment variables: " appStr)
        
        exePath := "", args := ""
        if (SubStr(appStr, 1, 1) == '"') {
            endQuote := InStr(appStr, '"', false, 2)
            if (endQuote) {
                exePath := SubStr(appStr, 2, endQuote - 2)
                args := Trim(SubStr(appStr, endQuote + 1))
            } else {
                exePath := SubStr(appStr, 2)
            }
        } else {
            spacePos := InStr(appStr, " ")
            if (spacePos) {
                exePath := SubStr(appStr, 1, spacePos - 1)
                args := Trim(SubStr(appStr, spacePos + 1))
            } else {
                exePath := appStr
            }
        }
        
        SplitPath(exePath, &nameOnly, &dirOnly, &extOnly, &nameNoExt)
        
        ; 1. Explorer Specific Logic
        if (StrLower(nameOnly) == "explorer.exe") {
            LogLaunch("Explorer detected. Checking existing instances...")
            if ActivateExplorer(args) {
                LogLaunch("Launch successful (Activated existing Explorer).")
                continue
            }
            LogLaunch("Launching new Explorer instance...")
            try {
                Run("explorer.exe " args)
                LogLaunch("Launch successful.")
            } catch as e {
                LogLaunch("Failed to launch Explorer: " e.Message)
            }
            continue
        }
        
        ; 2. Existing Instance Activation
        if (nameOnly != "" && StrLower(extOnly) == "exe") {
            LogLaunch("Checking existing instances...")
            if ActivateExistingInstance(nameOnly) {
                LogLaunch("Launch successful (Activated existing instance).")
                continue
            }
        }
        
        ; 3. Absolute Path
        if (dirOnly != "" && FileExist(exePath)) {
            LogLaunch("Absolute path found. Launching...")
            try {
                Run(appStr)
                LogLaunch("Launch successful.")
            } catch as e {
                LogLaunch("Failed to launch absolute path: " e.Message)
            }
            continue
        }
        
        ; 4. Resolve Path
        resolvedPath := ResolveAppPath(nameOnly, LogLaunch)
        if (resolvedPath != "") {
            LogLaunch("Resolved executable:`n" resolvedPath)
            
            cmd := '"' resolvedPath '"' (args != "" ? " " args : "")
            LogLaunch("Launching...")
            try {
                Run(cmd)
                LogLaunch("Launch successful.")
            } catch as e {
                LogLaunch("Failed to launch resolved path: " e.Message)
            }
            continue
        }
        
        ; 5. Fallback ShellExecute
        LogLaunch("Resolution failed. Falling back to ShellExecute / Run()...")
        try {
            Run(appStr)
            LogLaunch("Launch successful (Fallback).")
        } catch as e {
            LogLaunch("Error: Could not launch " appStr " | Reason: " e.Message)
        }
    }
    
    LogLaunch("`n--- Launch Sequence Complete ---")
}

ActivateExplorer(args) {
    targetPath := Trim(args, "`" ")
    
    if (targetPath != "" && InStr(targetPath, "shell:") == 0) {
        try {
            shellApp := ComObject("Shell.Application")
            for win in shellApp.Windows {
                try {
                    if (win.Name == "File Explorer" || win.Name == "Windows Explorer") {
                        openPath := win.Document.Folder.Self.Path
                        if (StrCompare(openPath, targetPath) == 0) {
                            hwnd := win.HWND
                            WinRestore("ahk_id " hwnd)
                            WinActivate("ahk_id " hwnd)
                            return true
                        }
                    }
                }
            }
        }
    }
    
    if (args == "") {
        if WinExist("ahk_class CabinetWClass") {
            hwnd := WinExist("ahk_class CabinetWClass")
            WinRestore("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return true
        }
    }
    
    return false
}

ActivateExistingInstance(exeName) {
    hwnds := WinGetList("ahk_exe " exeName)
    if (hwnds.Length == 0)
        return false
        
    for hwnd in hwnds {
        if DllCall("IsWindowVisible", "ptr", hwnd) {
            WinRestore("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return true
        }
    }
    return false
}

DerefEnv(str) {
    pos := 1
    while (pos := RegExMatch(str, "%([^%]+)%", &match, pos)) {
        val := EnvGet(match[1])
        if (val != "") {
            str := StrReplace(str, match[0], val)
            pos += StrLen(val)
        } else {
            pos += StrLen(match[0])
        }
    }
    return str
}

ResolveAppPath(exeName, LogFunc) {
    global StealthAppCache
    
    if (exeName == "")
        return ""
        
    LogFunc("Checking cache...")
    if StealthAppCache.Has(exeName) {
        cached := StealthAppCache[exeName]
        if FileExist(cached) {
            return cached
        } else {
            StealthAppCache.Delete(exeName)
            LogFunc("Cache invalidation (file no longer exists).")
        }
    }
    
    LogFunc("Checking portable directories...")
    if FileExist(A_ScriptDir "\" exeName) {
        StealthAppCache[exeName] := A_ScriptDir "\" exeName
        return StealthAppCache[exeName]
    }
    
    LogFunc("Checking App Paths...")
    try {
        appPath := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" exeName)
        if FileExist(appPath) {
            StealthAppCache[exeName] := appPath
            return appPath
        }
    }
    try {
        appPath := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" exeName)
        if FileExist(appPath) {
            StealthAppCache[exeName] := appPath
            return appPath
        }
    }
    
    LogFunc("Checking PATH...")
    pathEnv := EnvGet("PATH")
    Loop Parse, pathEnv, ";" {
        testPath := Trim(A_LoopField, "`" ")
        if (testPath != "") {
            fullPath := testPath "\" exeName
            if FileExist(fullPath) {
                StealthAppCache[exeName] := fullPath
                return fullPath
            }
        }
    }
    
    LogFunc("Checking WindowsApps...")
    localAppData := EnvGet("LOCALAPPDATA")
    winAppsPath := localAppData "\Microsoft\WindowsApps\" exeName
    if FileExist(winAppsPath) {
        StealthAppCache[exeName] := winAppsPath
        return winAppsPath
    }
    
    lowerName := StrLower(exeName)
    
    LogFunc("Checking Visual Studio...")
    if (lowerName == "devenv.exe") {
        vsPath := FindVisualStudio()
        if (vsPath != "") {
            StealthAppCache[exeName] := vsPath
            return vsPath
        }
    }
    
    LogFunc("Checking common install locations...")
    
    ; Visual Studio Code
    if (lowerName == "code.exe") {
        p1 := localAppData "\Programs\Microsoft VS Code\Code.exe"
        if FileExist(p1) {
            StealthAppCache[exeName] := p1
            return p1
        }
        p2 := EnvGet("ProgramFiles") "\Microsoft VS Code\Code.exe"
        if FileExist(p2) {
            StealthAppCache[exeName] := p2
            return p2
        }
    }
    
    ; Teams
    if (lowerName == "teams.exe" || lowerName == "ms-teams.exe") {
        p1 := localAppData "\Microsoft\Teams\current\Teams.exe"
        if FileExist(p1) {
            StealthAppCache[exeName] := p1
            return p1
        }
        p2 := localAppData "\Microsoft\Teams\Teams.exe"
        if FileExist(p2) {
            StealthAppCache[exeName] := p2
            return p2
        }
    }
    
    return ""
}

FindVisualStudio() {
    ; Look on disk instead of running vswhere. That was a hidden child process
    ; started through WScript.Shell.Exec - a console flash, and the
    ; script-host-spawns-a-process shape endpoint security watches for - and it
    ; asked for productPath, which is already devenv.exe, then appended
    ; Common7\IDE\devenv.exe to it, so it never matched anything anyway.
    ; Standard layout: <ProgramFiles>\Microsoft Visual Studio\<version>\<edition>.
    for vsRoot in [EnvGet("ProgramFiles"), EnvGet("ProgramFiles(x86)")] {
        if (vsRoot = "")
            continue
        try {
            Loop Files, vsRoot "\Microsoft Visual Studio\*", "D" {
                Loop Files, A_LoopFileFullPath "\*", "D" {
                    fullPath := A_LoopFileFullPath "\Common7\IDE\devenv.exe"
                    if FileExist(fullPath)
                        return fullPath
                }
            }
        }
    }
    
    try {
        Loop Reg, "HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VS7", "V" {
            p := RegRead()
            if FileExist(p "Common7\IDE\devenv.exe")
                return p "Common7\IDE\devenv.exe"
        }
    }
    
    pf64 := EnvGet("ProgramFiles")
    pf32 := EnvGet("ProgramFiles(x86)")
    years := ["2026", "2022", "2019", "2017"]
    editions := ["Enterprise", "Professional", "Community", "Preview", "BuildTools"]
    for year in years {
        for ed in editions {
            p := pf64 "\Microsoft Visual Studio\" year "\" ed "\Common7\IDE\devenv.exe"
            if FileExist(p)
                return p
            p32 := pf32 "\Microsoft Visual Studio\" year "\" ed "\Common7\IDE\devenv.exe"
            if FileExist(p32)
                return p32
        }
    }
    return ""
}

OnExit(ExitStealthPanic)

ExitStealthPanic(ExitReason, ExitCode) {
    global StealthPanicActive, StealthHiddenWindows, StealthSuspendedFeatures
    global StealthOriginalMic, StealthMuteMic
    SetTimer(LaunchSafeApps, 0)
    for hwnd in StealthHiddenWindows {
        if DllCall("IsWindow", "ptr", hwnd)
            try WinShow(hwnd)
    }
    StealthHiddenWindows := []
    PanicSetSpeakerMute("Stealth", false)
    if (!StealthPanicActive)
        return
    ; Exiting used to hand back the windows only: the speakers and microphone
    ; stayed muted after the program was gone, with nothing left to unmute them.
    if (StealthMuteMic)
        StealthSetMicMute(StealthOriginalMic)
    ; Flags only, no Sync*: Bye() runs next and tears every feature down anyway.
    ; This runs before Bye() (registered at load), so its WriteSettings() sees
    ; the real values even without the bracket.
    StealthApplyFeatureValues(StealthSuspendedFeatures)
    StealthSuspendedFeatures.Clear()
    StealthPanicActive := false
}
