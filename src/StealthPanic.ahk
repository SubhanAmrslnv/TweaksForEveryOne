; StealthPanic.ahk - Triple ESC Stealth Panic Mode Engine

global StealthPanicIniPath := A_ScriptDir "\StealthPanic.ini"

global StealthPanicEnabled := IniRead(StealthPanicIniPath, "stealth", "enabled", "1") == "1"
global StealthPanicTimeout := Number(IniRead(StealthPanicIniPath, "stealth", "timeout", "600"))
global StealthLaunchSafeApps := IniRead(StealthPanicIniPath, "stealth", "launchapps", "1") == "1"
global StealthSafeAppList := IniRead(StealthPanicIniPath, "stealth", "applist", "notepad.exe`ncalc.exe")
global StealthLaunchDelay := Number(IniRead(StealthPanicIniPath, "stealth", "delay", "500"))
global StealthRestoreWorkspace := IniRead(StealthPanicIniPath, "stealth", "restore", "1") == "1"
global StealthMuteAudio := IniRead(StealthPanicIniPath, "stealth", "muteaudio", "1") == "1"
global StealthMuteMic := IniRead(StealthPanicIniPath, "stealth", "mutemic", "1") == "1"
global StealthSuspendAnimations := IniRead(StealthPanicIniPath, "stealth", "suspendanim", "1") == "1"
global StealthSuspendOverlays := IniRead(StealthPanicIniPath, "stealth", "suspendover", "1") == "1"
global StealthSuspendBackground := IniRead(StealthPanicIniPath, "stealth", "suspendbg", "1") == "1"

global StealthPanicActive := false
global StealthHiddenWindows := []
global StealthOriginalMute := false
global StealthOriginalMic := false
global StealthSuspendedFeatures := Map()

global StealthEscCount := 0
global StealthEscTimer := 0

#HotIf StealthPanicEnabled
~Esc:: {
    global StealthEscCount, StealthEscTimer, StealthPanicTimeout
    StealthEscCount++
    if (StealthEscCount == 1) {
        StealthEscTimer := A_TickCount
        SetTimer(ResetStealthEsc, -StealthPanicTimeout)
    } else if (StealthEscCount == 3) {
        elapsed := A_TickCount - StealthEscTimer
        if (elapsed <= StealthPanicTimeout) {
            SetTimer(ResetStealthEsc, 0)
            StealthEscCount := 0
            ToggleStealthPanic()
        } else {
            ; Reset if time window expired
            StealthEscCount := 1
            StealthEscTimer := A_TickCount
            SetTimer(ResetStealthEsc, -StealthPanicTimeout)
        }
    }
}
#HotIf

ResetStealthEsc() {
    global StealthEscCount := 0
}

ToggleStealthPanic() {
    global StealthPanicActive
    if (StealthPanicActive)
        RestoreStealthPanic()
    else
        EnterStealthPanic()
}

EnterStealthPanic() {
    global StealthPanicActive, StealthHiddenWindows, StealthOriginalMute, StealthOriginalMic
    global StealthMuteAudio, StealthMuteMic, StealthLaunchSafeApps, StealthLaunchDelay

    if (StealthPanicActive)
        return
    
    StealthPanicActive := true
    StealthHiddenWindows := []
    
    ; 1. Hide windows
    ownPid := DllCall("GetCurrentProcessId", "uint")
    hwnds := WinGetList()
    for hwnd in hwnds {
        cls := ""
        try cls := WinGetClass(hwnd)
        if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
            continue
        pid := 0
        try pid := WinGetPID(hwnd)
        if (pid == ownPid)
            continue
        
        StealthHiddenWindows.Push(hwnd)
        try WinHide(hwnd)
    }
    
    ; 2. Mute audio
    if (StealthMuteAudio) {
        try StealthOriginalMute := SoundGetMute()
        catch
            StealthOriginalMute := false
        try SoundSetMute(true)
        
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
        ; Use Mic Kill Switch if available
        if IsSet(ToggleDefaultMic) {
            try StealthOriginalMic := (SoundGetMute(,"Microphone") == 1)
            catch {
                StealthOriginalMic := false
            }
            try SoundSetMute(1, , "Microphone")
        } else {
            try StealthOriginalMic := (SoundGetMute(,"Microphone") == 1)
            catch {
                StealthOriginalMic := false
            }
            try SoundSetMute(1, , "Microphone")
        }
    }
    
    ; 4. Suspend features
    SuspendStealthFeatures()
    
    ; 5. Launch Safe Workspace
    if (StealthLaunchSafeApps) {
        SetTimer(LaunchSafeApps, -StealthLaunchDelay)
    }
}

RestoreStealthPanic() {
    global StealthPanicActive, StealthHiddenWindows, StealthOriginalMute, StealthOriginalMic
    global StealthRestoreWorkspace, StealthMuteAudio, StealthMuteMic

    if (!StealthPanicActive)
        return
        
    StealthPanicActive := false
    
    if (StealthRestoreWorkspace) {
        for hwnd in StealthHiddenWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
    }
    StealthHiddenWindows := []
    
    if (StealthMuteAudio) {
        try SoundSetMute(StealthOriginalMute)
    }
    
    if (StealthMuteMic) {
        try SoundSetMute(StealthOriginalMic, , "Microphone")
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
    global ActiveBorderEnabled, ProximityGhostEnabled, LivePipEnabled, PrivacyBlurEnabled
    global SpotlightEnabled, BreathingEnabled, PulseEnabled, CursorYawnEnabled
    
    if (StealthSuspendAnimations) {
        if IsSet(OpenAnim) {
            StealthSuspendedFeatures["OpenAnim"] := OpenAnim
            OpenAnim := "None"
        }
        if IsSet(ContextMenuAnimEnabled) {
            StealthSuspendedFeatures["ContextMenuAnimEnabled"] := ContextMenuAnimEnabled
            ContextMenuAnimEnabled := false
        }
        if IsSet(RippleClickEnabled) {
            StealthSuspendedFeatures["RippleClickEnabled"] := RippleClickEnabled
            RippleClickEnabled := false
        }
    }
    if (StealthSuspendOverlays) {
        if IsSet(ActiveBorderEnabled) {
            StealthSuspendedFeatures["ActiveBorderEnabled"] := ActiveBorderEnabled
            ActiveBorderEnabled := false
        }
        if IsSet(ProximityGhostEnabled) {
            StealthSuspendedFeatures["ProximityGhostEnabled"] := ProximityGhostEnabled
            ProximityGhostEnabled := false
        }
        if IsSet(LivePipEnabled) {
            StealthSuspendedFeatures["LivePipEnabled"] := LivePipEnabled
            LivePipEnabled := false
        }
        if IsSet(PrivacyBlurEnabled) {
            StealthSuspendedFeatures["PrivacyBlurEnabled"] := PrivacyBlurEnabled
            PrivacyBlurEnabled := false
        }
    }
    if (StealthSuspendBackground) {
        if IsSet(SpotlightEnabled) {
            StealthSuspendedFeatures["SpotlightEnabled"] := SpotlightEnabled
            SpotlightEnabled := false
        }
        if IsSet(BreathingEnabled) {
            StealthSuspendedFeatures["BreathingEnabled"] := BreathingEnabled
            BreathingEnabled := false
        }
        if IsSet(PulseEnabled) {
            StealthSuspendedFeatures["PulseEnabled"] := PulseEnabled
            PulseEnabled := false
        }
        if IsSet(CursorYawnEnabled) {
            StealthSuspendedFeatures["CursorYawnEnabled"] := CursorYawnEnabled
            CursorYawnEnabled := false
        }
    }
}

RestoreStealthFeatures() {
    global StealthSuspendedFeatures
    
    global OpenAnim, ContextMenuAnimEnabled, RippleClickEnabled
    global ActiveBorderEnabled, ProximityGhostEnabled, LivePipEnabled, PrivacyBlurEnabled
    global SpotlightEnabled, BreathingEnabled, PulseEnabled, CursorYawnEnabled
    
    for key, val in StealthSuspendedFeatures {
        if (key == "OpenAnim" && IsSet(OpenAnim)) {
            OpenAnim := val
        }
        if (key == "ContextMenuAnimEnabled" && IsSet(ContextMenuAnimEnabled)) {
            ContextMenuAnimEnabled := val
        }
        if (key == "RippleClickEnabled" && IsSet(RippleClickEnabled)) {
            RippleClickEnabled := val
        }
        if (key == "ActiveBorderEnabled" && IsSet(ActiveBorderEnabled)) {
            ActiveBorderEnabled := val
        }
        if (key == "ProximityGhostEnabled" && IsSet(ProximityGhostEnabled)) {
            ProximityGhostEnabled := val
        }
        if (key == "LivePipEnabled" && IsSet(LivePipEnabled)) {
            LivePipEnabled := val
        }
        if (key == "PrivacyBlurEnabled" && IsSet(PrivacyBlurEnabled)) {
            PrivacyBlurEnabled := val
        }
        if (key == "SpotlightEnabled" && IsSet(SpotlightEnabled)) {
            SpotlightEnabled := val
        }
        if (key == "BreathingEnabled" && IsSet(BreathingEnabled)) {
            BreathingEnabled := val
        }
        if (key == "PulseEnabled" && IsSet(PulseEnabled)) {
            PulseEnabled := val
        }
        if (key == "CursorYawnEnabled" && IsSet(CursorYawnEnabled)) {
            CursorYawnEnabled := val
        }
    }
    StealthSuspendedFeatures.Clear()
}

LaunchSafeApps() {
    global StealthSafeAppList
    Loop Parse, StealthSafeAppList, "`n", "`r"
    {
        app := Trim(A_LoopField)
        if (app != "") {
            ; Try to find existing window of the app to activate
            if (WinExist("ahk_exe " app)) {
                WinActivate("ahk_exe " app)
            } else {
                try Run(app)
            }
        }
    }
}

OnExit(ExitStealthPanic)

ExitStealthPanic(ExitReason, ExitCode) {
    global StealthPanicActive, StealthHiddenWindows
    if (StealthPanicActive) {
        for hwnd in StealthHiddenWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
    }
}
