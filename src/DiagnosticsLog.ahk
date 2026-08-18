; Diagnostics log - the buffered debug log and the one user-facing notifier.
;
; Function definitions and global initialisers only, no top-level statements.
;
; NOTHING KEYED TO INPUT MAY TOUCH THE DISK. One FileAppend measured 1,900-9,300
; us here - open, write, close, plus the AV filter - and WriteLog used to be
; called from inside the drag path, so a single drag spent ~30 ms in disk I/O on
; the thread that runs the frame loop. Lines accumulate in LogBuf (0.3 us) and an
; idle one-shot writes them ~1.5 s after logging stops. Bye() calls FlushLog()
; directly because there is no idle on the way out.
;
; RotateLog also runs every 20 flushes, not just at startup: the 256 KB cap did
; nothing within a long session, so the file simply grew.

global LOG_FILE := A_ScriptDir "\snap.log"

global MAX_LOG_BYTES  := 262144

global LOG_FLUSH_BYTES := 16384

global LogBuf         := ""

; Logging is buffered and written by an idle one-shot, but it is still disk
; I/O and a growing file for something most users never read. It now has a
; switch like everything else.
global DEBUG          := false

RotateLog() {
    global LOG_FILE, MAX_LOG_BYTES
    try {
        if (FileExist(LOG_FILE) && FileGetSize(LOG_FILE) > MAX_LOG_BYTES) {
            if FileExist(LOG_FILE ".old")
                FileDelete(LOG_FILE ".old")
            FileMove(LOG_FILE, LOG_FILE ".old")
        }
    }
}

; Log lines are buffered in memory and written by an idle one-shot timer.
;
; Measured on this machine: one FileAppend of a single line costs 1.9 ms in the
; program folder and 9.3 ms under %TEMP% (open + write + close, times whatever
; the AV filter driver adds). WriteLog is called three times per drag, from the
; FinishDrag timer thread - so logging alone was spending 6-28 ms of blocking
; disk I/O inside every single drag, stalling the frame loop and every other
; timer with it. Appending to a string costs 0.3 us.
;
; A held file handle would be faster still, but it keeps the file locked and
; leaves the tail unflushed for "Open log"; buffering keeps both, and adds no
; permanent handle.
WriteLog(s) {
    global DEBUG, LogBuf, LOG_FLUSH_BYTES
    if !DEBUG
        return
    LogBuf .= A_Now "  " s "`n"
    if (StrLen(LogBuf) >= LOG_FLUSH_BYTES) {
        FlushLog()
        return
    }
    ; One-shot, re-armed on each line: nothing is scheduled while idle, and the
    ; write lands ~1.5 s after logging stops rather than inside the drag.
    SetTimer(FlushLog, -1500)
}

FlushLog() {
    global LogBuf, LOG_FILE
    static sinceCheck := 0
    if (LogBuf == "")
        return
    text := LogBuf
    LogBuf := ""                        ; clear first: a failed write must not
    SetTimer(FlushLog, 0)               ; re-queue the same text forever
    try FileAppend(text, LOG_FILE)
    ; RotateLog only ran at startup, so the 256 KB cap did nothing within a long
    ; session - the file just grew. Check every few flushes (FileGetSize is a
    ; disk call, measured at 14 us).
    if (++sinceCheck >= 20) {
        sinceCheck := 0
        RotateLog()
    }
}

Notify(msg) => TrayTip(msg, "Window Tweaks")
