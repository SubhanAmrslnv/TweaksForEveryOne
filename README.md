# Tweaks For Everyone — Window Manager & Snapping Tool for Windows 11

**Free, open-source window manager for Windows 11: magnetic window snapping,
inertial drag physics, 3×3 keyboard tiling, always-on-top, per-window
transparency, hot corners and 40+ power-user tweaks — in one tray app.**

Think *Magnet* or *Rectangle* on macOS, or *PowerToys FancyZones*, but with
window-to-window magnetism and physics-based glide. Written in
[AutoHotkey v2](https://www.autohotkey.com/). No admin rights, no telemetry,
nothing installed outside your user profile.

![Platform](https://img.shields.io/badge/platform-Windows%2011-0078D6)
![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2-334455)
![License](https://img.shields.io/badge/license-MIT-green)
![Admin](https://img.shields.io/badge/admin%20rights-not%20required-brightgreen)

One tray program, about 18 MB, near-zero CPU when idle.

```
Shift + Alt + W          settings
Shift + Alt + O          pin a window on top
Shift + Alt + S          magnetic snapping on / off
Shift + Alt + K          centre the active window
Shift + Alt + Numpad1-9  tile it to a 3x3 grid, laid out like the keypad
Shift + Alt + N          send it to the next monitor
Shift + Alt + Z          undo that
```

Full list: [docs/HOTKEYS.md](docs/HOTKEYS.md).

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

The pull scales with how fast you let go. Place a window slowly and the reach
shrinks, so you can park it a few pixels off an edge on purpose; flick it and
the reach grows, so momentum increases attraction. An edge the window is
already flush with holds on to it, and an edge it is moving away from stops
competing with the one it is heading for.

Corners pull harder than plain edges: once one axis grabs, the other is retried
with a much larger reach, so a window hugging the left edge drops into the
corner from far further away.

> Windows already snaps to *screen edges*. The new part is windows sticking
> **to each other**.

### Ice glide
Let go mid-drag and the window keeps sliding, decelerating on a quintic
ease-out, then settles onto whatever edge it drifts near. Flick harder and it
travels further. If the throw was still going when the edge stopped it, the
window overshoots slightly and springs back rather than stopping dead. It
never flies off-screen.

### Always on top
`Shift + Alt + O` pins the active window above everything else.

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

### Everything is tunable

Roughly 45 numbers that used to be hard-coded — animation durations, opacities,
distances, radii, delays and thresholds — are settings, each with a validated
range shown next to the field. Opacities are always a percentage, durations
always milliseconds, distances always pixels. The minimum of each range is the
lowest *usable* value: to switch a feature off, use its checkbox rather than
setting its duration to zero. See [docs/GUIDE.md](docs/GUIDE.md#about-the-numbers).

Four features ship **switched off** because they change how the mouse behaves
system-wide — Rubber-Band Scroll, middle-click Roll-Up, Middle-Click to Close and
Context Menu Unfold. Turn on whichever you want in the settings window.

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
- **Infinite Cursor Wrap**: Push the cursor into the left or right edge of the desktop and hold to teleport to the other side. Needs a deliberate push - approach speed, hold time, cooldown and edge tolerance are all configurable - so reaching for something at the screen edge never triggers it, and it never fires mid-drag.
- **Quick Spotlight Launcher**: Double-tap `Ctrl` for a minimalist, lightning-fast search and launch bar.
- **Smart Active Border**: Draws a sleek, accent-colored border around the currently active window.
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
- **Focus Pulse**: Switching to a window via Alt+Tab makes it pulse (expand by 2-3% and bounce back) to immediately draw your attention.
- **Ghost Slide-In**: New apps slide up from 30px below while fading in, similar to modern smartphone app launches.
- **Parallax Dragging**: Windows become transparent based on how fast you drag them, fading back to solid when you stop. The two speeds that define the ramp are settings: it starts fading at `[memory] parallaxfrom` px/s and reaches `parallaxmin` opacity at `parallaxfull` px/s.
- **Custom Taskbar Clock**: puts the time, the date and the current temperature in the free space to the left of the system tray. It never draws over the native clock, the date or the tray icons - Windows keeps drawing those where they are. Set a city in the settings to get the temperature; leave it blank and the block shows time and date only and makes no network request at all.
- **Magnetic Seam Flash**: A brief neon flash effect appears exactly on the seam when two windows magnetically snap together.
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
- **Focus Depth (Portal Scale-In)**: The active window subtly scales up and pushes background windows backward for depth of field.
- **Spark Typing & Acoustic Keystrokes**: Type with zero-latency mechanical ASMR clicks (MIDI) while a neon equalizer bounces at the window bottom, and your caret leaves a glowing neon trail.
- **Carousel Alt-Tab**: A 3D rotating carousel replacement for the standard flat Alt-Tab menu.
- **Dynamic Notch (OSD)**: Volume and brightness adjustments drop down a sleek iOS-style Dynamic Island pill from the top of the screen.
- **Curtain Drop (Win+D)**: Showing the desktop drops all windows simultaneously with a kinetic motion-blur effect.
- **Motion Blur Scroll**: Fast mouse-wheel scrolling applies a vertical motion blur to make 60Hz screens feel fluid.
- **Overscroll Bounce**: Scrolling past the end of a page elastically stretches and springs back.
- **Taskbar Icon Wave & Elastic Toasts**: Hovering over the taskbar creates a macOS-like icon wave, and notifications bounce elastically into view.
- **Start Menu Slide-Up Blur**: Opening the Start menu slides it up while deeply blurring the entire background.
- **Window Throw & Catch**: Forcefully flick a window towards another monitor, and it will kinetically fly across screens.
- **Shatter to Close**: Shift+Alt+F4 smashes the active window into dozens of 3D glass shards that fall with gravity.
- **Lightsaber Seam Glow**: Hovering over the seam between two snapped windows ignites a neon cyan glow.
- **Privacy Blur on Unfocus**: Mark a window as private (Win+Alt+B). When inactive, it gets a heavy frosted glass overlay.

> **Note:** Some features might be annoying, such as **Focus Depth of Field** (3d background scale), **Focus Pulse** (HeartBeat Active), and **Motion Blur Scroll** (Vertical speed blur). If you don't like windows jumping up and down, you can turn them off! :)

**Keyboard Window Layout:**
- **Numpad Tiling**: `Shift + Alt + Numpad 1-9` tiles the active window to a 3x3 grid laid out exactly like the keypad — `7` is the top-left quarter, `4` the left half, `2` the bottom half. **Requires NumLock on** — only the digit names are bound.
  `Shift + Alt + Up/Down` gives the top and bottom halves either way.
- **Centre & Resize**: `Shift + Alt + K` centres a window without resizing it; `Shift + Alt + U` cycles it through 50% / 75% / 90% of the work area, centred.
- **Next Monitor**: `Shift + Alt + N` sends a window to the next display, scaling it so a half-width window stays half-width on a screen of a different resolution.
- **Maximize Toggle**: `Shift + Alt + Numpad 0`.
- **Undo Layout**: `Shift + Alt + Z` puts the window back where it was before the last layout key.
- **Restore Everything**: `Shift + Alt + Y` is the panic key — it unrolls, un-ghosts and un-hides every window the program is holding, in one press.
- **Reset Transparency**: `Shift + Alt + X` returns the active window to fully opaque.

**Feature Toggles (`Shift + Alt + key`):**
- Hot corners (`C`), smart active border (`V`), infinite cursor wrap (`I`), multi-monitor dimmer (`D`), smart auto-hide taskbar (`T`), magnetic window groups (`J`), grab & pan (`Space`) — each toggles instantly, shows a tray notification, and saves the new state.

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
src/          the program - WindowTweaks.ahk plus its required includes
linux/        C++/Qt6 Linux port (early scaffold; see linux/CLAUDE.md)
scripts/      Windows tuning: apply and restore
docs/         guide, hotkeys, animation notes, technical findings
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
| [linux/docs/](linux/docs/) | The Linux port: architecture, feature matrix, Wayland limits, install |

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

### Linux

An independent C++20/Qt6 port for X11 and Wayland (Linux Mint/Cinnamon, GNOME,
KDE Plasma) lives in [`linux/`](linux/). It is an **early scaffold** — it does not
build yet and manages no windows. See [linux/docs/IMPLEMENTATION-AUDIT.md](linux/docs/IMPLEMENTATION-AUDIT.md)
for exactly what exists. The Windows program is unaffected by it.

---

## FAQ

### How do I snap windows to each other on Windows 11?

Windows' own Snap Assist only snaps to *screen* edges. Tweaks For Everyone adds
**window-to-window magnetism**: drag a window near another window's edge and it
jumps flush against it. Each axis resolves independently, so one window can stick
to a screen edge sideways and to another window vertically in the same motion.

### Is there a free Magnet alternative for Windows?

Yes — this is one. *Magnet* and *Rectangle* are macOS window managers; this gives
Windows 11 the same keyboard tiling (`Shift + Alt + Numpad 1-9` for a 3×3 grid,
centre, half-screen, cycle-size, next-monitor) plus magnetic snapping and glide
physics that neither of them has. It is MIT-licensed and free.

### How is this different from PowerToys FancyZones?

FancyZones is a zone-based layout manager: you define zones and windows land in
them. This is physics-based: windows snap to each other and to real edges as you
drag, keep sliding when you release, and bounce on landing. The two can be used
together — they don't conflict.

### Can I make a window always on top in Windows 11?

Yes. `Shift + Alt + O` pins the active window above everything else, and press
again to unpin. There is also **always on bottom** (`Shift + Alt + B`) to park a
window on the desktop as a widget.

### How do I make a window transparent on Windows 11?

Hold `Shift + Alt` and scroll the mouse wheel over any window to change its
opacity. `Shift + Alt + X` resets it to fully opaque.

### Does Windows 11 have hot corners?

Not natively. This adds macOS-style **hot corners** — throw the pointer into a
screen corner to trigger an action such as show-desktop or Task View — with a
dwell delay so reaching for a close button never triggers them by accident.

### How do I get picture-in-picture for any window?

`Shift + Alt + P` creates a live, always-on-top thumbnail of any background
window, using DWM thumbnails rather than screen capture.

### Does it need administrator rights?

No. Nothing is installed outside your user profile, there is no service, no
scheduled task and no `Run` registry key — only a Startup shortcut. The optional
Windows tuning writes to `HKCU` only and is fully reversible.

### Will it slow my PC down?

It idles at near-zero CPU. Polling timers only run for features you have switched
on, and the animation scheduler stops entirely when nothing is animating.

### Does it work on Windows 10?

It is developed and tested on Windows 11 (25H2, build 26200). Much of it will run
on Windows 10, but the taskbar and DWM behaviour it depends on is Windows 11
specific and is not tested there.

### Is there a Linux version?

An early C++/Qt6 scaffold for X11 and Wayland exists in [`linux/`](linux/), but it
does not build yet and manages no windows. See the
[implementation audit](linux/docs/IMPLEMENTATION-AUDIT.md).

---

## License

MIT — see [LICENSE](LICENSE).
