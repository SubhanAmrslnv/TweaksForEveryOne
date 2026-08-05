#Requires AutoHotkey v2.0
#Include ..\src\SnapCore.ahk
Persistent
; Guided live test. Run it, then drag windows around with the mouse.
;
; Why manual: a caption drag cannot be simulated reliably. Injected clicks do
; not engage the window's move loop the way a physical button press does, so
; "automated" drag tests either did nothing and passed vacuously, or moved the
; window by other means and tested a code path that real drags never take.
;
; This watches the same MOVESIZESTART / MOVESIZEEND events the program uses,
; predicts where the snap engine should put each window, then checks where it
; actually ended up.

SNAP := 30, BOOST := 2.2, PROX := 90

global Pass := 0, Fail := 0
global StartL := 0, StartT := 0, Watch := 0
global Report := ""

g := Gui("+AlwaysOnTop +Resize", "Live snap test - drag some windows")
g.SetFont("s9", "Segoe UI")
g.AddText("w560", "Drag any window by its title bar and release it near a screen edge, "
                . "a corner, or another window's edge. Each drag is checked below.")
g.AddEdit("w560 h300 ReadOnly vOut", "Waiting for a drag...")
g.AddText("w560 vScore", "0 passed, 0 failed")
g.Show()

cb := CallbackCreate(Ev, "F", 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0,
        "ptr", cb, "uint", 0, "uint", 0, "uint", 0x0002, "ptr")

Ev(hook, event, hwnd, idObj, idChild, thread, time) {
    global Watch, StartL, StartT
    if (idObj != 0)
        return
    if (event = 0x000A) {
        Watch := 0
        if !IsSnappable(hwnd)
            return
        if !GetRects(hwnd, &L, &T, &R, &B, &x, &y)
            return
        Watch := hwnd, StartL := L, StartT := T
        return
    }
    if (hwnd != Watch)
        return
    Watch := 0
    SetTimer(() => Judge(hwnd), -40)
}

Judge(hwnd) {
    global Pass, Fail, Report, StartL, StartT
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if !GetRects(hwnd, &eL, &eT, &eR, &eB, &ex, &ey)
        return
    if (Abs(eL - StartL) < 4 && Abs(eT - StartT) < 4)
        return                                   ; a click, not a drag
    if (WinGetMinMax(hwnd) != 0) {
        Note("skipped: Windows maximised it")
        return
    }

    CollectEdges(hwnd, eL, eT, eR, eB, &vLines, &hLines, PROX)
    snapped := ComputeSnap(eL, eT, eR, eB, vLines, hLines, SNAP, &pL, &pT, BOOST)

    Sleep 700                                    ; let the glide finish
    if !GetRects(hwnd, &fL, &fT, &fR, &fB, &fx, &fy)
        return

    try title := WinGetTitle(hwnd)
    catch
        title := "?"
    title := SubStr(title, 1, 26)

    if !snapped {
        ; No edge in range. With ice glide on, the window is allowed to coast
        ; past where it was released, so only a wild jump is a failure.
        drift := Abs(fL - eL) + Abs(fT - eT)
        if (drift <= 520) {
            Pass++
            Note(Format('"{1}" released at {2},{3} -> coasted to {4},{5}  OK', title, eL, eT, fL, fT))
        } else {
            Fail++
            Note(Format('"{1}" released at {2},{3} -> flew to {4},{5}  TOO FAR', title, eL, eT, fL, fT))
        }
        return
    }

    if (fL = pL && fT = pT) {
        Pass++
        Note(Format('"{1}" {2},{3} -> snapped to {4},{5}  OK', title, eL, eT, fL, fT))
    } else {
        Fail++
        Note(Format('"{1}" {2},{3} -> got {4},{5} but engine said {6},{7}  MISMATCH',
                    title, eL, eT, fL, fT, pL, pT))
    }
}

Note(line) {
    global Report, Pass, Fail, g
    Report := line "`n" Report
    try {
        g["Out"].Value := Report
        g["Score"].Value := Pass " passed, " Fail " failed"
    }
}

g.OnEvent("Close", (*) => ExitApp())
g.OnEvent("Escape", (*) => ExitApp())
