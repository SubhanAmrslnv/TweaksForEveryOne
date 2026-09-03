# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 11 tray utility — magnetic window snapping, inertial glide, window animations, ~40 power-user tweaks — plus an early Linux port. Two trees, sharing **no code**:

| Tree | What it is | State | Governed by |
|---|---|---|---|
| `csharp\` | **.NET 10 / WPF** tray app. 74 features, ~9,300 lines | The active implementation. Settings persist, the settings window is real, and the binary carries publisher metadata and a manifest | this file |
| `linux\` | **C++20 / Qt6 / CMake** port | Early scaffold that **does not manage windows** and has never been compiled on a real Linux box | **`linux\CLAUDE.md`** — read it before touching anything under `linux\` |

**No AutoHotkey.** `GEMINI.md` bans it outright: AV vendors (Bitdefender is named) flag AHK as a false positive, so all system-hook and window-manipulation work goes to C++ (preferred) or C# (acceptable where a WPF UI is needed). Do not suggest, write, or reintroduce an `.ahk` file.

**The AutoHotkey implementation used to live here and was deleted** — `src\` (52 modules, ~15,000 lines), `scripts\`, `build\`, `docs\`, `native\`, `assets\`, the AHK installers and the root `test*.ahk` harnesses. It is recoverable from git history at commit **`3a6fa68`** and its parents. That tree is where every measured finding in **Carried-over design knowledge** below comes from; when one of those notes is too terse to act on, the original prose is in `CLAUDE.md` at `3a6fa68`. Do not resurrect it as running code.

## Commands

No test runner, no CI, nothing automatic. `dotnet` is the only build system.

```powershell
# Build / run / publish
dotnet build   .\csharp\WindowTweaks.csproj                     # or open csharp\WindowTweaks.slnx
dotnet run --project .\csharp\WindowTweaks.csproj               # tray app; Shift+Alt+W for settings
dotnet publish .\csharp\WindowTweaks.csproj -c Release -r win-x64 --self-contained false -o .\csharp\publish

# Install to %ProgramFiles%\WindowTweaks + Startup shortcut. SELF-ELEVATES to admin.
.\Install.bat                    # -> Install-Tweaks.ps1

# Uninstall. Keeps %APPDATA%\WindowTweaks settings unless -RemoveSettings is passed.
.\Uninstall.bat                                  # -> Uninstall-Tweaks.ps1
.\Uninstall-Tweaks.ps1 [-RemoveSettings] [-Silent]
```

`Install-Tweaks.ps1` re-elevates itself with `-Verb RunAs`, publishes Release/win-x64 framework-dependent, `Stop-Process -Force`es any running `WindowTweaks`, copies to `%ProgramFiles%\WindowTweaks` and writes a Startup `.lnk`. It needs admin and writes outside the user profile — worth stating to a user, because the app itself needs neither.

`csharp\bin\`, `csharp\obj\` and `csharp\.vs\` are **tracked in git but listed in `.gitignore`** (they were committed before the ignore rules landed). They will keep producing diff noise on every build until they are untracked.

## The C# tree (`csharp\`)

`net10.0-windows`, `UseWPF` + `UseWindowsForms`, nullable and implicit usings enabled. One `WindowTweaks.csproj`, one `WindowTweaks.slnx`. Layout:

| Path | Role |
|---|---|
| `App.xaml.cs` | **The composition root.** Every feature is a field here; `OnStartup` wires and registers, `OnExit` disposes. There is no DI container and no config |
| `Core\FeatureRegistry.cs` | **Owns whether each feature is on.** Every hotkey, tray item and settings switch goes through it. `FeatureDescriptor` carries the title, page, hotkey label and an optional `Apply` |
| `Core\FeatureKeys.cs` | Every feature TOGGLE key, plus the Game Mode suspend list. A stored format - renaming one discards that setting for existing users |
| `Core\TuningRegistry.cs` | Every tunable NUMBER, string and choice: key, range, default and the UI copy, in one list. The settings window generates its controls from it, so adding a setting is one entry here and no UI change |
| `Core\SettingsStore.cs` | `%APPDATA%\WindowTweaks\settings.json`. Debounced 700 ms, temp-file-then-move, never throws |
| `Core\AlphaCompositor.cs` | **The only place allowed to write a foreign window's opacity.** `final = base * product(layers)` |
| `Core\ShutdownListener.cs` | A message-only window, so the app can be asked to exit at all |
| `Core\AppLifetime.cs` | **The exit flag and the exit watchdog.** `IsExiting` is checked at the top of both shared hooks; `BeginExit` makes shutdown idempotent; `StartWatchdog` guarantees the process actually ends |
| `Core\HookThread.cs` | **The thread that owns the low-level hooks**, above-normal priority, running nothing but a `GetMessage` pump. Read its header before moving a hook off it — this is the file that decides whether the whole OS feels laggy |
| `Core\KeyboardHook.cs` | **The one low-level keyboard hook in the process**, shared and reference-counted, installed on `HookThread`. Read its header before adding a subscriber |
| `Core\MouseHook.cs` | **The one low-level mouse hook**, same arrangement. Subscribers declare an event mask (`Move` / `Buttons` / `Wheel`), and events the app injected itself arrive with `IsOurs` set |
| `Core\SyntheticInput.cs` | **The only place allowed to inject keys or mouse events.** Everything it sends is tagged with `NativeMethods.SyntheticTag`, which is what makes `IsOurs` work |
| `Core\SoundEngine.cs` | **Every sound the app makes** - keystrokes, the editing confirmations and the Windows shortcut chords - synthesised as PCM in memory. Sounds differ by **shape** (rising, falling, ticking, clacking), not by pitch; a clip larger than `SlotBytes` is dropped **silently**, so check the arithmetic before adding a long one and written to a winmm `waveOut` device from its own thread. No audio files, no disk, no dispatcher. The device is opened once and held while sounds keep arriving - `PlaySound` opened and tore down a stream per click, which is what made the keyboard sound cut out for stretches and come back on its own |
| `Core\OverlayPlacement.cs` | **The only correct way to place an overlay from hook coordinates.** Hooks report physical pixels; `Window.Left` is in WPF units. Position via here, size via `ScaleAt` |
| `Core\OsdWindow.cs` | A reusable on-screen readout (a line of text, optionally a meter). Click-through, reused rather than recreated, and its `Post` refuses work while the app is exiting |
| `Core\WeatherService.cs` | **The only code in the app that touches the network.** open-meteo, off by default, inert until a city is set |
| `Core\HotkeyManager.cs` | `RegisterHotKey(IntPtr.Zero, id, ...)`, ids from 9001, `WM_HOTKEY` dispatched off `ComponentDispatcher.ThreadPreprocessMessage`. Failed registrations are reported, not swallowed |
| `Core\NativeMethods.cs` | The single P/Invoke surface. Put new interop here, not in a feature |
| `Core\SystemTrayManager.cs` | `NotifyIcon` + Settings / Restart / Exit. Uses `SystemIcons.Application` — the app has no icon of its own |
| `Core\AudioManager.cs` | Speaker and mic mute, and the master volume, over the MMDevice COM interfaces. **The render endpoint is cached and only touched from the UI thread** — building it costs ~6,500 µs, which is far too much per wheel notch |
| `Core\LayoutHistoryManager.cs` | Per-HWND rect stack behind `UndoLayoutFeature` |
| `MainWindow.xaml(.cs)` | The settings window. Built from `FeatureRegistry`; a switch applies and persists immediately, so there is no Save button |
| `Features\*.cs` | One feature per class |

**Each feature is self-contained, and the two places that arbitrate say so out loud.** A feature owns
its own Win32 hooks, its own `DispatcherTimer`s and its own teardown. There is no render pipeline, no
animation scheduler and no logging. Adding a feature is: a class, a field on `App`, a `Register` call,
a `Dispose` call.

The exceptions are documented in the code because two features cannot both own one button:
`MiddleClickCloseFeature` and `TaskbarVolumeFeature` both step aside for `GrabPanFeature` while it is
enabled, and act on the tagged click it replays instead. Anything else that wants the middle button
has to join that arrangement rather than invent a second one.

### `Apply` takes a state, never an instruction to flip

`FeatureRegistry` calls a feature's `Apply` with the state it WANTS, so **an `Apply` handler must be
idempotent** — `on => feature.SetEnabled(on)`, never `_ => feature.Toggle()`.

Nine features used to be wired the second way, discarding the argument, and it stayed invisible only
because the registry and the features happened to agree. Where they did not, the results were:
Alt-Drag started with its private flag `true` while no hook was installed, so `Apply(true)` at
startup turned it OFF and every switch read backwards for the rest of the session — including Game
Mode, which switched it ON. Any new feature whose flag does not start `false` reproduces this.

### How state flows, and the rules that keep it honest

**Nothing toggles a feature directly.** A hotkey, a tray item and a settings switch all call
`FeatureRegistry.Set/Toggle`, which owns the state, calls the feature's `Apply`, persists it and
raises `Changed` so an open settings window follows along. The registry owns the state because only
four feature classes expose one of their own and the rest flip a private field inside `Toggle()`.

A descriptor with a null `Apply` is a **gate**: a hotkey command with no background state, which just
checks `IsEnabled` before acting (plain paste, shatter close, always-on-top).

**Opacity is composed, never written absolutely.** `AlphaCompositor` holds one record per window - a
base the user chose times any number of named layers - and is the only code that calls
`SetLayeredWindowAttributes`. One owner per layer name, and the list lives in that file's header:
`"breathe"` (BreathingFeature), `"ghost"` (ProximityGhostFeature), `"drag"` (DragParallaxFeature).
`ChangeTransparencyFeature` is the only caller of `SetBase`. Two rules inside it are load-bearing:
`WS_EX_LAYERED` comes off only for a structurally neutral record **and** only if the compositor was
the one that added it (an app that set the style itself may rely on it - that is the black flicker
the old code worked around); and a ghost keeps its layer installed at factor 1.0 rather than clearing
it, or the style would be toggled dozens of times a second while the cursor rests on it.

Five things that will bite you here:

- **`Toggle()` is the name of every hotkey callback, including the one-shot commands.**
  `CenterWindowFeature.Toggle` and `UndoLayoutFeature.Toggle` act once. Never infer state from the name.
- **`ShutdownMode="OnExplicitShutdown"` in `App.xaml` is required, not a preference.** This app shows
  no window at startup, so the WPF default (`OnLastWindowClose`) would quit it the first time any
  window closed - closing the settings window would exit, and so would a ripple overlay finishing its
  420 ms fade.
- **`taskkill` without `/F` and `Process.CloseMainWindow()` cannot stop this app.** Measured: both
  only target *visible* top-level windows and this app has none, so taskkill reports success and the
  process keeps running. `ShutdownListener` answers `WM_CLOSE` (and `WM_QUERYENDSESSION`) on a hidden
  message-only window, and the installer and uninstaller post `WM_CLOSE` to every top-level window of
  the process rather than trusting either route. A forced kill skips `OnExit`, which is what flushes
  settings **and** what lets each feature undo the opacity, tray-hiding and re-parenting it applied to
  other applications' windows.
- **Every exit path goes through `App.RequestShutdown`, and it is not a formality.** Measured: posting
  `WM_CLOSE` to this process reaches **13–15 top-level windows**, so shutdown is genuinely requested
  many times over, and WPF throws on the second `Shutdown()` — from inside a message handler, leaving
  the first one half finished. `RequestShutdown` is idempotent, sets `AppLifetime.IsExiting` *before*
  teardown so the hooks stop feeding the dispatcher (a hand resting on the mouse or a held key kept
  queueing work onto the dispatcher that was trying to shut down), and arms a watchdog for the parts
  of teardown whose timing the app does not control — COM calls into an audio endpoint being removed,
  `SetParent` on a window whose owner has gone. **`MouseHook.Shutdown()` belongs in `OnExit` next to
  `KeyboardHook.Shutdown()`**, and `HookThread.Stop()` must come *after* both: the pump is what
  delivers hook callbacks, so stopping it with a hook still installed stalls input rather than
  freeing it. Exiting with hooks live now measures ~130 ms.
- **Game Mode's suspend list has to stay complete, and it is the second thing to check when a new
  feature is added.** `FeatureKeys.GameModeSuspends` is what Shift+Alt+F12 switches off, and a feature
  missing from it keeps a global input hook installed and keeps drawing top-most windows over a
  full-screen game — which gets blamed on the game, because Game Mode reported that it had suspended
  everything. Six entries were missing after the last round of features; every one of them held a
  mouse or keyboard hook.
- **Game Mode's suppression must never reach `settings.json`.** Shift+Alt+F12 switches ~24 features
  off in memory; persisting that would write the user's whole configuration as "off" with nothing left
  to restore it from. Three defences: `FeatureRegistry.Set(..., persist: false)`,
  `SettingsStore.SuppressPersistence` held for the duration, and a `Flush()` *before* the first flag is
  touched - which covers the one case no exit handler can, a power cut or a forced kill. Verified by
  shutting down mid-Game-Mode and confirming the file came back unchanged.
- **`CustomClockFeature` shows a permanently visible top-most window** and forwards `WM_CLOSE` to
  `Shutdown()` for the reason above: it is found before the app's own message window. Any future
  always-on overlay needs the same handler. It defaults to off and now has a real off switch.

**Every feature is constructed in `App`, described in `RegisterFeatures()`, and disposed in `OnExit`.**
All 27 `IDisposable` features are in that list. Nothing installs a hook or starts a timer in its
constructor any more - six features used to, which made them live from launch with no off switch,
reachable from no hotkey table and no checkbox.

**`Ctrl+G` (quick folder jump) is the one setting that needs a restart**, and its description in the UI
says so: the chord belongs to other applications, so it is claimed only when the feature is already on.
`Alt+F4` is the mirror case - it stays registered always and closes the window normally when the
gravity animation is off, because it cannot simply stop working.

### Settings, and where a new one goes

Two registries, and nothing outside them decides what the settings window shows:

- **`FeatureKeys` + `FeatureRegistry`** - the on/off switches. `App.RegisterFeatures()` describes each
  one (title, page, group, hotkey label, default, and an optional `Apply`).
- **`TuningRegistry`** - the numbers, strings and choices. One `TuningDescriptor` per value carries
  its key, min/max, default, unit and the sentence the UI shows.

**Adding a tunable value is one entry in `TuningRegistry` and nothing else.** The window builds a
slider, a text field or a drop-down from `Kind`, groups it by `Group`, files it under `Page`, and
persists it. There is no UI code to touch, which is the point: the tuning keys used to be private
consts inside the feature that owned them while the settings window addressed the same values with
duplicated string literals - so `"parallax.fromSpeed"` existed twice, in two files, with nothing
keeping them in step, and its range and default were a third copy.

**Read a tuning value once per operation, never per frame or per window.** Each read takes the
settings lock and parses a string. The features that consume one on a hot path cache it at the start
of the gesture instead, and say so in a comment:

- `DragParallaxFeature` captures its three values on `MOVESIZESTART`, because
  `EVENT_OBJECT_LOCATIONCHANGE` fires ~60 times a second while a window moves.
- `MagneticSnappingFeature` reads its four at the top of `SnapWindow`, because `NEIGHBOUR_PROX` is
  consumed inside the window enumeration.
- `BreathingFeature` reads its two per tick, not per window, because the tick enumerates every
  top-level window.

Ranges are enforced in the registry, so a slider cannot produce an invalid value and there is nothing
to validate. Only the free-text fields (city, date and time formats) can, which is why those commit
on `LostFocus` and are replayed on page change and on close - WPF does not reliably raise `LostFocus`
when a window closes with a field still focused.

### The taskbar clock

Two rows, two columns: weather glyph over conditions on the left, `HH:mm:ss` over `dd.MM.yyyy` on the
right. `Features/CustomClockFeature.cs` plus `Core/WeatherService.cs`.

**There is no coordinate anywhere in this feature**, and that is the design. The previous version sat
at `screenWidth - 280` and covered the native clock and the Control Center button — which reads as a
corrupted system tray, with the notification icons apparently moved. Nothing had moved; they were
underneath. Position is now `anchorLeft - gap - contentWidth`, with the anchor resolved **by class
name every tick**, because the notification area's width moves with its icon count (measured at
343 / 391 / 415 / 511 px inside one session). `clock.anchor` picks the anchor and the two options are
a real trade-off: `TrayEdge` (`TrayNotifyWnd`, default) is safe but far from the clock; `Clock`
(`TrayClockWClass`, a *grandchild* of the taskbar via `TrayNotifyWnd`) sits closer but covers whatever
is in those ~115 px.

**The block is painted in the taskbar's own colour, never colour-keyed.** Keying looks right in theory
and fringes in practice: a keyed background needs every background pixel to equal the key exactly, but
antialiased and ClearType glyph edges blend with it, so those pixels survive the keying and halo every
character. `SampleTaskbarColour` reads one pixel to the **left** of the block, so it can never sample
itself, and derives the text colour from that sample's luminance.

Three more things that are easy to undo by accident:

- **Every weather glyph is in the Basic Multilingual Plane.** The obvious emoji (U+1F324 and friends)
  are astral-plane, need Segoe UI Emoji, and WPF does not render colour emoji — a fallback miss shows
  tofu. The BMP symbols live in Segoe UI Symbol, which fallback finds.
- **The weather column exists whenever weather is on; only its VALUE is conditional.** It shows
  `set a city` or `--` until a reading arrives. Sizing it to nothing while waiting is what makes a
  merely *unconfigured* feature look like a *broken* one.
- **It forwards `WM_CLOSE` to `Shutdown()`.** It is the only permanently visible window the app owns,
  so it is found first when anything posts `WM_CLOSE` to the process — see the state-flow section.

### Hotkeys

Read from `App.OnStartup`, which is the only place they are declared. `Shift+Alt` is `MOD_ALT | MOD_SHIFT`.

| Hotkey | Feature |
|---|---|
| `Shift+Alt+W` | Settings window |
| `Shift+Alt+O` / `B` | Always on top / always on bottom |
| `Shift+Alt+S` / `M` / `E` | Magnetic snapping / position memory / breathing windows |
| `Shift+Alt+F` | Focus (cinema) mode |
| `Shift+Alt+R` / `H` | Roll-up / minimize to tray |
| `Shift+Alt+Esc` | Boss key |
| `Shift+Alt+K` / `U` / `N` | Centre / cycle size / next monitor |
| `Shift+Alt+Numpad1..9` | Tile to that cell of a 3×3 grid, keypad-shaped |
| `Shift+Alt+Numpad0` | Maximize / restore |
| `Shift+Alt+Up` / `Down` | Top half / bottom half — the only NumLock-independent layout keys |
| `Shift+Alt+Z` / `X` / `Y` | Undo layout / reset transparency / restore all |
| `Shift+Alt+C` / `I` / `D` / `T` / `J` | Hot corners / cursor wrap / monitor dimmer / smart taskbar / magnetic groups |
| `Shift+Alt+Space` | Grab & pan |
| `Shift+Alt+G` / `P` / `L` | Proximity ghost / live PiP / spotlight |
| `Shift+Alt+A` / `Q` | Mic kill-switch / Quick Look |
| `Shift+Alt+F4` | Shatter close |
| `Shift+Alt+F5` / `F6` | Restart / exit |
| `Shift+Alt+F12` | Game Mode - suspend interfering features, in memory only |
| `Alt+F4` | Gravity-drop close |
| `Ctrl+Alt+V` | Plain-text paste |
| `Ctrl+Alt+C` | camelCase the selection (owned by the feature's keyboard hook, not by `RegisterHotKey`) |
| `Ctrl+G` | Quick folder jump |

Not hotkeys — gestures answered by the two shared hooks: **triple `Esc`** → boss key, **double-tap `Alt`** → mic mute, **double-tap `Ctrl`** → spotlight, **`Shift+Alt+Wheel`** → transparency (gated on `GetAsyncKeyState` for Shift and Alt, clamping alpha to 25..255), **tap `Caps Lock`** → Escape or Backspace, **hold the middle button and drag** → grab & pan, **wheel over the taskbar** → volume, **middle-click the taskbar** → mute, **shake the mouse** → find the cursor, **drag sideways across text** → magnifier.

**Windows' own chords get sounds, not behaviour.** `ShortcutSoundsFeature` watches the shared keyboard
hook for Alt+Tab, Alt+Shift, Win+Tab, Win+Shift+S, Win+V, Win+`.`, Win+D, Win+L, Win+arrows,
Win+Ctrl+arrows and the rest, and plays one synthesised sound per chord. It never suppresses a key -
it comments on the user's shortcut, and Win+L in particular has to keep working. Three rules inside
it are load-bearing:

- **The layout switch is decided on RELEASE.** Pressing Alt while Shift is held is also the first
  half of every `Shift+Alt+` hotkey this app owns, and Ctrl+Shift opens a great many application
  shortcuts, so neither key-down can be the trigger. Each pair is armed when its two modifiers meet
  and disarmed by any third key; the release of any modifier fires the sound only if a pair is still
  armed. The cost is **two booleans - no keystroke is retained** (`docs/ANTIVIRUS.md`).
- **Which pair means "layout" is asked, not inferred.** Windows ships Alt+Shift but can be set to
  Ctrl+Shift, and there is no supported way to read which is live, so `sound.layoutHotkey` offers
  `altShift` / `ctrlShift` / `both` / `off`. Guessing is audible in both directions: a layout change
  with no sound, or a sound with no layout change.
- **`ClaimsKey` is a pure query over live modifier state**, which is how `AcousticKeyboardFeature`
  knows to stay silent on Win+V rather than stacking a letter click on top of the chord sound. A flag
  set by one hook subscriber for the other to read would depend on their subscription order, and that
  order follows whichever feature was switched on first.

**Undo and redo belong to `ClipboardOsdFeature`, not to the shortcut feature.** Ctrl+Z and Ctrl+Y are
editing commands the focused application carries out, the same kind of thing as Ctrl+C - and that
feature already owns `Announce`, which plays the sound off the dispatcher and draws the ring and the
word at the cursor. Ctrl+Shift+Z is redo, so the same key means opposite things depending on Shift.

`Shift+Alt+Numpad*` is bound only under the digit names, so with NumLock **off** the keypad sends the navigation names and the whole tiling gesture is dead.

### `MagneticSnappingFeature` — the one deep feature

The model to copy for fidelity, and the only feature that carries the original physics: `EVENT_SYSTEM_MOVESIZESTART`/`END` for the drag, `EVENT_OBJECT_LOCATIONCHANGE` for velocity, an EMA with a **time constant** (`k = 1 - Exp(-dtMs / 30.0)`) over velocity in **pixels per second**, the `DWMWA_EXTENDED_FRAME_BOUNDS` ↔ `GetWindowRect` conversion on both origin and size, speed-scaled reach, a corner boost that retries the second axis once the first grabs, hysteresis, a direction penalty for a line the window is moving away from, and a quintic ease-out glide with overshoot.

One divergence that remains: its glide is a per-feature `async` loop over `Task.Delay(15)` rather than one shared clock — so two features animating one window will fight, and there is no ownership claim to stop them.

**It defers to Windows' own snap, and that deference is load-bearing.** Dragging a window to a screen edge triggers Aero Snap, which *resizes* the window, and that resize is not always finished when `EVENT_SYSTEM_MOVESIZEEND` arrives — so reading the rectangle immediately still showed the pre-snap size, a magnetic snap was computed from stale geometry, and the glide put the window somewhere in the middle of the screen at its original size. Two rules follow: the decision waits `SettleMs` (45 ms) and then bails out if the window was resized during the drag or is now maximised, and **the glide is move-only — `SWP_NOSIZE`, with no width or height passed in at all.** The glide used to re-apply the size it captured before the animation started, which silently undid anything that resized the window mid-glide. A magnetic snap has no business changing a window's size.

### Missing Tweaks (Stubs)

The following 31 features have been generated as `IDisposable` stubs and integrated into `FeatureKeys.cs`, `App.xaml.cs`, and the Settings Window. They are currently inactive and await concrete implementation:

- `SmartActiveBorderFeature`: Draws a colorful, elegant border exclusively around the active window.
- `GlobalTextExpanderFeature`: Automatically expands abbreviations like @@mail or @@date into full text snippets.
- `ZeroDelayMenusFeature`: Opens context menus instantly (0-50ms) mimicking macOS responsiveness.
- `SnappyTaskbarPreviewsFeature`: Accelerates taskbar window previews from the default 400ms down to 100ms.
- `SmoothScrollingFeature`: Applies interpolated, buttery-smooth scrolling globally across all applications.
- `FadeInEaseOutFeature`: Replaces abrupt window disappearance in Focus Mode with cinematic fade-in/out transitions.
- `CustomTextCaretFeature`: Overrides the default text cursor with a thicker, smoother, eye-friendly caret.
- `BouncySnappingFeature`: Adds a rubber-band bounce effect when snapping windows to screen edges.
- `FocusPulseFeature`: Gently swells and shrinks (2-3% scale) a window when focused via Alt+Tab to draw attention.
- `GhostSlideInFeature`: Animates new application windows sliding up smoothly from the bottom like a smartphone app.
- `MagneticSeamFlashFeature`: Emits a brief neon flash effect where the borders of two windows magnetically snap together.
- `TheaterSpotlightFeature`: Darkens the background and creates a spotlight effect following the cursor over the active window.
- `FlyToMouseMinimizeFeature`: Sucks minimizing windows directly into the mouse cursor rather than the taskbar.
- `WindowUnrollingFeature`: Unrolls new windows vertically from top to bottom like a window blind in 0.2 seconds.
- `ContextMenuUnfoldFeature`: Unfolds context menus downwards like origami instead of appearing instantly.
- `ElasticDragFeature`: Creates a rubber-band stretching effect when dragging files and snaps back on release.
- `CursorYawnBreatheFeature`: Makes an idle cursor subtly "breathe" and "yawn" when left untouched.
- `MomentumTiltFeature`: Slightly tilts windows in the direction of movement while dragging and settles with inertia.
- `BlackHoleMinimizeFeature`: Sucks minimizing windows and deleted files into a gravitational black hole effect.
- `ResistanceEdgeFeature`: Simulates tactile rubber-like resistance when dragging a window against screen edges.
- `FocusDepthFeature`: Pushes inactive windows into the background in 3D while scaling the active one forward.
- `CarouselAltTabFeature`: Replaces the flat Alt-Tab switcher with a rotating 3D carousel of windows.
- `DynamicNotchFeature`: Drops an iOS-style "Dynamic Island" from the top of the screen for volume and brightness.
- `CurtainDropFeature`: Drops all windows to the desktop using kinetic motion blur.
- `MotionBlurScrollFeature`: Applies a vertical motion blur effect while scrolling fast for extreme perceived smoothness.
- `OverscrollBounceFeature`: Adds an Apple-style rubber-band bounce effect when reaching the end of a scrolling page.
- `TaskbarIconWaveFeature`: Makes taskbar icons wave and notifications bounce elastically on mouse hover like macOS.
- `StartMenuBlurFeature`: Generates a deep background blur effect transitioning smoothly as the Start Menu opens.
- `WindowThrowCatchFeature`: Allows throwing a window kinetically across monitors so it flies and lands on the other screen.
- `LightsaberSeamGlowFeature`: Illuminates a glowing Jedi lightsaber edge when hovering over the seam of snapped windows.
- `PrivacyBlurFeature`: Overlays an unreadable frosted glass blur over private windows when they lose focus.

## Antivirus false positives — a first-class constraint

Bitdefender and other engines flag this app. It contains nothing malicious; it trips the **keylogger
heuristic**, because a global keyboard hook plus clipboard access plus synthetic input plus a startup
shortcut is, on paper, exactly what a keylogger looks like. `docs/ANTIVIRUS.md` is the full treatment
— why it happens, what has been done, the vendor submission process, and the technical disclosure text
to paste into a false-positive report. Read it before changing anything in the table below.

This is *why* `GEMINI.md` bans AutoHotkey, and it is worth knowing that the ban does not solve it:
compiled AHK is flagged because the interpreter stub is shared with real malware, so you inherit its
reputation, whereas the C# build is flagged for its own behaviour and its lack of a signature.
Rewriting in C++ would not help either — the keyboard hook is the signal, not the language.
**Only code signing meaningfully fixes this** (`build/Sign.ps1`).

Rules that follow, and that must not be quietly undone:

- **One keyboard hook and one mouse hook, installed only on demand.** `Core/KeyboardHook.cs` and
  `Core/MouseHook.cs` are the single `WH_KEYBOARD_LL` and `WH_MOUSE_LL` hooks; four features used to
  install their own keyboard hook and five their own mouse hook, which reads as a program determined
  to capture input no matter what. Subscribe through them, never call `SetWindowsHookEx` again.
- **Never retain a keystroke.** Subscribers keep a tap counter and a stopwatch. Storing, buffering or
  logging key data would make the heuristic *correct*. The keyboard-sound feature is the closest
  call: it reads the virtual key to choose which click to play and discards it inside the callback,
  keeping only one timestamp for throttling. A "which keys are currently held" set would be over the
  line, which is why auto-repeat is thinned by time instead.
- **All synthetic input goes through `Core/SyntheticInput.cs`.** One small file, no key buffering
  anywhere near it, every event tagged so the app can recognise its own output.
- **Never add a packer, obfuscator, single-file bundle, trimming or ReadyToRun.** Each is a documented
  cause of false positives; the reasons are recorded in `WindowTweaks.csproj` so nobody re-adds them.
- **Keep the assembly metadata and `app.manifest` populated**, and keep the manifest at `asInvoker`.
  Only the installer elevates.
- **The weather lookup is the only network egress, and it is the one deliberate compromise.** Off by
  default, silent until a city is set, one request per 15 minutes to a public API. Do not add a second
  network path — periodic traffic from a process holding input hooks is what command-and-control looks
  like, and on an unsigned binary it will be scored that way.

## Carried-over design knowledge

Everything in this section was **measured against the removed AutoHotkey implementation** on Windows 11 build 26200. These are OS behaviours and design lessons, so they transfer — but none of them has been re-measured in C#, and most describe problems this tree has **not** solved yet. Treat them as the map of where it will break.

### The owner's taste, which governs what gets built

**Wanted: opacity.** Transparency, breathing and fading windows, ghosting, monitor dimming, drag parallax — anything whose whole expression is an alpha value.

**Not wanted:** heartbeat / pulse effects, neon, 3D carousel Alt-Tab, depth-of-field background scaling, and blur generally. Nine features were *deleted* over this rather than switched off. Do not propose a new effect in those classes and do not enable one by default. When something needs visual feedback, reach for a fade first. Ripple Click was deliberately kept.

### Compose opacity, never write it absolutely

Several unrelated features can want to dim the same window at once. If each writes a final alpha, the result is last-writer-wins with no way to reason about it. The concrete symptom, reproducible in this tree today: set a window to 50% with `Shift+Alt+Wheel`, then let breathing or ghosting touch it — that feature writes its own absolute and then writes "opaque" on restore, and the user's 50% is gone.

The fix is one persistent record per window holding a **base** the user chose times any number of **named modifier layers** (`final = base * product(layers)`), with exactly one owner per layer name, and only that record allowed to compute the committed value. Strip `WS_EX_LAYERED` only for a *structurally* neutral record (base opaque, zero layers) — never because the arithmetic happened to round to 255, or a ghosted window flickers between layered and not 40 times a second.

**This is now implemented in `Core\AlphaCompositor.cs`**, so the symptom above is no longer reachable. The paragraph stays because it is the reasoning behind the design, and because the next effect that wants to dim a window has to add a layer rather than become a fourth absolute writer.

### Win32 facts that cost real debugging time

- **A low-level hook callback runs on the thread that installed the hook, and Windows holds the input event until it returns.** Install one from the UI thread and every mouse move in the whole OS queues behind WPF — a ripple animation, a clock tick, a settings window laying itself out. Past `LowLevelHooksTimeout` (300 ms by default) Windows stops waiting and *silently removes the hook*, so the symptom is not "slow" but "the gesture worked the second time". This is why `Core\HookThread.cs` exists and why nothing else may live on it. A handler's budget there is microseconds: no disk, no COM, no `SendMessage` without a very short timeout.
- **Three coordinate spaces, not two.** On top of the frame-bounds pair below there is WPF: a hook reports **physical pixels**, and `Window.Left`/`Top`/`Width`/`Height` are **device-independent units**. Assigning one to the other is correct only at 100% scaling — at 150% every overlay lands two thirds of the way to the top-left corner, and on a 4K panel at 250% it lands off screen. That presents as "the feature does nothing", not as "it is in the wrong place", which is how it survived in four features at once. Position through `Core\OverlayPlacement.cs` (physical, via `SetWindowPos`) and divide any physical size by `ScaleAt`.
- **Two coordinate spaces.** `DWMWA_EXTENDED_FRAME_BOUNDS` (attr 9) is the visible frame; `GetWindowRect` includes the invisible DWM border. Convert both origin *and* size or every snap lands ~7 px off.
- **`SHAppBarMessage(ABM_SETSTATE)` is system-wide.** It takes one taskbar handle, but the auto-hide state it sets applies to *every* taskbar, secondary monitors included. There is no per-monitor form, so a decision taken from the primary monitor alone makes the second monitor's bar disappear with nothing on that monitor to explain why.
- **`SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)`** takes a window out of screen capture. It is the only clean way to stop a magnifier photographing itself; keeping the lens clear of the region it magnifies is impossible near a screen edge, where it has to be clamped back over it.
- **`DWMWA_CLOAKED`** (attr 14) is what filters UWP-suspended and other-virtual-desktop windows. `IsWindowVisible` alone does not catch them.
- **Never `SendMessage` to a foreign window without a timeout.** A window whose thread is not pumping ("Not Responding") never returns and freezes the whole process with it. Use `SendMessageTimeout` with `SMTO_ABORTIFHUNG`.
- **Never make a foreign window layered speculatively.** `SetLayeredWindowAttributes` forces `WS_EX_LAYERED`; on a GPU-composited or full-screen window that costs a redirection surface and can break exclusive full-screen presentation. Decide eligibility *before* touching it.
- **`SetParent` across processes** (always-on-bottom) is barely supported and is undone by nothing but your own restore path. A window left parented to `WorkerW` cannot be alt-tabbed to or moved normally, and dies with the next Explorer restart — so exit-time restoration is mandatory, not polish.
- **A shell-hook registration does not survive an Explorer restart.** `TaskbarCreated` is broadcast when the shell comes back; re-registering on it is the only thing that keeps new-window detection alive after an Explorer crash.
- **Position memory keyed on exe + window class** must exclude owned, tool-window, non-resizable and Picture-in-Picture windows — every Chrome popup shares a class with the main window.
- **A timer callback that throws kills that timer**, and the feature is dead for the rest of the session. Any window query inside a poll needs a `try` and an explicit fallback.
- **`DragFullWindows` is a hard functional dependency.** With it off, Windows drags a hollow outline and the window rect does not move until release — so velocity measures zero every frame and drag parallax, glide and velocity-based snapping all silently do nothing.
- **Windows' own Snap Assist wins at screen edges, by design.** Judge snapping by **window-to-window** magnetism, not screen edges.
- Hotkeys are inert against elevated windows unless the app itself is elevated. Title-bar drags cannot be automated — injected clicks don't engage the window's move loop.

### Animation and timing

- **A 15 ms frame period beats 16 ms, and it is not close.** Windows' clock tick is ~15.6 ms, so a 16 ms deadline always lands just past a tick and waits for the next, alternating 15.6 / 31.2 ms. Measured over 100 idle frames: period 16 → 25.15 ms mean, 7.59 ms jitter, 59% of frames over 20 ms; period **15** → 15.92 ms mean, 0.37 ms jitter, **0%** over 20 ms. `timeBeginPeriod(1)` is required for it. The C# glide loops use `Task.Delay(15)`, which is the right number but has no shared clock and no `timeBeginPeriod`.
- **Parameterise on elapsed time, never on frame count.** `t = elapsed / duration`. A fixed step per frame is frame-rate dependent: a 26-frame fade measured 659 ms instead of 416 ms once frames got heavy. Where a rate is genuinely the right model, scale by `dt` and clamp `dt` so a stall cannot teleport an animation to its end.
- **Velocity is pixels per second**, and every consumer must be calibrated in that unit. Smoothing must use a time constant, not a per-frame constant, or the same hand motion reports up to 3× the velocity under load.
- **Calibrate a ramp by its endpoints, not by a gain.** A parallax ramp of `alpha = 255 - speed * 0.06` left an ordinary 400 px/s drag at 88% opacity — doing exactly what it said and still indistinguishable from switched off. Name both ends instead.
- **Two animations must never drive the same property of the same window at once.** Enforce it with an ownership claim per `(window, channel)` that cancels the previous holder, not with hand-written lists of rivals — every such list in the original had drifted and missed at least one animation. One key per window per effect, covering both directions, so starting a fade-in cancels a fade-out instead of racing it.
- **A poll is a timer, not an animation.** A poller registered as a never-ending animation pinned the frame loop and `timeBeginPeriod(1)` for the whole session. A countdown is a one-shot timer, not a frame callback that compares a deadline.
- **Skip frames that would not change a pixel.** `SetWindowPos` on a real window costs ~260 µs and forces the target app to re-layout; compare against the last applied integer rect first.
- **A feature that owns an overlay must tear it down when its own flag goes false, and the flag test belongs inside that function.** Gating the call site instead means switching the feature off stops the only code that could have cleaned up — three overlays were stranded on screen that way, each unreachable with the feature that owned it disabled.
- **Set region and alpha *before* showing a window**, or you get one frame of a hard-edged opaque rectangle. When swapping a real window for a bitmap copy, show the copy before hiding the original.

### Performance

Measured costs, in a process where input paths and a 15 ms frame loop share one thread:

| Operation | Cost |
|---|---|
| Append one line to a log file | 1,900–9,300 µs |
| Write one ini key | 770 µs |
| Rebuild the audio-endpoint list over COM | 6,500 µs |
| `SetWindowPos` on a real window | 260 µs |
| `GetWindowRect` / monitor queries | ~2–3 µs |
| Window style / state getters | ~0.3 µs |

The rules that follow: **never touch the disk on an input path** — buffer and flush from an idle one-shot (one drag once spent 30 ms in file appends); **hoist any per-window predicate out of a per-window loop** behind an O(1) "could anything match?" gate; **cache anything derived from the display layout** and invalidate on `WM_DISPLAYCHANGE`; and **don't micro-optimise window queries** — three attempts measured as no change or worse. Measure A/B in one process against the same probe window, or the changing set of open windows makes the numbers meaningless.

Do not cache window *positions*: the user dragging a title bar changes them behind your back, and caching last-requested positions made a second snap to the same edge a no-op.

## Working rules

From `.agents\rules\` (`defensive_programming.md`, `professional_engineering.md`) and the repo's own history:

- **Defensive by default.** Anticipate sudden window closures, missing HWNDs, and empty collections. Check `IsWindow(hwnd)` before acting on a foreign window, guard dictionary access, and `try` anything inside a timer or hook callback. Fail gracefully; an unhandled exception in a hook pops a dialog at the user and kills the handler for the session.
- **Simple over clever.** Prefer readable, stable code to intricate maths or heavy loops. Small, single-responsibility classes.
- **Non-destructive integration.** New features stay isolated and modular, with minimal interference in existing hooks and global state. Do not remove existing functionality unless asked.
- **Architecture first.** Read the related files, trace the execution path and name the trade-offs before implementing; then self-review for duplicate logic, dead code, naming consistency, thread safety and regressions. Keep code, comments and identifiers in English.
- **Do not add throwaway test files to the project.** No scratch harnesses committed at the root — that is how eight of them accumulated in the deleted tree.
- **`linux\` has its own rules.** Read `linux\CLAUDE.md` before touching it, and do not add a completion claim to any doc under `linux\docs\`.

Two documents outside this file matter: **`docs/ANTIVIRUS.md`** (why the app is flagged, what has been done, and the vendor submission process - the reference for the rules in **Antivirus false positives** above) and **`build/Sign.ps1`** (signs and timestamps the published binary).
