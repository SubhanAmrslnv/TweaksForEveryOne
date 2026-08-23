# Window Tweaks — guide

A small program that makes windows behave better. It sits in the tray, uses about
18 MB, and does nothing to your system outside its own folder.

**Press `Shift + Alt + W` to open settings.**

---

## Install

Double-click **`Install.bat`** and follow it. It will:

1. install AutoHotkey v2 if you don't have it (via winget),
2. copy the program to `%LOCALAPPDATA%\Window Tweaks`,
3. make Start Menu, Desktop and Startup shortcuts,
4. check the one Windows setting the program needs,
5. start it.

No admin rights. No registry keys. Nothing outside your user profile.

To remove it: run **`Uninstall.ps1`**.

---

## The Core Features

### 15 Power-User Tweaks (Newly Added)
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
- **Smart Active Border**: Draws a sleek, accent-colored border around the currently active window.
- **Always on Bottom**: `Shift+Alt+B` pins any window permanently to your desktop background as a widget.
- **Global Text Expander**: Type `@@mail`, `@@date`, etc., to instantly expand snippets anywhere.
- **Middle-Click to Close**: Middle-click any window's title bar to instantly close it.
- **Proximity Ghost Window**: `Shift+Alt+G` makes a window 80% transparent; it fades in and becomes clickable only when your mouse gets close.

### 1. Magnetic snapping

Drag a window and let go near a screen edge, a corner, or **another window's
edge** — it jumps flush against it.

The two axes work independently, so a window can stick to a screen edge sideways
and to another window vertically in the same movement.

**Corners pull harder.** Once one edge grabs, the other direction is retried with
a much larger reach, so a window already hugging the left edge drops into the
top-left corner from far further away than a normal edge would catch it.

> Windows already snaps to *screen edges* by itself. The genuinely new thing here
> is windows sticking **to each other** — that's what to try when judging it.

How close it has to be before it grabs depends on how fast you let go: place a
window slowly and the reach shrinks, so you can park it a few pixels off an edge
on purpose; flick it and the reach grows. An edge the window already touches
keeps it, and an edge it is moving away from stops competing with the one it is
heading for.

**Settings:** Snap distance (the reach at an average drag speed), Snap speed
response (`0` = one fixed reach, as it used to be), Edge stickiness (how hard an
edge you already touch holds on), Corner boost (how much stronger corners are),
Neighbour reach (how far away another window can be and still attract).

### 2. Ice glide

Let go mid-drag and the window keeps sliding, slowing down, then settles onto
whatever edge it drifts near — like sliding something across ice.

Flick harder and it travels further. If the throw was still going when an edge
stopped it, the window overshoots slightly and springs back instead of stopping
dead. It never flies off-screen.

**Settings:** Throw strength (`0` = stop dead where you let go), Slide time (how
long the longest slide may take), Throw distance, Settle overshoot (`0` = land
without the spring-back).

> Needs "Show window contents while dragging" — see `ANIMATIONS.md`.

### 3. Always on top

**`Shift + Alt + O`** pins the window you're using above all others. Press again
to unpin. A tray message tells you which way it went.

### 4. Position memory

Each app's size and position is remembered, and reapplied next time you open a
window of that app.

Dialogs, popups, tool windows and Picture-in-Picture (PiP) windows are skipped on purpose — every Chrome popup
shares an identity with the main Chrome window, so remembering them by that alone
would fling popups to your main window's size and place.

Turn it off with **`Shift + Alt + M`**, or clear what it has learned with
*Forget saved positions* in settings.

### Also: the taskbar

There is no taskbar-height control any more. On Windows 11 build 26200 the
taskbar **cannot** be meaningfully shrunk by a normal program — the buttons need
the full height and the primary bar refuses to resize at all — so that engine was
removed rather than kept as a feature that mostly doesn't work.
[TASKBAR-AND-INTERNALS.md](TASKBAR-AND-INTERNALS.md) records what was measured and
why, so nobody has to rediscover it.

What remains is the part that does work: **Smart Auto-Hide** (General page) hides
the taskbar only when a window is maximized or reaches the bottom edge, and
**Taskbar Volume Scroll** (System & Media) puts volume on the wheel while your
mouse is over it.

### The Full Feature Suite (40+ Tweaks & Animations)

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
- **Custom Taskbar Clock**: time over date with the temperature beside it, drawn on the taskbar, with a settings page of its own. By default it sits left of every tray icon and covers nothing, painting no background at all so it reads as taskbar text; you can instead anchor it right beside the clock, which covers the tray buttons in that space. The info column shows a weather glyph with the temperature and the wind speed under it. It reads `--` until you set a city, and until then the program makes no network request at all.
- **Theater Spotlight**: A soft, circular vignette shadow follows your active window like a stage spotlight, dimming the rest of the screen.
- **Fly-to-Mouse Minimize**: Minimized windows spin and vacuum directly into your mouse cursor instead of dropping to the taskbar.
- **Window Unrolling**: New windows unroll from top to bottom like a window blind in 0.2 seconds.

**Productivity & Window Management:**
- **Transparency Control**: `Shift + Alt + Wheel` to adjust the opacity of any active window.
- **Cinema / Focus Mode**: `Shift + Alt + F` to black out the entire background, keeping only the active window visible.
- **Window Shade / Roll-Up**: Middle-click a window to roll it up (collapse to just the title bar), middle-click to restore.
- **Minimize to Tray**: Add a tray icon for any active window to declutter your taskbar.
- **Boss Key**: `Shift + Alt + Esc` to instantly hide all windows and mute system audio. Press again to restore.
- **Linux-Style Alt-Drag**: Hold `Alt + LeftClick` anywhere on a window to move it, or `Alt + RightClick` anywhere to resize it from the nearest edge.
- **Taskbar Volume Scroll**: Hover over the taskbar and scroll the mouse wheel to adjust volume, or middle-click to mute.
- **Quick Folder Jump**: Press `Ctrl + G` in any File Save/Open dialog to instantly jump to the folder of your most recently active Explorer window.
- **Global Plain-Text Paste**: `Ctrl + Alt + V` strips all formatting, colors, and fonts from your clipboard and pastes as pure plain text anywhere.
- **Smart Caps Lock**: Tap CapsLock to send `Escape` (or `Backspace`), hold it for 0.4 seconds to actually toggle CapsLock on/off.

---

## Hotkeys

| Key | Does |
|---|---|
| `Shift + Alt + W` | Open settings |
| `Shift + Alt + S` | Magnetic snapping, on/off |
| `Shift + Alt + M` | Position memory, on/off |
| `Shift + Alt + E` | Breathing windows, on/off |
| `Shift + Alt + F` | Focus mode, on/off |
| `Shift + Alt + O` | Always on top, on/off |
| `Shift + Alt + R` | Roll up / unroll |
| `Shift + Alt + H` | Minimize to tray |
| `Shift + Alt + Esc` | Boss key |
| `Shift + Alt + Wheel` | Transparency |
| `Alt + F4` | Close, with the gravity animation |

### Moving windows from the keyboard

| Key | Does |
|---|---|
| `Shift + Alt + Numpad 1`–`9` | Tile to a 3×3 grid, laid out like the keypad |
| `Shift + Alt + Numpad 0` | Maximize / restore |
| `Shift + Alt + K` | Centre the window, keeping its size |
| `Shift + Alt + U` | Cycle its size: 50% → 75% → 90%, centred |
| `Shift + Alt + N` | Move it to the next monitor |
| `Shift + Alt + ↑` / `↓` | Top half / bottom half |
| `Shift + Alt + Z` | Undo the last one of these |

The grid follows the shape of the numeric keypad, so the key you press is where
the window ends up — `7` is the top-left quarter, `4` the left half, `2` the
bottom half. **NumLock must be on** — only the digit names of the keypad keys
are bound, so with NumLock off the keypad sends navigation keys and nothing
happens. `Shift + Alt + Up/Down` works either way.

Left and right halves are the two the keypad covers but the arrow keys don't:
Windows' own `Win + ←/→` already does those.

### Getting out of trouble

| Key | Does |
|---|---|
| `Shift + Alt + Y` | Restore **everything** — unroll, un-ghost and un-hide every window |
| `Shift + Alt + X` | Make the active window fully opaque again |
| `Shift + Alt + F5` | Restart the program |
| `Shift + Alt + F6` | Quit |

`Shift + Alt + Y` is the one to remember. If a window has vanished to its title
bar, gone see-through, or disappeared into the tray, this brings it back.

### Switching a feature on or off

`Shift + Alt +` … `C` hot corners, `V` active border, `I` cursor wrap,
`D` multi-monitor dimmer, `T` smart auto-hide taskbar, `J` magnetic groups,
`Space` grab & pan. Each shows a tray notification and remembers the new state.

Several more hotkeys appear only when their feature is switched on.
`HOTKEYS.md` has the full list, the conflicts with Windows' own shortcuts, and
how to change them.

---

## The settings window

Seven pages down the left:

| Page | What's on it |
|---|---|
| **Window Management** | Snapping (distance, speed response, edge stickiness, corner boost, neighbour reach), ice glide (throw, slide time, throw distance, settle overshoot), drag opacity floor, tiling grid gap, rubber-band travel, alt-drag, fly-to-mouse minimize, grab & pan, roll-up, position memory |
| **Power Features** | Spotlight, live PiP, ghost window (opacity, fade range, click range), always on bottom, middle-click close, minimize to tray, quick folder jump, Quick Look |
| **System & Media** | Taskbar volume scroll, volume OSD (step, hold time, opacity), mic kill-switch, boss key, text expander, smart CapsLock, plain-text paste, "never dim these apps" |
| **Multi-Monitor** | Cursor wrap (tolerance, hold time, approach speed, cooldown), focus dimmer strength, active border (thickness, opacity, colour), breathing (delay, opacity), shake to find, cursor yawn, keystroke sound volume and pitch, new-window animation |
| **Animation** | Durations and intensities shared across features — open animation, snap bounce, roll-up, gravity close, overlay fade, OSD slide, focus-mode dim / softness / corners, transparency wheel step and floor |
| **Hot Corners** | Enable, corner size, hold time, plus an action per corner |
| **General** | Start with Windows, gravity drop on close, debug log, smart auto-hide taskbar, taskbar style / icon size, restart Explorer, open log, open folder, hotkeys, this guide |

Changes apply as you make them — there's no OK button. Typed values apply about
half a second after you stop typing. It follows your Windows light/dark theme.

### About the numbers

Every numeric field shows its usable range in the grey hint beside it, like
`px from an edge (4-120)`. A value outside that range is corrected when you leave
the field, not while you are typing, so you can always finish typing a number. A
value that is nonsense — or a `settings.ini` hand-edited into a bad state — falls
back to the default rather than stopping the program from starting.

The **minimum is the lowest usable value, not zero**. To switch a feature off use
its checkbox; don't set its duration to nothing. Where `0` genuinely means
something the hint says so: throw strength `0` is "stop where you let go",
neighbour reach `0` is "screen edges only", and cursor-wrap hold time or approach
speed at `0` switches that one gate off.

Opacities are always a percentage, durations always milliseconds, distances
always pixels — the same everywhere in the app.

### Things that ship switched off

These change how the mouse behaves system-wide, so they start disabled and you
opt in:

| Setting | Why it's off |
|---|---|
| **Rubber-Band Scroll** | Physically nudges whatever window is under the pointer on every wheel notch. |
| **Middle-click title bar to roll up** | Puts this app in front of every middle click in the system. `Shift+Alt+R` rolls a window up whether this is on or not. |
| **Middle-Click to Close** | Same, and a stray middle click closes a window. |
| **Context Menu Unfold** | Animates every right-click menu in Windows. |

Turning any of them on in the settings window is all it takes.

---

## Windows settings that matter

**One is required:** *Show window contents while dragging*. Without it Windows
drags an outline and you'd never see the glide. `Install.bat` checks this.

**One works against it:** Windows' own *Snap windows*. When it's on, dragging to
a screen edge triggers Windows' half-screen snap before this program sees it.
Window-to-window magnetism still works. Leaving it on is usually the right call —
turning it off also disables `Win + ←/→`.

Run **`scripts\Apply-Windows-Tuning.ps1`** for the optional polish, and
`scripts\Restore-Windows-Tuning.ps1` to undo it. Full detail in `ANIMATIONS.md`.

---

## If something looks wrong

| Problem | Fix |
|---|---|
| Nothing happens when I drag | Open settings → General → **Open log**. It records every drag and why it did or didn't snap. |
| Hotkeys dead in one app | That app is running as administrator. Run Window Tweaks as admin too, or click a normal window first. |
| A window keeps jumping somewhere | Position memory learned a bad spot. Settings → Window Management → **Forget saved positions**. |
| Taskbar looks odd, or auto-hide is stuck | Settings → General → **Restart Explorer**. That's a guaranteed reset — and the program notices Explorer coming back and re-attaches itself. |
| A window is stuck transparent or click-through | Ghost mode. Press `Shift + Alt + G` on it again. Exiting the program also restores every window it changed. |
| A window won't come back from the desktop | Always-on-bottom. Press `Shift + Alt + B` on it, or exit the program. |
| Position memory / new-window animations stopped working | Explorer restarted and the program lost its connection to it. This now repairs itself; if it doesn't, restart from the tray. |
| Won't start at all | AutoHotkey **v2** must be installed. v1 can't run it. |

---

## Files

| File | What it is |
|---|---|
| `WindowTweaks.ahk` | The program |
| `SnapCore.ahk` | Snapping maths — required |
| `RenderCore.ahk` | Applies every visual change — required |
| `AnimationScheduler.ahk` | Drives every animation — required |
| `MediaCore.ahk` | Detects windows that are playing audio or video, so they never get faded — required |
| `settings.ini` | Your settings, and your text-expander snippets |
| `window-positions.ini` | Remembered window positions |
| `snap.log` | Every drag and what it decided (auto-trimmed at 256 KB) |

Everything is written next to the program. No registry keys, no services, no
system files, no drivers.
