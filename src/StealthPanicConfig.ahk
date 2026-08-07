#Requires AutoHotkey v2.0

StealthPanicConfig_ReadAppList(iniFile) {
    list := ""
    ; Legacy fallback
    legacy := IniRead(iniFile, "stealth", "applist", "")
    if (legacy != "") {
        return legacy
    }
    
    apps := IniRead(iniFile, "SafeApps",, "")
    if (apps == "")
        return "notepad.exe`ncalc.exe"
        
    ; Parse section keys
    Loop Parse, apps, "`n", "`r" {
        eqPos := InStr(A_LoopField, "=")
        if (eqPos) {
            val := SubStr(A_LoopField, eqPos + 1)
            list .= val "`n"
        }
    }
    return Trim(list, "`n`r")
}

StealthPanicConfig_WriteAppList(iniFile, listStr) {
    ; Delete old section to remove deleted items
    try IniDelete(iniFile, "SafeApps")
    
    ; Delete legacy key
    try IniDelete(iniFile, "stealth", "applist")
    
    lines := StrSplit(listStr, "`n", "`r")
    index := 1
    for line in lines {
        IniWrite(line, iniFile, "SafeApps", index)
        index++
    }
}
