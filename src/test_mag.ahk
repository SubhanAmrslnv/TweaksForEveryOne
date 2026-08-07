#Requires AutoHotkey v2.0
CoordMode("Mouse", "Screen")

DllCall("LoadLibrary", "str", "Magnification.dll")
DllCall("Magnification\MagInitialize")

global MagFrameGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
MagFrameGui.BackColor := "Gray"
WinSetRegion("0-0 w144 h144 E", MagFrameGui.Hwnd)

global MagHostGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
WinSetRegion("0-0 w140 h140 E", MagHostGui.Hwnd)

global MagChildHwnd := DllCall("CreateWindowEx", "uint", 0
    , "str", "Magnifier"
    , "str", "MagnifierWindow"
    , "uint", 0x50000000 ; WS_CHILD | WS_VISIBLE
    , "int", 0, "int", 0, "int", 140, "int", 140
    , "ptr", MagHostGui.Hwnd, "ptr", 0, "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "ptr", 0, "ptr")

Transform := Buffer(36, 0)
NumPut("float", 2.0, Transform, 0)
NumPut("float", 2.0, Transform, 16)
NumPut("float", 1.0, Transform, 32)
DllCall("Magnification\MagSetWindowTransform", "ptr", MagChildHwnd, "ptr", Transform)

MagHostGui.Show("x0 y0 w140 h140 NoActivate")
MagFrameGui.Show("x0 y0 w144 h144 NoActivate")

SetTimer(UpdateMag, 16)

UpdateMag() {
    MouseGetPos(&mx, &my)
    
    ; Exclude both GUIs from being magnified (not strictly necessary on Win8+, but safe)
    
    SourceRect := Buffer(16, 0)
    NumPut("int", mx - 35, SourceRect, 0)
    NumPut("int", my - 35, SourceRect, 4)
    NumPut("int", mx + 35, SourceRect, 8)
    NumPut("int", my + 35, SourceRect, 12)
    DllCall("Magnification\MagSetWindowSource", "ptr", MagChildHwnd, "ptr", SourceRect)
    
    DllCall("SetWindowPos", "ptr", MagFrameGui.Hwnd, "ptr", -1, "int", mx - 72, "int", my - 162, "int", 0, "int", 0, "uint", 0x55)
    DllCall("SetWindowPos", "ptr", MagHostGui.Hwnd, "ptr", -1, "int", mx - 70, "int", my - 160, "int", 0, "int", 0, "uint", 0x55)
}

Esc::ExitApp()
