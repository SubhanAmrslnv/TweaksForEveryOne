# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 11 tray utility written in **AutoHotkey v2** (magnetic window snapping, inertial "ice glide", always-on-top, position memory, taskbar height), plus a reversible HKCU tuning pass. Shipped two ways: a PowerShell installer and a single-file setup `.exe` compiled from C#.

## Features and hotkeys

**Win + Ctrl** drives the window tweaks; **Win + Alt** drives the taskbar. Hotkeys are declared at `src/WindowTweaks.ahk:576-614` and each one delegates to a named function that the tray menu binds to as well — change behaviour in the function, never in the hotkey line, or the two drift apart.

| Hotkey | Action | Entry point |
|---|---|---|
| `Win+Ctrl+W` | Open the settings / tools window | `ShowWin()` |
| `Win+Ctrl+T` | Pin / unpin the active window always-on-top | inline block, `:598` |
| `Win+Ctrl+S` | Magnetic snapping on / off | `ToggleSnap()` |
| `Win+Ctrl+M` | Position memory on / off | `ToggleMemory()` |
| `Win+Alt+Up` | Taskbar one step taller | `StepHeight(+1)` |
| `Win+Alt+Down` | Taskbar one step shorter | `StepHeight(-1)` |
| `Win+Alt+0` | Restore the original taskbar | `RestoreTaskbar()` |
| `(Tray Menu)` | Restart the application | `Reload()` |

Every toggle fires `Notify()` → `TrayTip`, so state changes are always visible.

### The five features and where their state lives

| Feature | Behaviour | INI section / keys | Globals |
|---|---|---|---|
| **Magnetic snapping** | On drag-release, each axis independently snaps to a screen edge, a monitor work-area edge, or another window's edge. Corners pull harder: once one axis grabs, the other is retried with `CORNER_BOOST` × the reach | `[snap]` `enabled`, `distance`, `cornerBoost`, `neighbour` | `SnapEnabled`, `SNAP_DISTANCE` (30), `CORNER_BOOST` (2.2), `NEIGHBOUR_PROX` (90) |
| **Ice glide** | Release mid-drag and the window keeps sliding on a quintic ease-out, then snaps to whatever it drifts near. Never leaves the screen | `[glide]` `enabled`, `throw`, `ms` | `GlideEnabled`, `GLIDE_THROW` (0.9), `GLIDE_MS` (650), `GLIDE_MAX` (500) |
| **Always on top** | Toggles `WS_EX_TOPMOST` on the active window. Hotkey only — no persisted setting, and it self-excludes by PID so it can't pin its own GUI | — | — |
| **Position memory** | Each app reopens at its last size/position, keyed on `exe_class`. Dialogs, owned windows, `WS_EX_TOOLWINDOW`, anything without `WS_THICKFRAME`, and Picture-in-Picture (PiP) windows are excluded | `[memory]` `enabled` | `RestoreEnabled`, `POS_FILE` |
| **Taskbar height** | Resizes taskbar windows and re-places their XAML island children flush to the new bottom edge | `[taskbar]` `height`, `allowClip`, `cropPrimary` | `TB_Height` (32), `TB_AllowClip`, `TB_CropPrimary` |

Taskbar steps are `TB_HEIGHTS := [24, 28, 32, 36, 40, 44, 48]` (`src/TaskbarCore.ahk:5`), 48 being native. Below the measured content height it clamps unless **Allow clipping** is ticked, and the notification reports the height actually used — the primary bar may refuse outright.

### The Full Feature Suite (40+ Tweaks & Animations)

**15 Power-User Tweaks (Newly Added):**
- **Smart Auto-Hide Taskbar**: Only hides the taskbar when windows maximize or touch the bottom edge.
- **macOS "Quick Look"**: Press Space on any file in Explorer to instantly preview it.
- **Multi-Monitor Focus Dimmer**: Dims inactive monitors by 50% to reduce eye strain.
- **macOS "Hot Corners"**: Throw your mouse to screen corners to trigger actions (e.g. Hide windows, Task View).
- **Premium Volume OSD**: A sleek, blurred macOS-style volume indicator when scrolling the taskbar.
- **Live Window PiP**: `Win+Ctrl+P` creates a live, always-on-top thumbnail of any background window.
- **Universal Grab & Pan**: Hold Middle-Click to pan/scroll any window (like the Photoshop Hand Tool).
- **Global Mic Kill-Switch**: Double-tap `Alt` to instantly mute/unmute your microphone system-wide.
- **Infinite Cursor Wrap**: Teleport your cursor across screen edges for seamless multi-monitor navigation.
- **Quick Spotlight Launcher**: Double-tap `Ctrl` for a minimalist, lightning-fast search and launch bar.
- **Smart Active Border**: Draws a sleek, accent-colored border around the currently active window.
- **Always on Bottom**: `Win+Ctrl+B` pins any window permanently to your desktop background as a widget.
- **Global Text Expander**: Type `@@mail`, `@@date`, etc., to instantly expand snippets anywhere.
- **Middle-Click to Close**: Middle-click any window's title bar to instantly close it.
- **Proximity Ghost Window**: `Win+Ctrl+G` makes a window 80% transparent; it fades in and becomes clickable only when your mouse gets close.

**Performance & OS Tuning:**
- **Zero-delay Menus (MenuShowDelay)**: Windows menus open instantly (0-50ms) just like macOS, eliminating the artificial 400ms delay.
- **Snappy Taskbar Previews (MouseHoverTime)**: Taskbar thumbnails appear in 100ms instead of 400ms for a much more responsive feel.
- **Smooth Scrolling**: Silky smooth mouse wheel scrolling interpolation across all apps.

**Premium Window Animations:**
- **Fade In / Ease-Out**: Cinematic fade transitions for modes like Focus Mode instead of abrupt cuts.
- **Custom Text Caret**: A thicker, smoother blinking text cursor (caret) to reduce eye strain and look modern.
- **Bouncy Snapping**: Windows slightly squish and bounce back with realistic physics when hitting screen edges or other windows.
- **Gravity Drop Close**: When closing a window, it collapses into a bitmap and falls with gravity (or gets sucked into a black hole).
- **Breathing Backgrounds**: Inactive background windows slowly fade to 70% opacity after 5 seconds of inactivity, waking up instantly when hovered.
- **Focus Pulse**: Switching to a window via Alt+Tab makes it pulse (expand by 2-3% and bounce back) to immediately draw your attention.
- **Ghost Slide-In**: New apps slide up from 30px below while fading in, similar to modern smartphone app launches.
- **Parallax Dragging**: Windows become transparent based on how fast you drag them, fading back to solid when you stop.
- **Magnetic Seam Flash**: A brief neon flash effect appears exactly on the seam when two windows magnetically snap together.
- **Theater Spotlight**: A soft, circular vignette shadow follows your active window like a stage spotlight, dimming the rest of the screen.
- **Fly-to-Mouse Minimize**: Minimized windows spin and vacuum directly into your mouse cursor instead of dropping to the taskbar.
- **Window Unrolling**: New windows unroll from top to bottom like a window blind in 0.2 seconds.

**Productivity & Window Management:**
- **Transparency Control**: `Win + Ctrl + Wheel` to adjust the opacity of any active window.
- **Cinema / Focus Mode**: `Win + Ctrl + F` to black out the entire background, keeping only the active window visible.
- **Window Shade / Roll-Up**: Middle-click a window to roll it up (collapse to just the title bar), middle-click to restore.
- **Minimize to Tray**: Add a tray icon for any active window to declutter your taskbar.
- **Boss Key**: `Win + Ctrl + Esc` to instantly hide all windows and mute system audio. Press again to restore.
- **Linux-Style Alt-Drag**: Hold `Alt + LeftClick` anywhere on a window to move it, or `Alt + RightClick` anywhere to resize it from the nearest edge.
- **Taskbar Volume Scroll**: Hover over the taskbar and scroll the mouse wheel to adjust volume, or middle-click to mute.
- **Quick Folder Jump**: Press `Ctrl + G` in any File Save/Open dialog to instantly jump to the folder of your most recently active Explorer window.
- **Global Plain-Text Paste**: `Ctrl + Win + V` strips all formatting, colors, and fonts from your clipboard and pastes as pure plain text anywhere.
- **Smart Caps Lock**: Tap CapsLock to send `Escape` (or `Backspace`), hold it for 0.4 seconds to actually toggle CapsLock on/off.

### Two traps in this area

`TB_Height` is validated by **membership, not range** (`IsHeight()`, `:481`). 30 sits inside the range but isn't on the list, and the dropdown would then show 24px while the engine used 30. Range-check the other settings; list-check this one.

Tray menu labels embed their hotkey after a literal tab — `"Magnetic snap\tWin+Ctrl+S"` — and that **entire string is the lookup key** used by `SyncTray()` to set tick marks (`:162-168`). Renaming a label without updating both places silently breaks the checkmarks, with no error.

### Windows shortcuts this claims

AutoHotkey hooks the keyboard ahead of Windows, so while the program runs, `Win+Ctrl+S` no longer opens Speech Recognition. The rest are unclaimed by Windows. Deliberately **not** touched: `Win+Ctrl+←/→` (virtual desktops), `Win+↑/↓`, `Win+Tab`, `Win+D`, `Win+E`.

## Commands

There is **no build system, no test runner, and no CI**. No `.sln`, no `.csproj`, no Pester, no npm/make. Every command below is typed by hand.

```powershell
# Run from source
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" src\WindowTweaks.ahk

# Automated tests - 21 geometry checks, pure functions, touches no windows
cd tests
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" test-snap.ahk   # exits 0 / 1

# Guided live test - requires the app already running; opens an always-on-top
# GUI and judges each drag you perform. Never exits with a code.
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" test-live-manual.ahk

# Build the installer -> build\out\WindowTweaksSetup.exe
.\build\Build-Installer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Installer.ps1   # if policy is Restricted

# Install / uninstall (no admin required anywhere in this project)
.\Install.ps1 [-Silent] [-Tuning] [-NoAutoStart]
.\Uninstall.ps1 [-Silent]

# Windows tuning
.\scripts\Apply-Windows-Tuning.ps1 [-Animations | -Explorer | -All]
.\scripts\Restore-Windows-Tuning.ps1
```

`test-snap.ahk` is all-or-nothing — there is no single-test selector. To isolate one case, comment out the other `Check()` calls. Output goes to stdout via `FileAppend(s "\n", "*")`; the exit code is the signal (`ExitApp(Fail > 0 ? 1 : 0)`).

Re-run `test-snap.ahk` after Windows updates — the geometry assumptions are OS-version sensitive.

## Architecture

**One AutoHotkey v2 process.** `src\WindowTweaks.ahk` is the sole entry point; `#Include SnapCore.ahk` and `#Include TaskbarCore.ahk` (lines 3-4) pull the other two in at compile time. No IPC, no second process, nothing launches anything else. `#SingleInstance Force` is the only cross-instance coordination.

| File | Role |
|---|---|
| `src\WindowTweaks.ahk` | App shell: settings persistence, tray, hand-rolled sidebar-nav GUI (~350 lines), hotkeys, drag pipeline, position memory |
| `src\SnapCore.ahk` | Pure geometry + window predicates. No side effects |
| `src\TaskbarCore.ahk` | Taskbar enumeration and resize. `TB_` prefix = public, `tbc_` = private module state |

**The include contract.** `SnapCore.ahk` and `TaskbarCore.ahk` hold *function definitions only* (plus TaskbarCore's global initializers) — stated in their own headers — so `tests\test-snap.ahk` can `#Include ..\src\SnapCore.ahk` without starting the program. Adding top-level executable statements to either file silently breaks the tests.

**Coupling is by shared globals, not parameters.** `LoadSettings()` in `WindowTweaks.ahk` writes `TB_Height` / `TB_AllowClip` / `TB_CropPrimary` and reads `TB_HEIGHTS`, all of which are defined in `TaskbarCore.ahk`. Functions open with a bare `global` or a long global list. This is deliberate, not accidental.

**Drag pipeline** (`src\WindowTweaks.ahk:588-772`): `SetWinEventHook` on `EVENT_SYSTEM_MOVESIZESTART`/`END` → 16 ms velocity sampler with EMA smoothing → `FinishDrag` deferred 50 ms (it enumerates windows, so it must not run inside the hook) → `SnapWindow` → `Glide`. A `~LButton` hotkey was rejected because it makes AHK install a low-level mouse hook that wakes on every mouse move — measured at ~1.6% of a core while idle. MOVESIZEEND also fires *after* the OS modal move loop, which is the only safe moment to reposition.

`Glide` is elapsed-time driven (not step-counted), quintic ease-out `1-(1-t)**5`, bracketed by `winmm\timeBeginPeriod(1)`/`timeEndPeriod(1)` to make the short sleeps honest. Per-frame movement uses raw `SetWindowPos` with `SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE`, not `WinMove`.

### Win32 gotchas the code depends on

- **Two coordinate spaces.** Snapping measures with `DWMWA_EXTENDED_FRAME_BOUNDS` (attr 9); `WinGetPos` differs by the invisible DWM border. `GetRects()` (`SnapCore.ahk:73`) returns *both*, and `SnapWindow` converts back (`destX := winX + (newL - L)`). Ignore this and every snap lands ~7px off.
- **`DWMWA_CLOAKED` (attr 14)** filters UWP-suspended and other-virtual-desktop windows; `WS_VISIBLE` alone does not catch them.
- **`SetWindowPos` lies on `Shell_TrayWnd`.** The primary taskbar clamps its own size inside `WM_WINDOWPOSCHANGING`, which runs synchronously *inside* `SetWindowPos` — the call returns TRUE and the rect never changes. Always verify by re-reading `GetWindowRect` (`TaskbarCore.ahk:198-206`). Secondary bars have no such handler.
- **`SetWindowRgn` bypasses that clamp** (a region is not a size change), but the shell recomputes the work area from its appbar registration and reverts `SPI_SETWORKAREA` within ~100 ms, leaving a dead strip. This is why "Crop primary" ships off.
- **Position memory is keyed on exe + window class**, and excludes owned/tool/non-resizable and Picture-in-Picture windows — every Chrome popup shares a class with the main window.
- New windows are detected via `RegisterShellHookWindow`, not polling. The only timer is a 3-second taskbar check.

### Runtime files

`settings.ini`, `window-positions.ini`, `snap.log` (+ `.old`, rotated at 256 KB) are written to `A_ScriptDir` — so running from source writes into `src\`, not the installed copy at `%LOCALAPPDATA%\Window Tweaks`. All gitignored. Nothing is written outside the program folder except a Startup `.lnk`; the registry is read-only (`AppsUseLightTheme`) — there is no `Run` key, service, or scheduled task.

## Packaging

Two independent installers that must be kept in sync: `Install.ps1` (6 steps) and `build\Setup.cs` (5 steps, WinForms). They already diverge — `Setup.cs` `StopRunning()` kills *every* process named `AutoHotkey*`, while `Install.ps1` filters by command line matching `*WindowTweaks.ahk*`. Change install behaviour in both.

`build\Setup.cs` is compiled by the `csc.exe` that ships with the .NET Framework, i.e. a **C# 5 compiler**: no string interpolation, no expression-bodied members, no null-conditional. Keep it plain (the constraint is stated at `Setup.cs:6-8`).

`build\obj\` is a **generated staging directory** — `Build-Installer.ps1` wipes and repopulates it on every build, flattening `scripts\X.ps1` → `scripts_X.ps1` because manifest resource names cannot contain a path separator (`Setup.cs` reverses it with `Replace("_", "\\")`, so no payload filename may contain an underscore). It is gitignored. **Never edit anything under `build\obj\` — edit `src\`, `docs\`, or `scripts\`.**

The output exe is unsigned; SmartScreen will warn.

## Editing the AutoHotkey source

Three traps, all of which have cost real debugging time:

- **AHK identifiers are case-insensitive.** A variable named `oR` collides with the `or` keyword; `SUB` collides with the `Sub()` GUI helper. Both fail with confusing errors far from the cause. Hence `oLeft/oTop/oRight/oBottom` and `cSub`.
- **`Log` is a built-in** (logarithm). Never use it as a variable name.
- **Keep `.ahk` files pure ASCII, no BOM.** AutoHotkey reads a BOM-less file in the system codepage, so smart quotes and dashes become mojibake in the UI on other machines.

Conventions: section banners `; ====== Name ======`; predicates named `Is*`; tuning constants SCREAMING_SNAKE, mutable feature flags PascalCase; bare `try { }` with no catch as "best effort, never crash", with validation done by clamping afterwards. Comments explain *why* — almost every one records a measured OS behaviour.

### Defensive Programming & Quality Guidelines
When adding new features or modifying the code, AI agents must strictly adhere to the following principles to prevent edge-case bugs:
1. **Defensive Code**: Always anticipate sudden window closures, missing HWNDs, and empty Maps/Arrays. Rely heavily on `try / catch`, `Map.Has()`, and `DllCall("IsWindow", "ptr", hwnd)` checks before interacting with windows.
2. **Simple and Robust Logic**: Avoid complex mathematical animations or heavy `Loop`s that can cause instability. Prioritize readable, highly stable code over overly complicated transitions.
3. **Non-Destructive Integration**: New features must be written in an isolated, modular way. Ensure minimal interference with the core architecture and existing hooks.

## Constraints

- **AutoHotkey v2 only.** v1 cannot run this.
- Windows 11, developed and tested on 25H2 build 26200. All taskbar findings are build-specific; `docs\TASKBAR-AND-INTERNALS.md` documents four dead ends (`TaskbarSi`, `TaskbarSmallIcons`, two feature flags) so nobody retries them.
- Hotkeys are inert against elevated windows unless the app itself is elevated.
- **Windows' own Snap Assist wins at screen edges, by design** — the app skips windows Windows has maximised. Judge snapping by **window-to-window** magnetism, not screen edges.
- `DragFullWindows=1` is a hard functional dependency, not cosmetic: with it off Windows drags a hollow outline and the glide is invisible.
- **Title-bar drags cannot be automated.** Injected clicks don't engage the window's move loop, so an "automated" drag test either passes vacuously or exercises a code path real drags never take. That is why `test-live-manual.ahk` is manual.
- `tests\diagnostics\*` are one-off investigation probes, not a regression suite. `probe2.ahk` and `probe3.ahk` mutate the live taskbar and work area and rely on their own restore phase — not safe to batch-run.

## Docs

`docs\GUIDE.md` (user-facing), `docs\HOTKEYS.md`, `docs\ANIMATIONS.md` (which Windows settings the glide needs and why), `docs\WINDOWS-TUNING.md` (a worked example from one machine — the reasoning transfers, the readings don't), `docs\TASKBAR-AND-INTERNALS.md` (the measured taskbar findings and the snapping design; read this before touching `TaskbarCore.ahk`).
