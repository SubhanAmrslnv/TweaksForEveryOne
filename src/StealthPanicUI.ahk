#Requires AutoHotkey v2.0
Persistent

; StealthPanicUI.ahk - Standalone Configuration UI for Stealth Panic Mode

StealthIni := A_ScriptDir "\StealthPanic.ini"
#Include "StealthPanicConfig.ahk"

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
txtApps := SG.Add("Edit", "xm y+5 w350 r4", StealthSafeAppList)

btnSave := SG.Add("Button", "w100 x130 y+20 Default", "Save & Apply")
btnSave.OnEvent("Click", SaveSettings)

SG.Show()

SaveSettings(*) {
    IniWrite(chkEnable.Value ? "1" : "0", StealthIni, "stealth", "enabled")
    IniWrite(txtTimeout.Value, StealthIni, "stealth", "timeout")
    IniWrite(chkLaunchApps.Value ? "1" : "0", StealthIni, "stealth", "launchapps")
    StealthPanicConfig_WriteAppList(StealthIni, txtApps.Value)
    IniWrite(txtDelay.Value, StealthIni, "stealth", "delay")
    IniWrite(chkRestore.Value ? "1" : "0", StealthIni, "stealth", "restore")
    IniWrite(chkMuteAudio.Value ? "1" : "0", StealthIni, "stealth", "muteaudio")
    IniWrite(chkMuteMic.Value ? "1" : "0", StealthIni, "stealth", "mutemic")
    IniWrite(chkSuspendAnim.Value ? "1" : "0", StealthIni, "stealth", "suspendanim")
    IniWrite(chkSuspendOver.Value ? "1" : "0", StealthIni, "stealth", "suspendover")
    IniWrite(chkSuspendBg.Value ? "1" : "0", StealthIni, "stealth", "suspendbg")
    
    ; If the standalone runner is active, reload it so settings take effect
    if WinExist("Stealth Panic Mode.ahk ahk_class AutoHotkey") {
        PostMessage(0x0111, 65303, 0, , "Stealth Panic Mode.ahk ahk_class AutoHotkey") ; ID_FILE_RELOADSCRIPT
    }
    
    MsgBox("Settings saved successfully!", "Stealth Panic Mode", "Iconi 0x40000")
    ExitApp()
}
