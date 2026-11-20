; Keep each original rectangle through either direction of the animation.
; Restore All and exit can still recover an interrupted return.
ToggleCurtain() {
    global CurtainDropped, CurtainWindows
    Critical
    CurtainDropped := !CurtainDropped

    for hwnd, original in CurtainWindows.Clone() {
        current := CurtainReadRect(hwnd)
        if !current
            continue
        if CurtainDropped
            CurtainDropDown(hwnd, current)
        else
            CurtainBounceUp(hwnd, current, original)
    }
    if !CurtainDropped
        return

    for hwnd in WinGetList() {
        if (CurtainWindows.Has(hwnd) || !IsSnappable(hwnd))
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        current := CurtainReadRect(hwnd)
        if (!current || current.w <= 0 || current.h <= 0)
            continue
        CurtainWindows[hwnd] := current
        CurtainDropDown(hwnd, current)
    }
}

RestoreCurtain() {
    global CurtainDropped, CurtainWindows
    CurtainDropped := false
    saved := CurtainWindows.Clone()
    for hwnd, rect in saved {
        CancelAnimation("Curtain_" hwnd)
        if DllCall("IsWindow", "ptr", hwnd) {
            try RS_SetPos(hwnd, rect.x, rect.y, rect.w, rect.h, RS_PRI_USER)
        }
    }
    RS_Commit()
    for hwnd, rect in saved
        CurtainForgetRestored(hwnd, rect)
}

CurtainReadRect(hwnd) {
    rc := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        return false
    x := NumGet(rc, 0, "int"), y := NumGet(rc, 4, "int")
    return {x: x, y: y, w: NumGet(rc, 8, "int") - x, h: NumGet(rc, 12, "int") - y}
}

CurtainForgetRestored(hwnd, rect) {
    global CurtainDropped, CurtainWindows
    if (CurtainDropped || !CurtainWindows.Has(hwnd) || CurtainWindows[hwnd] != rect)
        return
    current := CurtainReadRect(hwnd)
    if !current {
        if !DllCall("IsWindow", "ptr", hwnd)
            CurtainWindows.Delete(hwnd)
        return
    }
    if (current.x = rect.x && current.y = rect.y && current.w = rect.w && current.h = rect.h)
        CurtainWindows.Delete(hwnd)
}

CurtainDropDown(hwnd, current) {
    global CurtainDropped
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 250
    destY := SysGet(77) + SysGet(79) + 50
    
    DropStep(dt, now) {
        if (!CurtainDropped || !DllCall("IsWindow", "ptr", hwnd))
            return false
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, current.x, destY, -1, -1, RS_PRI_USER)
            return false
        }
        
        ease := t ** 3
        curY := Round(current.y + (destY - current.y) * ease)
        
        RS_SetPos(hwnd, current.x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, DropStep)
}

CurtainBounceUp(hwnd, current, original) {
    global CurtainDropped
    animKey := "Curtain_" hwnd
    CancelAnimation(animKey)
    start := QPC()
    ms := 400
    landingQueued := false
    
    UpStep(dt, now) {
        if CurtainDropped
            return false
        if (landingQueued || !DllCall("IsWindow", "ptr", hwnd)) {
            CurtainForgetRestored(hwnd, original)
            return false
        }
        t := (now - start) / ms
        if (t >= 1) {
            RS_SetPos(hwnd, original.x, original.y, original.w, original.h, RS_PRI_USER)
            landingQueued := true
            return true
        }
        
        c1 := 1.70158
        c3 := c1 + 1
        ease := 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)
        
        curY := Round(current.y + (original.y - current.y) * ease)
        
        RS_SetPos(hwnd, original.x, curY, -1, -1, RS_PRI_USER)
        return true
    }
    Anim_Claim(hwnd, "geom", animKey, UpStep)
}

