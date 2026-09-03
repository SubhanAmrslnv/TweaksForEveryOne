# Window Tweaks — feature list

Every switch in the settings window, in the order the window itself groups them, plus the commands
that have no switch. Generated against `App.RegisterFeatures()` and `App.RegisterHotkeys()`; if the
two ever disagree, the code is right and this file is stale.

**Read the status column.** Thirty-one entries are marked **stub**: the switch exists, persists and
appears in the settings window, but the feature class behind it is empty and flipping it does
nothing yet. They are listed here because they are real settings a user can see, not because they
work.

Defaults are what a fresh `settings.json` gets. `—` means the feature has no hotkey of its own.

---

## Window Management

| Feature | Hotkey | Default | Status |
|---|---|---|---|
| Linux-style Alt-Drag — move a window from anywhere in it, not just the title bar | Alt+Drag | on | ✅ |
| Magnetic window snapping — windows attract to each other's edges, with velocity-scaled reach and a glide | Shift+Alt+S | off | ✅ |
| Magnetic window groups — snapped windows move together | Shift+Alt+J | off | ✅ |
| Middle-click title bar to close | — | off | ✅ |
| Position memory — restores a window's rect by exe + window class | Shift+Alt+M | off | ✅ |
| Window roll-up — collapses a window to its title bar | Shift+Alt+R | on | ✅ |
| Minimize to tray | Shift+Alt+H | on | ✅ |
| Always on top | Shift+Alt+O | on | ✅ |
| Always on bottom — re-parents the window to `WorkerW` | Shift+Alt+B | on | ✅ |
| Live picture-in-picture — a live always-on-top copy of any window | Shift+Alt+P | on | ✅ |
| Smart Active Border — a border around the active window | — | off | **stub** |

## Opacity & Effects

| Feature | Hotkey | Default | Status |
|---|---|---|---|
| Transparency wheel — sets a window's base opacity, clamped 25–255 | Shift+Alt+Wheel | on | ✅ |
| Parallax dragging — a window fades in proportion to drag speed | — | off | ✅ |
| Proximity ghost — a window stays transparent until the cursor approaches | Shift+Alt+G | on | ✅ |
| Breathing windows — inactive windows fade after an idle delay | Shift+Alt+E | off | ✅ |
| Multi-monitor focus dimmer — dims the monitors you are not on | Shift+Alt+D | off | ✅ |
| Focus / cinema mode — dims everything but the active window | Shift+Alt+F | on | ✅ |
| Theater Spotlight — a spotlight following the cursor | — | off | **stub** |
| Focus Depth — inactive windows pushed back in 3D | — | off | **stub** |
| Start Menu Slide-Up Blur | — | off | **stub** |
| Privacy Blur — frosted glass over private windows on unfocus | — | off | **stub** |

All four implemented opacity effects compose through `Core/AlphaCompositor.cs` rather than writing a
final alpha, so a transparency the user chose survives a feature dimming the same window.

## Animation

| Feature | Hotkey | Default | Status |
|---|---|---|---|
| Ripple click — a ripple at the pointer on every click | — | off | ✅ |
| Gravity-drop close — the window falls before closing | Alt+F4 | off | ✅ |
| Shatter to close | Shift+Alt+F4 | on | ✅ |
| Fade In / Ease-Out | — | off | **stub** |
| Bouncy Snapping | — | off | **stub** |
| Focus Pulse | — | off | **stub** |
| Ghost Slide-In | — | off | **stub** |
| Magnetic Seam Flash | — | off | **stub** |
| Fly-to-Mouse Minimize | — | off | **stub** |
| Window Unrolling | — | off | **stub** |
| Context Menu Unfold | — | off | **stub** |
| Elastic Drag | — | off | **stub** |
| Cursor Yawn & Breathe | — | off | **stub** |
| Momentum Tilt | — | off | **stub** |
| Black Hole Minimize | — | off | **stub** |
| Resistance Edge | — | off | **stub** |
| Carousel Alt-Tab | — | off | **stub** |
| Curtain Drop | — | off | **stub** |
| Motion Blur Scroll | — | off | **stub** |
| Overscroll Bounce | — | off | **stub** |
| Taskbar Icon Wave | — | off | **stub** |
| Window Throw & Catch | — | off | **stub** |
| Lightsaber Seam Glow | — | off | **stub** |

Alt+F4 stays registered whether or not the gravity animation is on; with it off, the hotkey closes
the window normally. A close chord cannot simply stop working.

## Power Features

| Feature | Hotkey | Default | Status |
|---|---|---|---|
| Plain-text paste | Ctrl+Alt+V | on | ✅ |
| camelCase the selection | Ctrl+Alt+C | on | ✅ |
| Quick folder jump — **needs a restart to take effect**, because Ctrl+G belongs to other apps | Ctrl+G | off | ✅ |
| Quick Look preview — Space previews the selected file in Explorer | Shift+Alt+Q | on | ✅ |
| Spotlight launcher | Shift+Alt+L | on | ✅ |
| Double-tap Ctrl for Spotlight | Ctrl, Ctrl | on | ✅ |
| Microphone kill-switch | Shift+Alt+A | on | ✅ |
| Double-tap Alt to mute the mic | Alt, Alt | on | ✅ |
| Smart Caps Lock — a tap sends Escape or Backspace | — | on | ✅ |
| Universal grab & pan — hold the middle button and drag to pan any window | Shift+Alt+Space | off | ✅ |
| Stealth panic — triple Escape | Esc Esc Esc | on | ✅ |
| Shake to find the cursor | — | on | ✅ |
| Magnifier while selecting text | — | on | ✅ |
| Keyboard sounds — a synthesised click per keystroke | — | off | ✅ |
| Copy, paste and undo feedback — Ctrl+C/V/X/A/Z/Y get a sound and a ring at the cursor | — | on | ✅ |
| Windows shortcut sounds — one sound per Windows chord | — | on | ✅ |
| Taskbar volume wheel — scroll over the taskbar to change volume, middle-click to mute | — | on | ✅ |
| Global Text Expander | — | off | **stub** |
| Zero-delay Menus | — | off | **stub** |
| Smooth Scrolling | — | off | **stub** |
| Custom Text Caret | — | off | **stub** |

Every sound in the app is synthesised as PCM in memory by `Core/SoundEngine.cs` — no audio files,
and nothing is read from disk while you type. Sounds are told apart by **shape** (rising, falling,
ticking, clacking), not by pitch. Profile and per-group volumes are on the Tuning page.

## Screen & Shell

| Feature | Hotkey | Default | Status |
|---|---|---|---|
| Hot corners | Shift+Alt+C | off | ✅ |
| Infinite cursor wrap | Shift+Alt+I | off | ✅ |
| Smart auto-hide taskbar | Shift+Alt+T | off | ✅ |
| Custom taskbar clock — two rows, positioned relative to the tray rather than at a fixed coordinate | — | off | ✅ |
| Clock weather — **the only part of the app that uses the network.** Off by default, and makes no request until a city is set | — | off | ✅ |
| Snappy Taskbar Previews | — | off | **stub** |
| Dynamic Notch (OSD) | — | off | **stub** |

## General

| Feature | Default | Status |
|---|---|---|
| Start with Windows — the default is read from the Startup folder, not from `settings.json` | (actual state) | ✅ |

---

## Commands with no switch

Always registered; they act when pressed and hold no state.

| Hotkey | Command |
|---|---|
| Shift+Alt+W | Open the settings window |
| Shift+Alt+F5 / F6 | Restart / exit the app |
| Shift+Alt+F12 | Game Mode — suspend interfering features **in memory only**, never persisted |
| Shift+Alt+Esc | Boss key |
| Shift+Alt+Y | Restore everything — un-rolls, un-hides, un-ghosts and clears leftover opacity |
| Shift+Alt+K / U / N | Centre / cycle size / move to the next monitor |
| Shift+Alt+Z / X | Undo the last layout change / reset transparency |
| Shift+Alt+Numpad0 | Maximize / restore |
| Shift+Alt+Numpad1..9 | Tile to that cell of a 3×3 grid, keypad-shaped |
| Shift+Alt+Up / Down | Top half / bottom half — the only NumLock-independent layout keys |

With NumLock **off** the keypad sends navigation names, so every `Shift+Alt+Numpad` binding is dead.
Shift+Alt+Up and Shift+Alt+Down are the exception.

## Gestures

Answered by the two shared hooks rather than by `RegisterHotKey`.

| Gesture | Effect |
|---|---|
| Triple `Esc` | Boss key |
| Double-tap `Alt` | Mic mute |
| Double-tap `Ctrl` | Spotlight |
| `Shift+Alt+Wheel` | Window transparency |
| Tap `Caps Lock` | Escape, or Backspace |
| Hold the middle button and drag | Grab & pan |
| Wheel over the taskbar | Volume |
| Middle-click the taskbar | Mute |
| Shake the mouse | Find the cursor |
| Drag sideways across text | Magnifier |

## Windows chords that get a sound

`ShortcutSoundsFeature` watches the shared keyboard hook and plays one sound per chord. **It never
suppresses a key** — every handler returns false, so Win+L in particular keeps working.

Alt+Tab · Alt+Shift+Tab · Ctrl+Alt+Tab · Win+Tab · Win+Shift+S · Win+PrintScreen · Win+V · Win+. ·
Win+; · Win+D · Win+M · Win+L · Win+E · Win+R · Win+S · Win+A · Win+I · Win+N · Win+K ·
Win+Left/Right/Up/Down · Win+Shift+Left/Right · Win+Shift+T · Win+Ctrl+Left/Right · Win+Ctrl+D ·
Win+Ctrl+F4

The keyboard-layout switch is the one gesture with no third key, so it is decided on **release** —
the pair is armed when its two modifiers meet and disarmed by anything else pressed in between.
Windows ships Alt+Shift but can be set to Ctrl+Shift and offers no way to ask which is live, so
`sound.layoutHotkey` asks instead (`altShift` / `ctrlShift` / `both` / `off`).
