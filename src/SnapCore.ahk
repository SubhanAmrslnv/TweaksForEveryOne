#Requires AutoHotkey v2.0
; Snap geometry and window inspection. Function definitions only, so the test
; scripts can include this without starting the program.
;
; Do not name edge variables oL/oT/oR/oB: AHK identifiers are case-insensitive,
; so `oR` collides with the `or` keyword and fails to parse.

; Returns whether an edge was found within `threshold`, NOT whether the window
; had to move. Those differ for a window that is already exactly flush, and
; conflating them broke the corner boost in precisely the case it exists for:
; ComputeSnap only retries the perpendicular axis once this returns true, so a
; window already hugging the left edge (L exactly on the line) reported "no
; snap" and never got the boosted pull into the corner.
; `dir` is the sign of travel on this axis (-1, 0, +1) and `hyst` is how strongly
; an edge the window is already flush with holds on to it. Both default to the
; old behaviour, so a caller that passes neither gets exactly the previous
; nearest-line result.
;
; Candidates are scored rather than measured, and the score is what the two extra
; parameters bend:
;
;   * a line that would pull the window BACKWARDS against the direction it was
;     thrown is penalised. Without this, a line the window is visibly moving away
;     from competes on equal terms with the one it is heading for, which is what
;     made a fast drag past a neighbour occasionally stick to the wrong side.
;   * a line the window's edge is already sitting on is discounted, so nudging an
;     already-snapped window a few pixels keeps it where it is instead of letting
;     a neighbour half a pixel closer steal it.
;
; Scores only ever reorder candidates; the accept test at the end is still a
; plain distance against `threshold`, so nothing outside the reach can be pulled
; in by a bias.
SnapAxis(lo, hi, lines, threshold, &newLo, dir := 0, hyst := 0) {
    size := hi - lo
    newLo := lo
    ; Not threshold+1: acceptance is decided by the `d > threshold` test below, so
    ; the score only has to order what already qualifies. Seeding this with the
    ; threshold would let the directional penalty push a perfectly good candidate
    ; back out of range, which is the opposite of what the bias is for.
    bestScore := 999999
    locked := false
    for v in lines {
        loop 2 {
            ; Edge 1 is the leading edge, edge 2 the trailing one.
            if (A_Index = 1) {
                d      := Abs(lo - v)
                cand   := v
                moving := v - lo
            } else {
                d      := Abs(hi - v)
                cand   := v - size
                moving := v - hi
            }
            if (d > threshold)
                continue
            score := d
            ; Against the throw: real, but it has to beat a forward candidate by
            ; a clear margin to win.
            if (dir != 0 && moving != 0 && ((moving > 0) != (dir > 0)))
                score *= 1.6
            ; Already flush with this line: hold on to it.
            ;
            ; The bonus tapers with distance (score becomes 2d - hyst inside the
            ; band) rather than being a flat subtraction. A flat one is not
            ; monotonic: with hyst 6, a line 6 px away would score 0 and beat a
            ; line 1 px away scoring 1, so "stickiness" would have pulled the
            ; window to the FURTHER of two nearby edges. This way the ordering
            ; inside the band still runs closest-first, and it joins the
            ; unbiased scores continuously at d = hyst.
            if (hyst > 0 && d <= hyst)
                score -= (hyst - d)
            if (score < bestScore) {
                bestScore := score
                newLo     := cand
                locked    := true
            }
        }
    }
    return locked
}

; cornerBoost > 1 retries the perpendicular axis with a larger threshold once
; one axis has locked, so a window hugging an edge drops into the corner from
; noticeably further away than a plain edge would catch it.
ComputeSnap(L, T, R, B, vLines, hLines, threshold, &newL, &newT, cornerBoost := 1.0
          , dirX := 0, dirY := 0, hyst := 0) {
    sx := SnapAxis(L, R, vLines, threshold, &newL, dirX, hyst)
    sy := SnapAxis(T, B, hLines, threshold, &newT, dirY, hyst)

    if (cornerBoost > 1.0) {
        boosted := Round(threshold * cornerBoost)
        if (sx && !sy)
            sy := SnapAxis(T, B, hLines, boosted, &newT, dirY, hyst)
        else if (sy && !sx)
            sx := SnapAxis(L, R, vLines, boosted, &newL, dirX, hyst)
    }

    return sx || sy
}

CollectEdges(hwnd, L, T, R, B, &vLines, &hLines, proximity := 0) {
    vLines := []
    hLines := []

    ; Per-monitor work areas, so a vertically offset second monitor stays right.
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        vLines.Push(wl, wr)
        hLines.Push(wt, wb)
    }

    for other in WinGetList() {
        if (other = hwnd) || !IsSnappable(other)
            continue
        if !GetRects(other, &oLeft, &oTop, &oRight, &oBottom, &oWinX, &oWinY)
            continue
        if (oRight <= oLeft || oBottom <= oTop)
            continue

        ; `proximity` widens the overlap test so a window can latch onto a
        ; neighbour it doesn't quite overlap yet.
        if (T < oBottom + proximity && B > oTop - proximity)
            vLines.Push(oLeft, oRight)
        if (L < oRight + proximity && R > oLeft - proximity)
            hLines.Push(oTop, oBottom)
    }
}

; Returns the visual frame rect plus the raw WinGetPos origin, so callers can
; convert between the two.
GetRects(hwnd, &fL, &fT, &fR, &fB, &winX, &winY) {
    ; One buffer for the life of the process. CollectEdges calls this once per
    ; window per snap, and a fresh Buffer(16) measured 0.43 us more than reusing
    ; one - pure garbage on a path that already runs N times per drag.
    static rc := Buffer(16, 0)

    try WinGetPos(&winX, &winY, &ww, &wh, hwnd)
    catch
        return false
    if (winX = "" || ww = "")
        return false

    ; DWMWA_EXTENDED_FRAME_BOUNDS excludes the invisible resize border, without
    ; which every snap lands ~7px off from where it looks like it should.
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 9, "ptr", rc, "int", 16) = 0) {
        fL := NumGet(rc, 0,  "int")
        fT := NumGet(rc, 4,  "int")
        fR := NumGet(rc, 8,  "int")
        fB := NumGet(rc, 12, "int")
    } else {
        fL := winX, fT := winY, fR := winX + ww, fB := winY + wh
    }
    return true
}

IsSnappable(hwnd) {
    if !hwnd
        return false
    if (DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != hwnd)
        return false

    try {
        cls := WinGetClass(hwnd)
        style := WinGetStyle(hwnd)
        state := WinGetMinMax(hwnd)
    } catch
        return false

    ; Kept inline and un-memoised on purpose. Measured A/B on the same probe:
    ; moving this to a helper function cost 10% (the call overhead exceeds the
    ; regex), and memoising the result per class name made no measurable
    ; difference at all. RegExMatch against a static pattern is already cheap.
    static skip := "^(Shell_TrayWnd|Shell_SecondaryTrayWnd|Progman|WorkerW"
                 . "|Windows\.UI\.Core\.CoreWindow|ApplicationFrameInputSinkWindow"
                 . "|ForegroundStaging|TaskListThumbnailWnd|Button|MultitaskingViewFrame"
                 . "|XamlExplorerHostIslandWindow|TopLevelWindowForOverflowXamlIsland)$"
    if (cls ~= skip)
        return false

    if (state != 0)                  ; minimized or maximized
        return false
    if !(style & 0x10000000)         ; WS_VISIBLE
        return false
    if (style & 0x08000000)          ; WS_DISABLED
        return false
    if IsCloaked(hwnd)               ; UWP suspended / other virtual desktop
        return false

    return true
}

IsCloaked(hwnd) {
    cloaked := 0
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 14, "int*", &cloaked, "int", 4) != 0)
        return false
    return cloaked != 0
}
