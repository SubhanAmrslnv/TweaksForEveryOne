; Custom taskbar clock - time, date and temperature on the taskbar, and the ONLY
; network egress in this program.
;
; Function definitions and global initialisers only, no top-level statements.
;
; ONE RULE SHAPES THE WHOLE FEATURE: THE BLOCK MAY NEVER INTERSECT TrayNotifyWnd.
; The first version did - 110 px wide, anchored on the clock and grown leftward -
; so it covered the native clock and the Control Center button. It read as a
; corrupted system tray: the notification icon looked like it had moved, the
; spacing was wrong, and a failed weather lookup printed "no data" where the time
; belongs. Nothing in Explorer had changed; it was all COVERED, not moved.
;
; So it draws in the free strip beside the tray, sized from its own content, and
; if the anchor cannot be found it draws NOTHING rather than guessing. It hides
; rather than reporting - no taskbar, taskbar not visible, auto-hidden, or no
; room, and the block disappears. Nothing about this program's state is ever
; rendered onto the taskbar; failures go to snap.log and one Notify().
;
; THE DEFAULT IS ON, AND THAT IS ONLY SAFE BECAUSE A BLANK LOCATION MAKES NO
; REQUEST. FetchWeather() returns immediately while the location is empty, so out
; of the box the block shows time and date and the program makes no outbound call
; at all. The temperature column appears - and the egress begins - only once a
; city is typed. Do not simplify that early return away.
;
; open-meteo over WinHttp, NOT wttr.in over MSXML. Measured: MSXML returns status
; 200 with an EMPTY responseText for an application/json body, so every reading
; came back blank; and wttr.in answers 200 with its HTML landing page instead of
; an error whenever it will not serve a reading. The request is opened async and
; polled with WaitForResponse(0), which returns immediately - a bare
; WaitForResponse() would block every timer in the process. The geocoder resolves
; the city once and the coordinates are cached, so the steady state is one
; request per 15 minutes, and WeatherFailed() triples the retry interval rather
; than retrying into a rate limit.
;
; ControlGetHwnd("TrayClockWClass", ...) THROWS. The clock is a grandchild of
; Shell_TrayWnd via TrayNotifyWnd, and a bare class name is not a valid ClassNN.
; Inside a timer callback that throw pops an error dialog and kills the timer, so
; the feature had never once drawn anything. Use FindWindowExW, and keep the
; whole tick body behind a try.
;
; The rect is diffed before it is queued. RenderCore does not cache positions on
; purpose, but this window is ours alone so the cache is valid here - which is
; what makes a fast tick free. It has to be fast: one new tray icon shifts the
; boundary 24 px.

; ----------------------------------------------------------------------------
; Custom Taskbar Clock
; ----------------------------------------------------------------------------

; A time / date / temperature block on the taskbar, and ONE rule shapes all of it:
; it may never intersect TrayNotifyWnd.
;
; The first version did. It was 110 px wide, anchored on TrayClockWClass and grown
; leftward, so it covered the native clock and the Control Center button. That read
; as a corrupted tray - the notification icon looked like it had moved, the spacing
; was wrong, and a failed weather lookup printed "no data" where the time belongs.
; Nothing in Explorer had changed; it was all covered, not moved.
;
; So it sits entirely to the LEFT of the tray, in the strip the task buttons have
; not used, it is sized to its own content, and if the tray cannot be located it
; does not draw at all - because then there is no way to prove it is not sitting on
; top of something. Windows keeps drawing its own clock, date and tray icons,
; untouched, to the right of it.
global CustomClockGui := 0

global CustomClockTimeText := 0

global CustomClockTempText := 0

global CustomClockReq := 0        ; held so the async request is not collected mid-flight

global WeatherReqAt := 0

global CustomClockBuiltFor := ""  ; theme, font and column widths the Gui was built for

global CustomClockRect := ""      ; last rect actually queued, so unchanged ticks cost nothing

; Padding around and between the two columns.
global CLOCK_GAP := 6

SyncCustomClockTimer() {
    global CustomClockEnabled, LastWeatherFetch, CustomClockWeather, WeatherNextMs
    global WeatherWarnedFor, GeoFor, ClockWarnedNoCity
    if (CustomClockEnabled) {
        ; Re-arming forces an immediate fetch, which is also how a changed location
        ; or unit takes effect: ApplyUi calls this after reading the controls. GeoFor
        ; is reset with it, so a new city is geocoded again instead of reusing the
        ; coordinates of the old one.
        LastWeatherFetch := 0
        WeatherNextMs := 900000
        CustomClockWeather := ""
        WeatherWarnedFor := "-"
        ClockWarnedNoCity := false
        GeoFor := "-"
        SetTimer(UpdateCustomClock, 250)
        UpdateCustomClock()
    } else {
        SetTimer(UpdateCustomClock, 0)
        HideCustomClock()
    }
}

HideCustomClock() {
    global CustomClockGui, CustomClockTimeText, CustomClockTempText
    global CustomClockBuiltFor, CustomClockRect
    if (CustomClockGui) {
        ; Mandatory, not tidiness: a -Caption +ToolWindow overlay raises no shell
        ; destroy notification, so nothing else would ever prune its RS_* entries.
        try RS_RemoveHwnd(CustomClockGui.Hwnd)
        try CustomClockGui.Destroy()
    }
    CustomClockGui := 0
    ; These referenced controls of the destroyed Gui. Left dangling, the next tick
    ; wrote .Value into a dead control and threw - inside a timer callback.
    CustomClockTimeText := 0
    CustomClockTempText := 0
    CustomClockBuiltFor := ""
    CustomClockRect := ""
}

; Where the block's right edge goes, resolved from LIVE window geometry by class
; name. There is no coordinate anywhere in this feature.
;
; Two anchors, and the difference is a real trade-off rather than an internal
; detail, which is why it is a setting:
;
;   "Clock"    - the left edge of TrayClockWClass. Adjacent to the native clock, so
;                the block reads as part of the tray. It therefore sits ON TOP of
;                whatever is immediately left of the clock, which on this shell is
;                the Control Center button.
;   "TrayEdge" - the left edge of TrayNotifyWnd, i.e. left of EVERY tray element.
;                Covers nothing at all. The cost is distance: TrayNotifyWnd is the
;                whole notification area and its width moves with the icon count -
;                measured 343, 391, 415 and 511 px in one session - so the block
;                drifts, and at 511 px it is 480 px away from the clock and reads
;                as floating in the middle of the taskbar rather than integrated.
;
; Returns 0 when the requested element cannot be found AND neither can the
; fallback, and the caller then draws nothing rather than guessing a position.
ResolveClockAnchor(tbHwnd) {
    global ClockAnchor
    ; Ordered: the requested anchor first, then the safe one. A shell without a
    ; TrayClockWClass - the stock Win11 XAML taskbar has none - falls through to
    ; the tray edge instead of losing the feature.
    order := (ClockAnchor == "TrayEdge")
        ? ["TrayNotifyWnd"]
        : ["TrayClockWClass", "TrayNotifyWnd"]
    for cls in order {
        h := FindTrayElement(tbHwnd, cls)
        if (h) {
            WinGetPos(&ex, &ey, &ew, &eh, "ahk_id " h)
            if (ew > 0)
                return ex
        }
    }
    return 0
}

; Shell_TrayWnd -> TrayNotifyWnd -> the element. The clock is a GRANDCHILD of the
; tray, so a direct-child search finds only TrayNotifyWnd itself; both levels are
; tried. Never throws: an absent element is a normal outcome on the XAML shell.
FindTrayElement(tbHwnd, cls) {
    try {
        if (cls == "TrayNotifyWnd") {
            h := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0, "str", cls, "ptr", 0, "ptr")
            return (h && DllCall("IsWindowVisible", "ptr", h)) ? h : 0
        }
        notify := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0
            , "str", "TrayNotifyWnd", "ptr", 0, "ptr")
        if (notify) {
            h := DllCall("FindWindowExW", "ptr", notify, "ptr", 0, "str", cls, "ptr", 0, "ptr")
            if (h && DllCall("IsWindowVisible", "ptr", h))
                return h
        }
        h := DllCall("FindWindowExW", "ptr", tbHwnd, "ptr", 0, "str", cls, "ptr", 0, "ptr")
        if (h && DllCall("IsWindowVisible", "ptr", h))
            return h
    }
    return 0
}

; The taskbar follows the SYSTEM theme. AppsUseLightTheme - the key the settings
; window reads - is a different setting and gets this backwards for anyone running
; a mixed theme, which is a supported combination in Windows 11.
IsTaskbarDark() {
    v := 0
    try v := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        , "SystemUsesLightTheme", 0)
    return (v = 0)
}

; open-meteo reports a WMO weather code. This maps it to one glyph.
;
; Built with Chr() rather than written as a literal so the .ahk source stays pure
; ASCII - AutoHotkey reads a BOM-less file in the system codepage, so a literal
; would arrive as mojibake on a machine with a different one. All of these are in
; the BMP on purpose: they live in Segoe UI Symbol, which font fallback finds. The
; astral-plane weather emoji need Segoe UI Emoji and come out as tofu in a plain
; Static control.
WeatherIcon(code) {
    if (code = 0)
        return Chr(0x2600)                      ; clear
    if (code = 1 || code = 2)
        return Chr(0x26C5)                      ; mainly clear / partly cloudy
    if (code >= 95)
        return Chr(0x26C8)                      ; thunderstorm
    if ((code >= 71 && code <= 77) || code = 85 || code = 86)
        return Chr(0x2744)                      ; snow
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
        return Chr(0x2614)                      ; drizzle / rain / showers
    return Chr(0x2601)                          ; overcast, fog, anything else
}

; The colour of the taskbar itself, so the block can be painted to disappear into
; it. Returns "" when it cannot be read, and the caller then keeps its theme-derived
; default rather than guessing.
;
; The sample point is deliberately to the LEFT of the block: sampling under the
; block would read the block's own pixels once it exists.
SampleTaskbarColor(tx, ty, th, blockX) {
    px := blockX - 12
    if (px < tx + 2)
        px := tx + 2
    try {
        CoordMode("Pixel", "Screen")
        c := PixelGetColor(px, ty + th // 2)
        if (c != "")
            return Format("{:06X}", c & 0xFFFFFF)
    }
    return ""
}

; One line, with the whole body behind a try, because this is a SetTimer callback:
; a throw here pops an error dialog and kills the timer for the rest of the session.
; That is not hypothetical - the version this replaces called
; ControlGetHwnd("TrayClockWClass", ...) with a bare class name, which is not a
; valid ClassNN, and AHK throws TargetError rather than returning 0. It died on its
; first tick, every time, so the feature had never once drawn anything.
UpdateCustomClock() {
    try UpdateCustomClockImpl()
}

PaintCustomClock() {
    global CustomClockTimeText, CustomClockTempText, CustomClockWeather, CustomClockWind
    if (CustomClockTimeText)
        try CustomClockTimeText.Value := FormatTime(, "HH:mm") "`n" FormatTime(, "dd.MM.yyyy")
    ; "--" rather than blank: an empty column is indistinguishable from a column
    ; that was never created, which is the confusion this feature already caused
    ; once. A placeholder says "this part is here and has nothing to show yet".
    if (CustomClockTempText) {
        ; "--" rather than blank: an empty column is indistinguishable from a column
        ; that was never created, which is the confusion this feature already caused
        ; once. A placeholder says "this part is here and has nothing to show yet".
        info := (CustomClockWeather == "") ? "--" : CustomClockWeather
        ; Gated on the temperature, not on the wind, so a failure that clears the
        ; reading cannot leave a stale wind line behind on its own.
        if (CustomClockWeather != "" && CustomClockWind != "")
            info .= "`n" CustomClockWind
        try CustomClockTempText.Value := info
    }
}

UpdateCustomClockImpl() {
    global CustomClockGui, CustomClockTimeText, CustomClockTempText
    global CustomClockBuiltFor, CustomClockRect, CLOCK_GAP
    global CustomClockWeather, LastWeatherFetch, WeatherNextMs, ClockWeatherEnabled, ClockAnchor

    ; Read the network first, so the fetch keeps its own schedule regardless of
    ; whether anything gets drawn this tick.
    PollWeather()
    if (LastWeatherFetch == 0 || (A_TickCount - LastWeatherFetch > WeatherNextMs))
        FetchWeather()

    tbHwnd := WinExist("ahk_class Shell_TrayWnd")
    ; The visibility test is the one that matters most: a full-screen app hides the
    ; taskbar, and an AlwaysOnTop overlay would otherwise sit on top of the game.
    if (!tbHwnd || !DllCall("IsWindowVisible", "ptr", tbHwnd)) {
        HideCustomClock()
        return
    }

    WinGetPos(&tx, &ty, &tw, &th, "ahk_id " tbHwnd)
    if (tw < 200 || th < 12) {
        HideCustomClock()
        return
    }

    ; Auto-hidden: Windows parks the bar two pixels inside its own monitor rather
    ; than moving it off-screen. This used to compare against A_ScreenHeight, which
    ; is the PRIMARY monitor - wrong the moment the taskbar is on a different one.
    monB := A_ScreenHeight, monR := A_ScreenWidth
    try {
        sm := ScreenMetrics()
        m := sm.mons[MonitorIndexAt(tx + tw // 2, ty + th // 2)]
        monB := m.b, monR := m.r
    }
    if (ty >= monB - 2 || tx >= monR - 2) {
        HideCustomClock()
        return
    }

    anchorLeft := ResolveClockAnchor(tbHwnd)
    if (!anchorLeft) {
        ; Nothing to measure against, so no way to prove we are not covering
        ; something. Draw nothing rather than guess.
        HideCustomClock()
        return
    }

    ; Widths from the font, not from a setting. The content is known - five glyphs
    ; of time over ten of date, at most six of temperature - so a width control
    ; could only ever be used to make it wrong. Segoe UI digits run about 0.6 em and
    ; em is about 4/3 of the point size at 96 dpi, which is what makes this follow
    ; the text size and the DPI instead of assuming either.
    fpt := Integer(Tune("clockFont"))
    glyph := fpt * 4 / 3 * 0.6
    dateW := Ceil(glyph * 10) + CLOCK_GAP
    ; The temperature column exists whenever the feature is on. Only its VALUE is
    ; conditional: it reads "--" until a location produces a reading. Sizing the
    ; column to zero when there was no reading yet is what made a feature that was
    ; merely unconfigured look like a feature that was broken.
    tempW := ClockWeatherEnabled ? Ceil(glyph * 9) + CLOCK_GAP : 0
    boxW := CLOCK_GAP + tempW + dateW + CLOCK_GAP
    x := anchorLeft - CLOCK_GAP - boxW
    if (x < tx) {
        HideCustomClock()
        return
    }

    ; Two stacked lines, centred vertically by hand: the taskbar can be 30 px or
    ; 48 px tall and nothing here may assume which.
    lineH := Ceil(fpt * 4 / 3 * 1.35)
    textY := (th - 2 * lineH) // 2
    if (textY < 0)
        textY := 0

    ; The block is painted in the TASKBAR'S OWN COLOUR, so the panel disappears and
    ; only the text reads. This replaces colour-key transparency, which fringed: a
    ; keyed background needs every background pixel to be exactly the key colour,
    ; but antialiased and ClearType glyph edges BLEND with it, those blended pixels
    ; are not the key any more, so they survive the keying and every character ends
    ; up haloed in the key colour. Magenta text edges, measured on screen.
    ;
    ; Sampling works here because the taskbar is one flat colour - measured 0x202020
    ; at x = 200, 600, 1000, 1200, 1300 and 1400, including over inactive task
    ; buttons - so there is no gradient to mismatch against.
    bgColor := IsTaskbarDark() ? "202020" : "F3F3F3"

    ; Colours, font, chrome and the column split are all fixed at creation, so a
    ; change to any of them rebuilds rather than restyles: Gui.SetFont only affects
    ; controls added after it, and a control cannot be resized into existence.
    stamp := bgColor "|" fpt "|" tempW "|" dateW "|" th
    if (CustomClockGui && CustomClockBuiltFor != stamp)
        HideCustomClock()

    if (!CustomClockGui) {
        dark := IsTaskbarDark()
        CustomClockGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 -DPIScale")
        CustomClockGui.MarginX := 0
        CustomClockGui.MarginY := 0
        ; Refined by one sample of the real bar, taken from a point LEFT of where the
        ; block goes so it can never sample itself. Only at creation: the taskbar
        ; colour does not change while the block sits on it, and a theme change
        ; rebuilds through the stamp anyway.
        sampled := SampleTaskbarColor(tx, ty, th, x)
        if (sampled != "")
            bgColor := sampled
        CustomClockGui.BackColor := bgColor
        CustomClockGui.SetFont("s" fpt " c" (dark ? "FFFFFF" : "1A1A1A") " q5", "Segoe UI")
        ; A WM_CLOSE arriving at a caption-less, click-through overlay is never a
        ; user closing a window. It is a process-wide close request - taskkill,
        ; Install.ps1's StopRunning, a Windows shutdown - that walked the process's
        ; top-level windows, found this one before the script's own hidden main
        ; window, and stopped there. Measured: with the block on screen the app
        ; NEVER exited and Bye() never ran, so a graceful close silently lost every
        ; setting and left the overlay behind. It is the first permanently visible
        ; overlay in the program, which is why nothing hit this before.
        CustomClockGui.OnEvent("Close", (*) => ExitApp())
        if (tempW) {
            ; Two lines, like the clock beside it: the condition glyph with the
            ; temperature, and the wind under it.
            CustomClockTempText := CustomClockGui.Add("Text"
                , "x" CLOCK_GAP " y" textY " w" (tempW - CLOCK_GAP)
                . " h" (2 * lineH) " Center", "")
        } else {
            CustomClockTempText := 0
        }
        CustomClockTimeText := CustomClockGui.Add("Text"
            , "x" (CLOCK_GAP + tempW) " y" textY " w" (dateW - CLOCK_GAP)
            . " h" (2 * lineH) " Center", "")
        CustomClockBuiltFor := stamp
        ; Text before Show: showing first costs one frame of an unpainted rectangle
        ; sitting on the taskbar.
        PaintCustomClock()
        CustomClockGui.Show("NA x" x " y" ty " w" boxW " h" th)
        WinSetTransColor(bgColor, CustomClockGui.Hwnd)
    }

    ; A one-shot producer: nothing else flushes for it, so it commits itself.
    ;
    ; The rect is diffed first. RenderCore deliberately does not cache positions -
    ; the user can move a window behind its back - but this window is ours alone, so
    ; the cache is valid here, and it is what lets the tick run at 250 ms for
    ; nothing. It has to be that fast because the anchor MOVES: one new tray icon
    ; shifted TrayNotifyWnd 24 px and left the block overlapping the tray until the
    ; next tick.
    rect := x "," ty "," boxW "," th
    if (rect != CustomClockRect) {
        RS_SetPos(CustomClockGui.Hwnd, x, ty, boxW, th, RS_PRI_AMBIENT)
        CustomClockRect := rect
    }
    ; Z-order is re-asserted every tick regardless: the taskbar is topmost too and
    ; comes to the front whenever it is clicked. On our own window that is one
    ; SetWindowPos with NOMOVE | NOSIZE, nothing like the 260 us a real move costs
    ; on a foreign window.
    RS_SetZOrder(CustomClockGui.Hwnd, -1, 0x0013, RS_PRI_AMBIENT)
    RS_Commit()

    PaintCustomClock()
}

ClockUrlPart(s) {
    ; CleanClockLocation has already reduced this to [A-Za-z0-9 ,.+-], so these
    ; three are the whole encoding problem. Nothing that could change the shape of
    ; the query - & = ? % / - can reach here.
    s := StrReplace(s, "+", "%2B")
    s := StrReplace(s, ",", "%2C")
    return StrReplace(s, " ", "+")
}

ForecastUrl() {
    global GeoLat, GeoLon, ClockUnits
    u := "https://api.open-meteo.com/v1/forecast"
        . "?current=temperature_2m,weather_code,wind_speed_10m"
        . "&latitude=" GeoLat "&longitude=" GeoLon

    ; Fahrenheit implies the rest of the imperial set, so the wind comes back in mph
    ; rather than km/h and the label below follows it.
    if (ClockUnits == "Fahrenheit")
        u .= "&temperature_unit=fahrenheit&wind_speed_unit=mph"
    return u
}

; WinHttp rather than Msxml2.XMLHTTP, and that is not a preference.
;
; Measured on this build: MSXML (3.0 and 6.0) returns status 200 with an EMPTY
; responseText for an application/json body - it will not decode a content type it
; does not consider text - so every reading came back blank. WinHttpRequest returns
; the body. It is opened async and polled with WaitForResponse(0), which returns
; immediately, so nothing on this path blocks; a bare WaitForResponse() would block
; the frame loop and every timer in the process.
StartWeatherRequest(stage, url) {
    global CustomClockReq, WeatherReqAt, WeatherStage
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        ; resolve, connect, send, receive - in ms. Async still needs these, or a
        ; dead route keeps the object alive until the process exits.
        req.SetTimeouts(4000, 8000, 8000, 12000)
        req.Open("GET", url, true)
        req.Send()
        CustomClockReq := req
        WeatherStage := stage
        WeatherReqAt := A_TickCount
        return
    }
    CustomClockReq := 0
    WeatherStage := ""
    WeatherFailed("the request could not be started")
}

; Two requests, because open-meteo takes coordinates rather than a place name: the
; geocoder resolves the city once and the result is cached for as long as the
; setting does not change, so the steady state is one request every 15 minutes.
;
; This replaced wttr.in, which was not dependable enough to build on: it answers
; 200 with its HTML landing page instead of an error status whenever it will not
; serve a reading, it did that for /Baku while answering /Berlin in plain text, it
; did it for ?format=%t on its own, and after roughly twenty requests in a few
; minutes it did it for everything - and then began timing out entirely. Every one
; of those is indistinguishable from success at the HTTP level.
FetchWeather() {
    global CustomClockReq, LastWeatherFetch, ClockLocation, GeoFor, CustomClockWeather
    global ClockWeatherEnabled, ClockWarnedNoCity
    if (CustomClockReq)
        return                        ; one in flight is enough
    ; Stamp the attempt BEFORE sending, or a slow endpoint would be re-requested on
    ; every tick. The interval itself is set by the outcome - see WeatherFailed and
    ; the success path in PollWeather - so this only records that we tried.
    LastWeatherFetch := A_TickCount
    ; No city, no network. The time and the date need nothing, so the block still
    ; draws - the temperature column simply is not there until a location is typed.
    ; This is also what makes the feature safe to default ON: out of the box it
    ; makes no outbound request whatsoever.
    ; Switched off, or no city: no request at all. The block still draws - the time
    ; and the date need nothing - and the temperature column shows "--". This is
    ; also what keeps the feature safe to default ON: out of the box it makes no
    ; outbound call whatsoever, and the egress begins only once a city is typed.
    if (!ClockWeatherEnabled) {
        CustomClockWeather := ""
        return
    }
    if (ClockLocation == "") {
        CustomClockWeather := ""
        ; Said once per session, and only because the column is visibly showing
        ; "--": the user can see something is missing, so tell them what fills it.
        if (!ClockWarnedNoCity) {
            ClockWarnedNoCity := true
            Notify("Taskbar clock: set a Location in Shift+Alt+W, Taskbar Clock`nto show the temperature.")
        }
        return
    }
    if (GeoFor != ClockLocation)
        StartWeatherRequest("geo", "https://geocoding-api.open-meteo.com/v1/search"
            . "?count=1&language=en&format=json&name=" ClockUrlPart(ClockLocation))
    else
        StartWeatherRequest("now", ForecastUrl())
}

; Polled from the clock tick rather than driven by an event handler. A handler is
; one more thing that has to work for the feature to work at all, and with MSXML it
; also forced the request object to be released from inside its own callback, while
; the library was still on the stack. The tick is already running, so this costs
; nothing and cannot fail in a way that is invisible.
PollWeather() {
    global CustomClockReq, WeatherStage, WeatherReqAt, CustomClockWeather
    global WeatherNextMs, WeatherFailMs, ClockLocation, ClockUnits
    global GeoFor, GeoLat, GeoLon, CustomClockWind
    if !CustomClockReq
        return
    ready := false
    try ready := CustomClockReq.WaitForResponse(0)
    catch {
        CustomClockReq := 0, WeatherStage := ""
        WeatherFailed("the connection failed")
        return
    }
    if (!ready) {
        if (A_TickCount - WeatherReqAt > 20000) {
            CustomClockReq := 0, WeatherStage := ""
            WeatherFailed("the request timed out")
        }
        return
    }
    status := 0, body := ""
    try status := CustomClockReq.Status
    try body := CustomClockReq.ResponseText
    stage := WeatherStage
    CustomClockReq := 0, WeatherStage := ""
    if (status != 200) {
        WeatherFailed("the server answered " status)
        return
    }

    if (stage == "geo") {
        ; results[0] first, so the first latitude/longitude in the body is the match.
        ; An unknown name comes back as 200 with {"generationtime_ms":...} and no
        ; results at all, which is why this is a parse failure rather than a status.
        if (!RegExMatch(body, '"latitude"\s*:\s*(-?[0-9.]+)', &mLa)
            || !RegExMatch(body, '"longitude"\s*:\s*(-?[0-9.]+)', &mLo)) {
            WeatherFailed("that place name was not found")
            return
        }
        GeoLat := mLa[1], GeoLon := mLo[1], GeoFor := ClockLocation
        StartWeatherRequest("now", ForecastUrl())     ; straight on to the reading
        return
    }

    ; The forecast body carries temperature_2m twice: once in current_units as the
    ; STRING "C, and once in current as the number. Requiring a digit right after
    ; the colon is what picks the second one.
    if !RegExMatch(body, '"temperature_2m"\s*:\s*(-?[0-9.]+)', &mT) {
        WeatherFailed("no temperature in the reply")
        return
    }
    n := Round(Number(mT[1]))
    ; Chr(176) rather than a literal degree sign, for the same ASCII-source reason
    ; as WeatherIcon.
    unit := (ClockUnits == "Fahrenheit") ? "F" : "C"
    temp := (n > 0 ? "+" : "") n Chr(176) unit

    ; The condition glyph and the wind are additive: a reply that omits either still
    ; produces a reading, because the temperature is the part that must be there.
    icon := ""
    if RegExMatch(body, '"weather_code"\s*:\s*([0-9]+)', &mC)
        icon := WeatherIcon(Integer(mC[1])) " "
    CustomClockWeather := icon temp

    CustomClockWind := ""
    if RegExMatch(body, '"wind_speed_10m"\s*:\s*(-?[0-9.]+)', &mW)
        CustomClockWind := Round(Number(mW[1])) (ClockUnits == "Fahrenheit" ? " mph" : " km/h")

    WeatherFailMs := 0
    WeatherNextMs := 900000
}

; Failure never reaches the taskbar: the block hides instead. It is said once per
; location in the log, and once in a tray tip when the user typed the location
; themselves, because "that city name does not work" is something only they can fix.
WeatherFailed(why) {
    global CustomClockWeather, ClockLocation, WeatherWarnedFor
    global WeatherNextMs, WeatherFailMs
    ; Back OFF rather than retrying at a fixed minute. The likeliest reason for a
    ; refusal is a rate limit at the far end - twenty wttr.in requests in a few
    ; minutes was enough to trip one, measured - and a fixed retry keeps you there.
    WeatherFailMs := Min(Max(WeatherFailMs * 3, 60000), 900000)
    WeatherNextMs := WeatherFailMs
    CustomClockWeather := ""
    key := ClockLocation == "" ? "(unset)" : ClockLocation
    if (WeatherWarnedFor == key)
        return
    WeatherWarnedFor := key
    WriteLog("Taskbar temperature: " why " (location: " key ")")
    Notify(ClockLocation == ""
        ? "Taskbar temperature needs a city.`nSet one in Shift+Alt+W, General."
        : "No temperature for " ClockLocation ".`n" why ".")
}
