#Requires AutoHotkey v2.0
#SingleInstance Off
#Include StealthPanicConfig.ahk

; test_stealthconfig.ahk - headless round-trip harness for the Safe Workspace
; application list. Exercises the REAL functions from StealthPanicConfig.ahk
; against a scratch directory under A_Temp, dumps raw file bytes both ways, and
; asserts exact round-trip over repeated save/reopen cycles.
;
;   AutoHotkey64.exe /ErrorStdOut src\test_stealthconfig.ahk
;
; Exit code = number of failed assertions. Report is written to
; %TEMP%\stealthcfg-report.txt because a GUI-subsystem AHK process has no
; console to print to.

global TC_Run := 0
global TC_Fail := 0
global TC_Dir := A_Temp "\stealthcfg_" A_TickCount
global TC_Ini := TC_Dir "\StealthPanic.ini"
global TC_Apps := StealthPanicConfig_AppsFilePath(TC_Ini)
global TC_Report := A_Temp "\stealthcfg-report.txt"

; A space followed by a semicolon starts a comment even inside a quoted string,
; so every semicolon in the test data is built from Chr instead.
global SEMI := Chr(59)

try FileDelete(TC_Report)

Say(text) {
    global TC_Report
    FileAppend(text, TC_Report, "UTF-8-RAW")
}

; Render a string so whitespace, line breaks and non-ASCII are all visible on an
; ASCII-only report.
Vis(text) {
    marked := StrReplace(text, "`r", "<CR>")
    marked := StrReplace(marked, "`n", "<LF>")
    marked := StrReplace(marked, "`t", "<TAB>")
    shown := ""
    Loop Parse, marked {
        code := Ord(A_LoopField)
        shown .= (code < 32 || code > 126) ? "<U+" Format("{:04X}", code) ">" : A_LoopField
    }
    return "[" shown "]"
}

; True raw bytes. FileRead with "RAW" returns a Buffer, does no decoding and no
; BOM skipping - the BOM is one of the things under test.
HexDump(path, maxBytes := 320) {
    if !FileExist(path)
        return "      <file does not exist>`n"
    buf := ""
    try buf := FileRead(path, "RAW")
    if !IsObject(buf)
        return "      <cannot read>`n"
    shown := (buf.Size < maxBytes) ? buf.Size : maxBytes
    dump := "", hexLine := "", txtLine := ""
    Loop shown {
        byte := NumGet(buf, A_Index - 1, "UChar")
        hexLine .= Format("{:02X} ", byte)
        txtLine .= (byte >= 32 && byte < 127) ? Chr(byte) : "."
        if (Mod(A_Index, 16) == 0) {
            dump .= "      " hexLine " " txtLine "`n"
            hexLine := "", txtLine := ""
        }
    }
    if (hexLine != "")
        dump .= "      " hexLine " " txtLine "`n"
    if (buf.Size > shown)
        dump .= "      ... " (buf.Size - shown) " more bytes`n"
    return dump
}

; == is the case-SENSITIVE comparison in v2. = would pass on a case difference,
; and a path that comes back lowercased is a genuine failure.
Check(name, expected, actual) {
    global TC_Run, TC_Fail, TC_Apps
    TC_Run++
    if (expected == actual) {
        Say("PASS  " name "`n")
        return true
    }
    TC_Fail++
    Say("FAIL  " name "`n")
    Say("      expected " Vis(expected) "`n")
    Say("      actual   " Vis(actual) "`n")
    Say("      raw bytes of the sidecar:`n")
    Say(HexDump(TC_Apps))
    return false
}

CheckTrue(name, condition) {
    global TC_Run, TC_Fail
    TC_Run++
    if (condition) {
        Say("PASS  " name "`n")
        return true
    }
    TC_Fail++
    Say("FAIL  " name "`n")
    return false
}

Reset() {
    global TC_Apps, TC_Ini
    try FileDelete(TC_Apps)
    try FileDelete(TC_Apps ".tmp")
    try FileDelete(TC_Ini)
}

; The core requirement: repeated Save -> Close -> Reopen must be lossless. Five
; cycles catches anything that grows or shrinks by one character per pass - a
; greedy Trim, a doubled terminator, a re-appended BOM.
Cycle(name, listStr, cycles := 5) {
    global TC_Run, TC_Fail, TC_Apps, TC_Ini
    Reset()
    text := listStr
    Loop cycles {
        if !StealthPanicConfig_WriteAppList(TC_Ini, text) {
            TC_Run++, TC_Fail++
            Say("FAIL  " name " - write returned false on cycle " A_Index "`n")
            return false
        }
        text := StealthPanicConfig_ReadAppList(TC_Ini)
    }
    ok := Check(name " (x" cycles ")", listStr, text)
    CheckTrue(name " leaves no .tmp behind", !FileExist(TC_Apps ".tmp"))
    return ok
}

; ---------------------------------------------------------------- test data ---

; Built with Chr so this source file stays pure ASCII.
NON_ASCII := "C:\" Chr(0x00DC) "bung\" Chr(0x4E2D) Chr(0x6587) "\app.exe"

LONG_PATH := "C:\"
Loop 20
    LONG_PATH .= "verylongdirectorysegment" A_Index "\"
LONG_PATH .= "app.exe"

QUOTED := '"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"'
QUOTED_ARGS := QUOTED " /rootsuffix Exp"

TWELVE := ""
Loop 12
    TWELVE .= (A_Index > 1 ? "`n" : "") "app" A_Index ".exe"

REQUIRED := "devenv.exe`nCode.exe`nms-teams.exe`nexplorer.exe"

EVERYTHING := REQUIRED "`n"
           . QUOTED "`n"
           . "devenv.exe /rootsuffix Exp`n"
           . QUOTED_ARGS "`n"
           . "%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe`n"
           . '"%ProgramFiles%\Some App\app.exe" --flag`n'
           . "Code.exe --user-data-dir=C:\temp\profile=2`n"
           . "app.exe --a=1" SEMI "--b=2`n"
           . SEMI "leading-semicolon.exe`n"
           . "[bracketed].exe`n"
           . "   leading-and-trailing-spaces.exe   `n"
           . "`n"
           . NON_ASCII "`n"
           . LONG_PATH

; -------------------------------------------------------------------- setup ---

DirCreate(TC_Dir)
Say("=== Stealth Panic safe-app list - round trip harness ===`n")
Say("AHK " A_AhkVersion "`n")
Say("scratch : " TC_Dir "`n")
Say("sidecar : " TC_Apps "`n`n")

CheckTrue("sidecar path derives from the ini path, not A_ScriptDir"
        , StealthPanicConfig_AppsFilePath(TC_Ini) == TC_Dir "\StealthPanicApps.txt")

; ------------------------------------------ the ini behaviour being escaped ---

Say("`n=== why the ini cannot hold this setting ===`n")
Reset()
IniWrite("alpha.exe`nbeta.exe`ngamma.exe", TC_Ini, "stealth", "applist")
truncated := IniRead(TC_Ini, "stealth", "applist", "")
Say("      wrote three lines into one key, IniRead gives " Vis(truncated) "`n")
CheckTrue("a single ini value truncates at the first newline", truncated == "alpha.exe")

Reset()
IniWrite('"C:\Program Files\App\a.exe"', TC_Ini, "quotetest", "k")
viaKey := IniRead(TC_Ini, "quotetest", "k", "")
Say("      single-key read of a quoted value gives " Vis(viaKey) "`n")
CheckTrue("a single-key ini read strips surrounding quotes", !InStr(viaKey, '"'))

Reset()
IniWrite("alpha.exe", TC_Ini, "SafeApps", 1)
IniWrite("beta.exe",  TC_Ini, "SafeApps", 2)
rawSection := IniRead(TC_Ini, "SafeApps", , "<<MISSING>>")
Say("      whole-section read gives " Vis(rawSection) "`n")
CheckTrue("whole-section read returns key=value pairs", InStr(rawSection, "1=alpha.exe") > 0)
CheckTrue("whole-section read separates with LF and no CR", !InStr(rawSection, "`r"))

; --------------------------------------------------------------- migration ---

Say("`n=== migration from the two older stores ===`n")

Reset()
IniWrite("alpha.exe", TC_Ini, "SafeApps", 1)
IniWrite("beta.exe",  TC_Ini, "SafeApps", 2)
IniWrite("gamma.exe", TC_Ini, "SafeApps", 3)
Check("indexed [SafeApps] migrates forward", "alpha.exe`nbeta.exe`ngamma.exe"
    , StealthPanicConfig_ReadAppList(TC_Ini))
CheckTrue("migration created the sidecar", FileExist(TC_Apps) != "")
CheckTrue("migration purged [SafeApps]"
        , IniRead(TC_Ini, "SafeApps", , "<<GONE>>") == "<<GONE>>")

; This is the reported bug, reproduced exactly: an ini left behind by the build
; that wrote the whole blob into one key.
Reset()
IniWrite(StrReplace(REQUIRED, "`n", "`r`n"), TC_Ini, "stealth", "applist")
Say("      ini as the old build left it:`n")
Say(HexDump(TC_Ini, 160))
migrated := StealthPanicConfig_ReadAppList(TC_Ini)
Say("      reads back as " Vis(migrated) "`n")
CheckTrue("legacy key still yields only its first line (it cannot hold more)"
        , migrated == "devenv.exe")
CheckTrue("legacy key is purged after migration"
        , IniRead(TC_Ini, "stealth", "applist", "<<GONE>>") == "<<GONE>>")

; The ordering regression that caused the whole bug: a legacy key must never
; outrank the sidecar, whatever order they were created in.
Reset()
StealthPanicConfig_WriteAppList(TC_Ini, "one.exe`ntwo.exe`nthree.exe")
IniWrite("stale-single-entry.exe", TC_Ini, "stealth", "applist")
Check("a legacy key cannot shadow the sidecar", "one.exe`ntwo.exe`nthree.exe"
    , StealthPanicConfig_ReadAppList(TC_Ini))

Reset()
StealthPanicConfig_WriteAppList(TC_Ini, "one.exe`ntwo.exe`nthree.exe")
IniWrite("stale1.exe", TC_Ini, "SafeApps", 1)
IniWrite("stale2.exe", TC_Ini, "SafeApps", 2)
Check("a stale [SafeApps] cannot shadow the sidecar", "one.exe`ntwo.exe`nthree.exe"
    , StealthPanicConfig_ReadAppList(TC_Ini))

Reset()
Check("a fresh install falls back to the built-in default"
    , StealthPanicConfig_DefaultAppList(), StealthPanicConfig_ReadAppList(TC_Ini))
CheckTrue("the default does not touch the disk", !FileExist(TC_Apps))

; ------------------------------------------------------------- round trips ---

Say("`n=== round trips, 5 save/reopen cycles each ===`n")
Cycle("single entry", "notepad.exe")
Cycle("THE FOUR REQUIRED APPS", REQUIRED)
Cycle("twelve entries, order preserved", TWELVE)
Cycle("quoted path", QUOTED)
Cycle("command-line arguments", "devenv.exe /rootsuffix Exp")
Cycle("quoted path plus arguments", QUOTED_ARGS)
Cycle("environment variable", "%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe")
Cycle("quoted env var plus flag", '"%ProgramFiles%\Some App\app.exe" --flag')
Cycle("value containing =", "Code.exe --user-data-dir=C:\temp\profile=2")
Cycle("value containing a semicolon", "app.exe --a=1" SEMI "--b=2")
Cycle("value starting with a semicolon", SEMI "commented.exe")
Cycle("value starting with a bracket", "[bracketed].exe")
Cycle("leading and trailing spaces preserved", "   notepad.exe   ")
Cycle("blank line in the middle", "a.exe`n`nb.exe")
Cycle("non-ASCII path", NON_ASCII)
Cycle("260+ character path", LONG_PATH)
Cycle("empty list", "")
Cycle("everything at once", EVERYTHING)

; Documented asymmetry: a blank line typed at the very end is indistinguishable
; from the file terminator, so it is dropped once and is stable thereafter.
Reset()
StealthPanicConfig_WriteAppList(TC_Ini, "a.exe`nb.exe`n")
once := StealthPanicConfig_ReadAppList(TC_Ini)
StealthPanicConfig_WriteAppList(TC_Ini, once)
twice := StealthPanicConfig_ReadAppList(TC_Ini)
Check("a trailing blank line is dropped once", "a.exe`nb.exe", once)
Check("and is stable thereafter", once, twice)

Reset()
StealthPanicConfig_WriteAppList(TC_Ini, "a.exe`r`nb.exe`r`nc.exe")
Check("CRLF input normalises to LF", "a.exe`nb.exe`nc.exe"
    , StealthPanicConfig_ReadAppList(TC_Ini))

; ---------------------------------------------------------------- encoding ---

Say("`n=== encoding ===`n")
Reset()
StealthPanicConfig_WriteAppList(TC_Ini, NON_ASCII "`nplain.exe")
Say("      raw bytes written to disk:`n")
Say(HexDump(TC_Apps))
rawBuf := FileRead(TC_Apps, "RAW")
CheckTrue("sidecar starts with a UTF-8 BOM"
        , NumGet(rawBuf, 0, "UChar") == 0xEF
       && NumGet(rawBuf, 1, "UChar") == 0xBB
       && NumGet(rawBuf, 2, "UChar") == 0xBF)
decoded := FileRead(TC_Apps, "UTF-8")
CheckTrue("the BOM is not visible in the decoded string"
        , Ord(SubStr(decoded, 1, 1)) != 0xFEFF)
Say("      raw bytes read back:  " Vis(decoded) "`n")
Check("non-ASCII survives the round trip", NON_ASCII "`nplain.exe"
    , StealthPanicConfig_ReadAppList(TC_Ini))
CheckTrue("sidecar ends with exactly one LF"
        , NumGet(rawBuf, rawBuf.Size - 1, "UChar") == 0x0A
       && NumGet(rawBuf, rawBuf.Size - 2, "UChar") != 0x0A)

; ------------------------------------------------------- never throws, ever ---
; ReadAppList runs from a top-level global initialiser inside WindowTweaks, so a
; throw here is a load-time error that kills the whole application.

Say("`n=== failure modes ===`n")
threw := false
try StealthPanicConfig_ReadAppList("Q:\no-such-volume\StealthPanic.ini")
catch
    threw := true
CheckTrue("ReadAppList does not throw on an unreachable path", !threw)

threw := false, result := true
try result := StealthPanicConfig_WriteAppList("Q:\no-such-volume\StealthPanic.ini", "a.exe")
catch
    threw := true
CheckTrue("WriteAppList does not throw on an unreachable path", !threw)
CheckTrue("WriteAppList reports failure instead of pretending", !result)

; A locked target must fail cleanly and must NOT destroy the existing list.
Reset()
StealthPanicConfig_WriteAppList(TC_Ini, "keepme.exe`nkeepme2.exe")
lockHandle := ""
try lockHandle := FileOpen(TC_Apps, "rw -rwd")
if IsObject(lockHandle) {
    threw := false, result := true
    try result := StealthPanicConfig_WriteAppList(TC_Ini, "replacement.exe")
    catch
        threw := true
    CheckTrue("a locked sidecar does not throw", !threw)
    CheckTrue("a locked sidecar reports failure", !result)
    lockHandle.Close()
    Check("a failed write left the old list intact", "keepme.exe`nkeepme2.exe"
        , StealthPanicConfig_ReadAppList(TC_Ini))
    CheckTrue("a failed write left no .tmp behind", !FileExist(TC_Apps ".tmp"))
} else {
    Say("SKIP  locked-file tests (could not acquire an exclusive handle)`n")
}

; -------------------------------------------------------------------- done ---

Reset()
try DirDelete(TC_Dir, true)

Say("`n" TC_Run " assertions, " TC_Fail " failed`n")
Say((TC_Fail == 0) ? "ALL PASS`n" : "FAILURES`n")
ExitApp(TC_Fail)
