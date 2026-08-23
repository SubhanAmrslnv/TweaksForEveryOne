# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 11 tray utility written in **AutoHotkey v2** (magnetic window snapping, inertial "ice glide", window animations, ~40 power-user tweaks), plus a reversible HKCU tuning pass. Shipped two ways: a PowerShell installer and a single-file setup `.exe` compiled from C#.

**This repository now holds two independent implementations.** Everything in this file describes the Windows one (`src/`, `scripts/`, `build/`, `docs/`). A separate C++20/Qt6/CMake port for Linux lives in **`linux/`** and has its own **`linux/CLAUDE.md`** — read that before touching anything under `linux/`. The two share **no code**, only design: the render-arbitration and animation-scheduler concepts were ported deliberately, so if you change an invariant on one side, check the other. The Linux port is an early scaffold that does not build; do not treat its docs as a description of working software.

**There is no taskbar-height engine any more.** `TaskbarCore.ahk`, the `TB_*` globals, `TB_HEIGHTS`, `IsHeight()` and the `Win+Alt+Up/Down/0` hotkeys were removed. What remains taskbar-related is Smart Auto-Hide (`SHAppBarMessage`, `[taskbar] smart`) and taskbar volume scroll. `docs\TASKBAR-AND-INTERNALS.md` keeps the measured findings from that work because the Win32 research is still valuable — but treat it as history, not as a description of the code.

## Features and hotkeys

**Every global hotkey is `Shift+Alt+<key>` — there is no second tier.** Commit `3dadac4` collapsed the old `Win+Ctrl` scheme into one chord, and the source binds `+!` and nothing else (the sole exception is `Ctrl+Alt+V` for plain-text paste, which shadows the paste it replaces). Hotkeys are declared in one block (`src/WindowTweaks.ahk`, search `=== Hotkeys ===`) and each one delegates to a named function that the tray menu binds to as well — change behaviour in the function, never in the hotkey line, or the two drift apart.

**`docs\HOTKEYS.md` is the source of truth for this table.** Do not re-derive it from memory; several documents and the tray labels still carry the pre-`3dadac4` chords.

| Hotkey | Action | Entry point |
|---|---|---|
| `Shift+Alt+W` | Open the settings window | `ShowWin()` |
| `Shift+Alt+S` | Magnetic snapping on / off | `ToggleSnap()` |
| `Shift+Alt+M` | Position memory on / off | `ToggleMemory()` |
| `Shift+Alt+E` | Breathing windows on / off | `ToggleBreathing()` |
| `Shift+Alt+F` | Focus / cinema mode | `ToggleFocusMode()` |
| `Shift+Alt+O` | Always-on-top the active window | inline block, `:3632` |
| `Shift+Alt+R` | Roll up / unroll | `ToggleRollUp()` |
| `Shift+Alt+H` | Minimize to tray | `HideToTray()` |
| `Shift+Alt+Esc` | Boss key | `ToggleBossKey()` |
| `Shift+Alt+Wheel` | Transparency of the active window | `ChangeTransparency()` |
| `Shift+Alt+K` | Centre the active window, keep its size | `CenterWindow()` |
| `Shift+Alt+U` | Cycle size 50 / 75 / 90 % of the work area, centred | `CycleWindowSize()` |
| `Shift+Alt+N` | Move to the next monitor, scaled to its work area | `MoveToNextMonitor()` |
| `Shift+Alt+Numpad1..9` | Tile to that cell of a 3×3 grid (keypad-shaped) | `TileWindow(cell)` |
| `Shift+Alt+Numpad0` | Maximize / restore | `ToggleMaximize()` |
| `Shift+Alt+Up` / `Down` | Top half / bottom half (laptop alias) | `TileWindow(8)` / `(2)` |
| `Shift+Alt+Z` | Undo the last layout change to this window | `UndoLayout()` |
| `Shift+Alt+X` | Reset the active window to fully opaque | `ResetTransparency()` |
| `Shift+Alt+Y` | Restore all rolled-up / ghosted / tray-hidden windows | `RestoreAllWindows()` |
| `Shift+Alt+F5` / `F6` | Restart / Exit | `Reload()` / `ExitApp()` |
| `Shift+Alt+C` | Hot corners on / off | `ToggleHotCorners()` |
| `Shift+Alt+I` | Infinite cursor wrap on / off | `ToggleCursorWrap()` |
| `Shift+Alt+D` | Multi-monitor dimmer on / off | `ToggleDimmer()` |
| `Shift+Alt+T` | Smart auto-hide taskbar on / off | `ToggleSmartTaskbar()` |
| `Shift+Alt+J` | Magnetic window groups on / off | `ToggleMagneticGroups()` |
| `Shift+Alt+Space` | Universal grab & pan on / off | `ToggleGrabPan()` |
| `Esc Esc Esc` | Stealth Panic Mode on / off (see its own section) | `ToggleStealthPanic()` |
| `(Tray Menu)` | Restart / Exit | `Reload()` / `ExitApp()` |

Behind a `#HotIf` on their feature flag, so the key stays free until the feature is on: `Shift+Alt+B` (always-on-bottom), `Shift+Alt+G` (proximity ghost), `Shift+Alt+P` (live PiP), `Shift+Alt+L` (spotlight), `Shift+Alt+A` (mic kill-switch), `Shift+Alt+Q` (Quick Look, and only in Explorer), `Shift+Alt+F4` (shatter close, `:9131`), `Alt+F4` (gravity close, `$!F4` at `:3122`), `Ctrl+Alt+V` (plain paste).

The triple-`Esc` binding is `~Esc`, so Escape still reaches the focused window — it does not go through `IsDoublePress` and it lives in `src\StealthPanic.ahk`, not the hotkey block. Note `Escape` is already claimed behind two other `#HotIf` contexts (Spotlight and Quick Look).

**Three hotkeys are declared inline, far from the hotkey block** — always-on-top (`+!o`, `:3632`), gravity close (`$!F4`, `:3122`) and shatter close (`+!F4`, `:9131`). A grep of the `=== Hotkeys ===` block alone will miss them.

**The keypad tiles are bound only under their digit names.** A comment above the block claims both names are bound — `Numpad7` *and* `NumpadHome` — but only `Numpad7`..`Numpad0` exist in the source. With NumLock **off** the keypad sends the navigation names and the whole tiling gesture is dead. Either bind the second set or fix the comment; `Shift+Alt+Up/Down` is currently the only NumLock-independent layout key.

Conditional on their feature flag: `Alt+LButton` / `Alt+RButton` (alt-drag), `*MButton` (grab-pan / roll-up / close), wheel and middle-click over the taskbar, `Ctrl+G` in file dialogs, `CapsLock`, `Space` in Explorer, double-tap `LAlt` (mic), double-tap `Ctrl` (spotlight).

Every toggle fires `Notify()` → `TrayTip`, so state changes are always visible. The one exception is `ChangeTransparency`, which debounces its notification through `FlushTransNotify` — a wheel gesture is many hotkey firings and used to produce one toast per notch.

### The four core features and where their state lives

| Feature | Behaviour | INI section / keys | Globals |
|---|---|---|---|
| **Magnetic snapping** | On drag-release, each axis independently snaps to a screen edge, a monitor work-area edge, or another window's edge. The reach SCALES WITH RELEASE SPEED (`adapt`): slow and deliberate reaches less so a window can be parked near an edge on purpose, a hard flick reaches further. A line the window is moving away from is penalised, and one it is already flush with wins ties by `hyst` px. Corners pull harder: once one axis grabs, the other is retried with `CORNER_BOOST` × the reach | `[snap]` `enabled`, `flash`, `distance`, `adapt`, `hyst`, `cornerBoost`, `neighbour` | `SnapEnabled`, `SNAP_DISTANCE` (30), `CORNER_BOOST` (2.2), `NEIGHBOUR_PROX` (90) |
| **Ice glide** | Release mid-drag and the window keeps sliding on a quintic ease-out, then snaps to whatever it drifts near. If the throw was still heading somewhere when the snap stopped it, the window overshoots the edge by up to `settle` px and springs back. Never leaves the screen | `[glide]` `enabled`, `throw`, `ms`, `settle` | `GlideEnabled`, `GLIDE_THROW` (0.9), `GLIDE_MS` (650), `GLIDE_MAX` (500) |
| **Always on top** | Toggles `WS_EX_TOPMOST` on the active window. Hotkey only — no persisted setting, and it self-excludes by PID so it can't pin its own GUI | — | — |
| **Position memory** | Each app reopens at its last size/position, keyed on `exe_class`. Dialogs, owned windows, `WS_EX_TOOLWINDOW`, anything without `WS_THICKFRAME`, and Picture-in-Picture (PiP) windows are excluded | `[memory]` `enabled` | `RestoreEnabled`, `POS_FILE` |

Feature *flags* still live under `[memory]` (the section name is historical — it is the general flag bucket), plus `[corners]`, `[taskbar] smart`, `[snap]`, `[glide]`, `[mouse]`, `[window]` and `[snippets]` for the text expander. Every tunable *number* lives in a per-feature section owned by the tuning registry: `[snap]`, `[glide]`, `[breathing]`, `[ghost]`, `[border]`, `[dimmer]`, `[focus]`, `[wrap]`, `[corners]`, `[osd]`, `[trans]`, `[anim]`, `[mouse]`. See **The tuning registry** below — that table, not this one, is where a range is defined.

### Infinite Cursor Wrap — the intent model

`CursorWrapMonitorStep` is not a threshold test; it is a small state machine, and the shape matters because the outer edge of the desktop is somewhere the pointer lands constantly (reaching a Back button, a close box, a scrollbar, the Start button). The original fired on any contact with the outermost pixel column, including mid-drag.

Three gates, **all** of which must pass:

1. **Approach speed** at the moment of contact (`[wrap] speed`, px/s). Sampled from the tick *before* contact — once Windows clamps the pointer at the edge its measured speed is zero by definition, so it cannot be sampled after.
2. **Dwell** (`[wrap] delay`, ms). Leaving the band resets the state, so a glance off the edge never accumulates.
3. **Cooldown** (`[wrap] cooldown`, ms) since the last wrap, so one gesture cannot chain.

Plus `[wrap] tolerance` for how wide the contact band is. Setting `speed` or `delay` to 0 disables that gate individually, which is how the old instant behaviour stays reachable.

Two things are deliberately **not** settings: suppression while any mouse button is down or `DragHwnd` is set (teleporting the cursor mid-drag is never wanted — `HotCornersMonitorStep` set that precedent), and the landing inset, which is derived as `tolerance + 8` so the destination can never re-arm the gate it just left.

The brief's "activation distance" collapses into `tolerance`: once the pointer reaches the edge it is clamped there, so further physical travel *into* the edge is not observable without raw input. The "push harder" intent is carried by the dwell and speed gates instead.

Hot Corners uses the same dwell model (`[corners] size`, `[corners] delay`) for the same reason, so the two features feel like one design.

### Effects the owner does not want

A taste constraint, stated directly, and it governs what gets built and what
ships on by default:

**Wanted: opacity.** Transparency, breathing/fading windows, ghosting, monitor
dimming, drag parallax - anything whose whole expression is an alpha value.

**Not wanted:** heartbeat / pulse effects, neon effects, the 3D Carousel
Alt-Tab, Focus Depth of Field (3D background scaling), and blur effects
generally.

Nine features were DELETED for this, not just switched off - Focus Pulse,
Magnetic Seam Flash, Lightsaber Seam Glow, Spark Typing, 3D Carousel Alt-Tab,
Focus Depth of Field, Start Menu Blur, Privacy Blur on Unfocus and Motion Blur
Scroll - along with their flags, settings, tuning rows and ini keys. Do not
reintroduce them. Ripple Click was deliberately KEPT.

Do not propose a new effect in the rejected classes, and do not enable one by
default. When something needs visual feedback, reach for a fade first.

### The Full Feature Suite (40+ Tweaks & Animations)

**15 Power-User Tweaks (Newly Added):**
- **Smart Auto-Hide Taskbar**: Only hides the taskbar when windows maximize or touch the bottom edge.
- **macOS "Quick Look"**: Press Space on any file in Explorer to instantly preview it.
- **Multi-Monitor Focus Dimmer**: Dims inactive monitors by 50% to reduce eye strain.
- **macOS "Hot Corners"**: Throw your mouse to screen corners to trigger actions (e.g. Hide windows, Task View).
- **Premium Volume OSD**: A sleek, blurred macOS-style volume indicator when scrolling the taskbar.
- **Live Window PiP**: `Shift+Alt+P` creates a live, always-on-top thumbnail of any background window.
- **Universal Grab & Pan**: Hold Middle-Click to pan/scroll any window (like the Photoshop Hand Tool).
- **Global Mic Kill-Switch**: Double-tap `Alt` to instantly mute/unmute your microphone system-wide.
- **Infinite Cursor Wrap**: Teleport your cursor across screen edges for seamless multi-monitor navigation.
- **Quick Spotlight Launcher**: Double-tap `Ctrl` for a minimalist, lightning-fast search and launch bar.
- **Always on Bottom**: `Shift+Alt+B` pins any window permanently to your desktop background as a widget.
- **Global Text Expander**: Type `@@mail`, `@@date`, etc., to instantly expand snippets anywhere.
- **Middle-Click to Close**: Middle-click any window's title bar to instantly close it.
- **Proximity Ghost Window**: `Shift+Alt+G` makes a window 80% transparent; it fades in and becomes clickable only when your mouse gets close.

**Performance & OS Tuning:**
- **Zero-delay Menus (MenuShowDelay)**: Windows menus open instantly (0-50ms) just like macOS, eliminating the artificial 400ms delay.
- **Snappy Taskbar Previews (MouseHoverTime)**: Taskbar thumbnails appear in 100ms instead of 400ms for a much more responsive feel.
- **Smooth Scrolling**: Silky smooth mouse wheel scrolling interpolation across all apps.

**Premium Window Animations:**
- **Fade In / Ease-Out**: Cinematic fade transitions for modes like Focus Mode instead of abrupt cuts.
- **Custom Text Caret**: A thicker, smoother blinking text cursor (caret) to reduce eye strain and look modern.
- **Bouncy Snapping**: Windows slightly squish and bounce back with realistic physics when hitting screen edges or other windows.
- **Gravity Drop Close**: When closing a window, it collapses into a bitmap and falls with gravity (or gets sucked into a black hole).
- **Breathing Backgrounds**: Inactive background windows slowly fade to 70% opacity after 6 seconds of inactivity, waking up instantly when hovered.
- **Ghost Slide-In**: New apps slide up from 30px below while fading in, similar to modern smartphone app launches.
- **Parallax Dragging**: Windows become transparent based on how fast you drag them, fading back to solid when you stop. The two speeds that define the ramp are settings: it starts fading at `[memory] parallaxfrom` px/s and reaches `parallaxmin` opacity at `parallaxfull` px/s.
- **Theater Spotlight**: A soft, circular vignette shadow follows your active window like a stage spotlight, dimming the rest of the screen.
- **Fly-to-Mouse Minimize**: Minimized windows spin and vacuum directly into your mouse cursor instead of dropping to the taskbar.
- **Window Unrolling**: New windows unroll from top to bottom like a window blind in 0.2 seconds.

**Next-Gen Physics & Tactile Animations (Recently Added):**
- **Ripple Click**: Every mouse click sends a subtle, water-drop ripple originating from the cursor.
- **Context Menu Unfold**: Right-click menus smoothly unfold downwards like origami instead of appearing instantly.
- **Elastic Drag (Ghost Drift)**: Dragging files or text creates a rubber-band effect where the ghost image trails behind and bounces forward.
- **Cursor Yawn & Breathe**: Leaving the mouse idle makes the cursor "stretch and yawn" before moving again.
- **Momentum Tilt**: Dragging a window tilts it slightly in the direction of motion, swinging back with inertia when stopped.
- **Black Hole Minimize & Delete**: Windows and deleted files get sucked into a tiny gravity well (funnel) with physics-based warping.
- **Resistance Edge**: Snapping a window to a screen edge creates a satisfying rubber-band resistance effect.
- **Mechanical Keystroke Sounds**: Every key makes a synthesised mechanical switch sound - a bright click layered over the keycap bottoming out - with its own voice for space, enter, backspace and copy/cut/paste.
- **Hotkey Sounds**: Commands get their own voices, distinct from typing - a rising two-tone when a feature switches on, falling when it switches off, a short snap for a window layout command and a deeper hit for restore-all and the boss key. Keystrokes and commands have separate volume settings.
- **Dynamic Notch (OSD)**: Volume and brightness adjustments drop down a sleek iOS-style Dynamic Island pill from the top of the screen.
- **Curtain Drop (Win+D)**: Showing the desktop drops all windows simultaneously with a kinetic motion-blur effect.
- **Overscroll Bounce**: Scrolling past the end of a page elastically stretches and springs back.
- **Taskbar Icon Wave & Elastic Toasts**: Hovering over the taskbar creates a macOS-like icon wave, and notifications bounce elastically into view.
- **Start Menu Slide-Up Blur**: Opening the Start menu slides it up while deeply blurring the entire background.
- **Window Throw & Catch**: Forcefully flick a window towards another monitor, and it will kinetically fly across screens.
- **Shatter to Close**: Shift+Alt+F4 smashes the active window into dozens of 3D glass shards that fall with gravity.

**Keyboard Window Layout:**
- **Numpad Tiling**: `Shift+Alt+Numpad1..9` tiles to a 3x3 grid of the work area, laid out like the keypad. **Only the digit names are bound**, so this is dead with NumLock off; `Shift+Alt+Up/Down` are the NumLock-independent halves.
- **Centre / Cycle Size / Next Monitor / Maximize / Undo**: `Shift+Alt+K` / `U` / `N` / `Numpad0` / `Z`. All except maximize go through `ApplyLayout()`.
- **Restore Everything**: `Shift+Alt+Y` unrolls, un-ghosts and un-hides every window the program is holding — the recovery path for state a user cannot see.
- **Reset Transparency**: `Shift+Alt+X`.

**Feature Toggles (`Shift+Alt+<key>`):** hot corners `C`, cursor wrap `I`, multi-monitor dimmer `D`, smart auto-hide taskbar `T`, magnetic groups `J`, grab & pan `Space`. Each flips the flag, persists it, updates the settings checkbox if the window is open, notifies, and calls the feature's `Sync*` — that last step is what actually starts or stops the timer.

**Productivity & Window Management:**
- **Transparency Control**: `Shift + Alt + Wheel` to adjust the opacity of any active window.
- **Cinema / Focus Mode**: `Shift + Alt + F` to black out the entire background, keeping only the active window visible.
- **Window Shade / Roll-Up**: Middle-click a window to roll it up (collapse to just the title bar), middle-click to restore.
- **Minimize to Tray**: Add a tray icon for any active window to declutter your taskbar.
- **Boss Key**: `Shift + Alt + Esc` to instantly hide all windows and mute system audio. Press again to restore.
- **Linux-Style Alt-Drag**: Hold `Alt + LeftClick` anywhere on a window to move it, or `Alt + RightClick` anywhere to resize it from the nearest edge.
- **Taskbar Volume Scroll**: Hover over the taskbar and scroll the mouse wheel to adjust volume, or middle-click to mute.
- **Quick Folder Jump**: Press `Ctrl + G` in any File Save/Open dialog to instantly jump to the folder of your most recently active Explorer window.
- **Global Plain-Text Paste**: `Ctrl + Win + V` strips all formatting, colors, and fonts from your clipboard and pastes as pure plain text anywhere.
- **Smart Caps Lock**: Tap CapsLock to send `Escape` (or `Backspace`), hold it for 0.4 seconds to actually toggle CapsLock on/off.

### Keyboard window layout

`; ====== Window layout ======` in `WindowTweaks.ahk` holds `CenterWindow`, `CycleWindowSize`, `TileWindow`, `MoveToNextMonitor`, `UndoLayout` and `ToggleMaximize`. Everything except `ToggleMaximize` funnels through **`ApplyLayout(hwnd, tx, ty, tw, th)`**, which takes a target rect *in visible-frame coordinates* and is the only place that knows the four things that make a keyboard move correct:

1. It calls `RS_Commit()`. These are one-shot producers, so nothing else ever flushes them — see the render-pipeline section.
2. It converts frame space to `WinMove` space using `GetRects()` + `WinGetPos()`, the same conversion `SnapWindow` does. Widths need it too (`destW := tw + (winW - (fR - fL))`), not just origins.
3. It cancels `Glide_`, `Bounce_` and `RollUp_` on that window first. A live glide writes `RS_SetPos` at the same priority every frame and would overwrite the queued move with no error.
4. It clears the roll-up region, because a rolled-up window is clipped to its *old* width and resizing it without that leaves a torn window.

Add a new layout action by computing a frame rect and handing it to `ApplyLayout` — do not queue `RS_SetPos` directly.

`ToggleMaximize` is the deliberate exception: it uses `WinMaximize`/`WinRestore` and **cannot** use `IsRestorable()` as its gate, because that goes through `IsSnappable()`, which rejects maximized windows — the one window it exists to un-maximize.

**Morph Maximize** (`MorphMaximize`) runs *after* the state change, not instead of it. `RS_*` has no concept of a maximize state - it queues explicit rects, and a window that merely covers the work area is not maximized to the OS or to the app. So Windows performs the state change, `MorphMaximize` reads where it landed, seeds one frame at the old rect and glides to the new one on the `"geom"` channel. The window is genuinely maximized throughout; only its rect is animated. It is skipped entirely when ice glide is off, so it inherits that preference rather than adding a setting.

Work areas are read live via `MonitorGetWorkArea` rather than cached in `ScreenMetrics()`: the work area changes when the taskbar auto-hides and that raises no `WM_DISPLAYCHANGE`, so a cached copy would be stale exactly when Smart Auto-Hide is on. Only the *monitor* rects come from the cache (`MonitorIndexAt`). This is a hotkey path, so the ~3 µs is irrelevant.

`LayoutUndo` and `SizeCycleIdx` are per-HWND Maps and are pruned in the `HSHELL_WINDOWDESTROYED` branch of the shell hook alongside `RolledUpWindows`.

## The tuning registry — where every user-tunable number lives

`TUNE_SPEC` (near the top of `WindowTweaks.ahk`, right after `EP_ICON_SIZES`) is **one row per tunable number** and the single source of truth for its INI section/key, default, `lo`/`hi` bounds, `step`, decimal places, settings page, label and hint. Loading, clamping, persistence and the settings control are all generated from it.

It exists because the original five numeric settings repeated their range in three places — the declared default, the clamp block at the end of `LoadSettings`, and the `Clamp()` call in `ApplyUi` — and those had already drifted.

| Piece | Role |
|---|---|
| `TUNE_SPEC` | the table. `TS(...)` builds a row |
| `TUNE_VAL` | key → validated value. **Not** `TUNE`: identifiers are case-insensitive, so a `TUNE` map and a `Tune()` accessor are the same name and the script refuses to load |
| `Tune(key)` / `TuneAlpha(key)` | read a value; `TuneAlpha` converts a percentage row to 0-255 |
| `TuneLoad` / `TuneSave` / `TuneApplyUi` / `TuneRow` | called from `LoadSettings`, `WriteSettings`, `ApplyUi`, `BuildWin` |
| `SyncTuningGlobals()` | mirrors the eight rows that back a long-standing global (`SNAP_DISTANCE`, `CORNER_BOOST`, `NEIGHBOUR_PROX`, `GLIDE_THROW`, `GLIDE_MS`, `GLIDE_MAX`, `BREATHE_IDLE_MS`, `CursorYawnIdleTime`) so every existing read site is untouched and pays no Map lookup |

Rules that come with it:

- **`lo` is the lowest *usable* value, not the lowest legal one.** A feature is switched off with its checkbox, never by typing 0 into its duration. Where 0 does mean something — "stop where you let go", "screen edges only", "gate disabled" — the row's hint says so.
- **`step` is documentation, not quantisation.** These are typed fields; snapping 33 to 35 while someone is typing 330 is hostile. It is surfaced in the generated hint instead.
- **Opacity is always a percentage.** Every opacity setting is stored 0-100 and converted by `TuneAlpha`, so the unit never varies between features. Durations are always ms, distances always px.
- **`ApplyUi(writeBack)`**: the debounced `Change` path passes `false`, `LoseFocus` and close pass `true`. Correcting an out-of-range number back into its control 600 ms after the last keystroke rewrites the field while the user is still typing it.
- Adding a setting = one `TUNE_SPEC` row + one `TuneRow(pg, key, FG, cSub)` call where it belongs on a page. Nothing else.

Two settings are deliberately *not* in the registry because they are not numbers: `BorderColor` (`auto` or `RRGGBB`, validated by shape) and `MediaFallbackList`.

### Three traps in this area

**A space followed by `;` starts a comment even inside a double-quoted string.** `x := "a ; b"` fails to load with `Missing """`; `x := "a; b"` is fine. This is why the shipped `media_fallback` default writes `"a.exe; b.exe"` and never `"a.exe ; b.exe"`. Verified against 2.0 in this repo — check any literal that contains a semicolon.

**Enumerated settings must be validated by membership, not range.** Every setting that feeds a DropDownList (`OpenAnim`, `SmartCapsAction`, the four `HotCorner*`, `EP_Style`, `EP_IconSize`) goes through `IniPick(section, key, allowedList, default)` in `LoadSettings`, and the control is built from the *same* list with `IndexOf()` for its `Choose<n>`. The lists live in one place — `OPEN_ANIMS`, `CAPS_ACTIONS`, `CORNER_ACTIONS`, `EP_STYLES`, `EP_ICON_SIZES` near the top of the file. Two things break if you skip this: `DropDownList.Choose("not in the list")` throws *inside* `BuildWin`, which leaves `Ctrl+Alt+W` permanently dead after one hand-edited `settings.ini`; and a value the dropdown cannot display leaves the GUI showing one thing while the engine uses another. Range-check the numeric settings; list-check these.

Tray menu labels embed their hotkey after a literal tab — `"Magnetic snap\tWin+Ctrl+S"` (the source writes the tab as an AHK escape) — and that **entire string is the lookup key** used by `SyncTray()` to set tick marks. Renaming a label without updating both places silently breaks the checkmarks, with no error.

**Those labels are stale and currently lie to the user.** Commit `3dadac4` moved every binding to `Shift+Alt`, but the display strings were not updated: `WindowTweaks.ahk:765`/`777-782` still say `Win+Ctrl+S` / `Win+Ctrl+M` / `Win+Ctrl+E` when the real hotkeys are `Shift+Alt+S` / `Shift+Alt+M` / `Shift+Alt+E`, and settings checkboxes such as `:953` ("Minimize to Tray (Win+Ctrl+H)") have the same problem against the real `Shift+Alt+H`. Fixing this means changing the label at **every** site that uses it as a lookup key — the `m.Add` call and both `Check`/`Uncheck` arms — in one commit, or the tick marks break. The authoritative list of real bindings is the `; ====== Hotkeys ======` block and `docs\HOTKEYS.md`.

### Windows shortcuts this claims

AutoHotkey hooks the keyboard ahead of Windows, so while the program runs, `Shift+Alt+S` no longer opens Speech Recognition. The rest are unclaimed by Windows.

Deliberately **not** touched: `Win+Ctrl+←/→` (virtual desktops), `Win+Ctrl+D` (new virtual desktop), `Win+Ctrl+Q` (Quick Assist), `Win+Ctrl+C` (colour filters), `Win+Ctrl+N` / `Win+Ctrl+Enter` (Narrator), `Win+Ctrl+O` (on-screen keyboard), `Win+Ctrl+Space` (previous input method), `Win+Ctrl+Shift+B` (reset the graphics driver), `Win+Ctrl+<digit>` (last active window of taskbar app N), `Win+↑/↓`, `Win+Tab`, `Win+D`, `Win+E`. Several of those are accessibility features; shadowing them is not a trade this program gets to make on the user's behalf.

**The `Win+Ctrl` tier is gone.** That list of Windows-reserved chords is exactly *why*: the program originally lived on `Win+Ctrl+<key>` and kept colliding with it, so commit `3dadac4` moved everything onto the single `Shift+Alt` chord. Nothing here binds a `Win` chord any more. The historical consequences of the old scheme are still visible — "centre the window" is on `K` rather than the obvious `C`, because `C` was once needed to dodge `Win+Ctrl+C` and is now taken by hot corners; and left/right halves still have no arrow alias because `Win+←/→` already does that job.

Before adding a hotkey: everything global is `Shift+Alt+<key>`, so the free letters are the constraint. Check the table at the top of this file (and `docs\HOTKEYS.md`) for what is taken - `V` is free again since Smart Active Border was removed — the chord space is nearly full, which is why `Space`, the arrows and `F5`/`F6` are already in use. Note that AutoHotkey wins against Windows for `Shift+Alt+S`, so Speech Recognition does not open while this runs.

## Commands

There is **no build system, no test runner, and no CI**. No `.sln`, no `.csproj`, no Pester, no npm/make. Every command below is typed by hand.

```powershell
# Run from source
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" src\WindowTweaks.ahk


# Build the installer -> build\out\WindowTweaksSetup.exe
.\build\Build-Installer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Installer.ps1   # if policy is Restricted

# Install / uninstall (no admin required anywhere in this project)
.\Install.ps1 [-Silent] [-Tuning] [-NoAutoStart]
.\Uninstall.ps1 [-Silent]

# Windows tuning
.\scripts\Apply-Windows-Tuning.ps1 [-Animations | -Explorer | -All]
.\scripts\Restore-Windows-Tuning.ps1

# Structural checks - the closest thing to a test suite. Run after every change
# that moves code between modules. See "Architecture rules" below.
.\scripts\Check-Split.ps1              # parse, motion proof, HotIf, case, hotkeys
.\scripts\Check-Split.ps1 -IniCheck    # + settings.ini round-trip (launches the app ~3s)
.\scripts\Check-Split.ps1 -Baseline    # re-anchor the references after an intended change
```

## Architecture

**One AutoHotkey v2 process** for everything except the Stealth Panic settings GUI (below). `src\WindowTweaks.ahk` is the sole entry point; the `#Include` lines at the top pull the rest in at load time. `#SingleInstance Force` is the only cross-instance coordination.

**44 modules, flat in `src\`.** The largest is 939 lines (`SettingsWindow.ahk`);
nothing else is close to the ~1000-line review threshold.

Phase 12 (`de0525d`) split the last three grab-bags, so three names that older
notes still reference no longer exist: `WindowCommands.ahk` became the six
`Cmd*.ahk` files, `WindowLifecycle.ahk` became `WindowClassification.ahk` /
`PositionMemory.ahk` / `WindowOpenAnim.ahk` / `ShellHook.ahk`, and
`WindowSpectacleFx.ahk` became the five `Fx*.ahk` files.

*Entry and process lifecycle*

| File | Role |
|---|---|
| `src\WindowTweaks.ahk` | **Entry point only** — process directives, the 29-line `#Include` manifest, one `Boot()` call. No globals, no functions |
| `src\ProcessLifecycle.ahk` | `Boot()` and `Bye()`. The single ordered startup sequence and the single teardown |

*Infrastructure — no feature knowledge*

| File | Role |
|---|---|
| `src\SnapCore.ahk` | Pure geometry + window predicates. No side effects |
| `src\RenderCore.ahk` | The only place allowed to touch a window's position, alpha, region or z-order |
| `src\AnimationScheduler.ahk` | One 15 ms timer multiplexing every animation; owns the `QPC()` timebase |
| `src\MediaCore.ahk` | WASAPI "is this window playing audio/video?", so playing windows are never faded |

*Substrate — settings, flags, logging*

| File | Role |
|---|---|
| `src\FeatureFlags.ahk` | Declared default of every boolean/string/enum setting + the seven enum lists. **First in the manifest** |
| `src\TuningRegistry.ahk` | `TUNE_SPEC` and the numeric load/clamp/persist/render runtime. Owns `Clamp()` |
| `src\DiagnosticsLog.ahk` | Buffered log, rotation, `Notify()` |
| `src\SettingsStore.ahk` | settings.ini read/write, `IniCache`, `LoadSettings`/`WriteSettings`, Start-with-Windows |

*Shared services*

| File | Role |
|---|---|
| `src\MonitorGeometry.ahk` | Monitor index and work-area lookup; the cached screen metrics |
| `src\OverlayGui.ahk` | One lifecycle for every transient overlay: `GuiDestroy`, `FadeGui`, `NotchAnim` |
| `src\AcousticKeystrokes.ahk` | The mechanical keystroke sound bank: synthesis, the per-key voice map, and playback |

*UI and input*

| File | Role |
|---|---|
| `src\SettingsWindow.ahk` | The sidebar-nav GUI. **Sole owner of `C`, `Win`, `Pages`, `NavItems`, `CurPage`**. Holds all ten non-ASCII lines |
| `src\FeatureToggles.ahk` | Tray menu + every `Toggle*` flag handler + the `+!o` always-on-top binding |
| `src\InputBindings.ahk` | The hotkey block and its `#HotIf` contexts, the keyboard hook, the hotstring expander |

*Features*

| File | Role |
|---|---|
| `src\CmdWindowGeometry.ahk` | Place, tile, cycle size, next monitor, undo, maximize. Owns `ApplyLayout()` |
| `src\CmdTransparency.ahk` | The opacity wheel, reset, and the `CustomTrans` registry |
| `src\CmdAltDrag.ahk` | `Alt+LButton` move and `Alt+RButton` resize |
| `src\CmdRollUp.ahk` | Window shade / roll-up |
| `src\CmdTrayMinimize.ahk` | Minimize to tray, and the boss key |
| `src\CmdRestoreAll.ahk` | `Shift+Alt+Y` — the recovery path for state the user cannot see |
| `src\DragPipeline.ahk` | MOVESIZE/menu hooks, velocity sampling, drag end, magnetic groups |
| `src\DropPlacement.ahk` | Where a released window lands: snap, verify, glide, bounce, throw, tiling grid |
| `src\WindowClassification.ahk` | Is this a main application window? The WMI-backed classifier |
| `src\PositionMemory.ahk` | Remember and restore per-app size/position; the buffered `window-positions.ini` writer |
| `src\WindowOpenAnim.ahk` | Animate a brand-new window in: unroll, ghost slide-in, portal scale-in |
| `src\ShellHook.ahk` | `RegisterShellHookWindow` + `ShellEvent`; re-registers on `TaskbarCreated` |
| `src\AmbientDimming.ahk` | Breathing windows, monitor dimmer, and the MediaCore bridge that suspends them |
| `src\ScreenEdgeGestures.ahk` | Hot corners and infinite cursor wrap |
| `src\AudioOsd.ahk` | Volume and microphone OSDs and their input |
| `src\OnDemandOverlays.ahk` | Summoned and dismissed: Quick Look, Spotlight, text magnifier |
| `src\FocusEmphasis.ahk` | Cinema / focus mode dimming |
| `src\PinnedWindowModes.ahk` | Modes a window is opted into and must be released on exit: PiP, always-on-bottom, ghost |
| `src\MouseGestureFx.ahk` | Pointer-motion / idle / wheel driven: shake-find, yawn, ripples, drag trail, clipboard feedback |
| `src\ShellSurfaceWatcher.ahk` | The one poll over shell surfaces: auto-hide, taskbar wave, toasts |
| `src\TaskbarClock.ahk` | The custom taskbar clock, and the only network egress in the program |
| `src\FxGravity.ahk` | Gravity-drop close (`Alt+F4`) |
| `src\FxShatter.ahk` | Shatter to close (`Shift+Alt+F4`) |
| `src\FxCurtain.ahk` | Curtain drop on `Win+D`, and `RestoreCurtain()` |
| `src\FxBlackHole.ahk` | Black-hole minimize and delete |

*Stealth Panic — a bolt-on that also runs standalone*

| File | Role |
|---|---|
| `src\StealthPanic.ahk` | Stealth Panic Mode engine — triple-ESC hotkey, hide/mute/suspend, safe-app launcher |
| `src\StealthPanicConfig.ahk` | Storage for the Stealth Panic safe-app list. Included by both of the above |
| `src\StealthPanicUI.ahk` | Stealth Panic settings GUI — **a separate process**, not part of the app shell |

**The include contract.** Every module holds *function definitions and global initialisers only* — stated in its own header. **No module may contain a top-level call**; everything that has to run at startup goes in `Boot()`. `scripts\Check-Split.ps1` check 8 enforces this, and before `Boot()` existed the ordering hazard it removes had already produced two real bugs (see the `ProcessLifecycle.ahk` header). `MediaCore.ahk` is additionally kept free of `QPC()`, `RegisterAnimation()` and `WriteLog()` calls so a test harness can include it alone; every function that needs the clock takes `now` as a parameter.

**Coupling is by shared globals, not parameters.** Functions open with a bare `global` or a long global list. This is deliberate. Note the AHK v2 rule it relies on: a function may *read* a global without declaring it, but must declare it to *assign*. An assignment to an undeclared name silently creates a local instead — which is why `ApplyUi`, `LoadSettings` and `SaveSettings` use a bare `global`, and why any name assigned in those functions becomes a global (hence the `ui*` / `ep*` prefixes on their scratch variables).

### Architecture rules — mandatory, not aspirational

SOLID, DRY, separation of concerns and single-source-of-truth are **requirements** for this repo, adapted to AHK v2. The goal is not more files; it is clear ownership. Optimise for that, never for file count.

**Ownership.** One file, one responsibility. A file approaching ~1000 lines gets reviewed for natural boundaries; ~2000+ is an architectural problem unless there is a documented reason. **The split is done.** `src\WindowTweaks.ahk` went from 10,447 lines to 99 — an entry point and nothing else — across eleven behaviour-preserving commits; `docs\MODULARIZATION.md` records the phases and what was deliberately deferred. Do not append a new feature to `WindowTweaks.ahk` or to whichever module happens to be open: find the module that owns the responsibility, or add one.

**Three rules the module layout depends on**, all enforced by `scripts\Check-Split.ps1`: modules stay **flat in `src\`** with **no underscore in any filename** (both installers glob `src\*.ahk`, and `build\Setup.cs` unflattens `_` to `\` on extract, so `Window_Commands.ahk` installs as `Window\Commands.ahk` and fails on end-user machines only); **no top-level calls** outside `Boot()`; and every module that defines a hotkey **opens and closes with a bare `#HotIf`**.

**Single source of truth.** A value, rule, mapping or validation gets one authoritative definition. `TUNE_SPEC` is the worked example: one row per tunable number, and load/clamp/persist/UI are all generated from it. Adding a setting must not mean editing five unrelated functions. Where a mirror is required for performance (`SyncTuningGlobals`), say explicitly which copy is authoritative and which is derived.

**Layering.** Dependencies flow one way: input → feature logic → shared services → infrastructure → Win32. A feature expresses desired state; infrastructure applies it. Concretely: nothing outside `RenderCore.ahk` may call `WinSetTransparent`, `SetWindowPos`, `WinMove`, `WinSetRegion` or `WinSetExStyle`; a polling monitor is a `SetTimer`, an interpolation is a `RegisterAnimation`; GUI event handlers, tray items and hotkeys all delegate to the *same* named feature function rather than re-implementing it.

**Do not over-abstract.** No interface with one implementation, no pattern for a one-off, and above all **no `Utils.ahk` / `Common.ahk` / `Helpers.ahk` / `Misc.ahk`** — a module name must state a responsibility. Extract only where a real boundary exists; prefer incremental behaviour-preserving refactoring over any rewrite.

**Verify structurally.** There is no test runner, so `scripts\Check-Split.ps1` is the safety net — run it after any change that moves code between modules. Its **motion proof** is the important one: it hashes the sorted code lines of the whole resolved `#Include` stream, so a pure code-motion commit must leave it byte-identical. If a commit legitimately changes behaviour, re-anchor with `-Baseline` **in that same commit**, so the next agent is comparing against something true. Reference artifacts live in `build\refs\` and are committed on purpose.

Two AHK v2 facts the split leans on, both easy to get wrong:

- **A top-level `global X := ...` is a super-global** — visible inside every function in the whole script, including functions in other files defined textually earlier. That is why moving a feature into its own module cannot break name resolution. The inverse is silent: a declaration duplicated in two modules raises **no error**, and the later `#Include` wins.
- **`#HotIf` is positional, not scoped, and bleeds across `#Include` boundaries.** A module ending with an open `#HotIf` applies that context to the first hotkeys of the next included file. Every module that defines a hotkey opens and closes with a bare `#HotIf`; `Check-Split.ps1` enforces it. The same applies to `#UseHook`, `#InputLevel`, `#MaxThreadsPerHotkey` and `#Warn`.

### The render pipeline — read this before touching any visual feature

Two files, one rule each, and they are not optional.

**`RenderCore.ahk`** owns all output. Nothing outside it may call `WinSetTransparent`, `SetWindowPos`, `WinMove`, `WinSetRegion` or `WinSetExStyle`. Features *queue* desired state:

```
RS_SetAlpha(hwnd, 180, RS_PRI_AMBIENT)   ; or "Off"
RS_SetPos(hwnd, x, y, w := -1, h := -1, pri)  ; -1 w/h = SWP_NOSIZE
RS_SetRegion(hwnd, regionStr, pri)       ; "" clears
RS_SetZOrder(hwnd, insertAfter, flags, pri)
```

**Opacity on a FOREIGN window is composed, never absolute.** Several unrelated features can
want to dim the same window at once, and priorities only arbitrate *within one flush* - across
flushes an absolute write is simply last-writer-wins. So RenderCore keeps one persistent record
per window, `RS_AlphaState`, holding a base the user chose times any number of named modifier
layers, and it is the only thing that computes the committed value:

```
RS_SetBaseAlpha(hwnd, alpha, pri)              ; the user's wheel, and nothing else
RS_SetAlphaLayer(hwnd, "breathe", 0.7, pri)    ; factor 0.0 - 1.0
RS_ClearAlphaLayer(hwnd, "breathe", pri)       ; cannot touch the base or another layer
RS_ResetAlphaState(hwnd, pri)                  ; teardown only
RS_ResetAllAlphaState(pri)                     ; teardown only - Bye() and the panic key
```

`final = base * product(layers)`. `RS_SetAlpha` stays, but **only for windows we created**,
where one owner is guaranteed by construction and composition would be overhead for a value
that could only ever have one contributor.

**One owner per layer name**, and the language cannot enforce it, so the list lives in
`RenderCore.ahk`'s header: `"drag"`, `"ghost"`, `"breathe"`, `"open"`, `"gravity"`.
Two owners of one name reproduce the oscillation bug this replaced, inside a single layer,
where it is harder to see.

Before this, every producer wrote an absolute including a hard `"Off"`, and three hand-rolled
compositions had grown to work around it. The user-visible symptom: set a window to 50% with
`Shift+Alt+Wheel`, then let any ambient effect touch it - it wrote its own absolute and then
`"Off"`, so the 50% was gone while `CustomTrans` still claimed 128. Dragging, ghosting or
idling the window all did it. `CustomTrans` survives as a *predicate and registry*, not as the source of truth, and
breathing's `WinTargetAlpha`/`WinCurrentAlpha` now hold that layer's numerator rather than an
absolute opacity.

**`"Off"` (256, which strips `WS_EX_LAYERED`) is emitted only for a STRUCTURALLY neutral
record** - base 255 and zero layers - never because the arithmetic rounded up to 255.
`ToggleGhostMode` installs its layer at factor `1.0` for exactly this reason: a numeric rule
would strip `WS_EX_LAYERED` and re-add it 40 times a second while the cursor rests on a ghost,
and in between the window is opaque, click-through and always-on-top with no visible cue.

Priorities (`RS_PRI_AMBIENT` 10 < `RS_PRI_ANIM` 20 < `RS_PRI_DRAG` 30 < `RS_PRI_USER` 40) arbitrate *within one flush*: a lower-priority write is dropped, a higher one overwrites. Queued entries are deleted as they are applied, so the pending Maps only ever hold outstanding work — that is what bounds their size and what makes arbitration per-flush with no reset pass.

**Who flushes matters, and getting it wrong is silent.**

- A **per-frame animator** registered with `RegisterAnimation()` only queues. The scheduler calls `RS_Flush()` once per frame for it.
- A **one-shot producer** — a hotkey, a monitor timer, anything that queues and returns — **must call `RS_Commit()` itself**.

The scheduler stops its timer the moment nothing is animating, so a queued change with nobody to flush it is simply never applied. This is not hypothetical: it is what silently killed snapping-without-glide, the transparency wheel, breathing restore and un-ghosting, and what left brand-new windows sitting at alpha 0 — invisible, focused and clickable. If you add a visual feature, decide which of the two kinds it is.

Deliberately **not** cached: window positions. A cache is only valid when the cache owns the state, and the user dragging a title bar changes a window's position behind this pipeline's back. Caching last-requested positions made a second snap to the same edge a no-op. Alpha and region *are* cached (`RS_LastAlpha` / `RS_LastRegion`) because re-applying them is individually expensive — `WinSetTransparent` adds/removes `WS_EX_LAYERED` and `WinSetRegion` rebuilds a GDI region — and both caches are pruned by `RS_RemoveHwnd()` and the periodic `RS_SweepDead()`.

**Call `RS_RemoveHwnd(hwnd)` whenever a window we touched is destroyed.** For foreign windows the shell hook does it. For our own overlay GUIs (dimmers, OSDs, focus layers, the smooth caret, gravity animation) nothing does, because `WS_EX_TOOLWINDOW` / `NoActivate` windows raise no shell destroy notification — so every destroy site does it explicitly, and `RS_SweepDead()` is the backstop.

**Never read the pending Maps as if they were state.** `RS_Pos[hwnd]` is a *request* that has not been applied and can still be outranked in the same flush — and every move-only producer (`Glide`, `MoveFast`, curtain, toast) queues `w = h = -1` to mean `SWP_NOSIZE`. A since-removed overlay used `RS_Pos` as a position source, so `W`/`H` came back as `-1`, failed its own sanity check and hid itself for the whole of every glide, snap and layout key. Measure the window (DWM frame bounds, `WinGetPos` fallback).

**`AnimationScheduler.ahk`** runs `RenderFrame` every 16 ms: call every registered callback (produce), then `RS_Flush()` exactly once (render). A callback returns `true` to stay registered, `false` to be removed. The produce loop iterates a **snapshot of the keys**, not the Map — 11 other timers, every hotkey and the `SetWinEventHook` callback can interrupt it between lines and several of them call `RegisterAnimation`/`CancelAnimation`; mutating a Map under a live `for` enumerator shifts items and silently skips or repeats animations. `RS_Flush()` is likewise re-entrancy-guarded, because timers call it directly while the frame loop may be inside it.

`StopScheduler()` **re-checks `ActiveAnimations.Count` and refuses to stop while work is queued.** `RenderFrame` tests the count and then calls it, and those two steps are not atomic: anything that interrupts in between and calls `RegisterAnimation` saw `SchedulerRunning` still true (so `StartScheduler` was a no-op) and then had its timer killed underneath it. `Bye()` passes `StopScheduler(true)` to override, because it is about to undo every animation anyway.

**Two animations must not share a window at the same priority — and the shell hook is a producer too.** Two animators that both wrote `RS_Pos[hwnd]` at `RS_PRI_ANIM` did not tie: Map keys enumerate sorted, so the alphabetically later key was produced last and won every frame, and the loser's captured rect — taken *mid-glide* — was then restored on its final frame, which discarded the snap the user had just made. That is what `Anim_Claim(hwnd, "geom", ...)` exists to prevent, and why a producer asks `Anim_Owner(hwnd, "geom")` rather than naming specific competitors: every hand-written list of rivals in this codebase had drifted and missed at least one. An **ambient** cue belongs at `RS_PRI_ANIM`; `RS_PRI_USER` is for an explicit command, and an ambient effect placed there out-ranks every glide and bounce on the window.

### Performance: what things actually cost

Measured on this machine (Windows 11 26200, AHK 2.0.26, median of interleaved A/B
runs against the same probe window). **Do not trust intuition on this codebase —
the two dominant costs were both disk I/O hiding behind innocent-looking calls.**

| Operation | Cost | Note |
|---|---|---|
| `FileAppend` one line | **1,900–9,300 µs** | open + write + close, plus the AV filter |
| `IniWrite` one key | **770 µs** | ×45 keys = 34 ms for a full settings save |
| MediaCore endpoint rebuild (COM) | 6,500 µs | every 30 s while a fade feature is on |
| `SetWindowPos` on a real window | 260 µs | drives actual composition; irreducible |
| MediaCore steady sweep | 230 µs | 1×/s |
| `IniRead` one key | 64 µs | LoadSettings does ~45 = 2.9 ms once |
| `WinGetList()` | 33 µs | plus ~8 µs per window for `IsSnappable`+`GetRects` |
| `CollectEdges` (whole snap) | 90–220 µs | scales with visible window count |
| `MonitorGet` / `MonitorGetCount` | 2.9–3.2 µs | cached in `ScreenMetrics()` |
| `MC_IsMediaHwnd` | 1.7 µs | per window per frame — hoist it |
| `WinGetPos` / `GetWindowRect` | 2.1 / 1.9 µs | no reason to prefer the DllCall |
| `WinGetClass` | 1.1 µs | allocates; 4× the cost of `WinGetStyle` |
| `WinGetStyle` / `ExStyle` / `MinMax` / `WinGetPID` | 0.28 µs | effectively free |
| Map get/set, object literal, `[]` | 0.33–0.6 µs | allocation is not a problem here |

**Rules that follow from those numbers:**

1. **Never touch the disk on an input path.** Logging is buffered in RAM and
   written by an idle one-shot (`WriteLog` → `FlushLog`); settings are diffed
   against `IniCache` and written by an idle one-shot (`SaveSettings` →
   `WriteSettings`). Before this, one drag spent **30 ms** in `FileAppend` and one
   toggle spent **31 ms** in `IniWrite`, both on threads that block the frame loop.
   `Bye()` calls `WriteSettings()`/`FlushLog()` directly because there is no idle
   on the way out.
2. **Hoist any per-window predicate out of a per-window loop.** `MC_AnyMedia()` is
   the O(1) "could anything match?" gate; call it once per tick and `&&` it.
3. **Cache anything derived from the display layout.** `ScreenMetrics()` caches
   monitor rects and virtual-screen bounds, invalidated by `WM_DISPLAYCHANGE`.
4. **Don't micro-optimise window queries.** The style/state getters are 0.28 µs.
   Two attempts that *lost*: moving the `IsSnappable` class regex into a helper
   function (−10%, call overhead beats the regex) and memoising it per class name
   (no measurable difference). A single-window fast path in `RS_Apply` also
   measured as no change, because the `SetWindowPos` dominates. All three were
   reverted — the comments at those sites say so, so nobody retries them.
5. **Measure A/B in one process against the same probe window.** The visible
   window set changes minute to minute, so comparing two separate benchmark runs
   is meaningless; several "regressions" during this work were only that.

One deliberate trade-off: a settings change is written ~700 ms after the last edit
rather than instantly, so a hard kill (not an exit or a reload) within that window
loses it.

### Animation rules

**The frame period is 15 ms and must not be "corrected" to 16.** Windows' clock
tick is ~15.6 ms, so a 16 ms deadline always lands just past the next tick, waits
for the one after, and the cadence alternates 15.6 / 31.2 ms. Measured over 100
frames, idle:

| period | mean | jitter | fps | frames > 20 ms |
|---|---|---|---|---|
| 16 | 25.15 ms | 7.59 ms | 39.8 | 59% |
| **15** | **15.92 ms** | **0.37 ms** | **62.8** | **0%** |

That single character was worth more than every other animation change combined.
`timeBeginPeriod(1)` is required for it (without, period 16 measured 26.26 ms /
8.17 ms jitter).

**Parameterise on elapsed time, never on frame count.** `t := (now - start) / ms`
is the standard shape. A fixed step per frame is frame-rate dependent: measured, a
26-frame fade took 659 ms instead of 416 ms once frames got heavy — slow motion
under load. Where a rate really is the right model (breathing, the focus
spotlight), scale by `dt`: rates are written as `perFrameValue / FRAME_MS` so they
still look identical at the nominal cadence. `dt` is clamped to 3 frames so a
stall cannot teleport an animation to its end.

**A ramp calibrated by gain rather than by endpoints cannot be checked by eye.**
Drag parallax was `alpha := 255 - speed * 0.06` with speed in px/s, so an ordinary
400 px/s drag landed at 225/255 - 88% opacity, a change nobody can see - and the
24% floor was only reached past 3200 px/s. It was doing exactly what it said and
was still indistinguishable from switched off. `ParallaxAlpha()` names both ends
instead (`[memory] parallaxfrom`, `parallaxfull`), so "invisible at a normal drag
speed" is a number on the settings page rather than a constant on a 15 ms path.
Both drag paths call that one function; the gain used to be written out longhand in
each of them, which is how they had drifted apart before.

**Never derive a duration from a frame count.** `ms := 12 * 16` was silently a
frame-count assumption; those are all plain millisecond values now.
**Velocity is pixels per SECOND, and every consumer is calibrated in that unit.**
`SampleVelocityStep(dt, now)` was handed `dt` and ignored it, smoothing the raw per-frame
displacement instead - so the throw gain, the monitor-throw and tilt thresholds, the parallax
opacity ramp and the magnetic-group break were all silently calibrated to a 15 ms frame, and
under load the same hand motion reported up to 3x the velocity. The smoothing constant is a
time constant (`k := 1 - Exp(-dt / 30.0)`) for the same reason. `AltDragMove` samples on a
`Sleep(10)` cadence rather than the frame clock, so it measures its own elapsed time and
publishes the same unit - which is what makes an alt-drag and a title-bar drag of the same
speed finally throw the same distance.

**Two animations must never drive the same property of the same window at the same
priority.** `RS_*` arbitration is per-flush and ties are broken by Map order, and
AHK enumerates a Map **sorted by key** — verified empirically. So `Bounce_<hwnd>`
was produced before `Glide_<hwnd>` and the glide overwrote every bounce frame:
"Bouncy Snapping" never put a pixel on screen unless ice glide was off. Anything
that should happen *when a window lands* has to be scheduled for after the glide,
which is what `BounceOnLanding` and `FlashSeams` do. The same applied to the seam
flash, which used to hang in empty space at the destination for up to 650 ms
before the window arrived.
**Ownership is enforced, not remembered.** `AnimationScheduler.ahk` owns a channel
registry: `Anim_Claim(hwnd, channel, key, cb)` gives one animation sole ownership of a
`(window, channel)` slot and cancels whoever held it, `Anim_Release(hwnd, channel)` clears it,
and `Anim_Owner(hwnd, channel)` answers "is anything driving this?". Channels are `"geom"`,
`"alpha"` and `"region"`. An animation that ends of its own accord releases its channel, so a
feature cannot forget to.

This replaced **five hand-maintained `CancelAnimation` lists** - in `ApplyLayout`,
`UndoLayout`, `ToggleMaximize`, `AltDragMove` and the MOVESIZESTART hook - which had drifted
apart and between them named only six of the ten animations that write `RS_Pos`. None of them
named `Jello_`, so grabbing a window during a 400 ms momentum wobble left the wobble resizing
it underneath the drag. Every window-motion animator now claims `"geom"`; `PulseWindow` and
`VerifySnap` decline on `Anim_Owner(hwnd, "geom")` instead of naming specific competitors.

**One animation key per window per effect, covering both directions.** The OSD
fades were `OSDIn_<hwnd>` and `OSDOut_<hwnd>` — different keys, so both could run
on the same window in the same frame. They share `OsdFade_<hwnd>` now, so
registering either cancels the other, and a fade can start from
`RS_CurrentAlpha()` rather than jumping.

**Set the region and the alpha before `Gui.Show()`.** Doing it after costs one
frame of a hard-edged, fully opaque window — the Spotlight launcher flashed a grey
rectangle on every launch. Likewise, when swapping a real window for a bitmap copy
(gravity close), show the copy *before* hiding the original or there is a frame
with neither on screen.

**Do not put a countdown in the scheduler.** Two OSD auto-hides were registered
animations that did nothing but compare a deadline, holding the 15 ms loop and
`timeBeginPeriod(1)` open for 95 and 127 frames. A negative `SetTimer` is the
right tool.

**Skip frames that would not change a pixel.** `SetWindowPos` on a real window
costs ~260 µs and forces the target app to re-layout; `Glide`, `PulseStep` and
`BounceStep` all compare against the last applied integer rect first.

There are **no taskbar animations** in this program — that engine was removed. The
taskbar's own animations are a Windows setting (`TaskbarAnimations`), handled by
`scripts\Apply-Windows-Tuning.ps1`.

### Timers

There is no single "the only timer" any more. `RenderFrame` at 16 ms while animating; then per-feature monitors, each started/stopped by its own `Sync*` function so a feature nobody enabled costs nothing: cursor wrap 20 ms, ghost proximity 25 ms, taskbar/UI 32 ms, shake+yawn detector 40 ms, hot corners / focus 50 ms, PiP / Quick Look 100 ms, breathing / dimmer / smart taskbar 200 ms, MediaCore 250 ms, breathe-cursor idle 1 s. Plus one-shot `SetTimer(..., -ms)` calls for deferred work.

**Every polling timer must have a `Sync*`, and `Bye()` must stop it.** Three did not: `CheckTaskbarAndUI` (32 ms), `ShakeDetector` (40 ms) and `CheckMouseIdle` (1 s) were armed unconditionally at load and ran forever regardless of their flags — `CheckToasts` alone enumerates every top-level window with a title filter on each tick. They are now `SyncTaskbarUiTimer()`, `SyncShakeDetector()` and `SyncCursorFxTimer()`, called from the deferred-init block and from `ApplyUi`. `Bye()` stops all of them plus the nine private 16 ms FX loops; several of those can otherwise re-create an overlay *after* `RS_Shutdown()`, and `Bye()` is also the tray → Restart path.

**A monitor is a `SetTimer`, never a `RegisterAnimation`.** A poller was once registered as an animation whose callback always returned `true`, so `ActiveAnimations` was never empty, the scheduler never reached its idle shutdown, and enabling that feature pinned the 15 ms frame loop *and* `timeBeginPeriod(1)` for the whole session. Same mistake as the OSD auto-hides. If it polls rather than interpolates, it is a timer — and it must call `RS_Commit()` itself.

**A feature that owns an overlay must tear it down when its flag goes false, and the flag test belongs *inside* that function.** Gating the call site instead means switching the feature off stops the only code that could ever clean up. Three separate overlays were stranded that way — a full-screen dimming sheet left over the desktop, a bar welded to a window edge, opaque sheets over marked windows — each visible with the feature that owned it disabled and no way left to reach it. `RenderTaskbarWave` has the right shape: `CheckTaskbarAndUI` calls its sub-checks unconditionally so they *can* clean up, and each tests its own flag as its first act.

**Drag pipeline**: `SetWinEventHook` on `EVENT_SYSTEM_MOVESIZESTART`/`END` → `SampleVelocityStep` on the frame loop (EMA-smoothed velocity, parallax alpha) → `FinishDrag` deferred 50 ms with the start rect captured in the closure (it enumerates windows, so it must not run inside the hook) → `SnapWindow` → `Glide` → `VerifySnap` scheduled for after the glide lands. MOVESIZEEND also fires *after* the OS modal move loop, which is the only safe moment to reposition.

A `~LButton` hotkey was originally rejected because it makes AHK install a low-level mouse hook that wakes on every mouse move — measured at ~1.6% of a core while idle. **That optimisation has since been given up**: `~LButton`, `~WheelUp`/`~WheelDown` and `*MButton` all exist now, and AHK installs the mouse hook whenever any mouse hotkey is defined, `#HotIf` notwithstanding. An attempt to verify whether disabling them releases the hook was inconclusive (`KeyHistory`, the only way to read hook state, installs both hooks itself). What *was* fixed is the per-event work: Elastic Scroll, middle-click Roll-Up and middle-click Close now default off, so the `#HotIf` is false and the bodies do not run; and the `WM_NCHITTEST` probe is skipped unless Roll-Up or Close is actually on.

**Nothing keyed to input may touch the disk.** `window-positions.ini` was written with four synchronous `IniWrite`s (~771 µs each ≈ 3 ms) at the end of every drag *and* again from `OnSnapLanded`. It is buffered in `PendingPositions` and flushed by a 900 ms one-shot (`WritePositions`), exactly like `SaveSettings` → `WriteSettings`; `Bye()` and `ForgetPositions` deal with the buffer directly. For the same reason `RememberPosition` no longer calls `IsMainApplicationWindow`, which reaches a **WMI query** through `ClassifyWindowImpl` — tens of milliseconds of blocking COM on the drag path. Classification belongs on the window-created path, where `RestorePosition` already does it.

The hook callback is **not** created with `"F"` (fast) mode. Fast mode runs on top of whatever script thread the event interrupted and must be trivial; this one queries the window, registers an animation and arms a timer.

`Glide` is elapsed-time driven (not step-counted), quintic ease-out `1-(1-t)**5`, and returns its duration in ms so the caller can schedule verification after it lands. `timeBeginPeriod(1)`/`timeEndPeriod(1)` are held by the scheduler for as long as anything is animating.

**Nothing in the drag or snap path may block.** `SnapWindow` used to spin twice for 40 ms in a busy-wait that never pumped messages, which froze every timer in the process — including the frame loop that had just been armed to run the glide it had started. Verification is a one-shot timer now, and it declines to act while a `Glide_<hwnd>` animation is still registered. Use `Sleep` (which yields) if you need to wait; there is no `PreciseSleep` any more.

### Keystroke sounds, and the hook they ride on

`AcousticKeystrokes.ahk` SYNTHESISES every click into a RIFF/WAVE image in
memory and plays it with `PlaySound` + `SND_MEMORY`. It replaced a MIDI
implementation that sent GM percussion (woodblock, rimshot, hi-hat, bass drum,
hand clap) through `midiOutShortMsg` - those are orchestral samples from the
Windows GS wavetable, so typing sounded like a drum kit rather than a keyboard,
and the timbre could not be tuned at all. A voice here is a bright noise
transient (the switch click) over a heavily damped low sine (the keycap
bottoming out on the plate), plus an optional second click at a fixed delay -
the spacebar's stabiliser rattle, and what makes the copy/cut voices read as a
double tick. Measured: the full bank of 30 clips renders in **78 ms**, so it is
built by a one-shot armed from `SyncKeySounds()` and never on the input path.

**Action voices are a second family, on their own flag and their own volume.**
`toggleon` / `toggleoff` / `command` / `alert` are rendered from the same synth
with a second strike at a different pitch (`pitch2`), which is what makes them
read as a deliberate gesture rather than as another key. `PlayHotkeySound()`
gates on `HotkeySoundsEnabled`; `PlayAcousticSound()` gates on
`TypingSoundsEnabled`; both go through `AK_Emit()`. **Every call site is a named
feature function, never a hotkey body** - `ToggleFeatureFlag()` covers all
thirteen feature toggles at once, `ApplyLayout()` covers centre/tile/cycle/next
monitor/undo - so the tray menu and the settings window sound the same as the
key. Measured at the shipped levels (keys 80%, actions 90%): 42 clips render in
203 ms and **zero** samples clip, the loudest peak being 30205 of 32767.

**`Map.Delete` THROWS on a key that is not in the map** - "Item has no value".
`AK_KeyReleased()` runs on every key-up, and plenty of those arrive with no
matching key-down: a key consumed by a suppressing hotkey (a Win chord sends no
`LWin` down to the hook but does send the up), a key already held when the hook
started, anything pressed while the feature was off. It is a hook callback, so
the throw pops an error dialog at the user and kills the handler for the session.
Guard every `Delete` with `Has()`.

**`InputHook.OnKeyDown` fires ONLY for keys carrying the Notify option.** The
shared `SparkHook` set none, so ordinary letters were never reported and the
keystroke sounds, the spark trail and the smooth caret only ever fired on a
handful of keys - the whole reason the feature sounded like percussion hits
rather than typing. `UpdateKeyboardHook()` now calls `KeyOpt("{All}", "N")`,
which is also what makes `OnKeyUp` fire, which `AK_IsRepeat()` needs: auto-repeat
delivers a key-down every 30-100 ms while a key is held and a real switch clicks
once, so the gate is "is this key already down", not a repeat-rate guess.

**A SUPPRESSING hotkey hides its key from the InputHook; a PASS-THROUGH one does
not.** Measured on 2.0.26 with Notify on: `$^v` fires and the hook never sees
`v`, but `~^c` fires AND the hook still reports `c`. So the two clipboard paths
are not naturally exclusive - without a guard every `Ctrl+C` clicked twice, once
from `AK_VoiceForKey()` and once from `TriggerCopyFeedback`. `AK_VoiceForKey()`
returns `""` (a deliberate silence, distinct from an unknown voice) for `c`/`x`
while `ClipboardAppendEnabled || CopyFeedbackEnabled` holds, and for `v` while
`MorphingPasteEnabled` holds. Those two conditions MIRROR the `#HotIf` contexts
in `InputBindings.ahk` and have to be changed together.

**Purge playback before freeing a buffer.** `SND_ASYNC` means winmm is reading
our `Buffer` after the call returns, so `AK_Shutdown()` calls `PlaySound` with
`SND_PURGE` first and drops `AK_BANK` second. `Bye()` does the same, and it is
also the tray -> Restart path.

**The same rule governs a RE-RENDER, and that is the path users actually take.**
Every change to a level or the pitch rebuilds the bank, usually while the user is
still typing in the settings field - so `AK_BuildBank()` would drop the last
reference to buffers the mixer is mid-way through. It publishes, purges, then
releases, in that order: `oldBank := AK_BANK` holds the previous clips alive,
`AK_BANK := bank` means a keystroke interrupting between the lines plays a NEW
clip, `SND_PURGE` stops anything still sounding from the old ones, and only then
is `oldBank` cleared.

**A level the user changed has to be AUDIBLE, or it is indistinguishable from a
setting that does nothing.** The field holds a number and the sound it governs
only happens on the next keystroke somewhere else, so `AK_BuildBank()` plays one
click at the new level whenever it re-renders because a setting moved - keystroke
voice for `keyVol`/`keyTone`, action voice for `hotkeyVol`. The boot render is
gated out (`prevVol < 0`), where a click out of nowhere would just be noise.

**All three stamps are declared beside the bank.** `AK_BankVol`, `AK_BankHotVol`
and `AK_BankTone` are what `SyncKeySounds()` compares against to decide whether a
re-render is needed, and `AK_Shutdown()` resets all three. `AK_BankHotVol` was
originally declared nowhere and reset nowhere - a name that exists only after the
first render, compared against on every settings change.

**The sound settings live at the TOP of the `System & Media` page**, not on
`Multi-Monitor` where they started. That page is over 1000 px of content in a
700 px window that scrolls without a scrollbar, so the levels sat below the fold
under a nav entry promising monitors. A setting nobody can reach is
indistinguishable from one that does not work - which is the same lesson the
clock settings taught, recorded under **The settings window scrolls**.

### Win32 gotchas the code depends on

- **Two coordinate spaces.** Snapping measures with `DWMWA_EXTENDED_FRAME_BOUNDS` (attr 9); `WinGetPos` differs by the invisible DWM border. `GetRects()` in `SnapCore.ahk` returns *both*, and `SnapWindow` converts back (`destX := winX + (newL - L)`). Ignore this and every snap lands ~7px off.
- **`DWMWA_CLOAKED` (attr 14)** filters UWP-suspended and other-virtual-desktop windows; `WS_VISIBLE` alone does not catch them.
- **Position memory is keyed on exe + window class**, and excludes owned/tool/non-resizable and Picture-in-Picture windows — every Chrome popup shares a class with the main window.
- **New windows are detected via `RegisterShellHookWindow`, not polling — and that registration does not survive an Explorer restart.** `TaskbarCreated` is broadcast when the shell comes back; handling it and re-registering is the only thing keeping position memory, the open animations, breathing seeding, fly-to-mouse minimize and per-window cleanup alive after an Explorer crash (or after this app's own "Restart Explorer" button).
- **Never make a foreign window layered speculatively.** `WinSetTransparent` on a new window forces `WS_EX_LAYERED`; on a GPU-composited or full-screen window that costs a redirection surface and can break exclusive full-screen presentation. `WillAnimateOpen()` is the single eligibility test, applied *before* hiding a new window rather than after.
- **Never `SendMessage` to a foreign window without a timeout.** A window whose thread is not pumping messages ("Not Responding") never returns, freezing this whole process — every timer and every hotkey — with it. Use `SendMessageTimeout` with `SMTO_ABORTIFHUNG` (see `AskWindowIcon()` and the `WM_NCHITTEST` probe in the `*MButton` handler).
- **A timer callback that throws pops an error dialog and kills that timer** — the feature is then dead for the rest of the session. Any window query in a monitor must be inside `try` with an explicit fallback; `IsMouseOverTaskbar()` is the pattern to copy.
- **`SetParent` across processes** (always-on-bottom) is not really supported by Win32 and is not undone by anything except `RestoreFromBottom()`. A window left parented to `WorkerW` cannot be alt-tabbed to, cannot be moved normally, and dies with the next Explorer restart — so exit-time restoration is mandatory, not polish.

### Stealth Panic Mode

Triple-tap `Esc` (default window 600 ms) hides every window, mutes system audio and the microphone, suspends the overlay and animation features, and launches a configured list of "safe" applications. Triple-tap again to put everything back.

It is a **bolt-on**, not part of the app shell, and the seams matter:

- `src\StealthPanic.ahk` is `#Include`d by `WindowTweaks.ahk` (hosted case) **and** runs on its own under `%LOCALAPPDATA%\Stealth Panic Mode` via `Stealth Panic Mode.ps1` (standalone case). Half the functions it wants to call — `SyncActiveBorderTimer`, `SyncBreathingTimers`, `ClosePiP`, `UnGhostWindow` — do not exist standalone. **A direct call to a missing function is a LOAD-time error that `try` cannot catch**, so every one of them goes through `StealthCall(name, args*)`, which resolves `%name%` at *runtime* and swallows the failure. Same reason the existing `IsSet(...)` guards are there; `IsSet` on an unknown identifier returns false rather than failing to load (verified).
- It has **its own config file** (`StealthPanic.ini`, section `[stealth]`) and **its own settings GUI in a separate process**. It does not use `IniStr` / `PutIni` / `IniCache` / `LoadSettings` / `WriteSettings` / `ApplyUi`. Note `StealthPanicUI.ahk` defines its own `SaveSettings(*)` — harmless while the processes are separate, a hard collision with `WindowTweaks.ahk:585` the moment anyone merges them.
- The GUI takes the ini path as **argument 1** (`StealthPanicConfig_ResolveIniPath()`), falling back to `A_ScriptDir`. Both installers pass it. Without that handoff, a machine carrying both installs has the GUI editing one folder's config while the engine reads another's — settings that appear to save and then do nothing.
- Saving does **not** reload Window Tweaks; that would run `Bye()` and un-hide every window, drop the tray icons and cancel every animation just to pick up a list. Instead `ToggleStealthPanic()` calls `StealthPanicRefreshSettings()` on the way **in** — and deliberately not on the way out, because `StealthMuteAudio`/`StealthMuteMic` decide whether the *original* mute state is handed back and must still hold what they held when it was captured. The reload `PostMessage` remains, but only targets the genuine standalone runner.
- `SuspendStealthFeatures()` / `RestoreStealthFeatures()` must call `StealthSyncFeatures()` after flipping the flags. Flipping a flag alone leaves the feature's timer running and its overlay on screen — the same failure mode documented under Timers, and worst here, since the whole point is that nothing of the previous workspace shows.

**Why the safe-app list is not in the ini, and must not be moved back.** Measured on 26200 / AHK 2.0.26:

| Behaviour | Consequence |
|---|---|
| `IniWrite` writes the LF bytes but `IniRead` stops at the first newline | A multi-line value stores as one line — this was the "only the first app survives" bug — and the remaining lines become key-less orphans in `[stealth]` **permanently**, since `IniDelete` removes only the `applist=` line |
| A single-key `IniRead` strips surrounding double quotes and trims whitespace | `"C:\Program Files\...\devenv.exe"` reads back unquoted and then fails the quote parsing in `LaunchSafeApps` |
| A whole-section `IniRead` does **not** strip, and returns `key=value` pairs LF-separated in physical file order | The two read paths on the same file disagree with each other |

So the list lives in `StealthPanicApps.txt`, one entry per line, UTF-8 **with** a BOM, written temp-then-`MoveFileExW`. Its path is derived from the *ini path*, never `A_ScriptDir`. `StealthPanicConfig_ReadAppList` checks sidecar → `[SafeApps]` → legacy `[stealth] applist` → default, and migrates forward. **The legacy key is checked last on purpose**: checking it first is exactly what made a saved list collapse back to one app on every reopen.

Two rules for that module: nothing in it may throw (it runs from a top-level initialiser that `WindowTweaks.ahk` includes, so an exception is a load-time error that kills the whole app), and the ini stores are purged only *after* the sidecar is written and read back — purging first turns a failed write into data loss. `src\test_stealthconfig.ahk` is the harness; it prints raw bytes both ways and exits with the failure count.

`CLAUDE.md`'s "pure ASCII, no BOM" rule is about `.ahk` **source** files. The sidecar is runtime data and its BOM is deliberate.

### Game Mode

`Shift+Alt+F12` suspends ~48 disruptive features for gameplay, holding the user's
real values in `GameModeSuspendedFeatures` and setting every flag to false.

**The suppression is an in-memory OVERLAY and must never reach settings.ini.**
`WriteSettings()` persists whatever the globals currently hold, so a shutdown,
restart or reload while Game Mode was on wrote all ~48 features as `0` - the
user's entire configuration, gone on the next launch with nothing to restore it
from. `WriteSettings()` therefore brackets its whole body with
`GameModeUnsuspendForWrite()` / `GameModeResuspend()` in a `try/finally`, so the
file records the configuration rather than the overlay no matter which path
writes it or what throws. `EnterGameMode()` additionally flushes settings BEFORE
it touches a flag, which covers the case no exit handler can - a power cut or a
`Stop-Process -Force` mid-session.

**One feature list.** `GAME_MODE_FEATURES` is the only copy. It used to be
written out twice, once per direction, and a name in one copy but not the other
is a feature that gets suppressed and never restored.

The four loops over it are assume-global (a bare `global`) because they assign
through a dynamic reference, `%gmFeat% := ...`, which resolves to a LOCAL in an
assume-local function and would silently suppress nothing at all. That makes
every assignment in them global, hence the `gm` prefix on their scratch
variables - the same rule `ApplyUi` follows with `ui`/`ep`.

### Runtime files

`settings.ini`, `window-positions.ini`, `snap.log` (+ `.old`, rotated at 256 KB) are written to `A_ScriptDir` — so running from source writes into `src\`, not the installed copy at `%LOCALAPPDATA%\Window Tweaks`. Stealth Panic adds `StealthPanic.ini` and `StealthPanicApps.txt` next to whichever copy is running. All gitignored. Nothing is written outside the program folder except a Startup `.lnk`; the registry is read-only (`AppsUseLightTheme`) — there is no `Run` key, service, or scheduled task.

### Custom Taskbar Clock - the one network egress

Time over date with the temperature beside it, drawn on the taskbar.
`CustomClockEnabled`, ini key `[taskbar] customclock` (default `1`), plus
`clockanchor`, `clockweather`, `clocklocation`, `clockunits` and `clockfont`. Wired
through `LoadSettings` / `WriteSettings` / `BuildWin` / `ApplyUi`, armed by
`SyncCustomClockTimer()`, drawn by a 250 ms `UpdateCustomClock()` timer. It has a
settings page of its own, registered as a `Taskbar Clock` entry in the sidebar nav
list.

**There is no coordinate anywhere in this feature.** Position is
`anchorLeft - gap - contentWidth`, where the anchor is resolved by CLASS NAME every
tick and the width comes from the font. Both halves of that matter, and both were
learned the hard way.

**Anchors are a setting, not a constant, because the two options are a genuine
trade-off.** `ResolveClockAnchor()` walks an ordered list and falls back:

| `[taskbar] clockanchor` | Anchor window | Cost |
|---|---|---|
| `TrayEdge` (default) | `TrayNotifyWnd` - left of every tray element | Distance. That window is the whole notification area and its width moves with the icon count: measured 343 / 391 / 415 / 511 px in one session. At 511 px the block ends up 480 px from the clock. |
| `Clock` | `TrayClockWClass` | Covers whatever is in those ~115 px - on this shell the Control Center button, the input indicator and part of the tray icons. |

The first version had no choice: it was 110 px wide, anchored on `TrayClockWClass`,
grown leftward, and it covered the native clock and the Control Center button. That
read as a corrupted system tray - the notification icon looked like it had moved,
the spacing was wrong, and a failed weather lookup printed `no data` where the time
belongs. Nothing in Explorer had changed; it was all *covered*, not moved.

**The block is painted in the taskbar's own colour, never colour-keyed.** Keying
looked right in theory and fringed in practice: a keyed background needs every
background pixel to be exactly the key colour, but antialiased and ClearType glyph
edges BLEND with it, so those pixels are no longer the key, survive the keying, and
halo every character in it - visibly magenta text edges. Painting an opaque block in
the bar's own colour makes the panel disappear instead, with no edge artefacts at
all. That works because the taskbar is one flat colour: measured `0x202020` at
x = 200, 600, 1000, 1200, 1300 and 1400, including over inactive task buttons.
`SampleTaskbarColor()` reads it once per rebuild from a point to the LEFT of the
block, so the block can never sample itself, and falls back to a theme-derived
default. Verified after the change: `WS_EX_LAYERED` absent and the block's own
corner pixel reading `202020`, identical to the bar.

**The info column carries the condition glyph and temperature on one line and the
wind on the next.** `WeatherIcon()` maps the WMO `weather_code` to a single glyph,
and every glyph it can return is in the BMP on purpose: those live in Segoe UI
Symbol, which font fallback finds, whereas the astral-plane weather emoji need
Segoe UI Emoji and render as tofu in a plain Static control. Both glyph and wind
are additive - a reply missing either still produces a reading, because the
temperature is the part that has to be there. Wind follows the temperature unit:
`km/h` for Celsius, `mph` for Fahrenheit via `wind_speed_unit`.

**The temperature column exists whenever the feature is on; only its VALUE is
conditional.** It reads `--` until a location produces a reading. Sizing the column
to zero when no reading had arrived yet is what made a merely *unconfigured* feature
look like a *broken* one, and that is the whole reason the placeholder is there.

Four things that are easy to reintroduce:

- **`ControlGetHwnd("TrayClockWClass", ...)` throws.** The clock is a *grandchild*
  of `Shell_TrayWnd` via `TrayNotifyWnd`, and a bare class name is not a valid
  ClassNN - AHK wants `TrayClockWClass1`. Measured on 26200: the bare form raises
  `TargetError: Target control not found.`, and `ControlGetHwnd` throws rather than
  returning 0, so the `if (!clockHwnd)` guard under it was unreachable. Inside a
  timer callback that throw pops an error dialog and kills the timer, so the feature
  had never once drawn anything. `FindTrayElement()` uses `FindWindowExW` at both
  levels and returns 0; keep the tick body behind the `try` in `UpdateCustomClock()`.
- **The overlay must forward `WM_CLOSE` to `ExitApp`.** `taskkill`, `Install.ps1`'s
  `StopRunning` and a Windows shutdown all post `WM_CLOSE` to the process's
  top-level windows. This is the first PERMANENTLY visible overlay in the program,
  so it is found before the script's own hidden main window and absorbs the request.
  Measured: the app then never exited, `Bye()` never ran, `settings.ini` was written
  with 4 lines instead of 142, and the block stayed on screen. Any future
  always-on overlay needs the same handler.
- **The default is ON, and that is only safe because nothing is requested until a
  city exists.** `FetchWeather()` returns immediately when `clockweather` is off or
  `clocklocation` is empty, so out of the box the block shows time and date and the
  program makes no outbound call at all. Do not "simplify" those early returns away.
- **open-meteo over WinHttp, not wttr.in over MSXML.** Measured: MSXML (3.0 and
  6.0) returns status 200 with an EMPTY `responseText` for an `application/json`
  body, so every reading came back blank; and wttr.in answers 200 with its HTML
  landing page instead of an error status whenever it will not serve a reading - it
  did that for `/Baku` while answering `/Berlin` in plain text, did it for
  `?format=%t` alone, did it for everything after roughly twenty requests in a few
  minutes, then began timing out entirely. `WinHttpRequest` is opened async and
  polled with `WaitForResponse(0)`, which returns immediately, so nothing on this
  path blocks; a bare `WaitForResponse()` would block every timer in the process.
  Two requests: the geocoder resolves the city once and the coordinates are cached
  for as long as the setting holds, so the steady state is one request per 15
  minutes. `WeatherFailed()` triples the retry interval up to 15 minutes rather than
  retrying into a rate limit.

### Two rules the settings window and its overlays learned the hard way

**AN INPUT NEEDS BOTH A BACKGROUND AND A TEXT COLOUR.** A Gui's `BackColor`
reaches an `Edit`'s background but never its text, which stays the system default
black - so on the dark theme every numeric field was black on near-black and
could only be read while it was selected and the highlight inverted it. `BuildWin`
defines `EDITBG`/`EDITFG` next to the rest of the palette and every `AddEdit` and
`AddDropDownList` takes both; `TuneRow` reads them as globals because it builds
most of the fields. Measured: with no options at all a DropDownList renders white
with black text (readable but jarringly light against a dark page), an Edit does
not.

**AN OVERLAY THAT AN ANIMATION SHOWS MUST NOT BE HIDDEN ONLY BY THAT ANIMATION.**
The smooth caret registered a glide, and the glide's settle branch returned
`false` - unregistering itself while the blue bar was still on screen at alpha
200. Nothing else was watching, so the bar stayed where the caret had last been,
through focus changes, through the caret disappearing, through the feature being
switched off, and through `Bye()`. `SmoothCaretWatchdog` is the fix and the
pattern: a 250 ms `SetTimer` armed when the overlay is shown, taking it down when
the caret is gone, the foreground window changed, the flag went false, or the
caret has simply held still - and one `HideSmoothCaret()` that every caller goes
through.

### The settings window scrolls, and that used to be invisible

`BuildWin` builds one long single column per page into a child Gui, and
`OnMouseWheel` scrolls it by moving that Gui - there is **no scrollbar**. So a page
taller than the client area is a page whose remaining controls the user has no
reason to believe exist. Measured: the Window Management page is over 1000 px of
content, and four drag-fade settings sat off screen with nothing to indicate it,
which reads exactly like "those settings were never added".

`UpdatePageHint()` turns the sidebar hint into that affordance - it flips to
"Scroll for more settings" whenever the current page is taller than the client area,
and is called from `SelectPage` and `Gui_Size`, the two things that can change the
answer. The default window height is 700 (was 560), so most pages now fit outright.

**Add a settings group as a PAGE, not as more rows.** The nav list at the top of
`BuildWin` feeds `Pages`, `NavItems` and `CreatePage` declaratively; appending six
rows to the already-full General page is what buried the clock settings in the
first place.

## Packaging

Two independent installers that must be kept in sync: `Install.ps1` (6 steps) and `build\Setup.cs` (5 steps, WinForms). They already diverge — `Setup.cs` `StopRunning()` kills *every* process named `AutoHotkey*`, while `Install.ps1` filters by command line matching `*WindowTweaks.ahk*`. Change install behaviour in both.

`build\Setup.cs` is compiled by the `csc.exe` that ships with the .NET Framework, i.e. a **C# 5 compiler**: no string interpolation, no expression-bodied members, no null-conditional. Keep it plain (the constraint is stated at `Setup.cs:6-8`).

`build\obj\` is a **generated staging directory** — `Build-Installer.ps1` wipes and repopulates it on every build, flattening `scripts\X.ps1` → `scripts_X.ps1` because manifest resource names cannot contain a path separator (`Setup.cs` reverses it with `Replace("_", "\\")`, so no payload filename may contain an underscore). It is gitignored. **Never edit anything under `build\obj\` — edit `src\`, `docs\`, or `scripts\`.**

**The `.ahk` payload is discovered, not listed — and two rules keep that working.** Both installers used to enumerate the eight `.ahk` files by name, which meant a new module was a *load-time* failure of the installed copy that was invisible during development, because running from `src\` finds the file regardless. `Install.ps1` and `Build-Installer.ps1` now both glob `src\*.ahk` excluding `test_*`. Therefore:

- **No module filename may contain an underscore.** `Setup.cs:335` unflattens `_` to `\`, so `Window_Commands.ahk` extracts as `Window\Commands.ahk` and the app fails to load on end-user machines and nowhere else. `Build-Installer.ps1` now throws at build time if you try.
- **The split stays flat in `src\`** — no `src\features\`, no `src\ui\`. Module names carry the grouping instead. The installers copy flat and `#Include` resolves against the entry file's own directory.
- `test_*.ahk` are standalone harnesses and are deliberately excluded from both.

The output exe is unsigned; SmartScreen will warn.

## Editing the AutoHotkey source

Three traps, all of which have cost real debugging time:

- **AHK identifiers are case-insensitive.** A variable named `oR` collides with the `or` keyword; `SUB` collides with the `Sub()` GUI helper. Both fail with confusing errors far from the cause. Hence `oLeft/oTop/oRight/oBottom` and `cSub`.
- **`Log` is a built-in** (logarithm). Never use it as a variable name.
- **Keep `.ahk` files pure ASCII, no BOM.** AutoHotkey reads a BOM-less file in the system codepage, so smart quotes and dashes become mojibake in the UI on other machines. Four of the five files are clean; `WindowTweaks.ahk` retains 17 non-ASCII lines that are *functional* — the emoji sidebar labels (which double as the `Pages` map keys), the OSD speaker/mic glyphs, and the localized Picture-in-Picture title regex. Do not "fix" those without changing the UI and the PiP exclusion on purpose. Everything else, including default values written into `settings.ini`, stays ASCII.
- **A Gui object's lifetime must cover its animation.** Pass the Gui object into the animation closure, not just its HWND, and finish with `Destroy()` — never `WinClose`, which only posts `WM_CLOSE` and leaves the object alive. `ShowSeamFlash` creates one of these on every single snap, so a leak here grows all session.
- **Collect-then-delete when removing entries from a Map you are iterating.** Deleting the current item shifts the remainder under the enumerator index and silently skips the next one. `MC_Expire()` and `BreathingAnimatorStep()` show the pattern; `.Clone()` is the alternative.
- **Guard long-running hotkey loops with `static busy`.** `#MaxThreadsPerHotkey 2` lets a second press interrupt the first, and two loops driving the same window from different origin snapshots fight each other.

**No offline syntax check exists** — AHK 2.0 has no `/validate` (that is 2.1+). To parse-check the whole file without running it, copy `src\*.ahk` somewhere, prepend `ExitApp` to a copy of `WindowTweaks.ahk`, and run it with `/ErrorStdOut`: AHK parses the entire script before executing anything, so a load-time error is reported and `ExitApp` stops it before a single hook, timer or tray icon is installed. Exit code 0 and no output means it parses. **`scripts\Check-Split.ps1` does exactly this as its first check** — run that instead of doing it by hand, and get the six structural checks with it.

Two traps that cost time while building that script, both about *empty* output rather than wrong output:

- **`Get-Content -Raw` on an empty file emits `AutomationNull`** — nothing at all, not `$null` — so `[string](...)` still yields `$null` and `.Trim()` throws. Only string interpolation, `"$(Get-Content ...)"`, reliably turns "no output" into `""`. Empty output is the *success* case for the parse check, so this failed exactly when everything was fine.
- **Killing the app with `Stop-Process -Force` skips `OnExit(Bye)`**, and `Bye()` is what calls `WriteSettings()`. Settings are written by a 700 ms debounced one-shot that a fresh run never triggers, so a force-killed instance wrote a 4-line `settings.ini` instead of 131. Close it with `taskkill` (no `/F`), which posts `WM_CLOSE` and lets AHK exit normally. Anything that needs the app's persisted state must let it exit gracefully.

Conventions: section banners `; ====== Name ======`; predicates named `Is*`; tuning constants SCREAMING_SNAKE, mutable feature flags PascalCase; bare `try { }` with no catch as "best effort, never crash", with validation done by clamping afterwards. Comments explain *why* — almost every one records a measured OS behaviour or a bug that has actually been hit.

### Defensive Programming & Quality Guidelines
When adding new features or modifying the code, AI agents must strictly adhere to the following principles to prevent edge-case bugs:
1. **Defensive Code**: Always anticipate sudden window closures, missing HWNDs, and empty Maps/Arrays. Rely heavily on `try / catch`, `Map.Has()`, and `DllCall("IsWindow", "ptr", hwnd)` checks before interacting with windows.
2. **Simple and Robust Logic**: Avoid complex mathematical animations or heavy `Loop`s that can cause instability. Prioritize readable, highly stable code over overly complicated transitions.
3. **Non-Destructive Integration**: New features must be written in an isolated, modular way. Ensure minimal interference with the core architecture and existing hooks.

## Constraints

- **AutoHotkey v2 only.** v1 cannot run this. Tested against 2.0.26.
- Windows 11, developed and tested on 25H2 build 26200. All taskbar findings are build-specific; `docs\TASKBAR-AND-INTERNALS.md` documents four dead ends (`TaskbarSi`, `TaskbarSmallIcons`, two feature flags) so nobody retries them.
- Hotkeys are inert against elevated windows unless the app itself is elevated.
- **Windows' own Snap Assist wins at screen edges, by design** — the app skips windows Windows has maximised. Judge snapping by **window-to-window** magnetism, not screen edges.
- `DragFullWindows=1` is a hard functional dependency, not cosmetic: with it off Windows drags a hollow outline, the window rect does not move until release, so `SampleVelocityStep` measures zero on every frame and drag parallax, the ice glide and velocity-based snapping all silently do nothing. **`CheckDragFullWindows()` now enables it at boot** rather than only warning — a persisted, system-wide `SPI_SETDRAGFULLWINDOWS` with `SPIF_UPDATEINIFILE | SPIF_SENDCHANGE`, logged and notified, re-read afterwards to confirm it took, and deliberately **not** reverted by `Bye()`. It only runs when parallax or glide is on.
- **Title-bar drags cannot be automated.** Injected clicks don't engage the window's move loop.

## Docs

`docs\GUIDE.md` (user-facing), `docs\HOTKEYS.md`, `docs\ANIMATIONS.md` (which Windows settings the glide needs and why), `docs\WINDOWS-TUNING.md` (a worked example from one machine — the reasoning transfers, the readings don't), `docs\TASKBAR-AND-INTERNALS.md` (the measured taskbar research and the snapping design — the taskbar-height engine it describes has been removed, so read the first half as history and the snapping half as current).

`docs\MODULARIZATION.md` is the live plan for splitting `WindowTweaks.ahk` — phase order, module boundaries, the `FEATURE_SPEC` / `TEARDOWN_SPEC` designs, and the AHK v2 traps the split hits. It is a working document, not user-facing, and is **not** shipped by the installer. Keep it current as phases land.

**`docs\HOTKEYS.md` is the single source of truth for key bindings.** It is the only document that was updated for the `Ctrl+Alt` / `Shift+Alt` migration in commit `3dadac4`. When a hotkey changes, change it there and in the `; ====== Hotkeys ======` block, and make every other document defer rather than re-listing — three near-identical copies of the feature list already exist across `README.md`, this file and `docs\GUIDE.md`, and they drift.

Two strays: `docs\FUTURE-ANIMATIONS.md` is a roadmap written mostly in Azerbaijani whose contents have largely shipped, and `docs\claude.md` is a one-line note (lowercase filename, distinct from this file on a case-sensitive host).

**Linux port docs** live under `linux\docs\` and are governed by `linux\CLAUDE.md`: `IMPLEMENTATION-AUDIT.md` (what actually exists — read first), `ARCHITECTURE.md`, `FEATURE-MATRIX.md`, `WAYLAND-LIMITATIONS.md`, `INSTALLATION.md`. None of them are shipped by the Windows installer, whose payload is the five documents hardcoded in `Install.ps1` and `build\Build-Installer.ps1`.
