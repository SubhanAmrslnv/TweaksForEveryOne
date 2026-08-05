#Requires AutoHotkey v2.0
Out(s) => FileAppend(s "`n", "*")

tb := DllCall("FindWindow", "str", "Shell_TrayWnd", "ptr", 0, "ptr")
rc := Buffer(16, 0)
DllCall("GetWindowRect", "ptr", tb, "ptr", rc)
x := NumGet(rc,0,"int"), y := NumGet(rc,4,"int")
w := NumGet(rc,8,"int") - x, h := NumGet(rc,12,"int") - y
Out(Format("Shell_TrayWnd  x={1} y={2} w={3} h={4}", x, y, w, h))

; ── A: can we clip it with a window region? Region isn't a size change, so
;      WM_WINDOWPOSCHANGING never sees it.
Out("`n=== A: SetWindowRgn (visual crop to bottom 32px) ===")
NEW := 32
rgn := DllCall("gdi32\CreateRectRgn", "int", 0, "int", h - NEW, "int", w, "int", h, "ptr")
ok := DllCall("SetWindowRgn", "ptr", tb, "ptr", rgn, "int", 1)
Out("  SetWindowRgn returned: " ok)
Sleep 600
box := Buffer(16, 0)
kind := DllCall("GetWindowRgnBox", "ptr", tb, "ptr", box)
Out(Format("  GetWindowRgnBox kind={1}  box=({2},{3})-({4},{5})   {6}",
    kind, NumGet(box,0,"int"), NumGet(box,4,"int"), NumGet(box,8,"int"), NumGet(box,12,"int"),
    (kind != 0) ? "REGION APPLIED" : "no region"))

; ── B: does SPI_SETWORKAREA hold on the primary?
Out("`n=== B: SPI_SETWORKAREA ===")
WorkBottom() {
    r := Buffer(16, 0)
    DllCall("SystemParametersInfo", "uint", 0x0030, "uint", 0, "ptr", r, "uint", 0)  ; SPI_GETWORKAREA
    return NumGet(r, 12, "int")
}
Out("  work bottom before: " WorkBottom())
wr := Buffer(16, 0)
NumPut("int", 0, wr, 0), NumPut("int", 0, wr, 4)
NumPut("int", w, wr, 8), NumPut("int", y + (h - NEW), wr, 12)
DllCall("SystemParametersInfo", "uint", 0x002F, "uint", 0, "ptr", wr, "uint", 0x02)
for ms in [100, 600, 2000] {
    Sleep ms
    Out("  after +" ms "ms: " WorkBottom())
}

; ── C: put it all back
Out("`n=== C: restore ===")
DllCall("SetWindowRgn", "ptr", tb, "ptr", 0, "int", 1)
NumPut("int", 0, wr, 0), NumPut("int", 0, wr, 4)
NumPut("int", w, wr, 8), NumPut("int", y, wr, 12)
DllCall("SystemParametersInfo", "uint", 0x002F, "uint", 0, "ptr", wr, "uint", 0x02)
Sleep 500
Out("  region cleared, work bottom back to: " WorkBottom())
ExitApp(0)
