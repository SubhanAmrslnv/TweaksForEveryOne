#Requires AutoHotkey v2.0
Out(s) => FileAppend(s "`n", "*")
global g_parent := 0, g_list := []

Rect(h, &x, &y, &w, &hh) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", h, "ptr", rc)
    x := NumGet(rc,0,"int"), y := NumGet(rc,4,"int")
    w := NumGet(rc,8,"int") - x, hh := NumGet(rc,12,"int") - y
}
ClassOf(h) {
    b := Buffer(512, 0)
    DllCall("GetClassName", "ptr", h, "ptr", b, "int", 256)
    return StrGet(b)
}
Children(p) {
    global g_parent, g_list
    g_parent := p, g_list := []
    cb := CallbackCreate(E, "F", 2)
    DllCall("EnumChildWindows", "ptr", p, "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return g_list
}
E(h, l) {
    global g_parent, g_list
    if (DllCall("GetParent", "ptr", h, "ptr") = g_parent)
        g_list.Push(h)
    return 1
}
WorkBottom() {
    r := Buffer(16, 0)
    DllCall("SystemParametersInfo", "uint", 0x0030, "uint", 0, "ptr", r, "uint", 0)
    return NumGet(r, 12, "int")
}

; ── Secondary taskbar children: where is the content actually drawn? ────────
sec := DllCall("FindWindowEx", "ptr", 0, "ptr", 0, "str", "Shell_SecondaryTrayWnd", "ptr", 0, "ptr")
Rect(sec, &sx, &sy, &sw, &sh)
Out(Format("Shell_SecondaryTrayWnd  x={1} y={2} w={3} h={4}", sx, sy, sw, sh))
for c in Children(sec) {
    Rect(c, &cx, &cy, &cw, &ch)
    Out(Format("   child {1}  class={2}  x={3} y={4} w={5} h={6}   (offset in parent: y={7})",
        c, ClassOf(c), cx, cy, cw, ch, cy - sy))
}

; ── Can we drive the shell's own appbar to reserve less space? ──────────────
Out("`n=== ABM_SETPOS on the shell's taskbar appbar ===")
tb := DllCall("FindWindow", "str", "Shell_TrayWnd", "ptr", 0, "ptr")
Rect(tb, &tx, &ty, &tw, &th)
Out("  work bottom before: " WorkBottom())

NEW := 32
ab := Buffer(48, 0)
NumPut("uint", 48, ab, 0)          ; cbSize
NumPut("ptr", tb, ab, 8)           ; hWnd
NumPut("uint", 3, ab, 20)          ; uEdge = ABE_BOTTOM
NumPut("int", tx,          ab, 24) ; rc.left
NumPut("int", ty + th - NEW, ab, 28) ; rc.top
NumPut("int", tx + tw,     ab, 32) ; rc.right
NumPut("int", ty + th,     ab, 36) ; rc.bottom
r := DllCall("shell32\SHAppBarMessage", "uint", 3, "ptr", ab, "ptr")   ; ABM_SETPOS
Out("  ABM_SETPOS returned: " r)
Out(Format("  it wrote back rc.top={1} rc.bottom={2}", NumGet(ab,28,"int"), NumGet(ab,36,"int")))
for ms in [200, 800, 2000] {
    Sleep ms
    Out("  work bottom +" ms "ms: " WorkBottom())
}

Out("`n=== restore appbar ===")
NumPut("int", ty, ab, 28)
NumPut("int", ty + th, ab, 36)
DllCall("shell32\SHAppBarMessage", "uint", 3, "ptr", ab, "ptr")
Sleep 800
Out("  work bottom after restore: " WorkBottom())
ExitApp(0)
