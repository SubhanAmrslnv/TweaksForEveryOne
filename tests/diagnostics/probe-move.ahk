#Requires AutoHotkey v2.0
SendMode "Input"
SetWinDelay -1
CoordMode "Mouse", "Screen"
Out(s) => FileAppend(s "`n", "*")

global events := []
cb := CallbackCreate(Ev, "F", 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", cb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

Ev(hook, event, hwnd, idObj, idChild, thread, time) {
    global events
    if (idObj = 0)
        events.Push((event = 0x000A ? "START" : "END") " hwnd=" hwnd)
}

Rect(h, &x, &y) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", h, "ptr", rc)
    x := NumGet(rc,0,"int"), y := NumGet(rc,4,"int")
}

Run "notepad.exe"
WinWait("ahk_exe notepad.exe", , 10)
hwnd := WinExist("ahk_exe notepad.exe")
Sleep 1500                     ; let position-memory restore settle first
if (WinGetMinMax(hwnd) != 0)
    WinRestore(hwnd), Sleep 400
WinMove(400, 400, 600, 400, hwnd)
WinActivate(hwnd)
WinWaitActive(hwnd, , 5)
Sleep 600
Rect(hwnd, &x0, &y0)
Out("before SC_MOVE : x=" x0 " y=" y0)

PostMessage(0x0112, 0xF012, 0, , "ahk_id " hwnd)
Sleep 700
MouseGetPos(&mx, &my)
Out("cursor after SC_MOVE: " mx "," my)
Rect(hwnd, &x1, &y1)
Out("window after SC_MOVE : x=" x1 " y=" y1)

; try mouse-driven move
loop 10 {
    MouseMove(mx - A_Index * 30, my, 0)
    Sleep 30
}
Sleep 300
Rect(hwnd, &x2, &y2)
Out("after mouse move     : x=" x2 " y=" y2 "   (moved " (x2 - x1) "px)")

; try arrow-key move
Send("{Left 5}")
Sleep 300
Rect(hwnd, &x3, &y3)
Out("after 5x Left arrow  : x=" x3 " y=" y3 "   (moved " (x3 - x2) "px)")

Send("{Enter}")
Sleep 800
Rect(hwnd, &x4, &y4)
Out("after Enter          : x=" x4 " y=" y4)

Out("`nevents seen: " events.Length)
for e in events
    Out("  " e)
WinClose(hwnd)
ExitApp(0)
