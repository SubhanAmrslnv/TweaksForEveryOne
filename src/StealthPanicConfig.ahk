#Requires AutoHotkey v2.0

; ============================================================================
; StealthPanicConfig.ahk - storage for the Safe Workspace application list.
;
; WHY this one setting is not in StealthPanic.ini.
;   The list is multi-line free text carrying quoted paths, command-line
;   arguments and environment variables. Every one of those is something the
;   Win32 profile API damages. Measured on Windows 11 26200 / AHK 2.0.26:
;
;   - IniWrite("a`nb`nc", ini, "stealth", "applist") puts the LF bytes into the
;     file verbatim, so [stealth] ends up holding "applist=a" followed by two
;     key-less lines "b" and "c". IniRead then returns "a" - the profile API
;     stops at the first newline. That is the original "only the first app
;     survives" bug. It also corrupts the file permanently: IniDelete removes
;     only the "applist=" line, and the orphans stay in [stealth] forever. They
;     are inert, and rewriting a user's settings file just to tidy them is not
;     worth the risk - AHK writes inis as UTF-16LE, so a rewrite has to
;     round-trip the encoding exactly.
;
;   - A single-key IniRead strips one enclosing pair of double quotes and trims
;     surrounding whitespace, so "C:\Program Files\...\devenv.exe" reads back
;     unquoted and then fails the quote parsing in LaunchSafeApps. A
;     whole-section IniRead does NOT strip. The two read paths on the same file
;     disagree with each other, which is a trap for whoever touches this next.
;
;   - The indexed [SafeApps] replacement survives newlines, but its order is
;     only the physical order of the keys in the file, and a failed IniDelete
;     leaves stale entries N+1..M that reappear on the next read.
;
;   A list of lines belongs in a file of lines. The sidecar is plain UTF-8 text,
;   one entry per line: entries survive byte for byte regardless of quotes,
;   spaces, "=", ";" or "%VARS%", order is the format, and the user can edit it
;   in Notepad.
;
; WHY nothing in here may throw.
;   StealthPanicConfig_ReadAppList is called from a top-level global initialiser
;   in StealthPanic.ahk, and WindowTweaks.ahk #Includes that. An exception there
;   is a LOAD-time error that kills the whole application before a single hotkey
;   is registered. Every I/O call below sits inside try, and both public
;   functions return a value on every path.
;
; Encoding note: CLAUDE.md's "pure ASCII, no BOM" rule is about .ahk SOURCE
; files. The sidecar is runtime data and is deliberately written UTF-8 WITH a
; BOM, so that anything reading it later - a future call site that forgets the
; encoding argument, Notepad, PowerShell's Get-Content - decodes a non-ASCII
; install path correctly instead of guessing the system codepage. This repo's
; own working directory is under a non-ASCII path, so that is not hypothetical.
; ============================================================================

StealthPanicConfig_DefaultAppList() {
    return "notepad.exe`ncalc.exe"
}

; The list lives next to the .ini the caller named, never next to A_ScriptDir.
; The engine and the settings GUI are separate processes whose A_ScriptDir can
; differ; the caller has already decided which ini it owns, and the list has to
; follow that decision rather than re-derive a second, possibly different one.
StealthPanicConfig_AppsFilePath(iniFile) {
    SplitPath(iniFile, , &dirOnly, , &nameNoExt)
    if (dirOnly == "")
        dirOnly := A_ScriptDir
    if (nameNoExt == "")
        nameNoExt := "StealthPanic"
    return dirOnly "\" nameNoExt "Apps.txt"
}

; Whoever launches the settings GUI may hand it the ini path it is actually
; using, so the two processes cannot drift onto different files. Falling back to
; A_ScriptDir keeps a bare double-click on StealthPanicUI.ahk working exactly as
; it did before.
StealthPanicConfig_ResolveIniPath() {
    if (A_Args.Length >= 1) {
        candidate := Trim(Trim(A_Args[1]), '"')
        if (candidate != "")
            return candidate
    }
    return A_ScriptDir "\StealthPanic.ini"
}

; Collapse any line ending to LF and drop ONE trailing terminator.
;
; Lines are otherwise preserved verbatim - interior blank lines and leading or
; trailing spaces included. Interpretation belongs at launch time, where
; LaunchSafeApps already trims each entry and skips the empty ones; doing it
; here as well would make the stored list differ from what the user typed.
;
; Exactly one trailing LF is dropped because the writer always appends one as a
; file terminator. Dropping none would grow a blank line on every save cycle;
; dropping all of them with a greedy Trim would eat blank lines that are data.
; The one consequence, and it is documented rather than fixed: a blank line the
; user types at the very END of the box is indistinguishable from the
; terminator, so it does not survive.
StealthPanicConfig_NormalizeList(listStr) {
    text := StrReplace(listStr, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    if (SubStr(text, -1) == "`n")
        text := SubStr(text, 1, StrLen(text) - 1)
    return text
}

; Write to a temp file in the SAME directory, then replace in one call.
; Same directory is required: MoveFileEx only replaces atomically within one
; volume, and a cross-volume move silently degrades to copy+delete, which is the
; crash window this exists to close.
StealthPanicConfig_WriteFileAtomic(targetPath, text) {
    SplitPath(targetPath, , &dirOnly)
    if (dirOnly != "" && !DirExist(dirOnly))
        try DirCreate(dirOnly)

    tmpPath := targetPath ".tmp"
    try FileDelete(tmpPath)

    fh := ""
    try {
        ; "UTF-8" emits a BOM. "UTF-8-RAW" would not - see the encoding note in
        ; the header. Never open this without an explicit encoding: FileOpen
        ; otherwise defaults to A_FileEncoding, i.e. the system codepage.
        fh := FileOpen(tmpPath, "w", "UTF-8")
        if !IsObject(fh)
            return false
        fh.Write(text)
        fh.Close()
        fh := ""
    } catch {
        if IsObject(fh)
            try fh.Close()
        try FileDelete(tmpPath)
        return false
    }

    ; MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH. A DllCall rather than
    ; FileMove because this is the data-integrity step and a real return code is
    ; worth more than an exception. Retried because this program is routinely
    ; installed under OneDrive and behind an AV filter, either of which can hold
    ; the target open for a few milliseconds - the same filter that makes one
    ; FileAppend cost 1.9-9.3 ms on this machine.
    attempt := 0
    while (attempt < 4) {
        if DllCall("MoveFileExW", "wstr", tmpPath, "wstr", targetPath
                 , "uint", 0x1 | 0x8, "int")
            return true
        attempt++
        Sleep(30)
    }

    try FileDelete(tmpPath)
    return false
}

; Best effort. IniDelete throws when the section or key is already absent, and a
; leftover key is harmless now that the sidecar is consulted first - that
; ordering is what stops the old stores shadowing anything. Never call this
; before the sidecar is verified on disk.
StealthPanicConfig_PurgeIniStores(iniFile) {
    try IniDelete(iniFile, "SafeApps")
    try IniDelete(iniFile, "stealth", "applist")
}

; The [SafeApps] indexed-key store written by the previous attempt at this fix.
; Measured: a whole-section IniRead returns "key=value" lines separated by LF,
; with no CR and no trailing newline, in physical file order - and unlike a
; single-key read it does not strip quotes. Everything after the FIRST "=" is
; the value, so an argument such as --flag=1 stays intact.
StealthPanicConfig_ReadIndexed(iniFile) {
    section := ""
    try section := IniRead(iniFile, "SafeApps", , "")
    if (section == "")
        return ""
    list := ""
    for line in StrSplit(section, "`n", "`r") {
        eqPos := InStr(line, "=")
        if (eqPos)
            list .= SubStr(line, eqPos + 1) "`n"
    }
    return StealthPanicConfig_NormalizeList(list)
}

; The original single-line key. Read LAST, not first. It can hold exactly one
; line by construction, so consulting it ahead of the real stores is precisely
; what made a full list collapse back to a single app on every reopen - the
; reported bug, on any machine carrying an ini from an older build.
StealthPanicConfig_ReadLegacy(iniFile) {
    v := ""
    try v := IniRead(iniFile, "stealth", "applist", "")
    return StealthPanicConfig_NormalizeList(v)
}

; Write the sidecar, read it back, compare, and only then retire the old stores.
; Order matters: a failed write followed by a successful purge destroys the
; user's list, which is a worse bug than the one being fixed.
StealthPanicConfig_MigrateToSidecar(iniFile, list) {
    appsPath := StealthPanicConfig_AppsFilePath(iniFile)
    if !StealthPanicConfig_WriteFileAtomic(appsPath, list "`n")
        return false

    back := ""
    try back := FileRead(appsPath, "UTF-8")
    catch
        return false
    if (StealthPanicConfig_NormalizeList(back) !== list)
        return false

    StealthPanicConfig_PurgeIniStores(iniFile)
    return true
}

StealthPanicConfig_ReadAppList(iniFile) {
    appsPath := StealthPanicConfig_AppsFilePath(iniFile)

    ; 1. The sidecar wins whenever it EXISTS, including when it is empty. "The
    ;    user cleared the list" and "there is no list yet" are different states,
    ;    and collapsing them would make a deliberately emptied list spring back
    ;    to the shipped default on the next open.
    if FileExist(appsPath) {
        raw := ""
        gotIt := false
        try {
            raw := FileRead(appsPath, "UTF-8")
            gotIt := true
        }
        if (gotIt) {
            ; FileRead skips the BOM it wrote. This covers the other case: a
            ; user who opens the sidecar in Notepad and saves it back. A stray
            ; U+FEFF would corrupt the first entry only, the hardest kind to
            ; spot.
            if (SubStr(raw, 1, 1) == Chr(0xFEFF))
                raw := SubStr(raw, 2)
            return StealthPanicConfig_NormalizeList(raw)
        }
    }

    ; 2. No sidecar: a first run, or an upgrade from a build that kept the list
    ;    in the ini. Take the newest store that has anything in it.
    list := StealthPanicConfig_ReadIndexed(iniFile)
    if (list == "")
        list := StealthPanicConfig_ReadLegacy(iniFile)

    ; 3. Built-in default. Deliberately does NOT create the sidecar - a default
    ;    is not user data, and leaving the disk untouched keeps a fresh
    ;    install's load path free of I/O.
    if (list == "")
        return StealthPanicConfig_DefaultAppList()

    ; Migrate forward so this branch never runs again. Best effort on purpose: a
    ; read-only or locked folder must degrade to "the list still loads, it just
    ; is not migrated yet", never to a throw.
    try StealthPanicConfig_MigrateToSidecar(iniFile, list)
    return list
}

; Returns true only when the list is verified on disk. The caller is expected to
; tell the user when this is false rather than report a successful save.
StealthPanicConfig_WriteAppList(iniFile, listStr) {
    list := StealthPanicConfig_NormalizeList(listStr)
    ok := false
    try ok := StealthPanicConfig_MigrateToSidecar(iniFile, list)
    return ok
}
