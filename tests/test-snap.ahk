#Requires AutoHotkey v2.0
#Include ..\src\SnapCore.ahk
; Run:  AutoHotkey64.exe test-snap.ahk   (writes results to stdout)

global Pass := 0, Fail := 0

Out(s) => FileAppend(s "`n", "*")

Check(name, got, want) {
    global Pass, Fail
    if (got = want) {
        Pass++
        Out(Format("  PASS  {1}  (= {2})", name, got))
    } else {
        Fail++
        Out(Format("  FAIL  {1}  got {2}, want {3}", name, got, want))
    }
}

TH := 15   ; same threshold the live script uses

Out("=== ComputeSnap: single axis ===")

; Left edge 8px from the monitor's left edge -> flush to 0, vertical untouched.
ComputeSnap(8, 100, 808, 700, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("left edge snaps to 0", nL, 0)
Check("  top left alone", nT, 100)

; Right edge 8px from the monitor's right edge -> window shifts so R lands on 1920.
ComputeSnap(1112, 100, 1912, 700, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("right edge snaps to 1920", nL, 1120)

; Bottom edge near the work-area bottom.
ComputeSnap(400, 494, 1200, 1194, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("bottom edge snaps to 1200", nT, 500)

Out("=== ComputeSnap: no candidate in range ===")
changed := ComputeSnap(500, 500, 1300, 900, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("returns false", changed, false)
Check("  x unchanged", nL, 500)
Check("  y unchanged", nT, 500)

Out("=== ComputeSnap: both axes independently ===")
; Left edge near monitor left AND top edge near another window's bottom (300).
ComputeSnap(8, 306, 808, 906, [0, 1920], [0, 300, 1200], TH, &nL, &nT)
Check("x snaps to monitor edge", nL, 0)
Check("y snaps to window edge", nT, 300)

Out("=== ComputeSnap: nearest candidate wins ===")
ComputeSnap(8, 100, 808, 700, [0, 10], [0, 1200], TH, &nL, &nT)
Check("picks 10 over 0", nL, 10)

Out("=== ComputeSnap: window-to-window abutting ===")
; Our left edge at 908 vs another window's right edge at 900 -> sit flush against it.
ComputeSnap(908, 100, 1708, 700, [0, 900, 1920], [0, 1200], TH, &nL, &nT)
Check("abuts neighbour's right edge", nL, 900)

Out("=== ComputeSnap: threshold boundary ===")
ComputeSnap(15, 100, 815, 700, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("15px away still snaps", nL, 0)
ComputeSnap(16, 100, 816, 700, [0, 1920], [0, 1200], TH, &nL, &nT)
Check("16px away does not", nL, 16)

Out("=== Corner boost ===")
; 8px from the left edge, 25px from the top. 25 is outside the plain 15px
; threshold, but inside the boosted 33px one -- so the corner should capture it.
ComputeSnap(8, 25, 808, 425, [0, 1920], [0, 1200], TH, &nL, &nT, 1.0)
Check("no boost: x snaps", nL, 0)
Check("no boost: y stays", nT, 25)

ComputeSnap(8, 25, 808, 425, [0, 1920], [0, 1200], TH, &nL, &nT, 2.2)
Check("boosted: x snaps", nL, 0)
Check("boosted: y pulled into corner", nT, 0)

; Same thing with the axes swapped: y locks first, x gets the extra pull.
ComputeSnap(25, 8, 825, 408, [0, 1920], [0, 1200], TH, &nL, &nT, 2.2)
Check("boosted: y snaps", nT, 0)
Check("boosted: x pulled into corner", nL, 0)

; A boost must never invent a snap when neither axis was near anything.
changed := ComputeSnap(500, 500, 1300, 900, [0, 1920], [0, 1200], TH, &nL, &nT, 2.2)
Check("boost does not fabricate a snap", changed, false)

; Beyond even the boosted range, the second axis stays put.
ComputeSnap(8, 200, 808, 600, [0, 1920], [0, 1200], TH, &nL, &nT, 2.2)
Check("boosted: far y untouched", nT, 200)

Out("=== Live environment ===")
Out(Format("  monitors: {1}", MonitorGetCount()))
loop MonitorGetCount() {
    MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
    Out(Format("    #{1} work area  L={2} T={3} R={4} B={5}", A_Index, wl, wt, wr, wb))
}

n := 0
sample := ""
for hwnd in WinGetList() {
    if !IsSnappable(hwnd)
        continue
    n++
    if (n <= 3 && GetRects(hwnd, &fL, &fT, &fR, &fB, &wx, &wy)) {
        try title := WinGetTitle(hwnd)
        catch
            title := "?"
        sample .= Format("    `"{1}`"  frame L={2} T={3}  WinGetPos x={4} y={5}  (border dx={6})`n",
                         SubStr(title, 1, 28), fL, fT, wx, wy, fL - wx)
    }
}
Out(Format("  snappable windows: {1}", n))
Out(sample)

Out(Format("=== {1} passed, {2} failed ===", Pass, Fail))
ExitApp(Fail > 0 ? 1 : 0)
