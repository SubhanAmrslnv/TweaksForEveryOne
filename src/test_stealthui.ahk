#Requires AutoHotkey v2.0
#SingleInstance Off
#Include StealthPanicConfig.ahk

; test_stealthui.ahk - the reported repro, automated.
;
; Drives the FULL loop the user drives: build the same multi-line Edit control
; StealthPanicUI.ahk builds, seed it the way the UI seeds it, read .Value back
; the way SaveSettings does, store it, then throw the control away and build a
; fresh one from disk. That is exactly "type the apps, Save, close, reopen".
;
;   AutoHotkey64.exe /ErrorStdOut src\test_stealthui.ahk
;
; Exit code = number of failed assertions. Report goes to
; %TEMP%\stealthui-report.txt.

global TU_Run := 0
global TU_Fail := 0
global TU_Dir := A_Temp "\stealthui_" A_TickCount
global TU_Ini := TU_Dir "\StealthPanic.ini"
global TU_Report := A_Temp "\stealthui-report.txt"

try FileDelete(TU_Report)

Say(text) {
    global TU_Report
    FileAppend(text, TU_Report, "UTF-8-RAW")
}

Vis(text) {
    marked := StrReplace(text, "`r", "<CR>")
    marked := StrReplace(marked, "`n", "<LF>")
    shown := ""
    Loop Parse, marked {
        code := Ord(A_LoopField)
        shown .= (code < 32 || code > 126) ? "<U+" Format("{:04X}", code) ">" : A_LoopField
    }
    return "[" shown "]"
}

Check(name, expected, actual) {
    global TU_Run, TU_Fail
    TU_Run++
    if (expected == actual) {
        Say("PASS  " name "`n")
        return true
    }
    TU_Fail++
    Say("FAIL  " name "`n")
    Say("      expected " Vis(expected) "`n")
    Say("      actual   " Vis(actual) "`n")
    return false
}

CheckTrue(name, condition) {
    global TU_Run, TU_Fail
    TU_Run++
    Say((condition ? "PASS  " : "FAIL  ") name "`n")
    if !condition
        TU_Fail++
    return condition
}

; One "open the settings window" - build the control exactly as
; StealthPanicUI.ahk:53 does, seeded from disk exactly as it is there.
OpenWindow() {
    global TU_Ini
    seed := StealthPanicConfig_ReadAppList(TU_Ini)
    g := Gui("-MinimizeBox", "Stealth Panic Mode Settings")
    ctl := g.Add("Edit", "xm y+5 w350 r6 -Wrap +HScroll", seed)
    ; A Default button is present in the real UI, and Enter must not fire it
    ; from inside the edit. r6 implies ES_WANTRETURN, which is what prevents it.
    btn := g.Add("Button", "w100 x130 y+20 Default", "Save & Apply")
    return { gui: g, ctl: ctl, seed: seed }
}

; ...and one "click Save & Apply, then close it".
SaveAndClose(win) {
    global TU_Ini
    ok := StealthPanicConfig_WriteAppList(TU_Ini, win.ctl.Value)
    win.gui.Destroy()
    return ok
}

; The whole reported cycle, `cycles` times over.
Repro(name, typed, cycles := 4) {
    global TU_Ini, TU_Run, TU_Fail
    try FileDelete(StealthPanicConfig_AppsFilePath(TU_Ini))
    try FileDelete(TU_Ini)

    ; Cycle 1: the user opens the window and types the list in.
    win := OpenWindow()
    win.ctl.Value := typed
    lineCount := SendMessage(0x00BA, 0, 0, win.ctl)      ; EM_GETLINECOUNT
    wanted := StrSplit(StealthPanicConfig_NormalizeList(typed), "`n").Length
    CheckTrue(name " - control holds " wanted " lines after typing"
            , lineCount == wanted)
    if !SaveAndClose(win) {
        TU_Run++, TU_Fail++
        Say("FAIL  " name " - save returned false`n")
        return
    }

    ; Cycles 2..n: reopen, change nothing, save, close.
    shown := ""
    Loop cycles {
        win := OpenWindow()
        shown := win.ctl.Value
        SaveAndClose(win)
    }

    Check(name " survives " (cycles + 1) " open/save/close cycles"
        , StealthPanicConfig_NormalizeList(typed), shown)
}

; ------------------------------------------------------------------- setup ---

DirCreate(TU_Dir)
Say("=== Stealth Panic settings window - reported repro, automated ===`n")
Say("AHK " A_AhkVersion "`n")
Say("scratch: " TU_Dir "`n`n")

REQUIRED := "devenv.exe`nCode.exe`nms-teams.exe`nexplorer.exe"

TWELVE := ""
Loop 12
    TWELVE .= (A_Index > 1 ? "`n" : "") "app" A_Index ".exe"

HARD := '"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe" /rootsuffix Exp'
     . "`n%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe"
     . "`nms-teams.exe"
     . "`nexplorer.exe C:\Temp"
     . "`nCode.exe --user-data-dir=C:\temp\profile=2"

; ------------------------------------------------------------------- tests ---

Say("--- the four apps from the bug report ---`n")
Repro("four required apps", REQUIRED)

Say("`n--- scale ---`n")
Repro("twelve entries", TWELVE)

Say("`n--- quoted paths, arguments, environment variables ---`n")
Repro("quoted paths + args + env vars", HARD)

; The upgrade path that actually caused the report: an ini left behind by the
; build that wrote the whole blob into one key.
Say("`n--- upgrade from an ini carrying the legacy applist key ---`n")
try FileDelete(StealthPanicConfig_AppsFilePath(TU_Ini))
try FileDelete(TU_Ini)
IniWrite(StrReplace(REQUIRED, "`n", "`r`n"), TU_Ini, "stealth", "applist")

win := OpenWindow()
Say("      what the window shows on first open: " Vis(win.ctl.Value) "`n")
CheckTrue("legacy ini still yields one entry on that first open"
        , win.ctl.Value == "devenv.exe")

; The user retypes all four and saves - and from here it must never regress.
win.ctl.Value := REQUIRED
SaveAndClose(win)

shown := ""
Loop 4 {
    win := OpenWindow()
    shown := win.ctl.Value
    SaveAndClose(win)
}
Check("after one save it holds through four more cycles", REQUIRED, shown)
CheckTrue("the legacy key is gone for good"
        , IniRead(TU_Ini, "stealth", "applist", "<<GONE>>") == "<<GONE>>")

; ---------------------------------------------------------------- teardown ---

try FileDelete(StealthPanicConfig_AppsFilePath(TU_Ini))
try FileDelete(TU_Ini)
try DirDelete(TU_Dir, true)

Say("`n" TU_Run " assertions, " TU_Fail " failed`n")
Say((TU_Fail == 0) ? "ALL PASS`n" : "FAILURES`n")
ExitApp(TU_Fail)
