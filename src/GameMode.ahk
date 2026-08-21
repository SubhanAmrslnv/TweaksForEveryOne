; GameMode.ahk - Temporarily suppresses disruptive features during gameplay.

ToggleGameMode() {
    global GameModeActive
    if (GameModeActive) {
        ExitGameMode()
    } else {
        EnterGameMode()
    }
}

EnterGameMode() {
    global GameModeActive, GameModeSuspendedFeatures
    if (GameModeActive)
        return
        
    GameModeActive := true
    GameModeSuspendedFeatures.Clear()
    
    ; Define disruptive features to suspend
    global HotCornersEnabled, InfiniteWrapEnabled, MultiMonitorDimmerEnabled, GrabPanEnabled
    global ActiveBorderEnabled, SnapEnabled, ElasticScrollEnabled, MotionBlurScrollEnabled
    global SpotlightEnabled, QuickLookEnabled, CursorYawnEnabled, RippleClickEnabled
    global LivePipEnabled, ProximityGhostEnabled, PrivacyBlurEnabled, BreathingEnabled
    global PulseEnabled, ElasticDragEnabled, TextMagnifierEnabled, TaskbarScrollEnabled
    global MorphingPasteEnabled, ClipboardAppendEnabled, CopyFeedbackEnabled, SmartCapsEnabled
    global AltDragEnabled, MiddleClickCloseEnabled, RollUpEnabled, ContextMenuAnimEnabled
    global MagneticGroupsEnabled, BreatheCursorEnabled, BlackHoleMinimizeEnabled, MomentumTiltEnabled
    global FocusDepthEnabled, CurtainDropEnabled, SparkTypingEnabled, CarouselAltTabEnabled
    global TaskbarWaveEnabled, ToastBounceEnabled, MonitorThrowEnabled, BlackHoleDeleteEnabled
    global ShatterEnabled, LightsaberSeamEnabled, ParallaxEnabled, SeamFlashEnabled
    global FlyMinimizeEnabled, QuickFolderJumpEnabled, PlainPasteEnabled, SmoothCaretEnabled
    global TypingSoundsEnabled, PremiumVolumeOSDEnabled, MicKillSwitchEnabled, TextExpanderEnabled
    global ShakeFindEnabled, GravityCloseEnabled, GlideEnabled, AlwaysOnBottomEnabled
    global OpenAnim

    features := [
        "HotCornersEnabled", "InfiniteWrapEnabled", "MultiMonitorDimmerEnabled", "GrabPanEnabled",
        "ActiveBorderEnabled", "SnapEnabled", "ElasticScrollEnabled", "MotionBlurScrollEnabled",
        "SpotlightEnabled", "QuickLookEnabled", "CursorYawnEnabled", "RippleClickEnabled",
        "LivePipEnabled", "ProximityGhostEnabled", "PrivacyBlurEnabled", "BreathingEnabled",
        "PulseEnabled", "ElasticDragEnabled", "TextMagnifierEnabled", "TaskbarScrollEnabled",
        "MorphingPasteEnabled", "ClipboardAppendEnabled", "CopyFeedbackEnabled", "SmartCapsEnabled",
        "AltDragEnabled", "MiddleClickCloseEnabled", "RollUpEnabled", "ContextMenuAnimEnabled",
        "MagneticGroupsEnabled", "BreatheCursorEnabled", "BlackHoleMinimizeEnabled", "MomentumTiltEnabled",
        "FocusDepthEnabled", "CurtainDropEnabled", "SparkTypingEnabled", "CarouselAltTabEnabled",
        "TaskbarWaveEnabled", "ToastBounceEnabled", "MonitorThrowEnabled", "BlackHoleDeleteEnabled",
        "ShatterEnabled", "LightsaberSeamEnabled", "ParallaxEnabled", "SeamFlashEnabled",
        "FlyMinimizeEnabled", "QuickFolderJumpEnabled", "PlainPasteEnabled", "SmoothCaretEnabled",
        "TypingSoundsEnabled", "PremiumVolumeOSDEnabled", "MicKillSwitchEnabled", "TextExpanderEnabled",
        "ShakeFindEnabled", "GravityCloseEnabled", "GlideEnabled", "AlwaysOnBottomEnabled"
    ]
    
    for feat in features {
        if (IsSet(%feat%)) {
            GameModeSuspendedFeatures[feat] := %feat%
            %feat% := false
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
    global GameModeActive, GameModeSuspendedFeatures
    if (!GameModeActive)
        return
        
    GameModeActive := false
    
    global HotCornersEnabled, InfiniteWrapEnabled, MultiMonitorDimmerEnabled, GrabPanEnabled
    global ActiveBorderEnabled, SnapEnabled, ElasticScrollEnabled, MotionBlurScrollEnabled
    global SpotlightEnabled, QuickLookEnabled, CursorYawnEnabled, RippleClickEnabled
    global LivePipEnabled, ProximityGhostEnabled, PrivacyBlurEnabled, BreathingEnabled
    global PulseEnabled, ElasticDragEnabled, TextMagnifierEnabled, TaskbarScrollEnabled
    global MorphingPasteEnabled, ClipboardAppendEnabled, CopyFeedbackEnabled, SmartCapsEnabled
    global AltDragEnabled, MiddleClickCloseEnabled, RollUpEnabled, ContextMenuAnimEnabled
    global MagneticGroupsEnabled, BreatheCursorEnabled, BlackHoleMinimizeEnabled, MomentumTiltEnabled
    global FocusDepthEnabled, CurtainDropEnabled, SparkTypingEnabled, CarouselAltTabEnabled
    global TaskbarWaveEnabled, ToastBounceEnabled, MonitorThrowEnabled, BlackHoleDeleteEnabled
    global ShatterEnabled, LightsaberSeamEnabled, ParallaxEnabled, SeamFlashEnabled
    global FlyMinimizeEnabled, QuickFolderJumpEnabled, PlainPasteEnabled, SmoothCaretEnabled
    global TypingSoundsEnabled, PremiumVolumeOSDEnabled, MicKillSwitchEnabled, TextExpanderEnabled
    global ShakeFindEnabled, GravityCloseEnabled, GlideEnabled, AlwaysOnBottomEnabled
    global OpenAnim

    features := [
        "HotCornersEnabled", "InfiniteWrapEnabled", "MultiMonitorDimmerEnabled", "GrabPanEnabled",
        "ActiveBorderEnabled", "SnapEnabled", "ElasticScrollEnabled", "MotionBlurScrollEnabled",
        "SpotlightEnabled", "QuickLookEnabled", "CursorYawnEnabled", "RippleClickEnabled",
        "LivePipEnabled", "ProximityGhostEnabled", "PrivacyBlurEnabled", "BreathingEnabled",
        "PulseEnabled", "ElasticDragEnabled", "TextMagnifierEnabled", "TaskbarScrollEnabled",
        "MorphingPasteEnabled", "ClipboardAppendEnabled", "CopyFeedbackEnabled", "SmartCapsEnabled",
        "AltDragEnabled", "MiddleClickCloseEnabled", "RollUpEnabled", "ContextMenuAnimEnabled",
        "MagneticGroupsEnabled", "BreatheCursorEnabled", "BlackHoleMinimizeEnabled", "MomentumTiltEnabled",
        "FocusDepthEnabled", "CurtainDropEnabled", "SparkTypingEnabled", "CarouselAltTabEnabled",
        "TaskbarWaveEnabled", "ToastBounceEnabled", "MonitorThrowEnabled", "BlackHoleDeleteEnabled",
        "ShatterEnabled", "LightsaberSeamEnabled", "ParallaxEnabled", "SeamFlashEnabled",
        "FlyMinimizeEnabled", "QuickFolderJumpEnabled", "PlainPasteEnabled", "SmoothCaretEnabled",
        "TypingSoundsEnabled", "PremiumVolumeOSDEnabled", "MicKillSwitchEnabled", "TextExpanderEnabled",
        "ShakeFindEnabled", "GravityCloseEnabled", "GlideEnabled", "AlwaysOnBottomEnabled"
    ]
    
    for feat in features {
        if (GameModeSuspendedFeatures.Has(feat) && IsSet(%feat%)) {
            %feat% := GameModeSuspendedFeatures[feat]
        }
    }
    
    if (GameModeSuspendedFeatures.Has("OpenAnim") && IsSet(OpenAnim)) {
        OpenAnim := GameModeSuspendedFeatures["OpenAnim"]
    }

    GameModeSuspendedFeatures.Clear()
    
    GameModeSyncFeatures()
    Notify("Game Mode OFF")
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
    try SyncActiveBorderTimer()
    try SyncBreathingTimers()
    try SyncCursorFxTimer()
    try SyncTaskbarUiTimer()
    try SyncShakeDetector()
    try SyncTextExpander()
    try UpdateKeyboardHook()
}
