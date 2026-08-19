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
; WHEN SWAPPING A REAL WINDOW FOR A BITMAP COPY, SHOW THE COPY BEFORE HIDING THE
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

    ; Maximized and full-screen windows are where PrintWindow costs the most (a
    ; whole-screen bitmap) and where the effect reads as a glitch rather than an
    ; animation, so they close the normal way.
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

    ; Capture window visual
    hbm := 0
    success := false
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    if hdcDest {
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
        if (hbm && hdcMem) {
            oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            ; PW_RENDERFULLCONTENT = 2
            success := DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
            DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
        }
        if hdcMem
            DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    }

    if !success {
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
        Send("!{F4}")
        return
    }

    ; Order matters: put the bitmap copy on screen FIRST, then hide the real
    ; window underneath it. Hiding first left a frame with neither visible - a
    ; black flash of whatever is behind the window, right at the start of the
    ; animation. The copy is pixel-identical and always-on-top, so covering the
    ; original before it disappears is seamless.
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20", "GravityCloseAnim")
    animGui.MarginX := 0, animGui.MarginY := 0
    pic := animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("x" x " y" y " w" w " h" h " NoActivate")

    try RS_SetAlphaLayer(hwnd, "gravity", 0.0, RS_PRI_ANIM)
    RS_Commit()

    startW := w, startH := h
    startX := x, startY := y

    animKey := "Gravity_" animGui.Hwnd
    start := QPC()
    ms := Tune("animGravityMs")
    ; Owns the bitmap and the GUI: whichever way this animation ends, both are
    ; released exactly once. The bitmap used to leak on every path except a clean
    ; finish - one 8 MB screen-compatible bitmap per Alt+F4.
    finished := false
    Cleanup() {
        if finished
            return
        finished := true
        gh := 0
        try gh := animGui.Hwnd
        try animGui.Destroy()
        if gh
            RS_RemoveHwnd(gh)      ; our own GUIs raise no shell destroy event
        if hbm
            DllCall("DeleteObject", "ptr", hbm)
    }

    GravityStep(dt, now) {
        if !DllCall("IsWindow", "ptr", animGui.Hwnd) {
            Cleanup()
            return false
        }

        t := (now - start) / ms
        if (t >= 1) {
            Cleanup()
            try PostMessage(0x0010, 0, 0, , hwnd) ; WM_CLOSE
            SetTimer(CheckGravityClose.Bind(hwnd), -400)
            return false
        }

        ; Falling under gravity is s = 1/2*a*t^2 - quadratic, not cubic. Cubic made
        ; the window hang almost still and then snap away at the end, which reads as
        ; a stutter rather than a drop. Quadratic is both correct and smoother.
        ease := t * t

        curW := Round(startW * (1 - ease * 0.95))
        curH := Round(startH * (1 - ease * 0.95))

        curX := Round(startX + (startW - curW) / 2)
        curY := Round(startY + ease * (startH * 0.8) + (startH - curH) / 2)

        try {
            animGui.Move(curX, curY, curW, curH)
            pic.Move(0, 0, curW, curH)

            if (t > 0.4) {
                alpha := Clamp(Round(255 * (1 - ((t - 0.4) / 0.6))), 0, 255)
                RS_SetAlpha(animGui.Hwnd, alpha, RS_PRI_ANIM)
            }
        }
        return true
    }

    RegisterAnimation(animKey, GravityStep)
}

; The window refused (or has not yet processed) WM_CLOSE - a "Save changes?"
; prompt, typically. Give it its opacity back, and actually commit: without the
; commit the window stayed at alpha 0, alive and focused but invisible.
CheckGravityClose(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    try RS_ClearAlphaLayer(hwnd, "gravity", RS_PRI_ANIM)
    RS_Commit()
}


; Gated in the hotkey criteria rather than re-sending #d from the body. With the
; feature off the key is simply not claimed, so Windows' own show-desktop runs -
; CLAUDE.md lists Win+D as deliberately not touched.
#HotIf CurtainDropEnabled
#!d:: {
    global CurtainDropped, CurtainWindows

    if (CurtainDropped) {
        CurtainDropped := false
        for hwnd, rect in CurtainWindows {
            if DllCall("IsWindow", "ptr", hwnd) {
                CurtainBounceUp(hwnd, rect.x, rect.y, rect.w, rect.h)
            }
        }
        CurtainWindows := Map()
    } else {
        CurtainDropped := true
        CurtainWindows := Map()
        
        for hwnd in WinGetList() {
            if !IsSnappable(hwnd)
                continue
            if !DllCall("IsWindowVisible", "ptr", hwnd)
                continue
                
            try WinGetPos(&x, &y, &w, &h, hwnd)
            catch
                continue
                
            if (w == 0 || h == 0)
                continue
                
            CurtainWindows[hwnd] := {x: x, y: y, w: w, h: h}
            CurtainDropDown(hwnd, x, y, w, h)
        }
    }
}
#HotIf

; Bye() calls this. CurtainWindows is the ONLY record of where these windows came
; from, and dropping them parks every one of them below the screen - so exiting
; while the curtain is down used to leave the whole desktop off-screen with
; nothing anywhere that could put it back.
RestoreCurtain() {
    global CurtainDropped, CurtainWindows
    for hwnd, rect in CurtainWindows {
        if DllCall("IsWindow", "ptr", hwnd) {
            try CancelAnimation("Curtain_" hwnd)
            try RS_SetPos(hwnd, rect.x, rect.y, rect.w, rect.h, RS_PRI_USER)
        }
    }
    CurtainWindows := Map()
    CurtainDropped := false
}

CurtainDropDown(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 250
    destY := A_ScreenHeight + 50
    
    DropStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        
        ease := t ** 3
        curY := Round(y + (destY - y) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, DropStep)
}

CurtainBounceUp(hwnd, x, y, w, h) {
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    startY := A_ScreenHeight + 50
    
    UpStep(dt, now) {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, x, y, -1, -1, RS_PRI_USER)
            return false
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        curY := Round(startY + (y - startY) * ease)
        
        RS_SetPos(hwnd, x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, UpStep)
}

#HotIf CarouselAltTabEnabled && !CarouselActive
*!Tab:: {
    global CarouselActive, CarouselWindows, CarouselIndex, Thumbnails, CarouselAngleOffset, CarouselGui
    CarouselActive := true
    CarouselWindows := []
    Thumbnails := []
    CarouselIndex := 1
    CarouselAngleOffset := 0
    
    for hwnd in WinGetList() {
        if !IsSnappable(hwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        CarouselWindows.Push(hwnd)
    }
    if CarouselWindows.Length == 0 {
        CarouselActive := false
        Send("!{Tab}")
        return
    }
    
    CarouselGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    CarouselGui.BackColor := "111111"
    CarouselGui.Show("w" A_ScreenWidth " h" A_ScreenHeight " x0 y0")
    RS_SetAlpha(CarouselGui.Hwnd, 220, RS_PRI_USER)
    RS_Commit()
    for hwnd in CarouselWindows {
        thumbId := 0
        DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", CarouselGui.Hwnd, "ptr", hwnd, "ptr*", &thumbId)
        Thumbnails.Push(thumbId)
    }
    RegisterAnimation("Carousel", CarouselCallback)
}
#HotIf

#HotIf CarouselActive
*!Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex++
    if (CarouselIndex > CarouselWindows.Length)
        CarouselIndex := 1
    CarouselAngleOffset += 1
}
*!+Tab:: {
    global CarouselIndex, CarouselWindows, CarouselAngleOffset
    CarouselIndex--
    if (CarouselIndex < 1)
        CarouselIndex := CarouselWindows.Length
    CarouselAngleOffset -= 1
}
; Both Alt keys, plus Escape. The opening hotkey is *!Tab, which fires on either
; Alt - so closing on LAlt alone meant that opening the carousel with RAlt left a
; full-screen AlwaysOnTop window up, a 16 ms timer running, and #HotIf
; CarouselActive swallowing !Tab and !+Tab. Alt+Tab itself was then dead and the
; only way out was Task Manager.
~LAlt up::CloseCarousel(true)
~RAlt up::CloseCarousel(true)
~Esc::CloseCarousel(false)
#HotIf

CloseCarousel(activateChoice) {
    global CarouselActive, CarouselGui, CarouselWindows, CarouselIndex, Thumbnails
    if (!CarouselActive)
        return
    CarouselActive := false
    CancelAnimation("Carousel")

    for thumbId in Thumbnails {
        try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", thumbId)
    }
    Thumbnails := []

    ; The chosen window can close while the carousel is open, and the index can
    ; be stale if the list was rebuilt - neither may throw out of a hotkey.
    hwnd := 0
    if (CarouselIndex >= 1 && CarouselIndex <= CarouselWindows.Length)
        hwnd := CarouselWindows[CarouselIndex]

    if (CarouselGui) {
        try RS_RemoveHwnd(CarouselGui.Hwnd)
        try CarouselGui.Destroy()
    }
    CarouselGui := ""

    if (activateChoice && hwnd && DllCall("IsWindow", "ptr", hwnd))
        try WinActivate(hwnd)
}

CarouselCallback(dt, now) {
    global CarouselGui, CarouselWindows, Thumbnails, CarouselIndex, CarouselAngleOffset, CarouselActive
    if (!CarouselActive)
        return false
        
    if (CarouselAngleOffset > 0)
        CarouselAngleOffset *= 0.8
    else if (CarouselAngleOffset < 0)
        CarouselAngleOffset *= 0.8
        
    if (Abs(CarouselAngleOffset) < 0.05)
        CarouselAngleOffset := 0
        
    num := CarouselWindows.Length
    centerX := A_ScreenWidth / 2
    centerY := A_ScreenHeight / 2
    radiusX := A_ScreenWidth * 0.3
    radiusY := A_ScreenHeight * 0.1
    
    PI := 3.141592653589793
    angleStep := (2 * PI) / num
    
    loop num {
        idx := A_Index
        dist := idx - CarouselIndex
        if (dist > num / 2)
            dist -= num
        else if (dist < -num / 2)
            dist += num
            
        angle := (dist + CarouselAngleOffset) * angleStep + (PI / 2)
        
        x := centerX + Cos(angle) * radiusX
        y := centerY + Sin(angle) * radiusY
        scale := 0.5 + (Sin(angle) + 1) * 0.25
        
        w := Round(400 * scale)
        h := Round(250 * scale)
        px := Round(x - w/2)
        py := Round(y - h/2)
        
        RS_UpdateDwmThumbnail(Thumbnails[idx], [px, py, w, h], "", (idx == CarouselIndex) ? 255 : Round(100 * scale), true, false)
    }
    return true
}

; ----------------------------------------------------------------------------
; 5. Black Hole Delete
; ----------------------------------------------------------------------------
global ActiveDeleteGuis := Map()

#HotIf BlackHoleDeleteEnabled && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class WorkerW") || WinActive("ahk_class Progman")) && A_Cursor != "IBeam"
~Delete:: {
    hwnd := WinExist("A")
    TriggerBlackHoleDelete(hwnd)
}
#HotIf

TriggerBlackHoleDelete(hwnd) {
    global ActiveDeleteGuis
    MouseGetPos(&mx, &my)
    
    guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
    guiObj.BackColor := "EEFFFF"
    
    thumb := 0
    DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
    
    size := 140
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    srcX := mx - wx - (size/2)
    srcY := my - wy - (size/2)
    
    guiObj.Show("NA x" (mx - size/2) " y" (my - size/2) " w" size " h" size)
    WinSetTransColor("EEFFFF", guiObj.Hwnd)
    
    animKey := "DeleteHole_" . guiObj.Hwnd
    start := QPC()
    ms := 600
    
    startX := mx - size/2
    startY := my - size/2
    
    prim := MonitorGetPrimary()
    MonitorGet(prim, &mL, &mT, &mR, &mB)
    destX := mL + 40
    destY := mT + 40
    
    distX := Abs(destX - startX)
    distY := Abs(destY - startY)
    
    ActiveDeleteGuis[animKey] := {gui: guiObj, thumb: thumb}
    
    Step(dt, now) {
        if (!ActiveDeleteGuis.Has(animKey))
            return false
            
        t := (now - start) / ms
        if (t >= 1) {
            CleanDeleteGui(animKey)
            return false
        }
        
        ease := t * t * t 
        
        curX := startX + (destX - startX) * ease
        curY := startY + (destY - startY) * ease
        
        if (distX > distY) {
            curW := Round(size * (1 + ease * 2)) 
            curH := Round(size * (1 - ease * 0.8)) 
        } else {
            curW := Round(size * (1 - ease * 0.8)) 
            curH := Round(size * (1 + ease * 2)) 
        }
        
        scaleDown := 1 - ease
        curW := Round(curW * scaleDown)
        curH := Round(curH * scaleDown)
        
        if (curW < 1)
            curW := 1
        if (curH < 1)
            curH := 1
            
        DllCall("SetWindowPos", "ptr", guiObj.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", curW, "int", curH, "uint", 0x14) 
        
        ; See the struct layout note in UpdateCarousel.
        alpha := Round(255 * (1 - ease))
        RS_UpdateDwmThumbnail(thumb, [0, 0, curW, curH], [Round(srcX), Round(srcY), size, size], alpha, true, true)
        return true
    }
    RegisterAnimation(animKey, Step)
}

CleanDeleteGui(animKey) {
    global ActiveDeleteGuis
    if (ActiveDeleteGuis.Has(animKey)) {
        obj := ActiveDeleteGuis[animKey]
        DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", obj.thumb)
        obj.gui.Destroy()
        ActiveDeleteGuis.Delete(animKey)
    }
}

; ----------------------------------------------------------------------------
; 6. Shatter to Close & Black Hole Minimize
; ----------------------------------------------------------------------------

TriggerBlackHoleMinimize(hwnd) {
    if !hwnd
        return
    try {
        if (WinGetMinMax(hwnd) != 0)
            return ; Don't animate maximized windows to save performance
        WinGetPos(&x, &y, &w, &h, hwnd)
    } catch {
        return
    }
    if (w < 1 || h < 1)
        return
        
    hbm := 0
    hdcDest := DllCall("GetDC", "ptr", 0, "ptr")
    if hdcDest {
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcDest, "int", w, "int", h, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcDest, "ptr")
        if (hbm && hdcMem) {
            oldObj := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
            DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
            DllCall("SelectObject", "ptr", hdcMem, "ptr", oldObj)
        }
        if hdcMem
            DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcDest)
    }
    if !hbm
        return
        
    animGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
    animGui.MarginX := 0, animGui.MarginY := 0
    animGui.Add("Picture", "x0 y0 w" w " h" h, "HBITMAP:" hbm)
    animGui.Show("NA x" x " y" y " w" w " h" h)
    
    animKey := "MinHole_" . animGui.Hwnd
    start := QPC()
    ms := 300
    
    startX := x
    startY := y
    destX := Round(A_ScreenWidth / 2)
    destY := Round(A_ScreenHeight)
    
    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            animGui.Destroy()
            DllCall("DeleteObject", "ptr", hbm)
            return false
        }
        
        ease := t * t * t 
        
        curX := startX + (destX - startX - w/2) * ease
        curY := startY + (destY - startY - h/2) * ease
        
        scaleDown := 1 - ease
        curW := Round(w * scaleDown)
        curH := Round(h * scaleDown)
        
        if (curW < 1)
            curW := 1
        if (curH < 1)
            curH := 1
            
        DllCall("SetWindowPos", "ptr", animGui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", curW, "int", curH, "uint", 0x14)
        
        WinSetTransparent(Round(255 * scaleDown), animGui.Hwnd)
        return true
    }
    RegisterAnimation(animKey, Step)
}

#HotIf ShatterEnabled
+!F4:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        TriggerShatterClose(hwnd)
    }
}
#HotIf

TriggerShatterClose(hwnd) {
    global ActiveShatters
    
    try WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    catch
        return
        
    gridX := 4
    gridY := 4
    pieceW := ww / gridX
    pieceH := wh / gridY
    
    shards := []
    
    loop gridX {
        col := A_Index
        loop gridY {
            row := A_Index
            
            guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20")
            guiObj.BackColor := "EEFFFF"
            WinSetTransColor("EEFFFF", guiObj.Hwnd)
            
            thumb := 0
            DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb)
            
            srcX := (col - 1) * pieceW
            srcY := (row - 1) * pieceH
            
            cx := wx + srcX + pieceW/2
            cy := wy + srcY + pieceH/2
            
            winCx := wx + ww/2
            winCy := wy + wh/2
            
            vx := (cx - winCx) * (Random(15, 40) / 100) 
            vy := (cy - winCy) * (Random(15, 40) / 100) - Random(5, 20) 
            
            spinW := Random(1, 8) * 0.1
            spinH := Random(1, 8) * 0.1
            
            shards.Push({gui: guiObj, thumb: thumb, x: wx + srcX, y: wy + srcY, w: pieceW, h: pieceH, srcX: srcX, srcY: srcY, vx: vx, vy: vy, spinW: spinW, spinH: spinH})
        }
    }
    
    animKey := "Shatter_" . hwnd

    ; Every other animation producer in this file cancels its own key before
    ; re-registering. Without it a second Shift+Alt+F4 on the same window
    ; overwrote the map entry and orphaned the first batch of 16 Guis and 16 DWM
    ; thumbnails, with nothing left holding a reference that could free them.
    CancelAnimation(animKey)
    CleanShatter(animKey)

    ; The real window is parked far off-screen so only the shards are visible.
    ; wx/wy go into the map BEFORE that happens: this is the only record of where
    ; it belongs, and Bye() needs it to put the window back if we exit mid-flight.
    ActiveShatters[animKey] := {shards: shards, hwnd: hwnd, x: wx, y: wy}

    RS_SetPos(hwnd, -19999, wy, -1, -1, RS_PRI_USER)

    start := QPC()
    ms := 1000

    Step(dt, now) {
        t := (now - start) / ms
        if (t >= 1) {
            CleanShatter(animKey)
            if (DllCall("IsWindow", "ptr", hwnd)) {
                try RS_SetPos(hwnd, wx, wy, -1, -1, RS_PRI_USER)
                try WinClose(hwnd)
            }
            return false
        }
        
        alpha := Round(255 * (1 - (t ** 2))) 
        
        for s in shards {
            s.vy += 1.2 ; Gravity
            s.x += s.vx
            s.y += s.vy
            
            curW := s.w * Abs(Cos(t * 15 * s.spinW))
            curH := s.h * Abs(Cos(t * 15 * s.spinH))
            
            if (curW < 1)
                curW := 1
            if (curH < 1)
                curH := 1
                
            curX := s.x + (s.w - curW)/2
            curY := s.y + (s.h - curH)/2
            
            DllCall("SetWindowPos", "ptr", s.gui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", Round(curW), "int", Round(curH), "uint", 0x14 | 0x40) 
            
            ; See the struct layout note in UpdateCarousel.
            RS_UpdateDwmThumbnail(s.thumb, [0, 0, Round(curW), Round(curH)], [Round(s.srcX), Round(s.srcY), s.w, s.h], alpha, true, true)
        }
        return true
    }
    
    RegisterAnimation(animKey, Step)
}

CleanShatter(animKey) {
    global ActiveShatters
    if (ActiveShatters.Has(animKey)) {
        obj := ActiveShatters[animKey]
        for s in obj.shards {
            DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", s.thumb)
            s.gui.Destroy()
        }
        ActiveShatters.Delete(animKey)
    }
}

; Bye() calls this. TriggerShatterClose parks the real window at x = -19999 and
; the ONLY thing that ever moves it back is the animation's final frame - which
; never arrives if the callback throws (the scheduler silently deregisters it) or
; if we exit mid-flight. The window was then alive, invisible and unrecoverable.
RestoreShatters() {
    global ActiveShatters
    for animKey, obj in ActiveShatters.Clone() {
        if (DllCall("IsWindow", "ptr", obj.hwnd))
            try RS_SetPos(obj.hwnd, obj.x, obj.y, -1, -1, RS_PRI_USER)
        try CancelAnimation(animKey)
        try CleanShatter(animKey)
    }
}
