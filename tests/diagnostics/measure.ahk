#Requires AutoHotkey v2.0
Out(s) => FileAppend(s "`n", "*")
global p := 0, g_kids := []

Rect(h, &x, &y, &w, &hh) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", h, "ptr", rc)
    x := NumGet(rc,0,"int"), y := NumGet(rc,4,"int")
    w := NumGet(rc,8,"int") - x, hh := NumGet(rc,12,"int") - y
}
Cls(h) {
    b := Buffer(512, 0)
    DllCall("GetClassName", "ptr", h, "ptr", b, "int", 256)
    return StrGet(b)
}
Kids(par) {
    global p, g_kids
    p := par, g_kids := []
    cb := CallbackCreate(E, "F", 2)
    DllCall("EnumChildWindows", "ptr", par, "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return g_kids
}
E(h, l) {
    global p, g_kids
    if (DllCall("GetParent", "ptr", h, "ptr") = p)
        g_kids.Push(h)
    return 1
}

bars := []
if (h := DllCall("FindWindow", "str", "Shell_TrayWnd", "ptr", 0, "ptr"))
    bars.Push(h)
prev := 0
loop 8 {
    h := DllCall("FindWindowEx", "ptr", 0, "ptr", prev, "str", "Shell_SecondaryTrayWnd", "ptr", 0, "ptr")
    if !h
        break
    bars.Push(h), prev := h
}

for b in bars {
    Rect(b, &bx, &by, &bw, &bh)
    Out(Format("{1}  y={2} h={3}", Cls(b), by, bh))
    maxh := 0
    for c in Kids(b) {
        Rect(c, &cx, &cy, &cw, &ch)
        Out(Format("    {1,-52} y={2} h={3}", Cls(c), cy - by, ch))
        if (ch > maxh)
            maxh := ch
    }
    Out("    -> tallest island: " maxh "px   removable padding: " (bh - maxh) "px`n")
}
ExitApp(0)
