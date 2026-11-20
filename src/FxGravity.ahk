; Window spectacle FX - one-shot takeovers of the whole desktop.
;
; Function definitions and global initialisers only, no top-level statements.
; This module opens and closes bare #HotIf around the five bindings it carries.
;
; Gravity close, curtain drop, carousel Alt-Tab, black-hole delete, black-hole
; minimize and shatter-to-close are grouped because they behave the same way:
; each fires once, seizes a large part of the screen, and has to put everything
; back. Their hotkeys live HERE rather than in InputBindings.ahk because in each
; case the binding body IS the feature.
;
; EACH BINDING IS GATED IN ITS #HotIf CRITERIA, NOT BY RE-SENDING THE KEY FROM
; THE BODY. With the feature off the key is simply not claimed, so Windows own
; behaviour runs - Alt+F4 closes, Win+D shows the desktop, Alt+Tab is the normal
; switcher. CLAUDE.md lists Win+D and Alt+Tab as deliberately not touched, and
; this is what keeps that true.
;
; WHEN SWAPPING A REAL WINDOW FOR A THUMBNAIL, SHOW THE THUMBNAIL BEFORE HIDING THE
; ORIGINAL, or there is a frame with neither on screen.
;
; Bye() calls RestoreCurtain() and RestoreShatters(). CurtainWindows is the ONLY
; record of where those windows came from, so exiting mid-effect without it
; leaves the desktop swept clean with no way back.
;
; A Gui object must outlive its animation: pass the OBJECT into the closure and
; finish with Destroy(), never WinClose. These effects create dozens of Guis per
; invocation, so a leak here is immediate rather than gradual.

; Behind its flag rather than re-sending Alt+F4 from the body: with the
; feature off the key is simply not claimed, so Windows' own close runs and
; nothing sits in front of Alt+F4 at all.
#HotIf
#HotIf GravityCloseEnabled
$!F4::GravityClose()
#HotIf

GravityClose() {
    global ActiveAnimations
    hwnd := WinExist("A")
    if !hwnd {
        Send("!{F4}")
        return
    }

    cls := ""
    try cls := WinGetClass(hwnd)
    if (!cls || IsShellSurface(hwnd, cls) || cls == "AutoHotkeyGUI") {
        Send("!{F4}")
        return
    }

    animKey := "Gravity_" hwnd
    if ActiveAnimations.Has(animKey)
        return

    ; Maximized and full-screen windows close normally.
    try {
        if (WinGetMinMax(hwnd) != 0) {
            Send("!{F4}")
            return
        }
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        Send("!{F4}")
        return
    }
    if (w < 1 || h < 1) {
        Send("!{F4}")
        return
    }

    if DllCall("IsHungAppWindow", "ptr", hwnd, "int") {
        Send("!{F4}")
        return
    }

    ; The compositor supplies the thumbnail without asking the target to paint
    ; synchronously. If it cannot supply one, let Windows handle Alt+F4.
    animGui := 0
    thumb := 0
    try {
        animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "GravityCloseAnim")
        animGui.BackColor := "EEFFFF"
        WinSetTransColor("EEFFFF", animGui.Hwnd)
        hr := DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", animGui.Hwnd, "ptr", hwnd, "ptr*", &thumb, "int")
        if (hr != 0 || !thumb)
            throw Error("Could not register a gravity close thumbnail")
        if (RS_UpdateDwmThumbnail(thumb, [0, 0, w, h], , 255, true) != 0)
            throw Error("Could not show a gravity close thumbnail")
        animGui.Show("x" x " y" y " w" w " h" h " NoActivate")
    } catch {
        if thumb
            try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", thumb)
        if animGui
            try animGui.Destroy()
        Send("!{F4}")
        return
    }

    try RS_SetAlphaLayer(hwnd, "gravity", 0.0, RS_PRI_ANIM)
    RS_Commit()

    startW := w, startH := h
    startX := x, startY := y

    start := QPC()
    ms := Tune("animGravityMs")
    Cleanup() {
        try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", thumb)
        try animGui.Destroy()
        if DllCall("IsWindow", "ptr", hwnd)
            try RS_ClearAlphaLayer(hwnd, "gravity", RS_PRI_ANIM)
        RS_Commit()
    }

    GravityStep(dt, now) {
        if !DllCall("IsWindow", "ptr", hwnd) {
            Cleanup()
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            Cleanup()
            try PostMessage(0x0112, 0xF060, 0, , hwnd) ; WM_SYSCOMMAND / SC_CLOSE
            return false
        }

        ; Falling under gravity is s = 1/2*a*t^2 - quadratic, not cubic. Cubic made
        ; the window hang almost still and then snap away at the end, which reads as
        ; a stutter rather than a drop. Quadratic is both correct and smoother.
        ease := t * t

        curW := Max(1, Round(startW * (1 - ease * 0.95)))
        curH := Max(1, Round(startH * (1 - ease * 0.95)))

        curX := Round(startX + (startW - curW) / 2)
        curY := Round(startY + ease * (startH * 0.8) + (startH - curH) / 2)

        try {
            animGui.Move(curX, curY, curW, curH)
            alpha := Clamp(Round(255 * (1 - ((t - 0.4) / 0.6))), 0, 255)
            if (RS_UpdateDwmThumbnail(thumb, [0, 0, curW, curH], , alpha) != 0)
                throw Error("Could not move a gravity close thumbnail")
        } catch {
            Cleanup()
            try PostMessage(0x0112, 0xF060, 0, , hwnd)
            return false
        }
        return true
    }

    RegisterAnimation(animKey, GravityStep)
}

; Gated in the hotkey criteria rather than re-sending #d from the body. With the
; feature off the key is simply not claimed, so Windows' own show-desktop runs -
; CLAUDE.md lists Win+D as deliberately not touched.
#HotIf CurtainDropEnabled || CurtainDropped
#!d::ToggleCurtain()
#HotIf
