try {
#include C:\Users\emras\OneDrive\Рабочий стол\TweaksForEveryOne\src\WindowTweaks.ahk
} catch as e {
FileAppend(e.Message '`n' e.What '`n' e.File '`n' e.Line, 'error.txt')
}

