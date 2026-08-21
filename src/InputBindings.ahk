; Input bindings - every keyboard and mouse binding in the program, in one place.
;
; Function definitions and global initialisers only, no top-level statements.
;
; EVERY GLOBAL HOTKEY IS Shift+Alt+<key>. There is no second tier. The old
; Win+Ctrl scheme was collapsed into this one chord because it kept colliding
; with shortcuts Windows had already claimed - several of them accessibility
; features, which is not a trade this program gets to make on the user's behalf.
; docs\HOTKEYS.md is the source of truth for the table; do not re-derive it.
;
; A BINDING DELEGATES, IT DOES NOT IMPLEMENT. Each hotkey calls a named function
; that the tray menu and the settings window also call, so the three can never
; drift. The one exception is +!o in FeatureToggles.ahk, which has no function
; to delegate to because the binding is the whole feature.
;
; #HotIf IS POSITIONAL, NOT SCOPED, AND BLEEDS ACROSS #Include BOUNDARIES. This
; file opens with a bare #HotIf and ends with one, and every context it opens in
; between is closed. A module that leaves one open silently applies that context
; to the first hotkeys of the next included file. scripts\Check-Split.ps1 check 5
; enforces the balance; the opening bare directive is on you.
;
; Not every binding is here. A hotkey whose body IS its feature stays with that
; feature so the two cannot be moved apart: gravity close and shatter close,
; curtain drop, carousel Alt-Tab, black-hole delete and privacy blur. Each of
; those modules brackets its own context.
;
; The keypad tiles are bound ONLY under their digit names (Numpad7..Numpad0).
; With NumLock OFF the keypad sends the navigation names instead and the whole
; tiling gesture is dead - Shift+Alt+Up/Down are the only NumLock-independent
; layout keys.

; =========================================================== Hotkeys ===========================================================
#HotIf !GameModeActive
+!w::ShowWin()
+!s::ToggleSnap()
+!m::ToggleMemory()
+!f::ToggleFocusMode()
+!h::HideToTray()
+!r::ToggleRollUp()
+!e::ToggleBreathing()
+!Esc::ToggleBossKey()

#HotIf !GameModeActive && (AlwaysOnBottomEnabled
)
+!b::ToggleAlwaysOnBottom()
#HotIf !GameModeActive

#HotIf !GameModeActive && (ProximityGhostEnabled
)
+!g::ToggleGhostMode()
#HotIf !GameModeActive
*+!WheelUp::ChangeTransparency(1)
*+!WheelDown::ChangeTransparency(-1)

#HotIf !GameModeActive && (LivePipEnabled
)
+!p::TogglePiP()
#HotIf !GameModeActive

; ----- Window layout ---------------------------------------------------------
; Shift+Alt+<key> acts on the active window. 
; All primary features and layout commands are mapped to this 3-key chord.
+!k::CenterWindow()
+!u::CycleWindowSize()
+!n::MoveToNextMonitor()
+!z::UndoLayout()

; 3x3 grid tiling, laid out like the numeric keypad: corners are quarters, 8/2
; are the top and bottom halves, 4/6 the left and right halves, 5 a centred half.
; Both names of every keypad key are bound, because with NumLock OFF the keypad
; sends NumpadHome/NumpadUp/... instead of Numpad7/Numpad8/... - binding only the
; digit names would leave the whole gesture dead for anyone who keeps NumLock off.
+!Numpad7::TileWindow(7)
+!Numpad8::TileWindow(8)
+!Numpad9::TileWindow(9)
+!Numpad4::TileWindow(4)
+!Numpad5::TileWindow(5)
+!Numpad6::TileWindow(6)
+!Numpad1::TileWindow(1)
+!Numpad2::TileWindow(2)
+!Numpad3::TileWindow(3)
+!Numpad0::ToggleMaximize()

; Laptop aliases for the two halves that have no Windows equivalent. The arrow
; keys are only free vertically - Win+Ctrl+Left/Right switch virtual desktops.
+!Up::TileWindow(8)
+!Down::TileWindow(2)

; ----- Utility ---------------------------------------------------------------
+!x::ResetTransparency()
+!y::RestoreAllWindows()
+!F5::Reload()
+!F6::ExitApp()

; ----- Keyboard access to gesture-only features ------------------------------
; Each of these already has a gesture; the gesture stays. A double-tap has to be
; disambiguated from two ordinary shortcuts (see IsDoublePress below), so an
; unambiguous key for the same action is worth having.
#HotIf !GameModeActive && (SpotlightEnabled
)
+!l::ToggleSpotlight()
#HotIf !GameModeActive

#HotIf !GameModeActive && (MicKillSwitchEnabled
)
+!a:: {
    state := ToggleDefaultMic()
    if (state != -1)
        ShowMicOSD(state)
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (QuickLookEnabled && WinActive("ahk_class CabinetWClass")
)
+!q::ToggleQuickLook()
#HotIf !GameModeActive

; ----- Feature toggles: Shift+Alt+<key> ---------------------------------
; These seven flags already persist to settings.ini; before this the only way to
; change one was to open the settings window.
+!c::ToggleHotCorners()
+!v::ToggleActiveBorder()
+!i::ToggleCursorWrap()
+!d::ToggleDimmer()
+!t::ToggleSmartTaskbar()
+!j::ToggleMagneticGroups()
+!Space::ToggleGrabPan()

#HotIf
+!F12::ToggleGameMode()

#HotIf !GameModeActive

; Helper function for modifier key double presses (ignores auto-repeat)
IsDoublePress(Timeout := 400) {
    global LastNonModifierKeyTime
    static lastTriggers := Map()

    if !(A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < Timeout)
        return false

    ; "Was the previous hotkey this same one, recently" is NOT enough on its own.
    ; ~LCtrl up and ~LAlt up fire on every release of those keys, and an ordinary
    ; shortcut like ^c is not a hotkey here - so it never becomes A_PriorHotkey.
    ; Ctrl+C followed by Ctrl+V inside the timeout therefore produced two
    ; consecutive ~LCtrl up firings and looked exactly like a deliberate
    ; double-tap: copy-then-paste opened the Spotlight launcher, and two Alt
    ; shortcuts in a row muted the microphone system-wide.
    ;
    ; A real double-tap has nothing pressed between the two releases. If a
    ; non-modifier key was pressed more recently than the previous release, this
    ; was two shortcuts, not a gesture.
    if (A_TickCount - LastNonModifierKeyTime < A_TimeSincePriorHotkey)
        return false

    last := lastTriggers.Has(A_ThisHotkey) ? lastTriggers[A_ThisHotkey] : 0
    if (A_TickCount - last < Timeout) {
        ; Prevent triple-press from triggering twice
        lastTriggers.Delete(A_ThisHotkey)
        return false
    }
    lastTriggers[A_ThisHotkey] := A_TickCount
    return true
}

#HotIf !GameModeActive && (MicKillSwitchEnabled
)
~LAlt up:: {
    if IsDoublePress() {
        state := ToggleDefaultMic()
        if (state != -1)
            ShowMicOSD(state)
    }
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (SpotlightEnabled
)
~LCtrl up:: {
    if IsDoublePress()
        ToggleSpotlight()
}
~RCtrl up:: {
    if IsDoublePress()
        ToggleSpotlight()
}
#HotIf !GameModeActive

IsSpotlightActive() {
    global SpotlightGui
    return SpotlightGui && WinActive("ahk_id " SpotlightGui.Hwnd)
}

#HotIf !GameModeActive && (IsSpotlightActive()
)
Enter::SpotlightExecute()
Escape::ToggleSpotlight()
#HotIf !GameModeActive

#HotIf !GameModeActive && (QuickLookEnabled && WinActive("ahk_class CabinetWClass") && !IsTypingInExplorer()
)
Space:: {
    if !ToggleQuickLook()
        Send "{Space}"
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (QuickLookEnabled && QuickLookGui && WinActive("ahk_id " QuickLookGui.Hwnd)
)
Space::CloseQuickLook()
Escape::CloseQuickLook()
#HotIf !GameModeActive

IsMouseOverTaskbar() {
    MouseGetPos(,, &hwnd)
    if !hwnd
        return false
    ; Runs inside a #HotIf, so it is evaluated on every wheel and middle-click.
    ; A window destroyed between MouseGetPos and here would otherwise throw
    ; from inside hotkey-criteria evaluation. 'cls' avoids the built-in Class.
    cls := ""
    try cls := WinGetClass(hwnd)
    return (cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd")
}

#HotIf !GameModeActive && (TaskbarScrollEnabled && IsMouseOverTaskbar()
)
WheelUp:: {
    if PremiumVolumeOSDEnabled
        ChangeVolumeOSD(1)
    else
        Send("{Volume_Up}")
}
WheelDown:: {
    if PremiumVolumeOSDEnabled
        ChangeVolumeOSD(-1)
    else
        Send("{Volume_Down}")
}
MButton:: {
    if PremiumVolumeOSDEnabled
        ToggleMuteOSD()
    else
        Send("{Volume_Mute}")
}
#HotIf !GameModeActive

#HotIf !GameModeActive && ((ElasticScrollEnabled || MotionBlurScrollEnabled) && !IsMouseOverTaskbar()
)
~WheelUp::
~WheelDown:: {
    MouseGetPos(,, &hwnd)
    global DragHwnd
    if (DragHwnd == hwnd)
        return
        
    dir := A_ThisHotkey = "~WheelUp" ? 1 : -1
    
    ; Order matters: this runs on EVERY wheel notch anywhere in the system.
    ; IsRestorable is ~6 cross-process queries plus a DWM call; WinGetMinMax is
    ; 0.28 us. Ask the cheap question first and most notches never reach the
    ; expensive one. Both features want the same two facts, so they are gathered
    ; once instead of IsRestorable being paid twice.
    if (!DllCall("IsWindow", "ptr", hwnd))
        return
    try {
        if (WinGetMinMax(hwnd) != 0)
            return
        WinGetPos(&bx, &by, &bw, &bh, hwnd)
    } catch
        return
    if (!IsRestorable(hwnd))
        return

    if (MotionBlurScrollEnabled)
        TriggerMotionBlur(hwnd, dir)

    if (!ElasticScrollEnabled)
        return
    ; A full-screen window has nowhere to lean to, and leaning it would expose
    ; the desktop behind it.
    if (bw >= A_ScreenWidth && bh >= A_ScreenHeight)
        return
    ElasticScroll(hwnd, dir, bx, by)
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (!IsMouseOverTaskbar()
)
~LButton:: {
    global TextMagnifierEnabled, RippleClickEnabled, ElasticDragEnabled
    
    MouseGetPos(&startX, &startY)

    if (RippleClickEnabled) {
        SpawnRipple(startX, startY)
    }

    if (TextMagnifierEnabled) {
        global MagActive, MagStartX, MagStartY
        if (A_Cursor == "IBeam") {
            MagStartX := startX, MagStartY := startY
            MagActive := false
            SetTimer(CheckMagDrag, 16)
        }
    }
    
    if (ElasticDragEnabled) {
        global DragTrailStartX := startX, DragTrailStartY := startY
        global DragTrailActive := false
        SetTimer(CheckElasticDrag, 16)
    }
}
#HotIf !GameModeActive

IsFileDialog(hwnd) {
    if !hwnd
        return false
    ; Evaluated inside a #HotIf, so this runs on the hotkey-criteria thread for
    ; every Ctrl+G press. A window that closed a moment ago must not throw from
    ; in there - same reasoning as IsMouseOverTaskbar.
    cls := ""
    try cls := WinGetClass(hwnd)
    if (cls != "#32770")
        return false
    try {
        ControlGetHwnd("Edit1", hwnd)
        return true
    }
    return false
}

GetActiveExplorerPath() {
    try {
        shell := ComObject("Shell.Application")
        hwnd := WinExist("ahk_class CabinetWClass")
        if !hwnd
            return ""
            
        for window in shell.Windows {
            if (window.HWND == hwnd)
                return window.Document.Folder.Self.Path
        }
    }
    return ""
}

#HotIf !GameModeActive && (QuickFolderJumpEnabled && IsFileDialog(WinExist("A"))
)
^g:: {
    hwnd := WinExist("A")
    path := GetActiveExplorerPath()
    if (path == "") {
        Notify("No open Explorer folder found.")
        return
    }
    
    try {
        oldText := ControlGetText("Edit1", hwnd)
        ControlFocus("Edit1", hwnd)
        ControlSetText(path, "Edit1", hwnd)
        Sleep(50)
        ControlSend("{Enter}", "Edit1", hwnd)
        Sleep(150)
        if (oldText != "")
            ControlSetText(oldText, "Edit1", hwnd)
    }
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (PlainPasteEnabled
)
^!v:: {
    if (A_Clipboard == "")
        return
    ClipSaved := ClipboardAll()
    A_Clipboard := A_Clipboard
    ; ClipWait, not a fixed spin: the round-trip through the clipboard is not
    ; instant, and a busy-wait would block every timer in the process meanwhile.
    ClipWait(1, false)
    Send("^v")
    Sleep(120)
    A_Clipboard := ClipSaved
    ClipSaved := ""
}
#HotIf !GameModeActive

; ====== Morphing Paste ======
global MorphMode := false
global MorphFormats := ["camelCase", "PascalCase", "snake_case", "kebab-case", "UPPERCASE"]
global MorphIndex := 1
global MorphOriginalText := ""

; Morphing is an IDENTIFIER-renaming gesture, not a general clipboard transform:
; every format concatenates words and drops the delimiters, so anything that is
; not already a symbol comes back corrupted - measured, "C:\Program Files\x.exe"
; morphed to "c:\programFiles\x.exe" and "SELECT * FROM t" to "select*FromT".
; A payload longer than this is far more likely to be prose or a document than a
; name, so the gesture declines and pastes normally instead.
;
; It is the cost gate too. One morph of a 54,000 char clipboard measured 16 ms,
; and it runs again on every wheel notch.
global MORPH_MAX_LEN := 512
; Display only. The preview label and its region are sized from the string, and
; an unbounded one asked for a 432,020 px wide region (measured, from a 48,000
; char morph). The clipboard still receives the full text.
global MORPH_PREVIEW_CHARS := 60

MorphString(text, format) {
    ; Two splits, not one. The lower->Upper pattern alone leaves an acronym glued
    ; to the word after it - "HTTPServerError" came out as "httpserverError" -
    ; because there is no lowercase letter before the "S" that starts "Server".
    ; This first pattern breaks a capital run before its LAST capital, which is
    ; the one that belongs to the next word.
    text := RegExReplace(text, "([A-Z]+)([A-Z][a-z])", "$1 $2")
    text := RegExReplace(text, "([a-z])([A-Z])", "$1 $2")
    ; \s, not just a space: a tab or a newline is a word break as much as an
    ; underscore is. Without it a multi-line clipboard morphed to one "word" with
    ; its CRLFs still embedded, so the paste inserted line breaks mid-identifier.
    raw := StrSplit(RegExReplace(Trim(text), "[_\-\s]+", " "), " ")
    ; Empty words are dropped here rather than tolerated in the loop below. A
    ; leading delimiter put "" at index 1, so the first REAL word landed at index
    ; 2 and took the not-first branch: camelCase("_leading") returned "Leading".
    words := []
    for word in raw {
        if (word != "")
            words.Push(word)
    }
    out := ""
    for i, word in words {
        if (format == "camelCase")
            out .= (i == 1) ? StrLower(word) : StrTitle(StrLower(word))
        else if (format == "PascalCase")
            out .= StrTitle(StrLower(word))
        else if (format == "snake_case")
            out .= (i == 1 ? "" : "_") . StrLower(word)
        else if (format == "kebab-case")
            out .= (i == 1 ? "" : "-") . StrLower(word)
        else if (format == "UPPERCASE")
            out .= (i == 1 ? "" : " ") . StrUpper(word)
    }
    return out
}

; One line, whitespace flattened and length capped - see MORPH_PREVIEW_CHARS.
MorphPreviewLine(s) {
    global MORPH_PREVIEW_CHARS
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " ")
    s := StrReplace(s, "`t", " ")
    if (StrLen(s) > MORPH_PREVIEW_CHARS)
        s := SubStr(s, 1, MORPH_PREVIEW_CHARS - 3) . "..."
    return s
}

ShowMorphPreview(fmt, result) {
    global MorphGui, MorphText, MORPH_PREVIEW_CHARS
    line := MorphPreviewLine(result)
    text := fmt . "`n" . line

    if (!IsSet(MorphGui) || !MorphGui) {
        MorphGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x20")
        MorphGui.BackColor := "1E1E1E"
        MorphGui.SetFont("s11 cWhite", "Segoe UI")
        ; No "h24" on the label. It carries TWO lines - the format name and the
        ; result - and a fixed 24 px Static clipped the second one away no matter
        ; what AutoSize did to the window around it. The size is set explicitly
        ; below instead, on every call, because a Static does not re-fit itself
        ; when its .Text is replaced with something longer.
        MorphText := MorphGui.AddText("vMorphText x10 y5 BackgroundTrans", text)
        RS_SetAlpha(MorphGui.Hwnd, 0, RS_PRI_ANIM)
        RS_Commit()
    }
    MorphText.Text := text

    ; ~9 px per character at s11 Segoe UI, and both lines are already capped, so
    ; the widest this can ask for is bounded.
    cols := Max(StrLen(fmt), StrLen(line))
    tw := cols * 9
    th := 44
    MorphText.Move(, , tw, th)
    winW := tw + 20
    winH := th + 10

    CaretGetPos(&cx, &cy)
    if (!cx)
        MouseGetPos(&cx, &cy)

    ; Region before Show, and Show straight to the final coordinates. The first
    ; version showed at AHK's default position and let the queued RS_SetPos drag
    ; the window over on the next frame, which is one frame of a hard-edged panel
    ; sitting in the middle of the screen - the same flash the Spotlight launcher
    ; used to have.
    RS_SetRegion(MorphGui.Hwnd, "0-0 w" winW " h" winH " r8-8", RS_PRI_ANIM)
    RS_Commit()
    MorphGui.Show("NoActivate x" (cx + 10) " y" (cy - winH - 10) " w" winW " h" winH)
    try WinSetAlwaysOnTop(1, MorphGui.Hwnd)
    FadeGui(MorphGui, 220)
}

HideMorphPreview() {
    global MorphGui
    if (IsSet(MorphGui) && MorphGui) {
        guiObj := MorphGui
        MorphGui := ""
        FadeGui(guiObj, 0, 0, true)
    }
}

#HotIf !GameModeActive && (MorphingPasteEnabled
)
$^v:: {
    global MorphMode, MorphIndex, MorphOriginalText, MorphFormats, MORPH_MAX_LEN
    ; #MaxThreadsPerHotkey is 2 process-wide (WindowTweaks.ahk), and both KeyWaits
    ; below are interruptible - verified with a harness: a second Ctrl+V reaches
    ; this handler while the first thread is still parked, and key auto-repeat
    ; alone is enough to produce one. Two threads then ran ClipboardAll() ->
    ; overwrite -> restore against each other, and whichever snapshotted second
    ; restored the MORPHED text as the user's clipboard, permanently.
    static busy := false
    if busy
        return
    busy := true
    try {
        ; Released inside 150 ms: an ordinary paste, and the gesture stays out of
        ; the way. Note this does mean a paste lands on key-up rather than
        ; key-down, so hold-to-repeat paste is not available while this is on.
        if KeyWait("v", "T0.15") {
            Send("^{v}")
            TriggerPasteFeedback()
            return
        }

        MorphOriginalText := A_Clipboard
        ; "" covers both an empty clipboard and an image/binary one, which
        ; A_Clipboard reports as blank. The length cap covers the other end - see
        ; MORPH_MAX_LEN. Either way, fall back to the paste the user asked for
        ; rather than swallowing the keypress.
        if (MorphOriginalText == "" || StrLen(MorphOriginalText) > MORPH_MAX_LEN) {
            KeyWait("v")
            Send("^{v}")
            TriggerPasteFeedback()
            return
        }

        MorphMode := true
        MorphIndex := 1
        ShowMorphPreview(MorphFormats[MorphIndex], MorphString(MorphOriginalText, MorphFormats[MorphIndex]))
        KeyWait("v")
        MorphMode := false
        HideMorphPreview()

        ClipSaved := ClipboardAll()
        A_Clipboard := MorphString(MorphOriginalText, MorphFormats[MorphIndex])
        Send("^{v}")
        Sleep(100)
        A_Clipboard := ClipSaved
        ClipSaved := ""
        TriggerPasteFeedback()
    } finally {
        ; Both of these unconditionally, on every exit path including a throw:
        ; MorphMode left true would leave the wheel hijacked for good, and busy
        ; left true would kill Ctrl+V for the rest of the session.
        MorphMode := false
        busy := false
    }
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (MorphMode
)
WheelUp:: {
    global MorphIndex, MorphFormats, MorphOriginalText
    MorphIndex--
    if (MorphIndex < 1)
        MorphIndex := MorphFormats.Length
    ShowMorphPreview(MorphFormats[MorphIndex], MorphString(MorphOriginalText, MorphFormats[MorphIndex]))
}
WheelDown:: {
    global MorphIndex, MorphFormats, MorphOriginalText
    MorphIndex++
    if (MorphIndex > MorphFormats.Length)
        MorphIndex := 1
    ShowMorphPreview(MorphFormats[MorphIndex], MorphString(MorphOriginalText, MorphFormats[MorphIndex]))
}
#HotIf !GameModeActive

; ====== Clipboard Append & Copy Feedback ======
global OldClipboard := ""
global LastCtrlC_Time := 0

; CLIP_BACKUP_MS must stay LONGER than CLIP_DOUBLE_MS, and that ordering is the
; whole mechanism rather than a safety margin.
;
; A single Ctrl+C arms the backup timer, and the timer is what records "the
; clipboard as it stands" so that a later double-tap has something to append TO.
; A double-tap therefore has to CANCEL that timer while it is still pending,
; which only works if the backup fires after the double-tap window has closed.
;
; With the original 200 ms against a 400 ms window, a tap gap anywhere in 200-400
; ms found the timer already fired: OldClipboard had been overwritten with the
; selection just copied, and the append produced "B\r\nB" instead of "A\r\nB".
global CLIP_DOUBLE_MS := 400
global CLIP_BACKUP_MS := 450

SaveOldClipboard() {
    global OldClipboard
    OldClipboard := A_Clipboard
}

#HotIf !GameModeActive && (ClipboardAppendEnabled || CopyFeedbackEnabled
)
~^c:: {
    global OldClipboard, LastCtrlC_Time, CLIP_DOUBLE_MS, CLIP_BACKUP_MS
    ; Same re-entrancy hazard as $^v, and worse here because the body is a
    ; read-modify-write of the clipboard wrapped around an interruptible Sleep:
    ; a third Ctrl+C landing inside that Sleep appended the same selection twice.
    static busy := false
    if busy
        return
    busy := true
    isDouble := false
    try {
        ; LastCtrlC_Time has to be non-zero as well as recent. A_TickCount is time
        ; since boot, so within the first 400 ms of a session "A_TickCount - 0" is
        ; itself inside the window and the very first Ctrl+C read as a double-tap.
        if (ClipboardAppendEnabled && LastCtrlC_Time && A_TickCount - LastCtrlC_Time < CLIP_DOUBLE_MS) {
            SetTimer(SaveOldClipboard, 0)     ; verified: deletes a pending one-shot
            Sleep(100)                        ; let the app finish putting the copy on the clipboard
            if (OldClipboard != "" && A_Clipboard != "") {
                A_Clipboard := OldClipboard "`r`n" A_Clipboard
                isDouble := true
                OldClipboard := A_Clipboard
            }
            LastCtrlC_Time := 0
        } else {
            LastCtrlC_Time := A_TickCount
            SetTimer(SaveOldClipboard, -CLIP_BACKUP_MS)
        }
    } finally {
        busy := false
    }

    ; Unconditional: the flag test lives inside the feedback function now, so the
    ; one place that can tear its overlay down is also the place that decides
    ; whether to build it.
    TriggerCopyFeedback(isDouble)
}

~^x:: {
    TriggerCutFeedback()
}
#HotIf !GameModeActive


#HotIf !GameModeActive && (SmartCapsEnabled
)
*CapsLock:: {
    global SmartCapsAction
    if !KeyWait("CapsLock", "T0.4") {
        SetCapsLockState(!GetKeyState("CapsLock", "T"))
        KeyWait("CapsLock")
    } else {
        if (SmartCapsAction == "Backspace")
            Send("{Blind}{Backspace}")
        else
            Send("{Blind}{Esc}")
    }
}
#HotIf !GameModeActive

#HotIf !GameModeActive && (AltDragEnabled
)
!LButton::AltDragMove()
!RButton::AltDragResize()
#HotIf !GameModeActive

#HotIf !GameModeActive && ((GrabPanEnabled || RollUpEnabled || MiddleClickCloseEnabled) && !IsMouseOverTaskbar()
)
*MButton:: {
    ; Guard against a second thread starting another pan loop over the same
    ; window: both would Send wheel events and fight over StartX/StartY.
    static busy := false
    if busy
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&sX, &sY, &hwnd, &ctrl, 2)
    if !hwnd
        return


    ; The title-bar probe costs a cross-process SendMessageTimeout with a 50 ms
    ; ceiling, and it is only ever used to decide between Close and Roll-Up. With
    ; neither of those on - grab & pan alone - it answered a question nobody
    ; asked, on every middle click in the system.
    res := 0
    if (RollUpEnabled || MiddleClickCloseEnabled) {
        lp := ((sY & 0xFFFF) << 16) | (sX & 0xFFFF)
        DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 0x84, "ptr", 0, "ptr", lp, "uint", 2, "uint", 50, "ptr*", &res)
    }
    
    if (!GrabPanEnabled) {
        if (res == 2) {
            KeyWait("MButton")
            if (MiddleClickCloseEnabled) {
                try WinClose("ahk_id " hwnd)
                return
            }
            if (RollUpEnabled) {
                ToggleRollUp(hwnd)
                return
            }
        }
        Send("{Blind}{MButton Down}")
        KeyWait("MButton")
        Send("{Blind}{MButton Up}")
        return
    }
    
    StartX := sX
    StartY := sY
    dragged := false
    threshold := 3
    step := 25

    busy := true
    try {
        Loop {
            if !GetKeyState("MButton", "P")
                break

            MouseGetPos(&CurX, &CurY)
            dx := CurX - StartX
            dy := CurY - StartY

            if (!dragged && (Abs(dx) > threshold || Abs(dy) > threshold))
                dragged := true

            if (dragged) {
                if (Abs(dy) >= step) {
                    count := Abs(dy) // step
                    if (dy < 0)
                        Send("{WheelDown " count "}")
                    else
                        Send("{WheelUp " count "}")
                    StartY := StartY + (dy < 0 ? -count * step : count * step)
                }

                if (Abs(dx) >= step) {
                    count := Abs(dx) // step
                    if (dx < 0)
                        Send("{WheelRight " count "}")
                    else
                        Send("{WheelLeft " count "}")
                    StartX := StartX + (dx < 0 ? -count * step : count * step)
                }
            }
            Sleep(10)
        }
    }
    busy := false

    if (!dragged) {
        if (res == 2) {
            if (MiddleClickCloseEnabled) {
                try WinClose("ahk_id " hwnd)
                return
            }
            if (RollUpEnabled) {
                ToggleRollUp(hwnd)
                return
            }
        }
        Send("{Blind}{MButton}")
    }
}
#HotIf !GameModeActive

; ====== Global Text Expander ======
IsExpanderActive(*) {
    global TextExpanderEnabled
    return TextExpanderEnabled
}

SyncTextExpander() {
    static lastSnippets := Chr(1)      ; sentinel: never equal to a real read
    HotIf(IsExpanderActive)

    try IniRead(INI, "snippets")
    catch {
        ; ASCII only in this file (AutoHotkey reads a BOM-less script in the
        ; system codepage, so anything else turns to mojibake on another
        ; machine). Users can put any text they like in settings.ini itself -
        ; that is read as a file, not as source.
        try IniWrite("your.email@example.com", INI, "snippets", "@@mail")
        try IniWrite("+994501234567", INI, "snippets", "@@tel")
        try IniWrite("Thanks!", INI, "snippets", "@@ty")
    }
    
    ; ApplyUi calls this on every checkbox click and every debounced keystroke, and
    ; re-registering the snippets costs a measured 113 us plus a 64 us section read
    ; for nothing. The snippets live in settings.ini and only change when the user
    ; edits that file, so compare and bail.
    str := ""
    try str := IniRead(INI, "snippets",, "")
    if (str == lastSnippets) {
        HotIf()
        return
    }
    lastSnippets := str

    Loop Parse str, "`n", "`r" {
        if (A_LoopField == "")
            continue
        parts := StrSplit(A_LoopField, "=", " `t", 2)
        if (parts.Length == 2)
            try Hotstring(":?*T:" parts[1], parts[2], "On")
    }


    try Hotstring(":?*:@@date", (*) => Send(FormatTime(, "yyyy-MM-dd")), "On")
    try Hotstring(":?*:@@time", (*) => Send(FormatTime(, "HH:mm")), "On")
    
    HotIf()
}

; ONE global keyboard observer, shared by every feature that needs to know a key
; was pressed. A global hook wakes this process on every keystroke, so it is
; started and stopped to match its consumers rather than being left running at
; load. UpdateKeyboardHook() is the Sync* for it: ApplyUi calls it on every
; settings change, and Boot() does the initial start once LoadSettings has run.
; It also owns the OnKeyDown wiring, so this stays a plain declaration.
global SparkHook := InputHook("V L0")

; When a key that is NOT a modifier was last pressed. IsDoublePress needs this to
; tell a deliberate double-tap from two ordinary shortcuts in a row.
global LastNonModifierKeyTime := 0

UpdateKeyboardHook() {
    global SparkHook, SparkTypingEnabled, MicKillSwitchEnabled, SpotlightEnabled, SmoothCaretEnabled, TypingSoundsEnabled
    SparkHook.OnKeyDown := OnObservedKeyDown
    SparkHook.KeyOpt("{All}", "+N")
    if (SparkTypingEnabled || MicKillSwitchEnabled || SpotlightEnabled || SmoothCaretEnabled || TypingSoundsEnabled) {
        try SparkHook.Start()
    } else {
        try SparkHook.Stop()
    }
}

OnObservedKeyDown(ih, vk, sc) {
    global LastNonModifierKeyTime
    ; Shift/Ctrl/Alt (0x10-0x12), their L/R forms (0xA0-0xA5) and the Win keys
    ; (0x5B/0x5C) do not count - a double-tap gesture is made of those, so
    ; recording them here would make every gesture look like ordinary typing.
    if !(vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C
        || vk = 0xA0 || vk = 0xA1 || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5)
        LastNonModifierKeyTime := A_TickCount

    OnTypingSpark(ih, vk, sc)
    
    if SmoothCaretEnabled
        UpdateSmoothCaret()
        
    if TypingSoundsEnabled {
        name := GetKeyName(Format("vk{:x}", vk))
        if (name = "Space") {
            PlayAcousticSound("space")
            WordPop()
        } else if (name = "Enter" || name = "NumpadEnter") {
            PlayAcousticSound("enter")
        } else if (name = "Backspace") {
            PlayAcousticSound("backspace")
        } else if ((vk >= 0x41 && vk <= 0x5A) || (vk >= 0x30 && vk <= 0x39)) {
            PlayAcousticSound("normal")
        } else if (name = "[" || name = "]" || name = "(" || name = ")" || name = "{" || name = "}") {
            PlayAcousticSound("structural")
        } else if !(vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C || vk = 0xA0 || vk = 0xA1 || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5) {
            PlayAcousticSound("operator")
        }
    }
}



#HotIf
