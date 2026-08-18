; On-demand overlays - summoned by a gesture, dismissed when done.
;
; Function definitions and global initialisers only, no top-level statements.
;
; Quick Look, the Spotlight launcher and the text-selection magnifier have
; nothing in common as features; they are together because they share a
; lifetime. Each builds a Gui on demand, owns the screen until dismissed, and
; must leave nothing behind - so each one is also a place the program can strand
; an overlay if its teardown is skipped.
;
; SET THE REGION AND THE ALPHA BEFORE Gui.Show(). Doing it after costs one frame
; of a hard-edged, fully opaque window - the Spotlight launcher flashed a grey
; rectangle on every single launch.
;
; CALL RS_RemoveHwnd(hwnd) ON DESTROY. These are WS_EX_TOOLWINDOW / NoActivate
; windows, so they raise no shell destroy notification and nothing else will
; prune them out of the RenderCore caches.
;
; A Gui object must outlive its animation: pass the OBJECT into the closure, not
; just its Hwnd, and finish with Destroy() - never WinClose, which only posts
; WM_CLOSE and leaves the object alive.

; ====== macOS Quick Look ======

IsTypingInExplorer() {
    try {
        ctrl := ControlGetClassNN(ControlGetFocus("A"))
        if (InStr(ctrl, "Edit") || InStr(ctrl, "Search") || InStr(ctrl, "Windows.UI.Core.CoreWindow"))
            return true
    }
    return false
}

GetSelectedExplorerFile() {
    try {
        hwnd := WinExist("A")
        for window in ComObject("Shell.Application").Windows {
            if (window.HWND == hwnd) {
                sel := window.Document.SelectedItems
                if (sel.Count > 0)
                    return sel.Item(0).Path
            }
        }
    }
    return ""
}

ToggleQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        CloseQuickLook()
        return true
    }
    path := GetSelectedExplorerFile()
    if (!path || !FileExist(path) || InStr(FileExist(path), "D"))
        return false 
        
    ; Build into a local and only publish it once there is something to show.
    ; Assigning QuickLookGui up front and then returning false for an unsupported
    ; extension left a created-but-never-shown window in the global, which made
    ; the next Space press take the "close it" branch and swallow the keystroke -
    ; so Space alternated between working and doing nothing.
    ext := StrLower(RegExReplace(path, ".*\.([^.]+)$", "$1"))
    if !(ext ~= "^(png|jpg|jpeg|gif|bmp|txt|md|ini|ahk|csv|log|json|xml|ps1|bat|cmd)$")
        return false

    g := Gui("-Caption +ToolWindow +AlwaysOnTop +LastFound +Border -DPIScale")
    g.BackColor := "111111"
    g.MarginX := 20
    g.MarginY := 20

    try {
        if (ext ~= "^(png|jpg|jpeg|gif|bmp)$")
            g.AddPicture("w-1 h-1", path)
        else
            g.AddEdit("w600 h400 ReadOnly Background111111 cWhite -E0x200", FileRead(path, "m4096"))
    } catch {
        try g.Destroy()
        return false
    }

    QuickLookGui := g
    RS_SetAlpha(g.Hwnd, 0, RS_PRI_ANIM)
    RS_Commit()
    g.Show("NoActivate AutoSize Center")
    FadeGui(g, 255)
    SetTimer(CheckQuickLookFocusStep, 100)
    return true
}

CloseQuickLook() {
    global QuickLookGui
    if (QuickLookGui) {
        SetTimer(CheckQuickLookFocusStep, 0)
        guiObj := QuickLookGui
        QuickLookGui := "" 
        FadeGui(guiObj, 0, 0, true)
    }
}

CheckQuickLookFocusStep() {
    global QuickLookGui
    if !QuickLookGui {
        SetTimer(CheckQuickLookFocusStep, 0)
        return
    }

    ahwnd := WinExist("A")
    ; WinGetClass(0) throws, and an uncaught throw in a timer thread pops an
    ; error dialog and kills the timer. There is routinely no active window at
    ; all - during a desktop switch, or on the lock screen.
    cls := ""
    if ahwnd
        try cls := WinGetClass(ahwnd)
    if (ahwnd != QuickLookGui.Hwnd && cls != "CabinetWClass")
        CloseQuickLook()
}

; ====== Quick Spotlight Launcher ======

ToggleSpotlight() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    
    if (SpotlightGui) {
        hwnd := 0
        try hwnd := SpotlightGui.Hwnd
        try SpotlightGui.Destroy()
        SpotlightGui := "", SpotlightInput := "", SpotlightResult := ""
        if hwnd
            RS_RemoveHwnd(hwnd)
        return
    }


    SpotlightGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
    SpotlightGui.BackColor := "202020" 
    
    SpotlightGui.SetFont("s24 cWhite", "Segoe UI")
    SpotlightInput := SpotlightGui.AddEdit("x20 y20 w600 h45 -VScroll -E0x200 Background202020 cWhite")
    
    SpotlightGui.SetFont("s14 cAAAAAA", "Segoe UI")
    SpotlightResult := SpotlightGui.AddText("x20 y85 w600 h35", "Type to search, calculate, or run...")
    
    SpotlightInput.OnEvent("Change", SpotlightOnChange)
    
    activeMon := MonitorGetPrimary()
    MonitorGet(activeMon, &L, &T, &R, &B)
    w := 640, h := 140
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 3 
    
    ; Round the corners and set the opacity BEFORE showing it. Doing it after Show
    ; meant one frame of a hard-edged, fully opaque grey rectangle before the
    ; region and alpha landed - a visible flash on every launch. The dimmer and the
    ; OSDs already did it in this order; this one did not.
    RS_SetRegion(SpotlightGui.Hwnd, "0-0 w640 h140 r20-20", RS_PRI_ANIM)
    RS_SetAlpha(SpotlightGui.Hwnd, 240, RS_PRI_ANIM)
    RS_Commit()
    SpotlightGui.Show("x" x " y" y " w" w " h" h)
}

SpotlightOnChange(ctrl, *) {
    global SpotlightResult
    text := Trim(ctrl.Value)
    if (text = "") {
        SpotlightResult.Text := "Type to search, calculate, or run..."
        return
    }

    ; A fresh MSHTML document per keystroke is not cheap, but it is only reached
    ; for arithmetic-looking input and a reused document has to be open()ed and
    ; close()d to be re-writable - which fails silently inside this try and would
    ; take the calculator with it. Left as it is on purpose.
    ; The character class is the guard: only digits, whitespace, brackets and the
    ; four operators ever reach eval, so nothing can escape arithmetic.
    if RegExMatch(text, "^[\d\+\-\*\/\.\(\)\s]+$") && RegExMatch(text, "\d") {
        try {
            doc := ComObject("htmlfile")
            doc.write("<body><script>document.write(eval('" text "'));</script></body>")
            ans := doc.body.innerText
            if (ans != "") {
                SpotlightResult.Text := "= " ans
                return
            }
        }
    }


    if FileExist(text) {
        SpotlightResult.Text := "Open path: " text
        return
    }
    
    SpotlightResult.Text := "Run: " text
}

SpotlightExecute() {
    global SpotlightGui, SpotlightInput, SpotlightResult
    text := Trim(SpotlightInput.Value)
    if (text = "")
        return
        
    resText := SpotlightResult.Text
    
    if (SubStr(resText, 1, 2) == "= ") {
        A_Clipboard := LTrim(resText, "= ")
        ToggleSpotlight()
        return
    }
    
    ToggleSpotlight()
    try {
        Run(text)
    } catch {
        q := StrReplace(text, " ", "+")
        try Run("https://www.google.com/search?q=" q)
    }
}

; ============================================================================
; Text Selection Magnifier
; ============================================================================

; Returns false if the magnifier is not usable on this machine. Every step is
; checked: MagInitialize can fail outright, and the whole thing is inside a try
; because it runs from a mouse-drag timer where a throw is an error dialog.
;
; MagFailed latches, so a machine without a working Magnification.dll pays the
; failed init exactly once instead of on every text drag.
InitMag() {
    global MagHostGui, MagFrameGui, MagChildHwnd, MagFailed

    if MagFailed
        return false
    try {
        if !DllCall("LoadLibrary", "str", "Magnification.dll", "ptr")
            throw Error("Magnification.dll")
        if !DllCall("Magnification\MagInitialize")
            throw Error("MagInitialize")

        MagFrameGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
        MagFrameGui.BackColor := "2A2A2A"
        WinSetRegion("0-0 w144 h144 E", MagFrameGui.Hwnd)

        ; WS_EX_LAYERED (0x80000) is REQUIRED on the host of a magnifier control -
        ; the API documents it, and without it the control has no surface to
        ; present into, which is why this effect had never actually shown a loupe.
        MagHostGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x80000")
        WinSetRegion("0-0 w140 h140 E", MagHostGui.Hwnd)

        MagChildHwnd := DllCall("CreateWindowEx", "uint", 0
            , "str", "Magnifier"
            , "str", "MagnifierWindow"
            , "uint", 0x50000000 ; WS_CHILD | WS_VISIBLE
            , "int", 0, "int", 0, "int", 140, "int", 140
            , "ptr", MagHostGui.Hwnd, "ptr", 0, "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "ptr", 0, "ptr")
        if !MagChildHwnd
            throw Error("CreateWindowEx Magnifier")

        Transform := Buffer(36, 0)
        NumPut("float", 2.0, Transform, 0)
        NumPut("float", 2.0, Transform, 16)
        NumPut("float", 1.0, Transform, 32)
        DllCall("Magnification\MagSetWindowTransform", "ptr", MagChildHwnd, "ptr", Transform)
        return true
    } catch as e {
        MagFailed := true
        MagChildHwnd := 0
        try MagFrameGui.Destroy()
        try MagHostGui.Destroy()
        MagFrameGui := "", MagHostGui := ""
        WriteLog("magnifier unavailable - " e.Message)
        return false
    }
}

; Returns whether the loupe is actually on screen. The caller MUST honour it:
; arming UpdateMag regardless is what turned a missing Magnification.dll into an
; error dialog on every text drag, because UpdateMag then dereferenced
; MagFrameGui.Hwnd on an empty string, outside any try, from a 16 ms timer.
ShowMag(mx, my) {
    global MagHostGui, MagFrameGui, MagChildHwnd
    if (!MagChildHwnd && !InitMag())
        return false
    if (!MagFrameGui || !MagHostGui)
        return false
    try {
        MagFrameGui.Show("x-1000 y-1000 w144 h144 NoActivate")
        MagHostGui.Show("x-1000 y-1000 w140 h140 NoActivate")
        return true
    }
    return false
}

HideMag() {
    global MagHostGui, MagFrameGui
    if (MagHostGui) {
        MagHostGui.Hide()
        MagFrameGui.Hide()
    }
}

CheckMagDrag() {
    global MagStartX, MagStartY, MagActive
    if (!GetKeyState("LButton", "P")) {
        SetTimer(CheckMagDrag, 0)
        return
    }
    MouseGetPos(&mx, &my)
    if (Abs(mx - MagStartX) > 5 || Abs(my - MagStartY) > 5) {
        SetTimer(CheckMagDrag, 0)
        if ShowMag(mx, my) {
            MagActive := true
            RegisterAnimation("MagLoupe", MagCallback)
        }
    }
}

MagCallback(dt, now) {
    global MagActive, MagChildHwnd, MagHostGui, MagFrameGui
    if (!GetKeyState("LButton", "P")) {
        MagActive := false
        HideMag()
        return false
    }

    if (!MagChildHwnd || !MagFrameGui || !MagHostGui) {
        MagActive := false
        return false
    }

    try {
        MouseGetPos(&mx, &my)
        SourceRect := Buffer(16, 0)
        NumPut("int", mx - 35, SourceRect, 0)
        NumPut("int", my - 35, SourceRect, 4)
        NumPut("int", mx + 35, SourceRect, 8)
        NumPut("int", my + 35, SourceRect, 12)
        DllCall("Magnification\MagSetWindowSource", "ptr", MagChildHwnd, "ptr", SourceRect)
        
        RS_SetPos(MagFrameGui.Hwnd, mx - 72, my - 162, -1, -1, RS_PRI_ANIM)
        RS_SetPos(MagHostGui.Hwnd, mx - 70, my - 160, -1, -1, RS_PRI_ANIM)
    }
    return true
}

global MagActive := false

global MagHostGui := ""

global MagFrameGui := ""

global MagChildHwnd := 0

global MagFailed := false

global MagStartX := 0, MagStartY := 0
