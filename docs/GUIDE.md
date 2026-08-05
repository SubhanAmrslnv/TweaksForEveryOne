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

## The four things it does

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

Dialogs, popups and tool windows are skipped on purpose — every Chrome popup
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
