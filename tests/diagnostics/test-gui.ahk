#Requires AutoHotkey v2.0
SendMode "Input"
SendLevel 1
Out(s) => FileAppend(s "`n", "*")

Send("#^w")
if !WinWait("Window Tweaks ahk_class AutoHotkeyGUI", , 6) {
    Out("FAIL: tools window did not open")
    ExitApp(1)
}
hwnd := WinExist("Window Tweaks ahk_class AutoHotkeyGUI")
WinGetPos(&x, &y, &w, &h, hwnd)
Out(Format("PASS: tools window opened  {1}x{2}", w, h))

; Enumerate the controls so we can confirm every section rendered.
n := 0
kinds := Map()
for ctl in WinGetControls(hwnd) {
    n++
    k := RegExReplace(ctl, "\d+$")
    kinds[k] := kinds.Has(k) ? kinds[k] + 1 : 1
}
Out("controls: " n)
s := ""
for k, v in kinds
    s .= k "=" v "  "
Out("  " s)

; Status box should be populated by RefreshStatus().
try {
    txt := ControlGetText("Edit4", hwnd)
    Out("status box: " (txt = "" ? "(EMPTY - bug)" : "populated"))
    Out(txt)
}

WinClose(hwnd)
Out("closed")
ExitApp(0)
