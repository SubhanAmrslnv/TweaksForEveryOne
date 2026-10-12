; ArithmeticEval.ahk - the Spotlight calculator's expression evaluator.
;
; Function definitions only, no top-level statements, and no dependency on any
; other module, so a standalone test harness can #Include it alone.
;
; It replaces an MSHTML "htmlfile" document that ran the input through a
; JavaScript eval(). The character-class guard made that safe, but a script host
; driving a COM HTML engine to execute script is a classic endpoint-security
; heuristic, and it cost a fresh document per keystroke. Four operators, unary
; signs, brackets and decimals are all the guard ever let through, so a small
; recursive-descent parser covers exactly the same language.
;
; Grammar:
;   expr    := term (("+" | "-") term)*
;   term    := unary (("*" | "/") unary)*
;   unary   := ("+" | "-") unary | primary
;   primary := number | "(" expr ")"
;   number  := digits ["." digits] | "." digits | digits "."

; Returns the value as display text ("3.5", "42"), or "" when the input is not a
; complete expression or divides by zero. Never throws.
CalcEvaluate(text) {
    try {
        src := RegExReplace(text, "\s+", "")
        if (src = "" || !RegExMatch(src, "^[\d\+\-\*\/\.\(\)]+$"))
            return ""
        pos := 1
        val := CalcExpr(src, &pos, 0)
        if (pos <= StrLen(src))
            return ""                    ; trailing input the grammar did not consume
        return CalcFormat(val)
    }
    return ""
}

; Integers print without a decimal point; anything else is rounded to 10 places
; and trimmed, so 0.1+0.2 reads 0.3 rather than 0.30000000000000004.
CalcFormat(val) {
    if (Abs(val) < 1e15 && val = Floor(val))
        return String(Integer(val))
    s := Format("{:.10f}", val)
    s := RegExReplace(s, "0+$", "")
    s := RegExReplace(s, "\.$", "")
    return (s = "-0") ? "0" : s
}

; depth bounds the recursion: a few thousand "(" would otherwise exhaust the
; stack, and this runs on every keystroke.
CalcExpr(src, &pos, depth) {
    if (depth > 64)
        throw ValueError("nesting")
    val := CalcTerm(src, &pos, depth)
    while (pos <= StrLen(src)) {
        op := SubStr(src, pos, 1)
        if (op != "+" && op != "-")
            break
        pos++
        rhs := CalcTerm(src, &pos, depth)
        val := (op = "+") ? val + rhs : val - rhs
    }
    return val
}

CalcTerm(src, &pos, depth) {
    val := CalcUnary(src, &pos, depth)
    while (pos <= StrLen(src)) {
        op := SubStr(src, pos, 1)
        if (op != "*" && op != "/")
            break
        pos++
        rhs := CalcUnary(src, &pos, depth)
        if (op = "/") {
            if (rhs = 0)
                throw ZeroDivisionError("division by zero")
            val := val / rhs
        } else {
            val := val * rhs
        }
    }
    return val
}

CalcUnary(src, &pos, depth) {
    if (depth > 64)
        throw ValueError("nesting")
    c := SubStr(src, pos, 1)
    if (c = "-") {
        pos++
        return -CalcUnary(src, &pos, depth + 1)
    }
    if (c = "+") {
        pos++
        return CalcUnary(src, &pos, depth + 1)
    }
    return CalcPrimary(src, &pos, depth)
}

CalcPrimary(src, &pos, depth) {
    c := SubStr(src, pos, 1)
    if (c = "(") {
        pos++
        val := CalcExpr(src, &pos, depth + 1)
        if (SubStr(src, pos, 1) != ")")
            throw ValueError("unclosed bracket")
        pos++
        return val
    }
    if !RegExMatch(src, "\G(\d+\.?\d*|\.\d+)", &m, pos)
        throw ValueError("number expected")
    pos += m.Len
    return Number(m[0]) + 0.0
}
