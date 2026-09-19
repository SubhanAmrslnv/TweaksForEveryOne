# Window Tweaks - Shadow & Ambient Effects Modification Report

## 1. Discovery and Features Identified

The source code does not typically use the literal word "shadow" to describe its own effects. Instead, the application's shadow-like visual embellishments are documented as ambient lighting, dimming, and glow effects. 

The following 4 features were identified as fitting the "shadow/glow/ambient" criteria alongside 1 native Windows shadow modification:

* **Breathe Cursor (Idle glow effect)**: Uses `BreatheCursorEnabled` flag.
* **Minimal Copy/Paste Feedback (Paste glow indicators)**: Uses `CopyFeedbackEnabled` flag.
* **Breathing Windows (Ambient dimming)**: Dims inactive windows to 70% opacity, acting as an ambient shadow effect. Uses `BreathingEnabled` flag.
* **Theater Spotlight**: Projects a soft circular vignette shadow over the screen. Uses `SpotlightEnabled` flag.
* **Windows Native Dropshadows**: Handled via the Windows API `SPI_SETDROPSHADOW` inside the `Apply-Windows-Tuning.ps1` tuning script.

## 2. Changed Files and Implementations

I successfully disabled all identified shadow-like default configurations while strictly preserving the underlying features, UI toggles, and user settings. 

### `src\FeatureFlags.ahk`
Modified the hard-coded default initialization globals to mathematically align with a disabled initial state.
* **Line 70**: `global BreatheCursorEnabled := false`
* **Line 107**: `global BreathingEnabled := false`
* **Line 129**: `global CopyFeedbackEnabled := false`
* **Line 149**: `global SpotlightEnabled := false`

### `src\SettingsStore.ahk`
Modified the default string argument injected into `IniStr()` during `LoadSettings()`. This serves as the fallback value generator when a user first launches the program without a pre-existing `settings.ini`.
* **Line 106**: `BreatheCursorEnabled := IniStr("mouse", "breathe", "0") = "1"`
* **Line 131**: `BreathingEnabled := IniStr("memory", "breathing", "0") = "1"`
* **Line 146**: `CopyFeedbackEnabled := IniStr("mouse", "copyfeedback", "0") = "1"`
* **Line 162**: `SpotlightEnabled := IniStr("memory", "spotlight", "0") = "1"`

### `scripts\Apply-Windows-Tuning.ps1`
Moved the Windows native drop-shadow initialization mask to the disable tier. When the installer executes tuning (or when manually run), Windows native drop shadows are disabled rather than forcibly enabled.
* **Lines 194-206**: Moved `'Show shadows under windows' = 0x1025` out of the `$effectsOn` array and into the `$effectsOff` array.

## 3. Fresh-Install vs. Existing-User Behavior

### Fresh Installation
During a genuinely fresh installation, the `LoadSettings()` method runs against a nonexistent configuration. The `IniStr()` calls hit our modified `"0"` fallback defaults, setting all shadow/glow effect variables to false. Because `WriteSettings()` is designed to immediately persist the actively evaluated variables on exit/save, the first generated `settings.ini` is natively seeded with these features disabled.

### Existing User Behavior Preserved
Because the logic safely accesses `IniStr(section, key, defaultVal)`, an existing user's `settings.ini` key for any of these features (e.g. `breathe=1`) will correctly evaluate, parse, and apply their saved "1" state. I have successfully fulfilled the strict constraint to NOT blindly overwrite user-configured settings.

## 4. Validation Test Results

Ran the codebase's local build/split integrity checker (`.\scripts\Check-Split.ps1`):
* **Parse Check**: All 46 modules parse successfully.
* **Structure & Case Clash**: Zero context leakage or undefined identifiers.
* **Code Motion Tracking**: Captured precisely 8 modified variable lines between `FeatureFlags.ahk` and `SettingsStore.ahk`. The structural logic has been safely preserved. Re-anchored the test baseline successfully.

All UI controls within `SettingsWindow.ahk` immediately inherit these exact state flags during window construction, so they inherently reflect the disabled state correctly on startup.
