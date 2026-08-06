# Tweaks For Everyone

Windows 11 window management that Windows doesn't give you, plus an honest,
fully reversible pass over the Windows settings that actually affect how smooth
the desktop feels.

One tray program, about 18 MB, near-zero CPU when idle. Nothing is installed
outside your user profile.

```
Win + Ctrl + W    settings
Win + Ctrl + T    pin a window on top
Win + Ctrl + S    magnetic snapping on / off
```

---

## Install

Download or clone the repo, then **double-click `Install.bat`**.

It installs AutoHotkey v2 if you don't have it, copies the program to
`%LOCALAPPDATA%\Window Tweaks`, makes Start Menu / Desktop / Startup shortcuts,
and starts it.

```powershell
# or from a terminal
.\Install.ps1                    # interactive
.\Install.ps1 -Silent            # no prompts
.\Install.ps1 -Tuning            # also apply the Windows tuning
.\Install.ps1 -NoAutoStart       # don't run at login
```

Remove it with `Uninstall.ps1`. No admin rights are needed at any point.

---

## What it does

### Magnetic snapping
Drag a window and let go near a screen edge, a corner, or **another window's
edge** and it jumps flush. Each axis resolves independently, so a window can
stick to a screen edge sideways and to another window vertically in one motion.

Corners pull harder than plain edges: once one axis grabs, the other is retried
with a much larger reach, so a window hugging the left edge drops into the
corner from far further away.

> Windows already snaps to *screen edges*. The new part is windows sticking
> **to each other**.

### Ice glide
Let go mid-drag and the window keeps sliding, decelerating on a quintic
ease-out, then settles onto whatever edge it drifts near. Flick harder and it
travels further. It never flies off-screen.

### Always on top
`Win + Ctrl + T` pins the active window above everything else.

### Position memory
Each app reopens at the size and position you last left it. Dialogs, popups,
tool windows, and Picture-in-Picture (PiP) windows are deliberately excluded.

### Taskbar management
The Windows 11 taskbar cannot be meaningfully shrunk by an ordinary program, so
Window Tweaks doesn't pretend to — the height engine that tried was removed, and
[docs/TASKBAR-AND-INTERNALS.md](docs/TASKBAR-AND-INTERNALS.md) records exactly what
was measured and why. Instead it integrates with **ExplorerPatcher**, which can do
it properly: the installer fetches and installs ExplorerPatcher for you, and
Window Tweaks gives you a clean UI to switch between Windows 10 and Windows 11
taskbar styles and to turn on small icons.

What Window Tweaks does to the taskbar itself is **Smart Auto-Hide** — hiding it
only when a window is maximized or reaches the bottom edge — and putting volume on
the mouse wheel while the pointer is over it.

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

---

## Windows tuning (optional)

`scripts\Apply-Windows-Tuning.ps1` turns on the animation and Explorer settings
that make the desktop feel fluid.

The surprising part: on a lot of machines these are **already switched off** by
well-meaning "optimization" guides, which is exactly why Windows feels abrupt
rather than fast. Turning them back on is the fix.

```powershell
.\scripts\Apply-Windows-Tuning.ps1              # animations + Explorer
.\scripts\Apply-Windows-Tuning.ps1 -Animations  # just the animations
.\scripts\Restore-Windows-Tuning.ps1            # undo everything
```

- Writes to `HKCU` only. No admin, no services, no system files, no drivers.
- Your original values are saved to `%LOCALAPPDATA%\Window Tweaks Backup\tuning-backup.json` on first run.
- Never touches Windows Update, Defender, or any security setting.

Detail in [docs/WINDOWS-TUNING.md](docs/WINDOWS-TUNING.md) and
[docs/ANIMATIONS.md](docs/ANIMATIONS.md).

---

## Repository layout

```
src/          the program - WindowTweaks.ahk plus two required includes
scripts/      Windows tuning: apply and restore
docs/         guide, hotkeys, animation notes, technical findings
tests/        automated geometry tests + a guided live test
build/        installer build script
Install.bat   double-click entry point
```

| Doc | What's in it |
|---|---|
| [docs/GUIDE.md](docs/GUIDE.md) | Everything the program does, in plain language |
| [docs/HOTKEYS.md](docs/HOTKEYS.md) | Every hotkey, conflicts, how to change them |
| [docs/ANIMATIONS.md](docs/ANIMATIONS.md) | Which Windows animation settings this needs and why |
| [docs/WINDOWS-TUNING.md](docs/WINDOWS-TUNING.md) | What the tuning changes, and what it deliberately won't |
| [docs/TASKBAR-AND-INTERNALS.md](docs/TASKBAR-AND-INTERNALS.md) | Why the taskbar can't be shrunk, and how the snapping works |

---

## Development

Requires **AutoHotkey v2** (v1 cannot run this).

```powershell
# run from source
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" src\WindowTweaks.ahk
```

There is **no test suite in this repository.** AutoHotkey 2.0 also has no offline
syntax check (`/validate` arrived in 2.1), so the closest thing to one is a parse
check: copy `src\*.ahk` to a scratch folder, prepend `ExitApp` to the copy of
`WindowTweaks.ahk`, and run that with `/ErrorStdOut`. AutoHotkey parses the whole
script before executing anything, so a load-time error is printed while `ExitApp`
stops it before a single hook, timer or tray icon is installed.

Testing is otherwise by hand, and deliberately so for the drag path: a title-bar
drag can't be simulated reliably — injected clicks don't engage the window's move
loop the way a physical press does, so an "automated" drag test either does
nothing and passes vacuously, or moves the window by other means and tests a code
path real drags never take.

Two naming traps worth knowing before editing the AutoHotkey source, both of
which cost real debugging time:

- AHK identifiers are **case-insensitive**, so a variable called `oR` collides
  with the `or` keyword, and `SUB` collides with a function called `Sub`. Both
  fail with confusing errors far from the real cause.
- `Log` is a built-in (logarithm). Don't use it as a variable name.

Keep the `.ahk` files **pure ASCII**. AutoHotkey reads a file without a BOM
using the system codepage, so smart quotes and dashes turn into mojibake in the
UI on other machines.

---

## Requirements

- Windows 11 (developed and tested on 25H2, build 26200)
- AutoHotkey v2 — installed automatically by `Install.bat` if missing

## License

MIT — see [LICENSE](LICENSE).
