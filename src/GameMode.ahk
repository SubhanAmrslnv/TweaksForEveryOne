; Game Mode - temporarily suppresses disruptive features during gameplay.
;
; Function definitions and global initialisers only, no top-level statements.
;
; SUPPRESSION IS AN IN-MEMORY OVERLAY, AND THE SETTINGS FILE MUST NEVER SEE IT.
; Entering Game Mode sets ~48 feature flags to false and keeps the user's real
; values in GameModeSuspendedFeatures. WriteSettings() persists whatever those
; globals currently hold - so shutting down, restarting or reloading while Game
; Mode was on wrote every suppressed feature to settings.ini as 0, and the user's
; entire configuration was gone on the next launch with no way to get it back.
; That is what GameModeUnsuspendForWrite() / GameModeResuspend() exist for:
; WriteSettings() brackets itself with them, so the file always records the real
; configuration even while the overlay is active.
;
; ONE FEATURE LIST. It used to be written out twice, once in each direction, and
; a name added to one copy and not the other is a feature that is suppressed and
; never restored. GAME_MODE_FEATURES is the only copy.
;
; The four loops below are assume-global (a bare `global`) because they assign
; through a dynamic reference - %gmFeat% := ... - which resolves to a local in an
; assume-local function and would silently suppress nothing at all. That makes
; every assignment in them global, so their own scratch variables carry a gm
; prefix, the same rule ApplyUi follows with ui/ep.

; Every flag Game Mode switches off. Names are resolved dynamically, and anything
; not declared elsewhere is skipped by the IsSet() guard rather than throwing.
global GAME_MODE_FEATURES := [
    "HotCornersEnabled", "InfiniteWrapEnabled", "MultiMonitorDimmerEnabled", "GrabPanEnabled",
    "SnapEnabled", "ElasticScrollEnabled",
    "SpotlightEnabled", "QuickLookEnabled", "CursorYawnEnabled", "RippleClickEnabled",
    "LivePipEnabled", "ProximityGhostEnabled", "BreathingEnabled",
    "ElasticDragEnabled", "TextMagnifierEnabled", "TaskbarScrollEnabled",
    "MorphingPasteEnabled", "ClipboardAppendEnabled", "CopyFeedbackEnabled", "SmartCapsEnabled",
    "AltDragEnabled", "MiddleClickCloseEnabled", "RollUpEnabled", "ContextMenuAnimEnabled",
    "MagneticGroupsEnabled", "BreatheCursorEnabled", "BlackHoleMinimizeEnabled", "MomentumTiltEnabled",
    "CurtainDropEnabled",
    "TaskbarWaveEnabled", "ToastBounceEnabled", "MonitorThrowEnabled", "BlackHoleDeleteEnabled",
    "ShatterEnabled", "ParallaxEnabled",
    "FlyMinimizeEnabled", "QuickFolderJumpEnabled", "PlainPasteEnabled", "SmoothCaretEnabled",
    "TypingSoundsEnabled", "HotkeySoundsEnabled", "PremiumVolumeOSDEnabled", "MicKillSwitchEnabled",
    "TextExpanderEnabled", "ShakeFindEnabled", "GravityCloseEnabled", "GlideEnabled",
    "AlwaysOnBottomEnabled"
]

ToggleGameMode() {
    global GameModeActive
    if (GameModeActive)
        ExitGameMode()
    else
        EnterGameMode()
}

EnterGameMode() {
    global
    if (GameModeActive)
        return

    ; The settings file is flushed BEFORE the flags are touched, so even a power
    ; cut or a Stop-Process -Force while Game Mode is on leaves the user's real
    ; configuration on disk. WriteSettings() is idempotent and diffed against
    ; IniCache, so this costs nothing when there is nothing pending.
    try WriteSettings()

    ; Sounded before the flags go down: HotkeySoundsEnabled is one of the ones
    ; Game Mode suppresses, so the confirmation has to happen first or the
    ; feature silences itself on the way in.
    PlayHotkeySound("toggleon")
    GameModeActive := true
    GameModeSuspendedFeatures.Clear()

    for gmFeat in GAME_MODE_FEATURES {
        if (IsSet(%gmFeat%)) {
            GameModeSuspendedFeatures[gmFeat] := %gmFeat%
            %gmFeat% := false
        }
    }

    if (IsSet(OpenAnim)) {
        GameModeSuspendedFeatures["OpenAnim"] := OpenAnim
        OpenAnim := "None"
    }

    GameModeSyncFeatures()
    Notify("Game Mode ON")
}

ExitGameMode() {
    global
    if (!GameModeActive)
        return

    GameModeActive := false

    for gmFeat in GAME_MODE_FEATURES {
        if (GameModeSuspendedFeatures.Has(gmFeat) && IsSet(%gmFeat%))
            %gmFeat% := GameModeSuspendedFeatures[gmFeat]
    }

    if (GameModeSuspendedFeatures.Has("OpenAnim") && IsSet(OpenAnim))
        OpenAnim := GameModeSuspendedFeatures["OpenAnim"]

    GameModeSuspendedFeatures.Clear()

    GameModeSyncFeatures()
    PlayHotkeySound("toggleoff")
    Notify("Game Mode OFF")
}

; ====== Persistence bracket ======
;
; Called by WriteSettings() and by nothing else. The pair puts the user's real
; values back into the globals for the duration of the write and then re-applies
; the suppression, so the file records the configuration rather than the overlay.
; Returns whether anything was changed, so the caller only has to undo what was
; actually done.
;
; Note this deliberately does NOT call GameModeSyncFeatures(): the flags are
; restored for microseconds, and starting every suspended feature's timer to stop
; it again on the next line would make each settings write a visible stutter.
GameModeUnsuspendForWrite() {
    global
    if (!GameModeActive || !GameModeSuspendedFeatures.Count)
        return false

    for gmFeat in GAME_MODE_FEATURES {
        if (GameModeSuspendedFeatures.Has(gmFeat) && IsSet(%gmFeat%))
            %gmFeat% := GameModeSuspendedFeatures[gmFeat]
    }
    if (GameModeSuspendedFeatures.Has("OpenAnim") && IsSet(OpenAnim))
        OpenAnim := GameModeSuspendedFeatures["OpenAnim"]
    return true
}

GameModeResuspend() {
    global
    if (!GameModeActive)
        return

    for gmFeat in GAME_MODE_FEATURES {
        if (GameModeSuspendedFeatures.Has(gmFeat) && IsSet(%gmFeat%))
            %gmFeat% := false
    }
    if (GameModeSuspendedFeatures.Has("OpenAnim") && IsSet(OpenAnim))
        OpenAnim := "None"
}

GameModeSyncFeatures() {
    global ProximityGhostEnabled, LivePipEnabled, GhostWindows, PipGuis

    if (IsSet(ProximityGhostEnabled) && !ProximityGhostEnabled && IsSet(GhostWindows)) {
        for hwnd, info in GhostWindows.Clone()
            UnGhostWindow(hwnd)
        try SetTimer(GhostMonitorStep, 0)
    }
    if (IsSet(LivePipEnabled) && !LivePipEnabled && IsSet(PipGuis)) {
        for src, pip in PipGuis.Clone()
            ClosePiP(src)
    }

    try SyncHotCornersTimer()
    try SyncCursorWrapTimer()
    try SyncDimmerTimer()
    try SyncBreathingTimers()
    try SyncCursorFxTimer()
    try SyncTaskbarUiTimer()
    try SyncShakeDetector()
    try SyncTextExpander()
    try UpdateKeyboardHook()
}
