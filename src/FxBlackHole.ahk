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

