#Requires AutoHotkey v2.0

IsDoublePress(ExpectedPriorKey, Timeout := 400) {
    static lastPresses := Map()
    
    FileAppend "A_PriorKey: " A_PriorKey "`n", "*"
    FileAppend "ExpectedPriorKey: " ExpectedPriorKey "`n", "*"
    
    if (A_PriorKey != ExpectedPriorKey) {
        if lastPresses.Has(A_ThisHotkey)
            lastPresses.Delete(A_ThisHotkey)
        FileAppend "Returned false because PriorKey mismatch`n", "*"
        return false
    }
    
    now := A_TickCount
    if (lastPresses.Has(A_ThisHotkey)) {
        diff := now - lastPresses[A_ThisHotkey]
        FileAppend "Diff: " diff "`n", "*"
        if (diff < Timeout) {
            lastPresses.Delete(A_ThisHotkey)
            FileAppend "Returned true`n", "*"
            return true
        }
    }
    
    lastPresses[A_ThisHotkey] := now
    FileAppend "Returned false (first press)`n", "*"
    return false
}

~LAlt up:: {
    if IsDoublePress("LAlt") {
        FileAppend "Double Pressed LAlt!`n", "*"
    }
}

SetTimer(SimulateKeys, -500)

SimulateKeys() {
    Send "{LAlt down}"
    Sleep 50
    Send "{LAlt up}"
    Sleep 100
    Send "{LAlt down}"
    Sleep 50
    Send "{LAlt up}"
    Sleep 500
    ExitApp
}
