#Requires AutoHotkey v2.0
; Functional check: does Win+Ctrl+T actually set WS_EX_TOPMOST on a real window?
SendMode "Input"
SetKeyDelay 40, 40

Out(s) => FileAppend(s "`n", "*")

WS_EX_TOPMOST := 0x00000008

Run "notepad.exe"
if !WinWait("ahk_exe notepad.exe", , 10) {
    Out("FAIL: notepad never appeared")
    ExitApp(1)
}
hwnd := WinExist("ahk_exe notepad.exe")
WinActivate(hwnd)
WinWaitActive(hwnd, , 5)
Sleep 800

before := WinGetExStyle(hwnd) & WS_EX_TOPMOST
Out("topmost before      : " (before ? "YES" : "no"))

Send("#^t")
Sleep 1500
afterOn := WinGetExStyle(hwnd) & WS_EX_TOPMOST
Out("topmost after 1st   : " (afterOn ? "YES" : "no"))

Send("#^t")
Sleep 1500
afterOff := WinGetExStyle(hwnd) & WS_EX_TOPMOST
Out("topmost after 2nd   : " (afterOff ? "YES" : "no"))

WinClose(hwnd)

ok := (!before) && afterOn && (!afterOff)
Out(ok ? "=== PASS: Win+Ctrl+T toggles topmost ===" : "=== FAIL: toggle did not behave ===")
ExitApp(ok ? 0 : 1)
