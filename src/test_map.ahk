#Requires AutoHotkey v2.0
m := Map()
try {
    m.Delete("foo")
    FileAppend "No error`n", "*"
} catch as e {
    FileAppend "Error: " e.Message "`n", "*"
}
ExitApp
