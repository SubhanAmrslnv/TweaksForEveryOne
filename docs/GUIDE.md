# Window Tweaks — guide

A small program that makes windows behave better. It sits in the tray, uses about
18 MB, and does nothing to your system outside its own folder.

**Press `Win + Ctrl + W` to open settings.**

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

**Settings:** Snap distance (how close before it grabs), Corner boost (how much
stronger corners are), Neighbour reach (how far away another window can be and
still attract).

### 2. Ice glide

Let go mid-drag and the window keeps sliding, slowing down, then settles onto
whatever edge it drifts near — like sliding something across ice.

Flick harder and it travels further. It never flies off-screen.

**Settings:** Throw strength (`0` = stop dead where you let go), Slide time (how
long the longest slide may take).

> Needs "Show window contents while dragging" — see `ANIMATIONS.md`.

### 3. Always on top

**`Win + Ctrl + T`** pins the window you're using above all others. Press again
to unpin. A tray message tells you which way it went.

### 4. Position memory

Each app's size and position is remembered, and reapplied next time you open a
window of that app.

Dialogs, popups, tool windows and Picture-in-Picture (PiP) windows are skipped on purpose — every Chrome popup
shares an identity with the main Chrome window, so remembering them by that alone
would fling popups to your main window's size and place.

Turn it off with **`Win + Ctrl + M`**, or clear what it has learned with
*Forget saved positions* in settings.

### Also: taskbar height

There's a taskbar page in settings, and it's honest about a hard limit: on
Windows 11 build 26200 the taskbar **cannot** be meaningfully shrunk by a normal
program. The buttons need the full height, and the primary taskbar refuses to
resize at all. The settings page shows you exactly what each bar can and can't
do. `README.md` explains why in detail.

### The Full Feature Suite (25+ Tweaks & Animations)

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

---

## Hotkeys

| Key | Does |
|---|---|
| `Win + Ctrl + W` | Open settings |
| `Win + Ctrl + T` | Always on top, on/off |
| `Win + Ctrl + S` | Magnetic snapping, on/off |
| `Win + Ctrl + M` | Position memory, on/off |
| `Win + Alt + ↑` | Taskbar taller |
| `Win + Alt + ↓` | Taskbar shorter |
| `Win + Alt + 0` | Restore taskbar |

`HOTKEYS.md` covers conflicts with Windows' own shortcuts and how to change these.

---

## The settings window

Five pages down the left:

| Page | What's on it |
|---|---|
| **Snapping** | On/off, snap distance, corner boost, neighbour reach |
| **Ice Glide** | On/off, throw strength, slide time |
| **Windows** | Position memory, forget saved positions |
| **Taskbar** | Height, what each bar can actually do, restore, restart Explorer |
| **General** | Start with Windows, open log, open folder, hotkeys, this guide |

Changes apply as you make them — there's no OK button. Typed values apply about
half a second after you stop typing. It follows your Windows light/dark theme.

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
| A window keeps jumping somewhere | Position memory learned a bad spot. Settings → Windows → **Forget saved positions**. |
| Taskbar looks short or odd | Settings → Taskbar → **Restart Explorer**. That's a guaranteed reset. |
| Taskbar stayed small after closing | It was killed rather than exited. Start it again and press `Win + Alt + 0`. |
| Won't start at all | AutoHotkey **v2** must be installed. v1 can't run it. |

---

## Files

| File | What it is |
|---|---|
| `WindowTweaks.ahk` | The program |
| `SnapCore.ahk` | Snapping maths — required |
| `TaskbarCore.ahk` | Taskbar engine — required |
| `settings.ini` | Your settings |
| `window-positions.ini` | Remembered window positions |
| `snap.log` | Every drag, and every taskbar decision (auto-trimmed at 256 KB) |
| `test-snap.ahk` | 21 automated checks of the snapping maths |
| `test-live-manual.ahk` | Run it, drag windows, watch each drag get judged |

Everything is written next to the program. No registry keys, no services, no
system files, no drivers.
