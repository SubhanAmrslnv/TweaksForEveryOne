#Requires AutoHotkey v2.0
Persistent

; StealthPanicUI.ahk - Standalone Configuration UI for Stealth Panic Mode

#Include "StealthPanicConfig.ahk"
; Whoever launches this may pass the ini path it is actually using as argument
; 1, so the GUI and the engine cannot drift onto different files when both the
; Window Tweaks install and the standalone install exist. With no argument this
; falls back to A_ScriptDir, exactly as before.
StealthIni := StealthPanicConfig_ResolveIniPath()

; Read current values
StealthPanicEnabled := IniRead(StealthIni, "stealth", "enabled", "1") == "1"
StealthPanicTimeout := IniRead(StealthIni, "stealth", "timeout", "600")
StealthLaunchSafeApps := IniRead(StealthIni, "stealth", "launchapps", "1") == "1"
StealthSafeAppList := StealthPanicConfig_ReadAppList(StealthIni)
StealthLaunchDelay := IniRead(StealthIni, "stealth", "delay", "500")
StealthRestoreWorkspace := IniRead(StealthIni, "stealth", "restore", "1") == "1"
StealthMuteAudio := IniRead(StealthIni, "stealth", "muteaudio", "1") == "1"
StealthMuteMic := IniRead(StealthIni, "stealth", "mutemic", "1") == "1"
StealthSuspendAnimations := IniRead(StealthIni, "stealth", "suspendanim", "1") == "1"
StealthSuspendOverlays := IniRead(StealthIni, "stealth", "suspendover", "1") == "1"
StealthSuspendBackground := IniRead(StealthIni, "stealth", "suspendbg", "1") == "1"

SG := Gui("-MinimizeBox", "Stealth Panic Mode Settings")
SG.OnEvent("Close", (*) => ExitApp())

SG.SetFont("s11 bold", "Segoe UI")
SG.Add("Text", "xm y15 w350", "Activation")
SG.SetFont("s9 norm", "Segoe UI")
chkEnable := SG.Add("Checkbox", "xm y+10 Checked" StealthPanicEnabled, "Enable Triple ESC Stealth Panic Mode")
SG.Add("Text", "xm y+10", "Triple ESC Time Window (ms):")
txtTimeout := SG.Add("Edit", "x+10 yp-3 w60 Number", StealthPanicTimeout)

SG.SetFont("s11 bold", "Segoe UI")
SG.Add("Text", "xm y+20 w350", "Audio & Privacy")
SG.SetFont("s9 norm", "Segoe UI")
chkMuteAudio := SG.Add("Checkbox", "xm y+10 Checked" StealthMuteAudio, "Mute system audio and stop playback")
chkMuteMic := SG.Add("Checkbox", "xm y+10 Checked" StealthMuteMic, "Mute microphone")

SG.SetFont("s11 bold", "Segoe UI")
SG.Add("Text", "xm y+20 w350", "Features & Recovery")
SG.SetFont("s9 norm", "Segoe UI")
chkSuspendAnim := SG.Add("Checkbox", "xm y+10 Checked" StealthSuspendAnimations, "Suspend animations")
chkSuspendOver := SG.Add("Checkbox", "xm y+10 Checked" StealthSuspendOverlays, "Suspend overlays")
chkSuspendBg := SG.Add("Checkbox", "xm y+10 Checked" StealthSuspendBackground, "Suspend background features")
chkRestore := SG.Add("Checkbox", "xm y+10 Checked" StealthRestoreWorkspace, "Restore all windows on second Triple ESC")

SG.SetFont("s11 bold", "Segoe UI")
SG.Add("Text", "xm y+20 w350", "Safe Workspace")
SG.SetFont("s9 norm", "Segoe UI")
chkLaunchApps := SG.Add("Checkbox", "xm y+10 Checked" StealthLaunchSafeApps, "Launch safe applications")
SG.Add("Text", "xm y+10", "Delay before launch (ms):")
txtDelay := SG.Add("Edit", "x+10 yp-3 w60 Number", StealthLaunchDelay)
SG.Add("Text", "xm y+10", "Applications to launch (one per line):")
; r4 already implies ES_MULTILINE and ES_WANTRETURN - measured, style
; 0x50211044 - so Enter inserts a newline here instead of firing the Default
; button, and .Value hands the text back LF-separated whatever was put in.
; -Wrap plus HScroll keeps a long quoted path on one visible line: a
; soft-wrapped box reads as though the control mangled the entry.
txtApps := SG.Add("Edit", "xm y+5 w350 r6 -Wrap +HScroll", StealthSafeAppList)

btnSave := SG.Add("Button", "w100 x130 y+20 Default", "Save & Apply")
btnSave.OnEvent("Click", SaveSettings)

SG.Show()

SaveSettings(*) {
    ; One try around the lot. An IniWrite that throws used to abort the handler
    ; part-way through, leaving half the settings written, no message and no
    ; ExitApp - the window just sat there looking as though nothing happened.
    iniOk := true
    try {
        IniWrite(chkEnable.Value ? "1" : "0", StealthIni, "stealth", "enabled")
        IniWrite(txtTimeout.Value, StealthIni, "stealth", "timeout")
        IniWrite(chkLaunchApps.Value ? "1" : "0", StealthIni, "stealth", "launchapps")
        IniWrite(txtDelay.Value, StealthIni, "stealth", "delay")
        IniWrite(chkRestore.Value ? "1" : "0", StealthIni, "stealth", "restore")
        IniWrite(chkMuteAudio.Value ? "1" : "0", StealthIni, "stealth", "muteaudio")
        IniWrite(chkMuteMic.Value ? "1" : "0", StealthIni, "stealth", "mutemic")
        IniWrite(chkSuspendAnim.Value ? "1" : "0", StealthIni, "stealth", "suspendanim")
        IniWrite(chkSuspendOver.Value ? "1" : "0", StealthIni, "stealth", "suspendover")
        IniWrite(chkSuspendBg.Value ? "1" : "0", StealthIni, "stealth", "suspendbg")
    } catch {
        iniOk := false
    }

    ; Written after the ini keys, and its result is checked: this one reports
    ; failure rather than throwing, and a save that silently did nothing is the
    ; bug this whole change exists to remove.
    appsOk := StealthPanicConfig_WriteAppList(StealthIni, txtApps.Value)

    ; This used to post to "Stealth Panic Mode.ahk ahk_class AutoHotkey". That
    ; title only exists in the standalone build - when the engine runs inside
    ; Window Tweaks the window is titled WindowTweaks.ahk, so the running engine
    ; never saw a saved change at all. Reloading Window Tweaks wholesale is not
    ; an option: it runs Bye(), which un-hides every window, tears down the tray
    ; icons and cancels every animation, just to pick up a list. So only the
    ; standalone runner is reloaded here, and Window Tweaks re-reads the
    ; settings itself on the next activation (StealthPanicRefreshSettings).
    for hw in WinGetList("ahk_class AutoHotkey") {
        title := ""
        try title := WinGetTitle(hw)
        if InStr(title, "Stealth Panic Mode.ahk")
            try PostMessage(0x0111, 65303, 0, , "ahk_id " hw)   ; ID_FILE_RELOADSCRIPT
    }

    if (appsOk && iniOk) {
        MsgBox("Settings saved successfully!", "Stealth Panic Mode", "Iconi 0x40000")
    } else if (!appsOk) {
        MsgBox("The application list could not be written to:`n`n"
             . StealthPanicConfig_AppsFilePath(StealthIni)
             . "`n`nYour previous list is unchanged. Check that the folder is writable."
             , "Stealth Panic Mode", "Iconx")
    } else {
        MsgBox("The application list was saved, but some settings could not be"
             . " written to:`n`n" StealthIni
             . "`n`nCheck that the folder is writable."
             , "Stealth Panic Mode", "Iconx")
    }
    ExitApp()
}
