# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 11 tray utility written in **AutoHotkey v2** (magnetic window snapping, inertial "ice glide", window animations, ~40 power-user tweaks), plus a reversible HKCU tuning pass. Shipped two ways: a PowerShell installer and a single-file setup `.exe` compiled from C#.

**There is no taskbar-height engine any more.** `TaskbarCore.ahk`, the `TB_*` globals, `TB_HEIGHTS`, `IsHeight()` and the `Win+Alt+Up/Down/0` hotkeys were removed. What remains taskbar-related is Smart Auto-Hide (`SHAppBarMessage`, `[taskbar] smart`) and taskbar volume scroll. `docs\TASKBAR-AND-INTERNALS.md` keeps the measured findings from that work because the Win32 research is still valuable — but treat it as history, not as a description of the code.

## Features and hotkeys

**Win + Ctrl** drives everything. Hotkeys are declared in one block (`src/WindowTweaks.ahk`, search `=== Hotkeys ===`) and each one delegates to a named function that the tray menu binds to as well — change behaviour in the function, never in the hotkey line, or the two drift apart.

| Hotkey | Action | Entry point |
|---|---|---|
| `Win+Ctrl+W` | Open the settings window | `ShowWin()` |
| `Win+Ctrl+S` | Magnetic snapping on / off | `ToggleSnap()` |
| `Win+Ctrl+M` | Position memory on / off | `ToggleMemory()` |
| `Win+Ctrl+E` | Breathing windows on / off | `ToggleBreathing()` |
| `Win+Ctrl+F` | Focus / cinema mode | `ToggleFocusMode()` |
| `Win+Ctrl+T` | Always-on-top the active window | inline block |
| `Win+Ctrl+B` | Always-on-bottom (desktop widget) | `ToggleAlwaysOnBottom()` |
| `Win+Ctrl+G` | Proximity ghost window | `ToggleGhostMode()` |
| `Win+Ctrl+P` | Live PiP thumbnail | `TogglePiP()` |
| `Win+Ctrl+R` | Roll up / unroll | `ToggleRollUp()` |
| `Win+Ctrl+H` | Minimize to tray | `HideToTray()` |
| `Win+Ctrl+Esc` | Boss key | `ToggleBossKey()` |
| `Win+Ctrl+Wheel` | Transparency of the active window | `ChangeTransparency()` |
| `Alt+F4` | Close with the gravity-drop animation | `GravityClose()` |
| `(Tray Menu)` | Restart / Exit | `Reload()` / `ExitApp()` |

Conditional on their feature flag: `Alt+LButton` / `Alt+RButton` (alt-drag), `*MButton` (grab-pan / roll-up / close), wheel and middle-click over the taskbar, `Ctrl+G` in file dialogs, `Ctrl+Win+V`, `CapsLock`, `Space` in Explorer, double-tap `LAlt` (mic), double-tap `Ctrl` (spotlight).

Every toggle fires `Notify()` → `TrayTip`, so state changes are always visible. The one exception is `ChangeTransparency`, which debounces its notification through `FlushTransNotify` — a wheel gesture is many hotkey firings and used to produce one toast per notch.

### The four core features and where their state lives

| Feature | Behaviour | INI section / keys | Globals |
|---|---|---|---|
| **Magnetic snapping** | On drag-release, each axis independently snaps to a screen edge, a monitor work-area edge, or another window's edge. Corners pull harder: once one axis grabs, the other is retried with `CORNER_BOOST` × the reach | `[snap]` `enabled`, `flash`, `distance`, `cornerBoost`, `neighbour` | `SnapEnabled`, `SNAP_DISTANCE` (30), `CORNER_BOOST` (2.2), `NEIGHBOUR_PROX` (90) |
| **Ice glide** | Release mid-drag and the window keeps sliding on a quintic ease-out, then snaps to whatever it drifts near. Never leaves the screen | `[glide]` `enabled`, `throw`, `ms` | `GlideEnabled`, `GLIDE_THROW` (0.9), `GLIDE_MS` (650), `GLIDE_MAX` (500) |
| **Always on top** | Toggles `WS_EX_TOPMOST` on the active window. Hotkey only — no persisted setting, and it self-excludes by PID so it can't pin its own GUI | — | — |
| **Position memory** | Each app reopens at its last size/position, keyed on `exe_class`. Dialogs, owned windows, `WS_EX_TOOLWINDOW`, anything without `WS_THICKFRAME`, and Picture-in-Picture (PiP) windows are excluded | `[memory]` `enabled` | `RestoreEnabled`, `POS_FILE` |

Everything else lives under `[memory]` too (the section name is historical — it is now the general feature-flag bucket), plus `[corners]` for hot corners, `[taskbar] smart`, and `[snippets]` for the text expander.

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
- **Breathing Backgrounds**: Inactive background windows slowly fade to 70% opacity after 6 seconds of inactivity, waking up instantly when hovered.
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

**Enumerated settings must be validated by membership, not range.** Every setting that feeds a DropDownList (`OpenAnim`, `SmartCapsAction`, the four `HotCorner*`, `EP_Style`, `EP_IconSize`) goes through `IniPick(section, key, allowedList, default)` in `LoadSettings`, and the control is built from the *same* list with `IndexOf()` for its `Choose<n>`. The lists live in one place — `OPEN_ANIMS`, `CAPS_ACTIONS`, `CORNER_ACTIONS`, `EP_STYLES`, `EP_ICON_SIZES` near the top of the file. Two things break if you skip this: `DropDownList.Choose("not in the list")` throws *inside* `BuildWin`, which leaves `Win+Ctrl+W` permanently dead after one hand-edited `settings.ini`; and a value the dropdown cannot display leaves the GUI showing one thing while the engine uses another. Range-check the numeric settings; list-check these.

Tray menu labels embed their hotkey after a literal tab — `"Magnetic snap\tWin+Ctrl+S"` — and that **entire string is the lookup key** used by `SyncTray()` to set tick marks. Renaming a label without updating both places silently breaks the checkmarks, with no error.

### Windows shortcuts this claims

AutoHotkey hooks the keyboard ahead of Windows, so while the program runs, `Win+Ctrl+S` no longer opens Speech Recognition. The rest are unclaimed by Windows. Deliberately **not** touched: `Win+Ctrl+←/→` (virtual desktops), `Win+↑/↓`, `Win+Tab`, `Win+D`, `Win+E`.

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
```

## Architecture

**One AutoHotkey v2 process.** `src\WindowTweaks.ahk` is the sole entry point; the four `#Include` lines at the top pull the rest in at load time. No IPC, no second process, nothing launches anything else. `#SingleInstance Force` is the only cross-instance coordination.

| File | Role |
|---|---|
| `src\WindowTweaks.ahk` | App shell: settings, tray, hand-rolled sidebar-nav GUI, hotkeys, drag pipeline, position memory, and every feature |
| `src\SnapCore.ahk` | Pure geometry + window predicates. No side effects |
| `src\RenderCore.ahk` | The only place allowed to touch a window's position, alpha, region or z-order |
| `src\AnimationScheduler.ahk` | One 16 ms timer multiplexing every animation |
| `src\MediaCore.ahk` | WASAPI "is this window playing audio/video?", so playing windows are never faded |

**The include contract.** All four included files hold *function definitions and global initialisers only* — stated in their own headers. Adding top-level executable statements to any of them silently breaks the script. `MediaCore.ahk` is additionally kept free of `QPC()`, `RegisterAnimation()` and `WriteLog()` calls so a test harness can include it alone; every function that needs the clock takes `now` as a parameter.

**Coupling is by shared globals, not parameters.** Functions open with a bare `global` or a long global list. This is deliberate. Note the AHK v2 rule it relies on: a function may *read* a global without declaring it, but must declare it to *assign*. An assignment to an undeclared name silently creates a local instead — which is why `ApplyUi`, `LoadSettings` and `SaveSettings` use a bare `global`, and why any name assigned in those functions becomes a global (hence the `ui*` / `ep*` prefixes on their scratch variables).

### The render pipeline — read this before touching any visual feature

Two files, one rule each, and they are not optional.

**`RenderCore.ahk`** owns all output. Nothing outside it may call `WinSetTransparent`, `SetWindowPos`, `WinMove`, `WinSetRegion` or `WinSetExStyle`. Features *queue* desired state:

```
RS_SetAlpha(hwnd, 180, RS_PRI_AMBIENT)   ; or "Off"
RS_SetPos(hwnd, x, y, w := -1, h := -1, pri)  ; -1 w/h = SWP_NOSIZE
RS_SetRegion(hwnd, regionStr, pri)       ; "" clears
RS_SetZOrder(hwnd, insertAfter, flags, pri)
```

Priorities (`RS_PRI_AMBIENT` 10 < `RS_PRI_ANIM` 20 < `RS_PRI_DRAG` 30 < `RS_PRI_USER` 40) arbitrate *within one flush*: a lower-priority write is dropped, a higher one overwrites. Queued entries are deleted as they are applied, so the pending Maps only ever hold outstanding work — that is what bounds their size and what makes arbitration per-flush with no reset pass.

**Who flushes matters, and getting it wrong is silent.**

- A **per-frame animator** registered with `RegisterAnimation()` only queues. The scheduler calls `RS_Flush()` once per frame for it.
- A **one-shot producer** — a hotkey, a monitor timer, anything that queues and returns — **must call `RS_Commit()` itself**.

The scheduler stops its timer the moment nothing is animating, so a queued change with nobody to flush it is simply never applied. This is not hypothetical: it is what silently killed snapping-without-glide, the transparency wheel, breathing restore and un-ghosting, and what left brand-new windows sitting at alpha 0 — invisible, focused and clickable. If you add a visual feature, decide which of the two kinds it is.

Deliberately **not** cached: window positions. A cache is only valid when the cache owns the state, and the user dragging a title bar changes a window's position behind this pipeline's back. Caching last-requested positions made a second snap to the same edge a no-op. Alpha and region *are* cached (`RS_LastAlpha` / `RS_LastRegion`) because re-applying them is individually expensive — `WinSetTransparent` adds/removes `WS_EX_LAYERED` and `WinSetRegion` rebuilds a GDI region — and both caches are pruned by `RS_RemoveHwnd()` and the periodic `RS_SweepDead()`.

**Call `RS_RemoveHwnd(hwnd)` whenever a window we touched is destroyed.** For foreign windows the shell hook does it. For our own overlay GUIs (seam flash, dimmers, OSDs, focus layers, active border, gravity animation) nothing does, because `WS_EX_TOOLWINDOW` / `NoActivate` windows raise no shell destroy notification — so every destroy site does it explicitly, and `RS_SweepDead()` is the backstop.

**`AnimationScheduler.ahk`** runs `RenderFrame` every 16 ms: call every registered callback (produce), then `RS_Flush()` exactly once (render). A callback returns `true` to stay registered, `false` to be removed. The produce loop iterates a **snapshot of the keys**, not the Map — 11 other timers, every hotkey and the `SetWinEventHook` callback can interrupt it between lines and several of them call `RegisterAnimation`/`CancelAnimation`; mutating a Map under a live `for` enumerator shifts items and silently skips or repeats animations. `RS_Flush()` is likewise re-entrancy-guarded, because timers call it directly while the frame loop may be inside it.

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

**Never derive a duration from a frame count.** `ms := 12 * 16` was silently a
frame-count assumption; those are all plain millisecond values now.

**Two animations must never drive the same property of the same window at the same
priority.** `RS_*` arbitration is per-flush and ties are broken by Map order, and
AHK enumerates a Map **sorted by key** — verified empirically. So `Bounce_<hwnd>`
was produced before `Glide_<hwnd>` and the glide overwrote every bounce frame:
"Bouncy Snapping" never put a pixel on screen unless ice glide was off. Anything
that should happen *when a window lands* has to be scheduled for after the glide,
which is what `BounceOnLanding` and `FlashSeams` do. The same applied to the seam
flash, which used to hang in empty space at the destination for up to 650 ms
before the window arrived.

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

There is no single "the only timer" any more. `RenderFrame` at 16 ms while animating; then per-feature monitors, each started/stopped by its own `Sync*` function so a feature nobody enabled costs nothing: cursor wrap 20 ms, ghost proximity 25 ms, hot corners / active border / focus 50 ms, PiP / Quick Look 100 ms, breathing / dimmer / smart taskbar 200 ms, MediaCore 250 ms. Plus one-shot `SetTimer(..., -ms)` calls for deferred work.

**Drag pipeline**: `SetWinEventHook` on `EVENT_SYSTEM_MOVESIZESTART`/`END` → `SampleVelocityStep` on the frame loop (EMA-smoothed velocity, parallax alpha) → `FinishDrag` deferred 50 ms with the start rect captured in the closure (it enumerates windows, so it must not run inside the hook) → `SnapWindow` → `Glide` → `VerifySnap` scheduled for after the glide lands. A `~LButton` hotkey was rejected because it makes AHK install a low-level mouse hook that wakes on every mouse move — measured at ~1.6% of a core while idle. MOVESIZEEND also fires *after* the OS modal move loop, which is the only safe moment to reposition.

The hook callback is **not** created with `"F"` (fast) mode. Fast mode runs on top of whatever script thread the event interrupted and must be trivial; this one queries the window, registers an animation and arms a timer.

`Glide` is elapsed-time driven (not step-counted), quintic ease-out `1-(1-t)**5`, and returns its duration in ms so the caller can schedule verification after it lands. `timeBeginPeriod(1)`/`timeEndPeriod(1)` are held by the scheduler for as long as anything is animating.

**Nothing in the drag or snap path may block.** `SnapWindow` used to spin twice for 40 ms in a busy-wait that never pumped messages, which froze every timer in the process — including the frame loop that had just been armed to run the glide it had started. Verification is a one-shot timer now, and it declines to act while a `Glide_<hwnd>` animation is still registered. Use `Sleep` (which yields) if you need to wait; there is no `PreciseSleep` any more.

### Win32 gotchas the code depends on

- **Two coordinate spaces.** Snapping measures with `DWMWA_EXTENDED_FRAME_BOUNDS` (attr 9); `WinGetPos` differs by the invisible DWM border. `GetRects()` in `SnapCore.ahk` returns *both*, and `SnapWindow` converts back (`destX := winX + (newL - L)`). Ignore this and every snap lands ~7px off.
- **`DWMWA_CLOAKED` (attr 14)** filters UWP-suspended and other-virtual-desktop windows; `WS_VISIBLE` alone does not catch them.
- **Position memory is keyed on exe + window class**, and excludes owned/tool/non-resizable and Picture-in-Picture windows — every Chrome popup shares a class with the main window.
- **New windows are detected via `RegisterShellHookWindow`, not polling — and that registration does not survive an Explorer restart.** `TaskbarCreated` is broadcast when the shell comes back; handling it and re-registering is the only thing keeping position memory, the open animations, focus pulse, breathing seeding, fly-to-mouse minimize and per-window cleanup alive after an Explorer crash (or after this app's own "Restart Explorer" button).
- **Never make a foreign window layered speculatively.** `WinSetTransparent` on a new window forces `WS_EX_LAYERED`; on a GPU-composited or full-screen window that costs a redirection surface and can break exclusive full-screen presentation. `WillAnimateOpen()` is the single eligibility test, applied *before* hiding a new window rather than after.
- **Never `SendMessage` to a foreign window without a timeout.** A window whose thread is not pumping messages ("Not Responding") never returns, freezing this whole process — every timer and every hotkey — with it. Use `SendMessageTimeout` with `SMTO_ABORTIFHUNG` (see `AskWindowIcon()` and the `WM_NCHITTEST` probe in the `*MButton` handler).
- **A timer callback that throws pops an error dialog and kills that timer** — the feature is then dead for the rest of the session. Any window query in a monitor must be inside `try` with an explicit fallback; `IsMouseOverTaskbar()` is the pattern to copy.
- **`SetParent` across processes** (always-on-bottom) is not really supported by Win32 and is not undone by anything except `RestoreFromBottom()`. A window left parented to `WorkerW` cannot be alt-tabbed to, cannot be moved normally, and dies with the next Explorer restart — so exit-time restoration is mandatory, not polish.

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
- **Keep `.ahk` files pure ASCII, no BOM.** AutoHotkey reads a BOM-less file in the system codepage, so smart quotes and dashes become mojibake in the UI on other machines. Four of the five files are clean; `WindowTweaks.ahk` retains 17 non-ASCII lines that are *functional* — the emoji sidebar labels (which double as the `Pages` map keys), the OSD speaker/mic glyphs, and the localized Picture-in-Picture title regex. Do not "fix" those without changing the UI and the PiP exclusion on purpose. Everything else, including default values written into `settings.ini`, stays ASCII.
- **A Gui object's lifetime must cover its animation.** Pass the Gui object into the animation closure, not just its HWND, and finish with `Destroy()` — never `WinClose`, which only posts `WM_CLOSE` and leaves the object alive. `ShowSeamFlash` creates one of these on every single snap, so a leak here grows all session.
- **Collect-then-delete when removing entries from a Map you are iterating.** Deleting the current item shifts the remainder under the enumerator index and silently skips the next one. `MC_Expire()` and `BreathingAnimatorStep()` show the pattern; `.Clone()` is the alternative.
- **Guard long-running hotkey loops with `static busy`.** `#MaxThreadsPerHotkey 2` lets a second press interrupt the first, and two loops driving the same window from different origin snapshots fight each other.

**No offline syntax check exists** — AHK 2.0 has no `/validate` (that is 2.1+). To parse-check the whole file without running it, copy `src\*.ahk` somewhere, prepend `ExitApp` to a copy of `WindowTweaks.ahk`, and run it with `/ErrorStdOut`: AHK parses the entire script before executing anything, so a load-time error is reported and `ExitApp` stops it before a single hook, timer or tray icon is installed. Exit code 0 and no output means it parses.

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
- `DragFullWindows=1` is a hard functional dependency, not cosmetic: with it off Windows drags a hollow outline and the glide is invisible.
- **Title-bar drags cannot be automated.** Injected clicks don't engage the window's move loop.

## Docs

`docs\GUIDE.md` (user-facing), `docs\HOTKEYS.md`, `docs\ANIMATIONS.md` (which Windows settings the glide needs and why), `docs\WINDOWS-TUNING.md` (a worked example from one machine — the reasoning transfers, the readings don't), `docs\TASKBAR-AND-INTERNALS.md` (the measured taskbar research and the snapping design — the taskbar-height engine it describes has been removed, so read the first half as history and the snapping half as current).
