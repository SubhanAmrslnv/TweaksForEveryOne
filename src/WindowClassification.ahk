; Window lifecycle - classify a window, remember where it was, put it back, and
; animate it in. Owns the shell hook.
;
; Function definitions and global initialisers only, no top-level statements.
; Boot() registers the SHELLHOOK and TaskbarCreated handlers and calls
; RegisterShellHook() as the very last thing it does, because ShellEvent is the
; widest-reaching callback in the program - created, destroyed, activated and
; minimised - so nothing may still be uninitialised when it starts delivering.
;
; NEW WINDOWS ARE DETECTED VIA RegisterShellHookWindow, NOT POLLING - AND THAT
; REGISTRATION DOES NOT SURVIVE AN EXPLORER RESTART. Explorer broadcasts
; TaskbarCreated when the shell comes back; handling it and re-registering is the
; only thing keeping position memory, the open animations, focus pulse, breathing
; seeding, fly-to-mouse minimize and per-window cleanup alive after an Explorer
; crash - or after this program's own "Restart Explorer" button.
;
; POSITION MEMORY IS KEYED ON exe + WINDOW CLASS, and excludes dialogs, owned
; windows, WS_EX_TOOLWINDOW, anything without WS_THICKFRAME, and Picture-in-
; Picture. Every Chrome popup shares a class with the main window.
;
; NOTHING KEYED TO INPUT MAY TOUCH THE DISK. window-positions.ini was written
; with four synchronous IniWrites (~771 us each) at the end of every drag AND
; again from OnSnapLanded. It is buffered in PendingPositions and flushed by a
; 900 ms one-shot. For the same reason RememberPosition does NOT call
; IsMainApplicationWindow, which reaches a WMI query through ClassifyWindowImpl -
; tens of milliseconds of blocking COM on the drag path. Classification belongs
; on the window-created path, where RestorePosition already does it.
;
; NEVER MAKE A FOREIGN WINDOW LAYERED SPECULATIVELY. WinSetTransparent forces
; WS_EX_LAYERED; on a GPU-composited or full-screen window that costs a
; redirection surface and can break exclusive full-screen presentation.
; WillAnimateOpen() is the single eligibility test, applied BEFORE hiding a new
; window rather than after - get that backwards and brand-new windows sit at
; alpha 0, invisible but focused and clickable.
;
; The per-HWND state Maps are pruned in the HSHELL_WINDOWDESTROYED branch of the
; shell hook. Anything keyed on hwnd anywhere in the program has to be pruned
; there too, or it leaks for the session.

global WindowCmdLineCache := Map()

IsRestorable(hwnd) {
    if !IsSnappable(hwnd)
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")        ; GW_OWNER
        return false
    try {
        if (WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "uint"))
            return false
            
        title := WinGetTitle(hwnd)
        if RegExMatch(title, "i)^(Picture.?in.?Picture|PiP|Картинка в картинке|Resim içinde resim|Şəkil içində şəkil)$")
            return false
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        ; Browser PiP windows (or popups) often don't have the standard title if localized, 
        ; but they are typically Always-On-Top (0x8) and lack a Maximize Box (0x10000).
        if ((exStyle & 0x8) && !(style & 0x10000)) {
            exe := WinGetProcessName(hwnd)
            if RegExMatch(exe, "i)^(chrome|msedge|firefox|brave|opera|vivaldi)\.exe$")
                return false
        }
            
        ; Every AutoHotkey GUI shares one class, so a single saved entry would
        ; drag every unrelated AHK window to the same spot.
        if (WinGetClass(hwnd) = "AutoHotkeyGUI")
            return false
        if (exStyle & 0x80)                                       ; WS_EX_TOOLWINDOW
            return false
        if !(style & 0x00040000)                                  ; WS_THICKFRAME
            return false
    } catch
        return false
    return true
}

WindowKey(hwnd) {
    try {
        exe := WinGetProcessName(hwnd)
        cls := WinGetClass(hwnd)
    } catch
        return ""
    return SubStr(RegExReplace(exe "_" cls, "[^A-Za-z0-9_]", ""), 1, 80)
}

GetProcessCommandLine(pid, hwnd) {
    global WindowCmdLineCache
    if WindowCmdLineCache.Has(hwnd)
        return WindowCmdLineCache[hwnd]

    ; The locator is built once. ComObjGet("winmgmts:") connects to the WMI
    ; service, and doing that per window made an already expensive query worse;
    ; this runs from HandleNewWindow's timer, so every millisecond is a stalled
    ; frame. Cached in a static, rebuilt if the service connection goes away.
    static wmi := ""
    cmdLine := ""
    try {
        if !wmi
            wmi := ComObjGet("winmgmts:")
        for proc in wmi.ExecQuery("Select CommandLine from Win32_Process where ProcessId=" pid) {
            cmdLine := proc.CommandLine
            break
        }
    } catch {
        wmi := ""
    }
    
    if DllCall("IsWindow", "ptr", hwnd)
        WindowCmdLineCache[hwnd] := cmdLine
        
    return cmdLine
}

IsMainApplicationWindow(hwnd) {
    return ClassifyWindowImpl(hwnd) == "Main"
}

ClassifyWindowImpl(hwnd) {
    try {
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            return "Transient"
            
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        if !(style & 0x00040000)
            return "Transient"
            
        if !(style & 0x10000000)
            return "Transient"
            
        if (style & 0x80000000)
            return "Transient"
            
        if (exStyle & 0x80)
            return "Transient"
            
        if IsCloaked(hwnd)
            return "Transient"

        title := WinGetTitle(hwnd)
        
        ; DISTINCTIVE phrases only.
        ;
        ; This list used to contain the bare words Settings, Options, Open,
        ; Print, About, Properties, Account, License, Loading, Progress, Trial,
        ; Welcome, Subscription and Wizard, matched anywhere in the title. Those
        ; are ordinary words in ordinary MAIN window titles - "Options - Mozilla
        ; Firefox", a VS Code "Settings" tab, any document named Account.xlsx -
        ; so position memory was silently switched off for a large slice of real
        ; windows, with nothing to tell the user why their app kept reopening in
        ; the wrong place.
        ;
        ; The generic single words are gone. What remains is multi-word or
        ; unambiguous. The structural tests above (owned window, no thick frame,
        ; tool window, cloaked) already reject most real dialogs, so this list
        ; only has to catch the ones that look structurally like a main window.
        static transientTitles := "i)\b(Getting Started|What's New|First Run|First Launch|Welcome Back"
            . "|Log In|Sign In|Two Factor|Security Check|Account Selection|Account Picker|User Selection|Profile Selection"
            . "|Chrome Profile Picker|Chrome Welcome|Chrome First Run|Chrome Sign In"
            . "|Edge Profile Picker|Edge Welcome|Edge First Run|Firefox Profile Manager|Brave Welcome|Opera Welcome|Arc Onboarding"
            . "|Configuration Wizard|Setup Wizard|InstallShield|MSI Installer|Inno Setup"
            . "|Downloading Update|Installing Update|Patch Installer|Version Upgrade"
            . "|Product Activation|License Activation|Subscription Activation"
            . "|Splash Screen|Boot Screen"
            . "|Profile Picker|User Picker|Folder Picker|File Picker|Color Picker|Font Picker|Emoji Picker|Device Picker|Printer Picker"
            . "|Settings Dialog|Message Box"
            . "|Permission Request|Allow Access|Administrator Prompt|Windows Security|Credential Dialog"
            . "|Visual Studio Installer|JetBrains Toolbox|Creative Cloud Installer|Office Installer|Epic Installer|Steam Installer|Riot Installer|EA Installer"
            . "|Steam Login|Discord Login|Slack Login|Teams Login|Zoom Login|Adobe Login|Epic Login|Battle\.net Login|Riot Login|Dropbox Login|OneDrive Login|Google Login|Apple Login"
            . "|Choose Profile|Save As|Choose Account|Choose Workspace|Workspace Picker|Device Setup|Connection Wizard)\b"
            
        if RegExMatch(title, transientTitles)
            return "Transient"

        pid := WinGetPID(hwnd)
        cmdLine := GetProcessCommandLine(pid, hwnd)
        static cmdLineArgs := "i)(--profile-picker|--first-run|--welcome|--setup|--installer|--install|--update|--updater|--repair|--activation|--login|--signin|--profile-manager)"
        
        if (cmdLine != "" && RegExMatch(cmdLine, cmdLineArgs))
            return "Transient"

    } catch {
        return "Transient"
    }

    return "Main"
}

IsShellSurface(hwnd, cls := "") {
    if (cls == "")
        try cls := WinGetClass(hwnd)
        catch
            return false
    return (cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || cls == "Progman" || cls == "WorkerW")
}

