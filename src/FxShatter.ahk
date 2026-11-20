#HotIf ShatterEnabled
+!F4:: {
    hwnd := WinExist("A")
    if (hwnd && IsRestorable(hwnd)) {
        TriggerShatterClose(hwnd)
    }
}
#HotIf

TriggerShatterClose(hwnd) {
    global ActiveShatters, FRAME_MS

    animKey := "Shatter_" . hwnd
    if ActiveShatters.Has(animKey)
        return

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
            try WinSetTransColor("EEFFFF", guiObj.Hwnd)
            
            thumb := 0
            hr := DllCall("Dwmapi\DwmRegisterThumbnail", "ptr", guiObj.Hwnd, "ptr", hwnd, "ptr*", &thumb, "int")
            if (hr != 0 || !thumb) {
                try guiObj.Destroy()
                continue
            }
            
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

    if !shards.Length
        return

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
                RS_Commit()
                try WinClose(hwnd)
            }
            return false
        }
        
        steps := (dt > 0 ? dt : FRAME_MS) / FRAME_MS
        alpha := Round(255 * (1 - (t ** 2))) 
        
        for s in shards {
            s.vy += 1.2 * steps ; Gravity
            s.x += s.vx * steps
            s.y += s.vy * steps
            
            curW := s.w * Abs(Cos(t * 15 * s.spinW))
            curH := s.h * Abs(Cos(t * 15 * s.spinH))
            
            if (curW < 1)
                curW := 1
            if (curH < 1)
                curH := 1
                
            curX := s.x + (s.w - curW)/2
            curY := s.y + (s.h - curH)/2
            
            if DllCall("IsWindow", "ptr", s.gui.Hwnd) {
                try DllCall("SetWindowPos", "ptr", s.gui.Hwnd, "ptr", -1, "int", Round(curX), "int", Round(curY), "int", Round(curW), "int", Round(curH), "uint", 0x14 | 0x40)
                ; See the DWM_THUMBNAIL_PROPERTIES layout in RS_UpdateDwmThumbnail.
                try RS_UpdateDwmThumbnail(s.thumb, [0, 0, Round(curW), Round(curH)], [Round(s.srcX), Round(s.srcY), s.w, s.h], alpha, true, true)
            }
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
            if (s.thumb)
                try DllCall("Dwmapi\DwmUnregisterThumbnail", "ptr", s.thumb)
            gh := 0
            try gh := s.gui.Hwnd
            try s.gui.Destroy()
            if gh
                RS_RemoveHwnd(gh)
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
    RS_Commit()
}
