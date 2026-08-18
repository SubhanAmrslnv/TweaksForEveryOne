; Audio OSD - the volume and microphone indicators, and the input that drives
; them.
;
; Function definitions and global initialisers only, no top-level statements.
;
; ONE ANIMATION KEY PER WINDOW PER EFFECT, COVERING BOTH DIRECTIONS. The fades
; were once OSDIn_<hwnd> and OSDOut_<hwnd> - different keys, so both could run on
; the same window in the same frame. They share OsdFade_<hwnd> now, so registering
; either cancels the other and a fade starts from RS_CurrentAlpha() rather than
; jumping.
;
; DO NOT PUT A COUNTDOWN IN THE SCHEDULER. Both auto-hides used to be registered
; animations that did nothing but compare a deadline, holding the 15 ms loop and
; timeBeginPeriod(1) open for 95 and 127 frames at a time. A negative SetTimer is
; the right tool.
;
; SET THE REGION AND THE ALPHA BEFORE Gui.Show(). Doing it after costs one frame
; of a hard-edged, fully opaque window.
;
; The speaker and microphone glyphs are non-ASCII, so this file is UTF-8 and must
; stay BOM-less.

; ====== Premium Volume OSD ======

ChangeVolumeOSD(dir) {
    try {
        stepPct := Tune("osdStep")
        SoundSetVolume((dir > 0 ? "+" : "-") stepPct)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

ToggleMuteOSD() {
    try {
        SoundSetMute(-1)
        ShowVolumeOSD(SoundGetVolume(), SoundGetMute())
    }
}

GetVolumeOSDPos(&x, &visibleY, &hiddenY) {
    ; Not monitor 1: that is an enumeration index, not the primary, and the OSD
    ; answers a scroll over a taskbar that may be on any screen.
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    
    dpiScale := 1.0
    try {
        rect := Buffer(16)
        NumPut("Int", WL, "Int", WT, "Int", WR, "Int", WB, rect)
        if hMonitor := DllCall("MonitorFromRect", "Ptr", rect, "UInt", 2, "Ptr") {
            DllCall("Shcore\GetDpiForMonitor", "Ptr", hMonitor, "Int", 0, "UInt*", &dpiX:=0, "UInt*", &dpiY:=0)
            if dpiY
                dpiScale := dpiY / 96.0
        }
    }
    
    x := WL + (WR - WL - 280) // 2
    margin := Round(75 * dpiScale)
    visibleY := WB - 64 - margin
    hiddenY := WB + 10
}

ShowVolumeOSD(vol, isMuted) {
    global OsdGui, OsdHiding

    if (OsdGui) {
        ; Reuse the window even if it is mid-fade-out. Previously HideVolumeOSD
        ; cleared OsdGui immediately, so a notch during the 100 ms fade built a
        ; SECOND OSD on top of the one still fading - two semi-transparent copies
        ; at the same coordinates, which reads as a flicker. The shared fade key
        ; cancels the outgoing fade, and OsdFadeIn brings this one back.
        UpdateOSD(vol, isMuted)
        ; UpdateOSD destroys the window and clears OsdGui if any of its controls
        ; have gone. Everything below dereferences it, and NotchAnim's argument
        ; is evaluated OUTSIDE any try - so on that path an ordinary wheel notch
        ; over the taskbar popped an error dialog. Re-check, and rebuild on the
        ; next notch instead.
        if (!OsdGui)
            return
        try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
        if OsdHiding {
            OsdHiding := false
            ; Explicit fallback rather than a bare `try`: a failed WinGetPos leaves
            ; cy UNSET and NotchAnim reads it. The parked position is the right
            ; default - that is where a hidden OSD sits.
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            cy := hiddenY
            try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
            NotchAnim(OsdGui.Hwnd, cy, visibleY, true)
        }
    } else {
        try {
            OsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale")
            OsdGui.BackColor := "181818"
            OsdGui.SetFont("s24 cWhite", "Segoe UI Emoji")
            OsdGui.AddText("vIcon x15 y12 w40 h40 BackgroundTrans Center", GetSpeakerIcon(vol, isMuted))
            
            OsdGui.SetFont("s10 cWhite bold", "Segoe UI")
            pctStr := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
            OsdGui.AddText("vPct x55 y21 w50 h24 BackgroundTrans Right", pctStr)
            
            OsdGui.AddText("x115 y29 w150 h6 Background333333")
            w := Max(1, Round(150 * (vol / 100)))
            OsdGui.AddText("vBar x115 y29 w" w " h6 BackgroundFFFFFF")

            RS_SetAlpha(OsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()
            
            OsdGui.Show("NoActivate w280 h64")
            try WinSetAlwaysOnTop(1, OsdGui.Hwnd)
            RS_SetRegion(OsdGui.Hwnd, "0-0 w280 h64 r20-20", RS_PRI_ANIM)
            
            GetVolumeOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            OsdGui.Move(x, y)
            
            NotchAnim(OsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; A plain one-shot, re-armed on every notch, so it hides 1.5 s after the LAST
    ; scroll. This was an entry in the animation scheduler, which meant 95 frames
    ; of the 15 ms loop - holding timeBeginPeriod(1) and running a full produce +
    ; flush pass - purely to compare two numbers. Nothing was animating.
    SetTimer(HideVolumeOSD, -Tune("osdHide"))
}

UpdateOSD(vol, isMuted) {
    global OsdGui
    OsdGui["Icon"].Text := GetSpeakerIcon(vol, isMuted)
    OsdGui["Pct"].Text := (isMuted || vol == 0) ? "Muted" : Round(vol) "%"
    w := Max(1, Round(150 * (vol / 100)))
    OsdGui["Bar"].Move(,, w)
    try {
        if (isMuted)
            OsdGui["Bar"].Opt("Background555555")
        else
            OsdGui["Bar"].Opt("BackgroundFFFFFF")
    }
    OsdGui["Bar"].Redraw()
}

GetSpeakerIcon(vol, isMuted) {
    if (isMuted || vol == 0)
        return "🔇"
    if (vol < 30)
        return "🔈"
    if (vol < 70)
        return "🔉"
    return "🔊"
}

HideVolumeOSD() {
    global OsdGui, OsdHiding
    if (!OsdGui)
        return
    OsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetVolumeOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, OsdGui.Hwnd)
    NotchAnim(OsdGui.Hwnd, cy, hiddenY, false, ClearVolumeOSD)
}

ClearVolumeOSD() {
    global OsdGui, OsdHiding
    OsdGui := ""
    OsdHiding := false
}

; ====== Global Mic Kill-Switch ======

ToggleDefaultMic() {
    try {
        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        pDevice := 0
        ComCall(4, IMMDeviceEnumerator, "UInt", 1, "UInt", 0, "Ptr*", &pDevice)
        if !pDevice
            return -1
            
        IID_IAudioEndpointVolume := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", IID_IAudioEndpointVolume)
        
        pAudioEndpointVolume := 0
        ComCall(3, pDevice, "Ptr", IID_IAudioEndpointVolume, "UInt", 23, "Ptr", 0, "Ptr*", &pAudioEndpointVolume)
        ObjRelease(pDevice)
        if !pAudioEndpointVolume
            return -1
            
        muted := 0
        ComCall(15, pAudioEndpointVolume, "Int*", &muted)
        
        newMuted := !muted
        ComCall(14, pAudioEndpointVolume, "Int", newMuted, "Ptr", 0)
        
        ObjRelease(pAudioEndpointVolume)
        return newMuted
    }
    return -1
}

ShowMicOSD(isMuted) {
    global MicOsdGui, MicOsdHiding

    if (MicOsdGui) {
        UpdateMicOSD(isMuted)
        if MicOsdHiding {           ; revive it rather than stacking a second one
            MicOsdHiding := false
            try FadeGui(MicOsdGui, TuneAlpha("osdAlpha"))
        }
    } else {
        try {
            MicOsdGui := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound -DPIScale")
            
            if (isMuted) {
                MicOsdGui.BackColor := "8B0000" 
                txt := "🎙️ Mic Muted"
            } else {
                MicOsdGui.BackColor := "006400" 
                txt := "🎙️ Mic Active"
            }
            
            MicOsdGui.SetFont("s20 cWhite bold", "Segoe UI")
            MicOsdGui.AddText("vText x0 y15 w240 h40 BackgroundTrans Center", txt)

            RS_SetAlpha(MicOsdGui.Hwnd, 0, RS_PRI_ANIM)
            RS_Commit()
            
            MicOsdGui.Show("NoActivate w240 h70")
            RS_SetRegion(MicOsdGui.Hwnd, "0-0 w240 h70 r20-20", RS_PRI_ANIM)
            
            GetMicOSDPos(&x, &visibleY, &hiddenY)
            y := hiddenY
            MicOsdGui.Move(x, y)
            
            NotchAnim(MicOsdGui.Hwnd, y, visibleY, true)
        }
    }

    ; Plain one-shot, same reasoning as the volume OSD: this was 127 frames of the
    ; animation loop spent comparing a deadline.
    SetTimer(HideMicOSD, -Tune("osdHide"))
}

UpdateMicOSD(isMuted) {
    global MicOsdGui
    if (isMuted) {
        MicOsdGui.BackColor := "8B0000"
        MicOsdGui["Text"].Text := "🎙️ Mic Muted"
    } else {
        MicOsdGui.BackColor := "006400"
        MicOsdGui["Text"].Text := "🎙️ Mic Active"
    }
}

HideMicOSD() {
    global MicOsdGui, MicOsdHiding
    if (!MicOsdGui)
        return
    MicOsdHiding := true
    ; Explicit fallback: a bare `try` leaves cy unset and NotchAnim reads it.
    GetMicOSDPos(&x, &visibleY, &hiddenY)
    cy := visibleY
    try WinGetPos(&cx, &cy, &cw, &ch, MicOsdGui.Hwnd)
    NotchAnim(MicOsdGui.Hwnd, cy, hiddenY, false, ClearMicOSD)
}

; Mirrors GetVolumeOSDPos so the two OSDs pick their monitor the same way. The
; mic OSD keeps its top-of-screen notch placement; only the monitor choice moved.
GetMicOSDPos(&x, &visibleY, &hiddenY) {
    ; WorkAreaOf already falls back to the primary internally, so a false return
    ; means there is no readable display at all. Do NOT retry MonitorGetWorkArea
    ; here - it would throw, and HideMicOSD/HideVolumeOSD run from timers where
    ; an uncaught throw kills the timer.
    if !WorkAreaOf(CursorMonitorIndex(), &WL, &WT, &WR, &WB)
        WL := 0, WT := 0, WR := A_ScreenWidth, WB := A_ScreenHeight
    x := WL + (WR - WL - 240) // 2
    visibleY := WT + 10
    hiddenY := WT - 70
}

ClearMicOSD() {
    global MicOsdGui, MicOsdHiding
    MicOsdGui := ""
    MicOsdHiding := false
}
