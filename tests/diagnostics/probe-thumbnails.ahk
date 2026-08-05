#Requires AutoHotkey v2.0
#SingleInstance Force
; Run:  AutoHotkey64.exe probe-thumbnails.ahk   (writes results to stdout)
;
; Answers one question: when the thumbnail flyout opens, is there an HWND?
;
; This decides whether ANY out-of-process approach to reordering thumbnails can
; work. If a window appears, its class is the handle we can reach from outside.
; If nothing appears, the flyout is pure XAML inside explorer's visual tree and
; only in-process code can touch it.
;
; Manual on purpose. SetCursorPos-driven hover does not open the flyout - the
; taskbar ignores synthetic movement here, the same way the window move loop
; ignores injected clicks (see README, "Development"). Measured: two UIA
; snapshots of Shell_TrayWnd taken around a synthetic hover were identical at
; 42 elements, with only the clock ticking between them.
;
; HOVER A GROUPED TASKBAR ICON WITH A REAL MOUSE WHILE THIS RUNS.

Out(s) => FileAppend(s "`n", "*")

SECONDS := 20
POLL_MS := 120

DetectHiddenWindows true

Baseline := Map()
for hwnd in WinGetList()
    Baseline[hwnd] := true

Out("=== probe-thumbnails ===")
Out("Baseline: " Baseline.Count " top-level windows")
Out("")
Out("Hover a taskbar icon that has MULTIPLE windows open, with a real mouse.")
Out("Candidates on this machine when last checked: Terminal (3), Chrome (2).")
Out("Watching for " SECONDS " seconds...")
Out("")

Seen  := Map()
Ticks := (SECONDS * 1000) // POLL_MS

loop Ticks {
    for hwnd in WinGetList() {
        if Baseline.Has(hwnd) || Seen.Has(hwnd)
            continue
        Seen[hwnd] := true
        try {
            cls   := WinGetClass(hwnd)
            pid   := WinGetPID(hwnd)
            title := WinGetTitle(hwnd)
            proc  := WinGetProcessName(hwnd)
        } catch
            continue

        r := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", hwnd, "ptr", r)
        x := NumGet(r,  0, "int"), y := NumGet(r,  4, "int")
        w := NumGet(r,  8, "int") - x, h := NumGet(r, 12, "int") - y
        vis := DllCall("IsWindowVisible", "ptr", hwnd) ? "visible" : "hidden"

        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 14
              , "int*", &cloaked, "int", 4)

        Out("NEW  " Format("0x{:X}", hwnd))
        Out("     class   : " cls)
        Out("     process : " proc " (pid " pid ")")
        Out("     title   : " title)
        Out("     rect    : " x "," y "  " w "x" h "  " vis
          . (cloaked ? "  CLOAKED" : ""))

        ; A thumbnail host sits above the taskbar and is wider than one button.
        if (h > 80 && w > 150 && proc = "explorer.exe")
            Out("     ^^ shape and owner match a thumbnail flyout")
        Out("")
    }
    Sleep POLL_MS
}

Out("=== done ===")
if (Seen.Count = 0) {
    Out("No new windows appeared.")
    Out("")
    Out("If you definitely saw thumbnails, the flyout has no HWND of its own:")
    Out("it is a WinUI Popup inside explorer's XamlRoot. Out-of-process code")
    Out("cannot reach it, and the payload must run inside explorer.exe.")
} else {
    Out(Seen.Count " new window(s) recorded above.")
}
ExitApp(0)
