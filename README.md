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
Each app reopens at the size and position you last left it. Dialogs, popups and
tool windows are deliberately excluded.

### Taskbar management
The Windows 11 taskbar cannot be meaningfully shrunk by an ordinary program (see
[docs/TASKBAR-AND-INTERNALS.md](docs/TASKBAR-AND-INTERNALS.md)). To solve this, 
we integrate directly with **ExplorerPatcher**. The installer automatically fetches 
and installs ExplorerPatcher for you, and Window Tweaks provides a clean UI to toggle 
between Windows 10 and Windows 11 styles, and switch to small icons.

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

# 21 automated geometry tests - doesn't touch your windows
cd tests
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" test-snap.ahk

# guided live test - run it, then drag windows and watch each drag get judged
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" test-live-manual.ahk
```

`tests\test-live-manual.ahk` is deliberately manual. A title-bar drag can't be
simulated reliably: injected clicks don't engage the window's move loop the way
a physical press does, so an "automated" drag test either does nothing and
passes vacuously, or moves the window by other means and tests a code path real
drags never take.

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
