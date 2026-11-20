global TrayIcons := Map()
global TrayIdToHwnd := Map()
global NextTrayIconId := 1

TrayIconClick(wParam, lParam, msg, hwnd) {
    global TrayIdToHwnd
    if (lParam == 0x0202) {
        if TrayIdToHwnd.Has(wParam)
            RestoreFromTray(TrayIdToHwnd[wParam])
    }
}

AddTrayNotifyIcon(uid, title, hIcon) {
    cbSize := A_PtrSize == 8 ? 976 : 956
    nid := Buffer(cbSize, 0)
    NumPut("uint", cbSize, nid, 0)
    NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
    NumPut("uint", uid, nid, A_PtrSize == 8 ? 16 : 8)
    NumPut("uint", 0x7, nid, A_PtrSize == 8 ? 20 : 12)
    NumPut("uint", 0x1000, nid, A_PtrSize == 8 ? 24 : 16)
    NumPut("ptr", hIcon, nid, A_PtrSize == 8 ? 32 : 20)
    StrPut(SubStr(title, 1, 63), nid.Ptr + (A_PtrSize == 8 ? 40 : 24), "UTF-16")
    return DllCall("shell32\Shell_NotifyIconW", "uint", 0, "ptr", nid)
}

DeleteTrayNotifyIcon(uid) {
    cbSize := A_PtrSize == 8 ? 976 : 956
    nid := Buffer(cbSize, 0)
    NumPut("uint", cbSize, nid, 0)
    NumPut("ptr", A_ScriptHwnd, nid, A_PtrSize == 8 ? 8 : 4)
    NumPut("uint", uid, nid, A_PtrSize == 8 ? 16 : 8)
    return DllCall("shell32\Shell_NotifyIconW", "uint", 2, "ptr", nid)
}

RemoveTrayIcon(hwnd) {
    global TrayIcons, TrayIdToHwnd
    if !TrayIcons.Has(hwnd)
        return false
    info := TrayIcons[hwnd]
    DeleteTrayNotifyIcon(info.id)
    TrayIcons.Delete(hwnd)
    if TrayIdToHwnd.Has(info.id)
        TrayIdToHwnd.Delete(info.id)
    return true
}

ReAddAllTrayIcons() {
    global TrayIcons
    for hwnd, info in TrayIcons.Clone() {
        if !DllCall("IsWindow", "ptr", hwnd) {
            RemoveTrayIcon(hwnd)
            continue
        }
        hIcon := info.hIcon
        if !hIcon
            hIcon := DllCall("LoadIcon", "ptr", 0, "ptr", 32512, "ptr")
        AddTrayNotifyIcon(info.id, info.title, hIcon)
    }
}

; WM_GETICON, asked politely. A plain SendMessage to a foreign window blocks
; until that window's thread pumps messages - so a hung ("Not Responding") app
; froze this whole process, every timer and every hotkey with it, forever.
; SMTO_ABORTIFHUNG plus a short timeout costs us a default icon at worst.
AskWindowIcon(hwnd) {
    static ICON_SMALL2 := 2, ICON_BIG := 1, GCLP_HICON := -14
    for which in [ICON_SMALL2, ICON_BIG] {
        res := 0
        ok := DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x7F
            , "ptr", which, "ptr", 0, "uint", 2, "uint", 100, "ptr*", &res)
        if (ok && res)
            return res
    }
    ; Class icon needs no cooperation from the target thread at all.
    try {
        if (A_PtrSize == 8)
            return DllCall("GetClassLongPtrW", "ptr", hwnd, "int", GCLP_HICON, "ptr")
        return DllCall("GetClassLongW", "ptr", hwnd, "int", GCLP_HICON, "uint")
    }
    return 0
}

HideToTray(hwnd := 0) {
    global TrayMinimizeEnabled, TrayIcons, TrayIdToHwnd, NextTrayIconId
    if (!TrayMinimizeEnabled)
        return
        
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd || !IsRestorable(hwnd) || TrayIcons.Has(hwnd)
        return
        
    title := "Hidden Window"
    try title := WinGetTitle(hwnd)
    if (title == "")
        title := "Hidden Window"

    hIcon := AskWindowIcon(hwnd)
    if !hIcon
        hIcon := DllCall("LoadIcon", "ptr", 0, "ptr", 32512, "ptr")

    uid := NextTrayIconId
    NextTrayIconId += 1

    if !AddTrayNotifyIcon(uid, title, hIcon)
        return
    
    TrayIcons[hwnd] := {id: uid, title: title, hIcon: hIcon}
    TrayIdToHwnd[uid] := hwnd
    try WinHide(hwnd)
    if (!DllCall("IsWindow", "ptr", hwnd) || DllCall("IsWindowVisible", "ptr", hwnd))
        RemoveTrayIcon(hwnd)
}

RestoreFromTray(hwnd, activate := true) {
    global TrayIcons
    if !TrayIcons.Has(hwnd)
        return false
    if !DllCall("IsWindow", "ptr", hwnd) {
        RemoveTrayIcon(hwnd)
        return false
    }
    try WinShow(hwnd)
    if !DllCall("IsWindowVisible", "ptr", hwnd)
        return false
    RemoveTrayIcon(hwnd)
    if activate
        try WinActivate(hwnd)
    return true
}

global BossKeyActive := false

global BossKeyWindows := []

ToggleBossKey() {
    global BossKeyActive, BossKeyWindows, BossKeyEnabled
    ; Re-entry here is the most damaging of any toggle in the file: a second
    ; press during the WinGetList/WinHide loop would start a fresh BossKeyWindows
    ; array and the first pass's hidden windows would have no record left at all.
    static busy := false
    if busy
        return
    ; Only the HIDE direction is gated. Gating both meant that turning the feature
    ; off while it was active left every window on the desktop hidden with no way
    ; to get them back short of quitting - the one path that must always work is
    ; the one that undoes what we already did.
    if (!BossKeyEnabled && !BossKeyActive)
        return
    busy := true
    try {

    if (BossKeyActive) {
        for hwnd in BossKeyWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                try WinShow(hwnd)
        }
        BossKeyWindows := []
        PanicSetSpeakerMute("BossKey", false)
        BossKeyActive := false
        ; Coming back only. On the way IN this mutes the system on purpose,
        ; so a sound announcing it would be exactly the wrong thing.
        PlayHotkeySound("alert")
    } else {
        BossKeyActive := true
        PanicSetSpeakerMute("BossKey", true)
        
        hwnds := WinGetList()
        BossKeyWindows := []
        ownPid := DllCall("GetCurrentProcessId", "uint")

        for hwnd in hwnds {
            if (!BossKeyActive)
                break
            cls := ""
            try cls := WinGetClass(hwnd)
            ; Shell_SecondaryTrayWnd is the taskbar on every non-primary monitor.
            ; Hiding it left those taskbars gone for good if this process died
            ; while Boss Key was active.
            if (!cls || IsShellSurface(hwnd, cls) || IsCloaked(hwnd))
                continue

            ; Our own overlays (active border, monitor dimmers, the OSDs, the
            ; focus vignette) are visible top-level windows too. Hiding them and
            ; showing them back later resurrects overlays whose feature may have
            ; been switched off in between.
            pid := 0
            try pid := WinGetPID(hwnd)
            if (pid == ownPid)
                continue

            BossKeyWindows.Push(hwnd)
            try WinHide(hwnd)
        }

    }
    }
    busy := false
}

global PendingTransMsg := ""
