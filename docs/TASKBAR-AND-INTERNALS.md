# Window Tweaks

One program, four tweaks. Runs in the tray as a single ~18 MB process.

**Win + Ctrl + W** opens the tools window. All hotkeys are in `HOTKEYS.md`,
setup is in the repository `README.md`.

| Tweak | What it does |
|---|---|
| Magnetic snapping | Windows stick to screen edges, corners and to each other |
| Always on top | Pin any window above the rest |
| Position memory | Apps reopen where you last put them |
| Taskbar height | Shrinks the taskbar as far as the shell allows — see the honest limits below |

---

## Magnetic snapping

Drag a window and release it near a screen edge, or near another window's edge,
and it jumps flush. Each axis resolves independently, so a window can stick to a
monitor edge horizontally and to another window vertically in one gesture.

**Corners pull harder than plain edges.** Once one axis locks on, the
perpendicular axis is retried with a threshold `Corner boost` times larger — so
a window already hugging the left edge drops into the top-left corner from much
further away than a plain edge would catch it.

Tune it in the tools window:

| Setting | Default | Meaning |
|---|---|---|
| Snap distance | 30 px | How close an edge must be before it sticks |
| Corner boost | 2.2 × | Extra pull on the second axis once the first locks |
| Neighbour reach | 90 px | How far off a neighbouring window can be and still attract |

Dragging to a *screen edge* is something Windows already does by itself. The
genuinely new behaviour is windows sticking to **each other**, so test that when
judging whether it works.

`snap.log` records every drag and why it did or didn't snap, and every taskbar
measurement, resize attempt and refusal (those lines start `taskbar`). Open it
from the tools window if something looks wrong.

## Always on top

**Win + Ctrl + T** pins or unpins the active window. A tray notification
confirms which state it went to.

## Position memory

Each app's window size and position is remembered per executable + window class
and reapplied when you next open a window of that app. Stored in
`window-positions.ini`; clear it from the tools window.

Dialogs, popups and tool windows are deliberately excluded — every Chrome popup
shares a window class with the main Chrome window, so restoring by class alone
would fling popups to the main window's geometry.

Because the key is per-app, *every* new window of that app opens where you last
put one. If that's not what you want, turn it off with **Win + Ctrl + M**.

---

## Taskbar management

The Windows 11 taskbar cannot be meaningfully shrunk by an ordinary program. 
Because of this, Window Tweaks now integrates directly with **ExplorerPatcher** to achieve a small, responsive taskbar.

The installer automatically fetches the latest `ep_setup.exe` from GitHub and installs it with administrator privileges.
Once installed, Window Tweaks provides a UI to switch between the Windows 10 style taskbar (which supports small icons) and the Windows 11 style.

The old method of manually cropping the taskbar (using `TaskbarCore.ahk`) has been completely removed as it was fundamentally broken on modern builds of Windows 11.

---|---|
| `TaskbarSi` registry value | Dead since KB5022913; ignored on 24H2/25H2 |
| `TaskbarSmallIcons` | Present in the registry but inert on the Win11 shell |
| Feature flag `29785184` | Is `TaskbarDynamicIconScaling`, already on by default; only shrinks icons when the bar is crowded |
| Feature flag `61090762` | *"No configuration found in the Runtime store"* — the small-taskbar code is not in build 26200; it ships in 26300+ |

**If you want a genuinely shorter taskbar** you need a tool that injects into
`explorer.exe`. [ExplorerPatcher](https://github.com/valinet/ExplorerPatcher) is
the free option (StartAllBack is the paid one). Check its release notes list
your exact build as tested, run `ep_setup.exe` elevated, then right-click the
taskbar → Properties → Taskbar → style **Windows 10** + **small taskbar
buttons** for roughly 30px.

This project does not bundle, install or recommend it — read these cautions
first:

- It installs `C:\Windows\dxgi.dll`, the textbook DLL-hijack path. Corporate
  EDR (Bitdefender, SentinelOne, CrowdStrike) commonly quarantines it, and per
  ExplorerPatcher's own notes *explorer.exe will not start if that file exists
  but is blocked from loading*. On a managed machine you may not be able to add
  the exclusion yourself.
- Smart App Control must be off, or explorer may fail to start.
- Have the rollback ready **before** installing: `ep_setup.exe /uninstall`
  elevated, or if the desktop won't load, boot Safe Mode and delete
  `C:\Windows\dxgi.dll`.

---

## Resource use

One process, ~18 MB, essentially 0% CPU at idle:

- New windows are detected via the shell hook (`RegisterShellHookWindow`), not
  by polling. An earlier version enumerated every window on the desktop about
  86 times a minute just to notice new ones.
- The only timer is a 3-second taskbar check, which is two `FindWindow` calls
  and one `GetWindowRect` per bar.
- Runs at below-normal priority, with AHK's history buffers disabled.

Combining the two original scripts into one program halved the memory.

## Files

| File | Purpose |
|---|---|
| `WindowTweaks.ahk` | The program — hotkeys, tools window, snapping, position memory |
| `SnapCore.ahk` | Snap geometry and window inspection |
| `test-snap.ahk` | 21 geometry tests, fully automated; doesn't touch your windows |
| `test-live-manual.ahk` | Guided live test — run it, drag windows, watch each drag get judged |
| `diagnostics\` | The probe scripts used to work out what the shell does and doesn't allow |

`test-live-manual.ahk` is deliberately manual. A caption drag can't be simulated:
injected clicks don't engage the window's move loop the way a physical press
does, so "automated" drag tests either did nothing and passed vacuously, or moved
the window by other means and tested a path real drags never take.

Created at runtime: `settings.ini`, `window-positions.ini`, `snap.log`
(auto-rotates at 256 KB). Nothing is written outside this folder.

Re-run the tests after a Windows update:

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" test-snap.ahk
```
