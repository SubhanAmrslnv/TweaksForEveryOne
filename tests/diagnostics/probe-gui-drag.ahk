#Requires AutoHotkey v2.0
SendMode "Input"
SendLevel 1
SetWinDelay -1
CoordMode "Mouse", "Screen"
Out(s) => FileAppend(s "`n", "*")

global events := []
cb := CallbackCreate(Ev, "F", 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", cb, "uint", 0, "uint", 0, "uint", 0, "ptr")   ; OUTOFCONTEXT, see all

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

; A plain AHK GUI is a classic Win32 window with a real, non-XAML caption.
g := Gui("+Resize", "DragProbe")
g.AddText("w400 h200", "drag target")
g.Show("x400 y400 w420 h240")
hwnd := g.Hwnd
Sleep 800
Rect(hwnd, &x0, &y0)
Out("before drag : x=" x0 " y=" y0 "  hwnd=" hwnd)

MouseMove(x0 + 200, y0 + 12, 0)
Sleep 250
Click("Down")
Sleep 250
loop 20 {
    MouseMove(x0 + 200 - A_Index * 18, y0 + 12, 0)
    Sleep 20
}
Sleep 250
Click("Up")
Sleep 1200

Rect(hwnd, &x1, &y1)
Out("after drag  : x=" x1 " y=" y1 "   (moved " (x1 - x0) "px)")
Out("`nevents seen: " events.Length)
for e in events
    Out("  " e)
ExitApp(0)
