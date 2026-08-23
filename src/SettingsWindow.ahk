; Settings window - the hand-rolled sidebar-nav GUI, and nothing else.
;
; Function definitions and global initialisers only, no top-level statements.
; ShowWin() is reached from Shift+Alt+W and from the tray.
;
; SOLE OWNER OF Win, Pages, NavItems, CurPage AND C. Nothing outside this file
; touches the control map. A toggle hotkey fires whether or not the window is
; open and Win may be a stale handle, so a caller that wants to reflect state
; into a checkbox goes through ToggleFeatureFlag() in FeatureToggles.ahk rather
; than reaching in here.
;
; THIS FILE CARRIES THE ENCODING HAZARD. Ten lines are deliberately non-ASCII:
; the emoji sidebar labels, which double as the Pages map keys, and the page
; titles that must match them exactly. AutoHotkey reads a BOM-less file as UTF-8,
; so this file must stay UTF-8 WITHOUT a BOM - Windows PowerShell 5.1 destroys
; that (Set-Content/Out-File default to UTF-16LE, and -Encoding utf8 adds a BOM).
; Mojibake here does not throw; it shows up as a nav page that never appears.
;
; ApplyUi(writeBack): the debounced Change path passes false, LoseFocus and close
; pass true. Correcting an out-of-range number back into its control 600 ms after
; the last keystroke rewrites the field while the user is still typing it.
;
; ApplyUi is declared bare "global" - assume-global - so EVERY assignment inside
; it creates a super-global. That is why its scratch variables carry a ui/ep
; prefix, and why a registry loop must never be written inline in it.

global Win := "", Pages := Map(), NavItems := Map(), CurPage := ""

global C := Map()

; =========================================================== Settings window ===========================================================

IsDark() {
    try return (RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                        "AppsUseLightTheme") = 0)
    return true
}

ShowWin() {
    global Win
    if (Win) {                       ; Win holds a Gui object, not a string
        try {
            WinActivate("ahk_id " Win.Hwnd)
            return
        }
        Win := ""                    ; stale handle - fall through and rebuild
    }
    BuildWin()
}

BuildWin() {
    global Win, Pages, NavItems, C, CurPage, VERSION
    global SnapEnabled, MagneticGroupsEnabled, ElasticScrollEnabled, SNAP_DISTANCE, CORNER_BOOST, NEIGHBOUR_PROX
    global TextMagnifierEnabled, SmartGridEnabled
    global RippleClickEnabled, ContextMenuAnimEnabled, ElasticDragEnabled, BreatheCursorEnabled
    global GlideEnabled, GLIDE_THROW, GLIDE_MS
    global BlackHoleMinimizeEnabled, MomentumTiltEnabled
    global CurtainDropEnabled
    global TaskbarWaveEnabled, CustomClockEnabled, ClockLocation, ClockUnits, ClockAnchor, ClockWeatherEnabled, ToastBounceEnabled, MonitorThrowEnabled, BlackHoleDeleteEnabled, CursorYawnEnabled, ShatterEnabled
    global RestoreEnabled, BreathingEnabled, OpenAnim, FlyMinimizeEnabled, RollUpEnabled, TrayMinimizeEnabled, BossKeyEnabled, AltDragEnabled, TaskbarScrollEnabled, QuickFolderJumpEnabled, PlainPasteEnabled, MorphingPasteEnabled, ClipboardAppendEnabled, SmoothCaretEnabled, TypingSoundsEnabled, HotkeySoundsEnabled, CopyFeedbackEnabled, SmartCapsEnabled, SmartCapsAction, ParallaxEnabled, EP_Style, EP_IconSize
    global NAV, SEL, SELF, FG, EDITBG, EDITFG

    dark := IsDark()
    BG   := dark ? "1F1F1F" : "F5F5F5"      ; content background
    NAV  := dark ? "171717" : "E6E6E6"      ; sidebar
    FG   := dark ? "FFFFFF" : "141414"      ; primary text
    cSub  := dark ? "9A9A9A" : "5A5A5A"      ; secondary text
    SEL  := dark ? "0F5FA6" : "CCE4F7"      ; selected nav
    SELF := dark ? "FFFFFF" : "0A0A0A"      ; selected nav text
    ; EVERY Edit AND DropDownList NEEDS BOTH A BACKGROUND AND A TEXT COLOUR.
    ; The Gui BackColor reaches an input control's background but never its
    ; text, which stays the system default black - so in dark mode every input
    ; was black on near-black and could only be read while it was selected and
    ; the highlight inverted it. TuneRow builds most of them, hence the global.
    EDITBG := dark ? "2B2B2B" : "FFFFFF"    ; input background
    EDITFG := dark ? "F0F0F0" : "141414"    ; input text

    W := 780, H := 700, SW := 196

    g := Gui("+Resize +OwnDialogs", "Window Tweaks")
    g.OnEvent("Size", Gui_Size)
    OnMessage(0x020A, OnMouseWheel)
    g.BackColor := BG
    g.MarginX := 0, g.MarginY := 0
    Win := g
    Pages := Map(), NavItems := Map(), C := Map()

    ; --- sidebar ---
    g.SidebarBg := g.AddText("x0 y0 w" SW " h" H " Background" NAV)
    g.SetFont("s13 bold", "Segoe UI")
    g.AddText("x20 y22 w160 c" FG " Background" NAV, "Window Tweaks")
    g.SetFont("s8 norm", "Segoe UI")
    g.AddText("x21 y50 w160 c" cSub " Background" NAV, "version " VERSION)

    g.SetFont("s10 norm", "Segoe UI")
    ny := 88
    for name in ["🪟 Window Management", "⚡ Power Features", "🔊 System & Media", "🖥️ Multi-Monitor", "✨ Animation", "🕒 Taskbar Clock", "📐 Hot Corners", "⚙️ General"] {
        t := g.AddText("x0 y" ny " w" SW " h42 +0x200 c" FG " Background" NAV, "    " name)
        t.OnEvent("Click", NavClick.Bind(name))
        NavItems[name] := t
        ny += 42
    }

    g.SetFont("s8", "Segoe UI")
    g.HintLbl := g.AddText("x20 y" (H - 40) " w160 c" cSub " Background" NAV, "Shift+Alt+W  opens this")

    ; --- content ---
    CX := SW + 28, CW := W - SW - 56

    ; Registers under 'name' as well as building the page, so the nav key is
    ; written once. It used to be repeated in a trailing Pages[...] := pg, and
    ; the two names had to agree or the page silently never showed.
    CreatePage(name) {
        pg := Gui("+Parent" Win.Hwnd " -Caption")
        pg.BackColor := BG
        pg.MarginX := 0, pg.MarginY := 26
        Pages[name] := pg
        return pg
    }

    ; ---- Window Management
    pg := CreatePage("🪟 Window Management")
    Head(pg, CW, FG, "Window Management")
    Sub(pg, CW, cSub, "Fluid, physics-based movement and snapping.", "xm y+10")
    
    C["snap"] := Box(pg, CW, FG, "Enable magnetic snapping", SnapEnabled, "xm y+16")
    C["magnetic"] := Box(pg, CW, FG, "Magnetic Window Groups (Shift+Alt+J)", MagneticGroupsEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Groups windows together when snapped. Dragging one will pull the other.", "xm y+8")
    
    C["shatter"] := Box(pg, CW, FG, "Shatter to Close (Shift+Alt+F4)", ShatterEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Aggressively close the active window by smashing it into dozens of 3D glass shards.", "xm y+8")
    
    C["smartgrid"] := Box(pg, CW, FG, "Smart Tiling Grid (Hold Shift while dragging)", SmartGridEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shows a visual 3-zone layout grid. Drop the window into a zone to snap it.", "xm y+8")
    TuneRow(pg, "gridGap", FG, cSub)

    C["elastic"] := Box(pg, CW, FG, "Rubber-Band Scroll (Kinetic lean)", ElasticScrollEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Scrolling forcefully pulls the entire window elastically, springing back when stopped.", "xm y+8")
    TuneRow(pg, "elasticAmt", FG, cSub)

    TuneRow(pg, "snapDist",  FG, cSub)
    TuneRow(pg, "snapAdapt", FG, cSub)
    TuneRow(pg, "snapHyst",  FG, cSub)
    TuneRow(pg, "snapBoost", FG, cSub)
    TuneRow(pg, "snapProx",  FG, cSub)
    C["glide"] := Box(pg, CW, FG, "Enable ice glide (Physics-based throwing)", GlideEnabled, "xm y+16")
    TuneRow(pg, "glideThrow",  FG, cSub)
    TuneRow(pg, "glideMs",     FG, cSub)
    TuneRow(pg, "glideMax",    FG, cSub)
    TuneRow(pg, "glideSettle", FG, cSub)

    C["parallax"] := Box(pg, CW, FG, "Parallax Dragging (Velocity Transparency)", ParallaxEnabled, "xm y+16")
    Sub(pg, CW, cSub, "A window fades while you drag it and springs back to solid when you let go.", "xm y+8")
    TuneRow(pg, "parallaxFrom", FG, cSub)
    TuneRow(pg, "parallaxFull", FG, cSub)
    TuneRow(pg, "parallaxMin", FG, cSub)
    C["altdrag"] := Box(pg, CW, FG, "Linux-Style Alt-Drag (Move & Resize)", AltDragEnabled, "xm y+12")
    
    C["fly"] := Box(pg, CW, FG, "Fly-to-Mouse Minimize (vacuum effect)", FlyMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Minimizes windows to your cursor rather than the taskbar.", "xm y+8")
    
    C["blackhole"] := Box(pg, CW, FG, "Black Hole Minimize (Taskbar suck effect)", BlackHoleMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Minimizes windows directly into the bottom center like a funnel.", "xm y+8")
    
    C["curtain"] := Box(pg, CW, FG, "Curtain Drop (Win+Alt+D)", CurtainDropEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Smoothly drops windows down off-screen instead of instantly vanishing.", "xm y+8")
    
    C["grabpan"] := Box(pg, CW, FG, "Universal Grab && Pan (Shift+Alt+Space)", GrabPanEnabled, "xm y+12")
    C["rollup"] := Box(pg, CW, FG, "Middle-click title bar to roll up", RollUpEnabled, "xm y+12")
    Sub(pg, CW, cSub, "Shift+Alt+R rolls a window up whether this is on or off - this is the mouse gesture.", "xm y+8")
    
    C["mem"] := Box(pg, CW, FG, "Remember window positions", RestoreEnabled, "xm y+16")
    b := pg.AddButton("xm y+12 w190 h30", "Forget saved positions")
    b.OnEvent("Click", (*) => ForgetPositions())

    ; ---- Power Features
    pg := CreatePage("⚡ Power Features")
    Head(pg, CW, FG, "Power Features")
    Sub(pg, CW, cSub, "Advanced overlays, widgets, and shortcuts.", "xm y+10")
    
    C["spotlight"] := Box(pg, CW, FG, "Quick Spotlight Launcher (Double-tap Ctrl)", SpotlightEnabled, "xm y+16")
    Sub(pg, CW, cSub, "A fast, minimalist search bar for calculations, folders, and apps.", "xm y+8")
    
    C["pip"] := Box(pg, CW, FG, "Live Window PiP (Shift+Alt+P)", LivePipEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Shift+Alt+P on any window to create a live, always-on-top thumbnail.", "xm y+8")
    
    C["ghost"] := Box(pg, CW, FG, "Proximity Ghost Window (Shift+Alt+G)", ProximityGhostEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Turns active window into an interactive ghost overlay that fades in as your mouse approaches.", "xm y+8")
    TuneRow(pg, "ghostAlpha", FG, cSub)
    TuneRow(pg, "ghostRange", FG, cSub)
    TuneRow(pg, "ghostClick", FG, cSub)

    C["bottom"] := Box(pg, CW, FG, "Always on Bottom / Widget (Shift+Alt+B)", AlwaysOnBottomEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Pins any window permanently to your desktop background, transforming it into a widget.", "xm y+8")
    
    C["midclose"] := Box(pg, CW, FG, "Middle-Click Titlebar to Close", MiddleClickCloseEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Overrides Roll-Up. Middle-click any window's title bar to close it.", "xm y+8")
    
    C["traymin"] := Box(pg, CW, FG, "Minimize to Tray (Shift+Alt+H)", TrayMinimizeEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Hides the active window completely and creates a custom System Tray icon.", "xm y+8")
    
    C["quickfolder"] := Box(pg, CW, FG, "Quick Folder Jump (Ctrl+G in dialogs)", QuickFolderJumpEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Ctrl+G in any File Dialog to jump to the last active Explorer folder.", "xm y+8")
    
    C["quicklook"] := Box(pg, CW, FG, "macOS Quick Look (Spacebar Preview)", QuickLookEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Press Space on any file in Explorer to preview files instantly.", "xm y+8")

    ; ---- System & Media
    pg := CreatePage("🔊 System & Media")
    Head(pg, CW, FG, "System & Media")
    Sub(pg, CW, cSub, "Audio, typing, and system-wide controls.", "xm y+10")

    ; THE SOUND SETTINGS LIVE AT THE TOP OF THIS PAGE, and both halves of that
    ; matter. They used to sit ~980 px down the Multi-Monitor page: this window
    ; is 700 px tall and scrolls without a scrollbar, so the levels were below
    ; the fold, on a page whose name promises monitors rather than audio. A
    ; setting nobody can reach is indistinguishable from one that does not work.
    C["typingsounds"] := Box(pg, CW, FG, "Mechanical Keystroke Sounds", TypingSoundsEnabled, "xm y+16")
    Sub(pg, CW, cSub, "A synthesised switch click on every key, with its own voice for space, enter, backspace and copy/cut/paste.", "xm y+8")
    TuneRow(pg, "keyVol", FG, cSub)
    TuneRow(pg, "keyTone", FG, cSub)

    C["hotkeysounds"] := Box(pg, CW, FG, "Hotkey Sounds", HotkeySoundsEnabled, "xm y+16")
    Sub(pg, CW, cSub, "A distinct sound when a command runs - rising for a feature switched on, falling for off, a deeper tone for restore-all and the boss key.", "xm y+8")
    TuneRow(pg, "hotkeyVol", FG, cSub)
    
    C["taskbarscroll"] := Box(pg, CW, FG, "Taskbar Volume Scroll", TaskbarScrollEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Scroll over the taskbar to adjust volume. Middle-click to mute.", "xm y+8")
    
    C["osd"] := Box(pg, CW, FG, "Premium Volume OSD", PremiumVolumeOSDEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Show a sleek, macOS-style volume indicator when scrolling the taskbar.", "xm y+8")
    TuneRow(pg, "osdStep",  FG, cSub)
    TuneRow(pg, "osdHide",  FG, cSub)
    TuneRow(pg, "osdAlpha", FG, cSub)

    C["mickill"] := Box(pg, CW, FG, "Global Mic Kill-Switch (Double-tap Alt)", MicKillSwitchEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Quickly double-tap the Alt key to instantly mute or unmute your microphone system-wide.", "xm y+8")
    
    C["bosskey"] := Box(pg, CW, FG, "Boss Key (Shift+Alt+Esc)", BossKeyEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Instantly hides all windows and mutes system volume. Press again to restore.", "xm y+8")
    
    C["expander"] := Box(pg, CW, FG, "Global Text Expander (Snippets)", TextExpanderEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Type @@mail, @@tel, @@date to auto-expand. Edit snippets in WindowTweaks.ini", "xm y+8")
    
    C["smartcaps"] := Box(pg, CW, FG, "Smart Caps Lock (Hold for Caps, Tap for action)", SmartCapsEnabled, "xm y+16")
    C["smartcaps_act"] := pg.AddDropDownList("x320 yp-3 w90 Background" EDITBG " c" EDITFG " Choose" IndexOf(CAPS_ACTIONS, SmartCapsAction), CAPS_ACTIONS)
    Sub(pg, CW, cSub, "Holding CapsLock for 0.4s toggles CapsLock. Tapping it sends Esc or Backspace.", "xm y+8")
    
    C["plainpaste"] := Box(pg, CW, FG, "Plain-Text Paste (Ctrl+Alt+V)", PlainPasteEnabled, "xm y+16")
    
    C["morphingpaste"] := Box(pg, CW, FG, "Morphing Paste (Ctrl+V + Scroll)", MorphingPasteEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Scroll wheel while holding Ctrl+V to cycle casing (camelCase, snake_case).", "xm y+8")

    C["clipboardappend"] := Box(pg, CW, FG, "Clipboard Append (Double Ctrl+C)", ClipboardAppendEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Double-tap Ctrl+C to append selection to the current clipboard content.", "xm y+8")

    ; Editable at last: this drives MediaCore's fallback list, which decides
    ; which programs are never dimmed by breathing or the monitor dimmer, and
    ; until now it could only be changed by hand-editing settings.ini.
    Lbl(pg, FG, "Never dim these apps", "xm y+20", 190)
    C["mediafallback"] := pg.AddEdit("xm y+6 w" CW " Background" EDITBG " c" EDITFG, MediaFallbackList)
    ; No " ;" in this string: a space followed by a semicolon starts a comment
    ; even INSIDE a quoted string, so the literal would truncate mid-argument and
    ; the file would fail to load with "Missing """. Same reason the shipped
    ; media_fallback default writes "a.exe; b.exe" and never "a.exe ; b.exe".
    Sub(pg, CW, cSub, "Executable names, comma or semicolon separated - used when no audio API reports playback.", "xm y+6")

    ; ---- Multi-Monitor
    pg := CreatePage("🖥️ Multi-Monitor")
    Head(pg, CW, FG, "Multi-Monitor & Visuals")
    Sub(pg, CW, cSub, "Dual/Triple monitor optimizations and focus effects.", "xm y+10")
    
    C["shakefind"] := Box(pg, CW, FG, "Shake to Find Cursor (macOS style)", ShakeFindEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shake your mouse left and right rapidly to make the cursor temporarily grow.", "xm y+8")
    TuneRow(pg, "shakeCount", FG, cSub)
    TuneRow(pg, "shakeSize",  FG, cSub)

    C["cursoryawn"] := Box(pg, CW, FG, "Cursor Yawn (Wakes up after idle)", CursorYawnEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Cursor stretches and 'yawns' the first time you touch it after a long idle.", "xm y+8")
    TuneRow(pg, "yawnIdle", FG, cSub)

    C["monthrow"] := Box(pg, CW, FG, "Window Throw & Catch (Monitor to Monitor)", MonitorThrowEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Throw a window forcefully towards another monitor to make it fly and land in the center.", "xm y+8")
    
    C["ripple"] := Box(pg, CW, FG, "Ripple Click (Tactile water ripple on click)", RippleClickEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Draws a fast fading ripple when you left click.", "xm y+8")
    
    C["contextanim"] := Box(pg, CW, FG, "Context Menu Unfold (Origami open animation)", ContextMenuAnimEnabled, "xm y+16")
    C["elasticdrag"] := Box(pg, CW, FG, "Elastic Drag (Rubber band trail when dragging)", ElasticDragEnabled, "xm y+16")
    C["breathe"] := Box(pg, CW, FG, "Breathe Cursor (Idle glow effect)", BreatheCursorEnabled, "xm y+16")
    
    C["momentum"] := Box(pg, CW, FG, "Momentum Tilt (Jello bounce on drag stop)", MomentumTiltEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Window jiggles elastically when you suddenly stop moving it.", "xm y+8")
    
    C["smoothcaret"] := Box(pg, CW, FG, "Smooth Gliding Caret & Word Pop", SmoothCaretEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Premium macOS-style gliding caret interpolation and word completion feedback.", "xm y+8")

    C["copyfeedback"] := Box(pg, CW, FG, "Minimal Copy/Paste Feedback", CopyFeedbackEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Subtle visual vacuum collection and paste glow indicators.", "xm y+8")

    C["textmag"] := Box(pg, CW, FG, "Text Selection Magnifier (iOS style)", TextMagnifierEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shows a 2x zoom loupe when selecting text.", "xm y+8")
    
    C["wrap"] := Box(pg, CW, FG, "Infinite Cursor Wrap (Shift+Alt+I)", InfiniteWrapEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Push the cursor into the left/right edge of the desktop and hold to teleport to the other side.", "xm y+8")
    TuneRow(pg, "wrapTol",   FG, cSub)
    TuneRow(pg, "wrapDelay", FG, cSub)
    TuneRow(pg, "wrapSpeed", FG, cSub)
    TuneRow(pg, "wrapCool",  FG, cSub)

    C["multidimmer"] := Box(pg, CW, FG, "Multi-Monitor Focus Dimmer (Shift+Alt+D)", MultiMonitorDimmerEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Automatically dims every monitor except the one your mouse is currently on.", "xm y+8")
    TuneRow(pg, "dimmerAlpha", FG, cSub)

    C["breath"] := Box(pg, CW, FG, "Breathing (dim inactive windows)", BreathingEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Windows fade out once you have not touched them for a while.", "xm y+8")
    TuneRow(pg, "breatheIdle",  FG, cSub)
    TuneRow(pg, "breatheAlpha", FG, cSub)

    Lbl(pg, FG, "New window animation", "xm y+16")
    C["openanim"] := pg.AddDropDownList("x160 yp-3 w160 Background" EDITBG " c" EDITFG " Choose" IndexOf(OPEN_ANIMS, OpenAnim), OPEN_ANIMS)

    ; ---- Animation & Timing
    ; The cross-cutting motion values. Everything on this page affects more than
    ; one feature, so it does not belong under any single checkbox.
    pg := CreatePage("✨ Animation")
    Head(pg, CW, FG, "Animation & Timing")
    Sub(pg, CW, cSub, "How long things take and how far they move. Lower is snappier.", "xm y+10")

    Lbl(pg, FG, "Window animations", "xm y+16")
    TuneRow(pg, "animOpenMs",    FG, cSub)
    TuneRow(pg, "animOpenSlide", FG, cSub)
    TuneRow(pg, "animBounceMs",  FG, cSub)
    TuneRow(pg, "animBounce",    FG, cSub)
    TuneRow(pg, "animRollMs",    FG, cSub)
    TuneRow(pg, "animGravityMs", FG, cSub)

    Lbl(pg, FG, "Overlays", "xm y+20")
    TuneRow(pg, "animFadeMs",   FG, cSub)
    TuneRow(pg, "animNotchMs",  FG, cSub)

    Lbl(pg, FG, "Focus mode (Shift+Alt+F)", "xm y+20")
    TuneRow(pg, "focusAlpha",   FG, cSub)
    TuneRow(pg, "focusFeather", FG, cSub)
    TuneRow(pg, "focusRadius",  FG, cSub)

    Lbl(pg, FG, "Transparency wheel (Shift+Alt+Wheel)", "xm y+20", 300)
    TuneRow(pg, "transStep", FG, cSub)
    TuneRow(pg, "transMin",  FG, cSub)

    ; ---- Taskbar Clock
    pg := CreatePage("🕒 Taskbar Clock")
    Head(pg, CW, FG, "Taskbar Clock")

    C["customclock"] := Box(pg, CW, FG, "Show a clock block on the taskbar", CustomClockEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Time over date, with the temperature beside it. Windows keeps drawing its own", "xm y+8")
    Sub(pg, CW, cSub, "clock, date and tray icons - this never replaces them, it sits next to them.", "xm y+2")

    Lbl(pg, FG, "Sit beside", "xm y+16", 190)
    C["clockanchor"] := pg.AddDropDownList("x196 yp-3 w120 Background" EDITBG " c" EDITFG " Choose" IndexOf(CLOCK_ANCHORS, ClockAnchor), CLOCK_ANCHORS)
    Sub(pg, 250, cSub, "TrayEdge covers nothing", "x+12 yp+3")
    Sub(pg, CW, cSub, "Clock puts it right beside the clock, but then it covers the tray buttons in", "xm y+8")
    Sub(pg, CW, cSub, "that space. TrayEdge sits left of every tray icon and hides nothing at all.", "xm y+2")
    Sub(pg, CW, cSub, "TaskbarLeft places it at the far left of the taskbar.", "xm y+2")

    TuneRow(pg, "clockFont", FG, cSub)

    C["clockweather"] := Box(pg, CW, FG, "Show the temperature", ClockWeatherEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Shows -- until a location is set below. Setting one is what starts the only", "xm y+8")
    Sub(pg, CW, cSub, "outbound request this program makes: open-meteo.com, once every 15 minutes.", "xm y+2")

    Lbl(pg, FG, "Location", "xm y+16", 190)
    C["clockloc"] := pg.AddEdit("x196 yp-3 w120 Background" EDITBG " c" EDITFG, ClockLocation)
    Sub(pg, 250, cSub, "a city, e.g. Baku", "x+12 yp+3")

    Lbl(pg, FG, "Units", "xm y+16", 190)
    C["clockunits"] := pg.AddDropDownList("x196 yp-3 w120 Background" EDITBG " c" EDITFG " Choose" IndexOf(CLOCK_UNITS, ClockUnits), CLOCK_UNITS)


    ; ---- Hot Corners
    pg := CreatePage("📐 Hot Corners")
    Head(pg, CW, FG, "macOS Hot Corners")
    Sub(pg, CW, cSub, "Throw your mouse into the corners of the screen to trigger actions.", "xm y+10")
    
    C["corners_en"] := Box(pg, CW, FG, "Enable Hot Corners (Shift+Alt+C)", HotCornersEnabled, "xm y+16")
    TuneRow(pg, "cornerSize",  FG, cSub)
    TuneRow(pg, "cornerDelay", FG, cSub)

    ; Choose by index, not by text: Choose("something not in the list") throws,
    ; and it would throw here - inside BuildWin, with no catch - which used to
    ; leave Shift+Alt+W permanently broken after a hand-edited settings.ini.
    ; LoadSettings validates these now; IndexOf is the second line of defence.
    ; ONE PER ROW. The right-hand pair used to sit in a second column built out
    ; of "x+30" and "x+10" relative offsets, which put them at x=700 on a page
    ; whose content is ~528 wide - both dropdowns ran off the edge and were
    ; clipped to a sliver, unreadable and barely clickable. Every other page in
    ; this window is a single column of label-then-control; so is this one now.
    Lbl(pg, FG, "Top Left:", "xm y+20", 130)
    C["corner_tl"] := pg.AddDropDownList("x140 yp-3 w180 Background" EDITBG " c" EDITFG " Choose" IndexOf(CORNER_ACTIONS, HotCornerTL), CORNER_ACTIONS)

    Lbl(pg, FG, "Top Right:", "xm y+14", 130)
    C["corner_tr"] := pg.AddDropDownList("x140 yp-3 w180 Background" EDITBG " c" EDITFG " Choose" IndexOf(CORNER_ACTIONS, HotCornerTR), CORNER_ACTIONS)

    Lbl(pg, FG, "Bottom Left:", "xm y+14", 130)
    C["corner_bl"] := pg.AddDropDownList("x140 yp-3 w180 Background" EDITBG " c" EDITFG " Choose" IndexOf(CORNER_ACTIONS, HotCornerBL), CORNER_ACTIONS)

    Lbl(pg, FG, "Bottom Right:", "xm y+14", 130)
    C["corner_br"] := pg.AddDropDownList("x140 yp-3 w180 Background" EDITBG " c" EDITFG " Choose" IndexOf(CORNER_ACTIONS, HotCornerBR), CORNER_ACTIONS)
    ; ---- General
    pg := CreatePage("⚙️ General")
    Head(pg, CW, FG, "General Settings")
    
    C["auto"] := Box(pg, CW, FG, "Start with Windows", IsAutoStart(), "xm y+16")

    C["gravityclose"] := Box(pg, CW, FG, "Gravity Drop on Close (Alt+F4)", GravityCloseEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Closing a window drops it off the screen. Off leaves Alt+F4 entirely to Windows.", "xm y+8")

    C["debuglog"] := Box(pg, CW, FG, "Write a debug log (snap.log)", DEBUG, "xm y+16")
    Sub(pg, CW, cSub, "Only needed when reporting a problem. Buffered in memory, written when idle.", "xm y+8")
    
    C["smart_tb"] := Box(pg, CW, FG, "Smart Auto-Hide Taskbar (Shift+Alt+T)", SmartTaskbarEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Only hides taskbar when windows maximize or touch the bottom edge.", "xm y+8")
    
    C["deletehole"] := Box(pg, CW, FG, "Recycle Bin Black Hole (Delete Animation)", BlackHoleDeleteEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Deleting a file visually sucks it into a top-left singularity (spaghettification).", "xm y+8")
    
    C["twave"] := Box(pg, CW, FG, "Taskbar Icon Wave", TaskbarWaveEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Hovering over the taskbar creates a magnifying glass bubble that tracks your mouse.", "xm y+8")
    
    ; The taskbar clock has its own page - see CreatePage("[clock]") above.
    
    C["toast"] := Box(pg, CW, FG, "Elastic Toast Notifications", ToastBounceEnabled, "xm y+16")
    Sub(pg, CW, cSub, "Notifications slide in elastically with an overshoot bounce.", "xm y+8")

    Lbl(pg, FG, "Taskbar Style", "xm y+16")
    C["epStyle"] := pg.AddDropDownList("x170 yp-3 w100 Background" EDITBG " c" EDITFG " Choose" IndexOf(EP_STYLES, EP_Style), EP_STYLES)
    Sub(pg, 220, cSub, "Win10 supports small icons", "x+16 yp+3")

    Lbl(pg, FG, "Icon Size", "xm y+16")
    C["epIconSize"] := pg.AddDropDownList("x170 yp-3 w100 Background" EDITBG " c" EDITFG " Choose" IndexOf(EP_ICON_SIZES, EP_IconSize), EP_ICON_SIZES)
    
    b2 := pg.AddButton("xm y+24 w150 h30", "Restart Explorer")
    b2.OnEvent("Click", (*) => RestartExplorer())
    
    b := pg.AddButton("xm y+24 w150 h30", "Open log")
    b.OnEvent("Click", (*) => OpenLog())
    b3 := pg.AddButton("x+12 yp w150 h30", "Open folder")
    b3.OnEvent("Click", (*) => Run(A_ScriptDir))
    b4 := pg.AddButton("xm y+12 w150 h30", "Hotkeys")
    b4.OnEvent("Click", (*) => ShowHotkeys())
    b5 := pg.AddButton("x+12 yp w150 h30", "Guide")
    b5.OnEvent("Click", (*) => OpenDoc("GUIDE.md"))
    ; Stealth Panic ships with this program and had no entry point anywhere in
    ; the UI - not a page, not a button, not a tray item.
    b6 := pg.AddButton("xm y+12 w312 h30", "Stealth Panic Mode settings (Esc Esc Esc)")
    b6.OnEvent("Click", (*) => OpenStealthPanicSettings())

    g.OnEvent("Close", (*) => CloseWin(g))
    g.OnEvent("Escape", (*) => CloseWin(g))

    for key, ctl in C {
        if (key == "epStyle" || key == "epIconSize" || key == "clockanchor" || key == "clockunits")
            ctl.OnEvent("Change", (*) => ApplyUi(true))
        else if InStr(ctl.Type, "CheckBox")
            ctl.OnEvent("Click", (*) => ApplyUi(true))
        else {
            ; Typed fields apply on their own, debounced, so a value takes
            ; effect without needing to click something else afterwards.
            ;
            ; The debounced path deliberately passes writeBack = false. Correcting
            ; an out-of-range number back into the control 600 ms after the last
            ; keystroke would rewrite the field while the user is still typing it -
            ; "3" on the way to "330" becomes the clamped minimum. The correction
            ; happens when focus leaves instead, which is when the user is done.
            ctl.OnEvent("Change", (*) => SetTimer(ApplyUi, -600))
            ctl.OnEvent("LoseFocus", (*) => ApplyUi(true))
        }
    }

    if dark {
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 20, "int*", 1, "uint", 4)
        for ctl in g {
            if (ctl.Type = "Edit" || ctl.Type = "ComboBox" || ctl.Type = "Button")
                DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
        }
        for pname, cpg in Pages {
            for ctl in cpg {
                if (ctl.Type = "Edit" || ctl.Type = "ComboBox" || ctl.Type = "Button")
                    DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
            }
        }
    }

    g.Show("w" W " h" H)
    SelectPage("🪟 Window Management")
}

Head(pg, w, col, txt, pos := "xm") {
    pg.SetFont("s14 bold", "Segoe UI")
    t := pg.AddText(pos " w" w " c" col, txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return t
}

Sub(pg, w, col, txt, pos := "xm y+8") {
    pg.SetFont("s9 norm", "Segoe UI")
    return pg.AddText(pos " w" w " c" col, txt)
}

; `w` defaults to the original 160 so every existing call is unchanged; the
; generated tuning rows pass a wider label because their names are longer.
Lbl(pg, col, txt, pos := "xm y+16", w := 160) {
    pg.SetFont("s10 norm", "Segoe UI")
    t := pg.AddText(pos " w" w " c" col, txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return t
}

Box(pg, w, col, txt, checked, pos := "xm y+16") {
    pg.SetFont("s10 norm", "Segoe UI")
    ; 'ctl', not 'c' - AHK identifiers are case-insensitive, so 'c' is the
    ; global control Map C.
    ctl := pg.AddCheckbox(pos " w" w " c" col (checked ? " Checked" : ""), txt)
    pg.SetFont("s9 norm", "Segoe UI")
    return ctl
}

; The pages scroll on the mouse wheel (OnMouseWheel) but there is no scrollbar, so
; nothing tells the user that a long page continues below the fold. This turns the
; sidebar hint into that affordance. Called whenever the page or the window size
; changes - the two things that can alter whether anything is hidden.
UpdatePageHint() {
    global Win, CurPage, Pages
    if (!Win || !CurPage || !Pages.Has(CurPage))
        return
    try {
        Pages[CurPage].GetPos(, , , &pageH)
        Win.GetClientPos(, , , &clientH)
        Win.HintLbl.Text := (pageH > clientH)
            ? "Scroll for more settings"
            : "Shift+Alt+W  opens this"
    }
}

NavClick(name, *) => SelectPage(name)

SelectPage(name) {
    global Pages, NavItems, CurPage, Win, NAV, SEL, SELF, FG
    if !Pages.Has(name)
        return

    for pname, pg in Pages {
        if (pname = name) {
            y_off := pg.HasOwnProp("Y_Offset") ? pg.Y_Offset : 0
            pg.Show("x224 y" y_off " w528 NoActivate")
        } else {
            pg.Hide()
        }
    }
    
    for pname, item in NavItems {
        item.Opt((pname = name) ? "Background" SEL " c" SELF : "Background" NAV " c" FG)
        item.Redraw()
    }
    CurPage := name
    UpdatePageHint()
}

Gui_Size(thisGui, minMax, width, height) {
    if (minMax = -1)
        return
    try thisGui.SidebarBg.Move(,,, height)
    try thisGui.HintLbl.Move(, height - 40)
    UpdatePageHint()
    
    global CurPage, Pages
    if CurPage && Pages.Has(CurPage) {
        pg := Pages[CurPage]
        if !pg.HasOwnProp("Y_Offset")
            pg.Y_Offset := 0
        pg.GetPos(,,, &h)
        minY := height - h
        if (minY > 0)
            minY := 0
        if (pg.Y_Offset < minY) {
            pg.Y_Offset := minY
            pg.Move(, minY)
        }
    }
}

OnMouseWheel(wParam, lParam, msg, hwnd) {
    global CurPage, Pages, Win
    if !Win || !CurPage || !Pages.Has(CurPage)
        return
    if !WinActive("ahk_id " Win.Hwnd)
        return
        
    pg := Pages[CurPage]
    delta := (wParam << 32 >> 48)
    
    if !pg.HasOwnProp("Y_Offset")
        pg.Y_Offset := 0
        
    newY := pg.Y_Offset + (delta > 0 ? 40 : -40)
    
    pg.GetPos(,,, &h)
    Win.GetClientPos(,,, &ph)
    
    minY := ph - h
    if (minY > 0)
        minY := 0
        
    if (newY > 0)
        newY := 0
    if (newY < minY)
        newY := minY
        
    pg.Y_Offset := newY
    pg.Move(, newY)
}

; Closing the window used to run SaveSettings() and only THEN cancel the pending
; debounced ApplyUi, so a value typed within 600 ms of closing was thrown away.
; Apply first, then save, then tear down.
CloseWin(g) {
    global Win
    SetTimer(ApplyUi, 0)
    ApplyUi(true)
    SaveSettings()
    try g.Destroy()
    Win := ""
}

; writeBack corrects an out-of-range number back into its control. Only the
; LoseFocus and close paths ask for it - the debounced Change path must not,
; because rewriting a field between keystrokes turns a half-typed "3" into the
; clamped minimum and the user can never finish typing "330".
ApplyUi(writeBack := false) {
    ; Bare 'global', like LoadSettings/SaveSettings. A partial list is a trap
    ; here: AHK v2 makes a silent local out of any name assigned but not
    ; declared, so a missing entry means that control quietly does nothing.
    global
    if !Win
        return

    ; Reading the controls and acting on them are separated on purpose. It used
    ; to be one long try with no catch, so a single failing control skipped every
    ; assignment after it AND the SaveSettings() at the end - silently.
    ;
    ; ApplyUi is assume-global, so every name assigned here becomes a global -
    ; the ui* prefix keeps these from colliding with anything else.
    uiAutoStart := "", uiOldSmartTb := ""
    ; Turning a feature off has to undo what it already did. Ghost, always-on-
    ; bottom and PiP are each driven by a hotkey inside `#HotIf <flag>`, so once
    ; the flag is false the hotkey no longer exists and the user cannot undo the
    ; state by hand: ghosted windows stay click-through and topmost, pinned windows
    ; stay children of the desktop, thumbnails stay on screen.
    uiOldGhost := ProximityGhostEnabled
    uiOldBottom := AlwaysOnBottomEnabled
    uiOldPip := LivePipEnabled
    ; Same class of problem, one step smaller. The drag layer is installed by a
    ; frame callback that stops running the moment the flag is false, so unticking
    ; the box mid-drag left the window it was fading stuck at that opacity with
    ; nothing left in the program that would ever clear it.
    uiOldParallax := ParallaxEnabled
    try {
        SnapEnabled    := C["snap"].Value
        MagneticGroupsEnabled := C["magnetic"].Value
        SmartGridEnabled := C["smartgrid"].Value
        ElasticScrollEnabled := C["elastic"].Value

        GlideEnabled   := C["glide"].Value
        RestoreEnabled := C["mem"].Value
        BreathingEnabled := C["breath"].Value
        OpenAnim       := C["openanim"].Text
        FlyMinimizeEnabled := C["fly"].Value
        RollUpEnabled  := C["rollup"].Value
        MiddleClickCloseEnabled := C["midclose"].Value
        ProximityGhostEnabled := C["ghost"].Value
        SpotlightEnabled := C["spotlight"].Value
        TrayMinimizeEnabled := C["traymin"].Value
        BossKeyEnabled := C["bosskey"].Value
        AltDragEnabled := C["altdrag"].Value
        GrabPanEnabled := C["grabpan"].Value
        LivePipEnabled := C["pip"].Value
        MicKillSwitchEnabled := C["mickill"].Value
        ShakeFindEnabled := C["shakefind"].Value
        TextMagnifierEnabled := C["textmag"].Value
        RippleClickEnabled := C["ripple"].Value
        ContextMenuAnimEnabled := C["contextanim"].Value
        ElasticDragEnabled := C["elasticdrag"].Value
        BreatheCursorEnabled := C["breathe"].Value
        InfiniteWrapEnabled := C["wrap"].Value
        BlackHoleMinimizeEnabled := C["blackhole"].Value
        MomentumTiltEnabled := C["momentum"].Value
        CurtainDropEnabled := C["curtain"].Value
        TypingSoundsEnabled := C["typingsounds"].Value
        HotkeySoundsEnabled := C["hotkeysounds"].Value
        SmoothCaretEnabled := C["smoothcaret"].Value
        CopyFeedbackEnabled := C["copyfeedback"].Value
        MorphingPasteEnabled := C["morphingpaste"].Value
        ClipboardAppendEnabled := C["clipboardappend"].Value
        TaskbarWaveEnabled := C["twave"].Value
        CustomClockEnabled := C["customclock"].Value
        ClockUnits := C["clockunits"].Text
        ClockAnchor := C["clockanchor"].Text
        ClockWeatherEnabled := C["clockweather"].Value
        ; Shape validation - it is not a number, so it is not a TUNE_SPEC row.
        ; Whatever survives goes straight into a URL.
        ClockLocation := CleanClockLocation(C["clockloc"].Value)
        ToastBounceEnabled := C["toast"].Value
        MonitorThrowEnabled := C["monthrow"].Value
        BlackHoleDeleteEnabled := C["deletehole"].Value
        CursorYawnEnabled := C["cursoryawn"].Value
        ShatterEnabled := C["shatter"].Value
        TaskbarScrollEnabled := C["taskbarscroll"].Value
        PremiumVolumeOSDEnabled := C["osd"].Value
        QuickFolderJumpEnabled := C["quickfolder"].Value
        QuickLookEnabled := C["quicklook"].Value
        MultiMonitorDimmerEnabled := C["multidimmer"].Value
        
        HotCornersEnabled := C["corners_en"].Value
        HotCornerTL := C["corner_tl"].Text
        HotCornerTR := C["corner_tr"].Text
        HotCornerBL := C["corner_bl"].Text
        HotCornerBR := C["corner_br"].Text

        AlwaysOnBottomEnabled := C["bottom"].Value
        TextExpanderEnabled := C["expander"].Value
        PlainPasteEnabled := C["plainpaste"].Value
        SmartCapsEnabled := C["smartcaps"].Value
        SmartCapsAction := C["smartcaps_act"].Text
        ParallaxEnabled := C["parallax"].Value

        uiOldSmartTb := SmartTaskbarEnabled
        SmartTaskbarEnabled := C["smart_tb"].Value

        EP_Style       := C["epStyle"].Text
        EP_IconSize    := C["epIconSize"].Text

        ; No validation beyond trimming: MC_ParseExeList already rejects paths
        ; and normalises separators, and an empty list is a legitimate value
        ; (it means "trust the audio API alone").
        MediaFallbackList := Trim(C["mediafallback"].Value)

        GravityCloseEnabled := C["gravityclose"].Value
        DEBUG := C["debuglog"].Value

        uiAutoStart := C["auto"].Value
    } catch as e {
        WriteLog("ApplyUi: could not read a control - " e.Message)
    }

    ; Separate try of its own, for the same reason the block above is separated
    ; from the block below: one unreadable Edit must not cost every OTHER number
    ; its value. TuneApplyUi already skips a control it cannot read.
    try TuneApplyUi(writeBack)

    ; Everything below is applying state, not reading controls, and each step is
    ; independent - so one failure cannot silently skip the rest or the save.
    if (uiAutoStart != "" && uiAutoStart != IsAutoStart())
        try SetAutoStart(uiAutoStart)

    ; Switched off: hand the taskbar back the auto-hide state it had at startup.
    if (uiOldSmartTb != "" && uiOldSmartTb && !SmartTaskbarEnabled && OriginalTaskbarState != -1)
        try SetTaskbarAutoHide(OriginalTaskbarState & 1)

    ; Switched off: release whatever the feature is still holding, through the same
    ; functions the hotkeys and Bye() use.
    if (uiOldGhost && !ProximityGhostEnabled) {
        for hwnd, info in GhostWindows.Clone()
            try UnGhostWindow(hwnd)
        SetTimer(GhostMonitorStep, 0)
        SyncMediaCore()
    }
    if (uiOldBottom && !AlwaysOnBottomEnabled) {
        for hwnd, info in BottomWindows.Clone()
            try RestoreFromBottom(hwnd)
    }
    if (uiOldPip && !LivePipEnabled) {
        for src, pip in PipGuis.Clone()
            try ClosePiP(src)
    }
    if (uiOldParallax && !ParallaxEnabled && DragHwnd) {
        try RS_ClearAlphaLayer(DragHwnd, "drag", RS_PRI_DRAG)
        try RS_Commit()
    }

    try UpdateKeyboardHook()         ; start/stop the keyboard hook to match the boxes
    try SyncTray()
    try SyncBreathingTimers()        ; start/stop the polling to match the checkbox
    try SyncSmartTaskbar()
    try SyncDimmerTimer()
    try SyncHotCornersTimer()
    try SyncCursorWrapTimer()
    try SyncCustomClockTimer()
    try SyncTextExpander()
    try SyncShakeDetector()
    try SyncCursorFxTimer()
    try SyncTaskbarUiTimer()
    try SyncMediaCore()
    try SaveSettings()
}

NumOr(text, fallback) => IsNumber(text) ? Number(text) : fallback

RestartExplorer() {
    RunWait('taskkill /f /im explorer.exe', , "Hide")
    Run "explorer.exe"
}

; This listed 13 of the ~45 real bindings and claimed Ctrl+Win+V for plain paste,
; which is bound to Ctrl+Alt+V. Every toggle and the whole keyboard-layout set
; were missing, so the only way to find out Shift+Alt+I wraps the cursor was to
; read the source. Keep this in step with the "=== Hotkeys ===" block and
; docs\HOTKEYS.md - that file is the source of truth for the table.
ShowHotkeys() {
    MsgBox(
    "WINDOWS AND MODES  (Shift+Alt)`n"
  . "W`t`tSettings window`n"
  . "O`t`tAlways on top (active window)`n"
  . "R`t`tRoll up / unroll the active window`n"
  . "H`t`tMinimize the active window to the tray`n"
  . "Wheel`t`tTransparency of the active window`n"
  . "F`t`tFocus mode (cinema) on / off`n"
  . "Esc`t`tBoss key - hide everything and mute`n`n"
  . "LAYOUT  (Shift+Alt)`n"
  . "K`t`tCentre the window, keep its size`n"
  . "U`t`tCycle size 50 / 75 / 90 percent, centred`n"
  . "N`t`tMove to the next monitor`n"
  . "Numpad 1-9`tTile to that cell of a 3x3 grid`n"
  . "Numpad 0`tMaximize / restore`n"
  . "Up / Down`tTop half / bottom half`n"
  . "Z`t`tUndo the last layout change`n"
  . "(the keypad keys need NumLock ON - Up/Down do not)`n`n"
  . "FEATURE TOGGLES  (Shift+Alt)`n"
  . "S`t`tMagnetic snapping`n"
  . "M`t`tPosition memory`n"
  . "E`t`tBreathing windows`n"
  . "C`t`tHot corners`n"
  . "V`t`tSmart active border`n"
  . "I`t`tInfinite cursor wrap`n"
  . "D`t`tMulti-monitor dimmer`n"
  . "T`t`tSmart auto-hide taskbar`n"
  . "J`t`tMagnetic window groups`n"
  . "Space`t`tUniversal grab and pan`n`n"
  . "RECOVERY  (Shift+Alt)`n"
  . "Y`t`tRestore every rolled-up, ghosted or hidden window`n"
  . "X`t`tReset the active window to fully opaque`n"
  . "F5 / F6`tRestart / Exit`n`n"
  . "SYSTEM AND MEDIA`n"
  . "Ctrl+Alt+V`tPaste as plain text`n"
  . "Alt+F4`t`tClose with the gravity-drop animation`n"
  . "Esc Esc Esc`tStealth Panic Mode on / off`n`n"
  . "WHEN A FEATURE IS ENABLED`n"
  . "Double-tap Ctrl`tQuick Spotlight Launcher`n"
  . "Double-tap Alt`tGlobal Mic Kill-Switch`n"
  . "Shift+Alt+B`tAlways on bottom (desktop widget)`n"
  . "Shift+Alt+G`tProximity Ghost Window`n"
  . "Shift+Alt+P`tLive Window Picture-in-Picture`n"
  . "Shift+Alt+L`tQuick Spotlight Launcher`n"
  . "Shift+Alt+A`tMic kill-switch`n"
  . "Shift+Alt+Q`tQuick Look (in Explorer)`n"
  . "Shift+Alt+F4`tShatter to close`n"
  . "Win+Alt+D`tCurtain drop (show the desktop)`n"
  . "Delete`t`tBlack-hole delete (in Explorer)`n"
  . "Alt+LeftDrag`tMove a window from anywhere`n"
  . "Alt+RightDrag`tResize a window from the nearest edge`n"
  . "Middle-click`tTitle bar: close, or roll up`n"
  . "Middle-click`tHold to grab and pan`n"
  . "Ctrl+G`t`tIn a Save/Open dialog: jump to the last Explorer folder`n"
  . "Spacebar`t`tIn Explorer: Quick Look preview`n"
  . "@@date / @@time`tText Expander snippets`n"
  . "CapsLock`ttap = Escape or Backspace, hold = Caps`n`n"
  . "OVER THE TASKBAR`n"
  . "Wheel`t`tVolume up / down`n"
  . "Middle-click`tMute`n`n"
  . "HOTKEYS.md explains conflicts and how to change these.",
    "Window Tweaks - Hotkeys", "Iconi")
}

; The Stealth Panic engine is #Included into this process, but its settings are
; a SEPARATE GUI process with its own ini - and nothing in this program pointed
; at it, so the feature was undiscoverable unless you already knew to triple-tap
; Escape. The ini path goes in as argument 1, exactly as both installers pass
; it: without that handoff a machine carrying both the Window Tweaks install and
; the standalone install gets the GUI editing one folder's config while the
; engine reads another's - settings that appear to save and then do nothing.
;
; StealthPanicUI.ahk has no #SingleInstance, so a second click would open a
; second window over the first. Activate the one that is already up instead.
OpenStealthPanicSettings() {
    global StealthPanicIniPath
    if WinExist("Stealth Panic Mode Settings") {
        try WinActivate("Stealth Panic Mode Settings")
        return
    }
    ui := A_ScriptDir "\StealthPanicUI.ahk"
    if !FileExist(ui) {
        Notify("StealthPanicUI.ahk not found")
        return
    }
    ini := IsSet(StealthPanicIniPath) ? StealthPanicIniPath : A_ScriptDir "\StealthPanic.ini"
    try Run('"' A_AhkPath '" "' ui '" "' ini '"')
    catch
        Notify("Could not open Stealth Panic settings")
}

OpenLog() {
    global LOG_FILE
    FlushLog()                    ; the tail is in RAM until something flushes it
    if FileExist(LOG_FILE)
        Run 'notepad.exe "' LOG_FILE '"'
    else
        Notify("No log yet")
}

OpenDoc(name) {
    p := A_ScriptDir "\" name
    if FileExist(p)
        Run 'notepad.exe "' p '"'
    else
        Notify(name " not found")
}
