global CustomTrans := Map()

; The wheel targets the window being dragged if there is one, and the active
; window otherwise.
;
; Two separate reasons for the drag branch, and both need it to skip IsRestorable
; rather than merely tolerate it. Windows' modal move loop can leave WinExist("A")
; pointing somewhere else for the duration of the drag, so the active window is
; not reliably the one under the hand; and IsRestorable goes through IsSnappable,
; which rejects a window mid-move. DragHwnd is the window MOVESIZESTART accepted,
; so it has already passed that same predicate - re-testing it here could only
; ever produce a false negative.
;
; It used to read `!IsRestorable(hwnd) && hwnd != DragHwnd`, which is unreachable:
; hwnd had just been assigned DragHwnd on the line above, so the guard was dropped
; entirely rather than deliberately skipped. DragHwnd is a super-global
; initialised in DragPipeline.ahk, so the IsSet() around it was dead too.
ChangeTransparency(dir) {
    global CustomTrans, PendingTransMsg, DragHwnd
    if (DragHwnd && DllCall("IsWindow", "ptr", DragHwnd)) {
        hwnd := DragHwnd
    } else {
        hwnd := WinExist("A")
        if (!hwnd || !IsRestorable(hwnd))
            return
    }

    current := CustomTrans.Has(hwnd) ? CustomTrans[hwnd] : 255

    step := Tune("transStep")
    if (dir > 0)
        current += step
    else
        current -= step

    ; The floor is a real one: a window at alpha 0 is invisible, focused and
    ; still clickable, and the only way back is Shift+Alt+X on a window you can
    ; no longer see.
    floor := TuneAlpha("transMin")
    if (current > 255)
        current := 255
    if (current < floor)
        current := floor

    CustomTrans[hwnd] := current

    ; No hand-off to breathing any more. This used to write the chosen alpha into
    ; WinTargetAlpha/WinCurrentAlpha so breathing would not immediately fade the
    ; window back down - one module reaching into another's private state to
    ; hand-compose two opacities. RenderCore multiplies the base by the breathe
    ; factor now, so the two are independent by construction.
    if (current == 255) {
        RS_SetBaseAlpha(hwnd, 255, RS_PRI_USER)
        CustomTrans.Delete(hwnd)
        PendingTransMsg := "Transparency: OFF"
    } else {
        RS_SetBaseAlpha(hwnd, current, RS_PRI_USER)
        PendingTransMsg := "Opacity: " Round((current / 255) * 100) "%"
    }
    ; One-shot producer: nothing else is animating, so nothing else will flush.
    RS_Commit()
    ; One tray tip per gesture, not one per wheel notch - a single scroll used to
    ; queue a dozen notifications into the Action Center.
    SetTimer(FlushTransNotify, -400)
}

FlushTransNotify() {
    global PendingTransMsg
    if (PendingTransMsg != "") {
        Notify(PendingTransMsg)
        PendingTransMsg := ""
    }
}

; Back to fully opaque in one press.
;
; This clears the breathe layer as well as the user's own opacity, and that is
; deliberate: the key means "make this window solid NOW", so leaving it dim
; because it happens to be idle would read as the key having done nothing. The
; window starts breathing again on the next monitor tick, which is the same
; behaviour as before - it used to be achieved by writing 255 into breathing's
; two private maps from here.
ResetTransparency() {
    global CustomTrans, WinCurrentAlpha, WinTargetAlpha
    hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd)
        return
    if CustomTrans.Has(hwnd)
        CustomTrans.Delete(hwnd)
    if WinCurrentAlpha.Has(hwnd)
        WinCurrentAlpha[hwnd] := 255
    if WinTargetAlpha.Has(hwnd)
        WinTargetAlpha[hwnd] := 255
    RS_SetBaseAlpha(hwnd, 255, RS_PRI_USER)
    RS_ClearAlphaLayer(hwnd, "breathe", RS_PRI_USER)
    RS_Commit()                    ; one-shot producer: nothing else will flush
    Notify("Transparency: OFF")
}

; The panic key. Every state this app can put a window into that is not obvious
