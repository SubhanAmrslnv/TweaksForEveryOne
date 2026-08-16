# Implementation Audit

> **Status: early scaffold. The Linux port does not build and does not run.**
>
> This document records what is *actually in the tree*, verified file by file. The design
> intent lives in `ARCHITECTURE.md`, `FEATURE-MATRIX.md` and `WAYLAND-LIMITATIONS.md`;
> nothing in those three files should be read as a statement about current behaviour.
>
> A previous revision of this file ended with a 21-item checklist in which every box was
> ticked — including KDE support, tests, and multi-monitor support, none of which exist.
> That checklist has been removed. Do not reinstate a claim here without pointing at the
> code that backs it.

## Verify this yourself

Every claim below is reproducible from the repository root:

```bash
# Missing directories -> nothing implemented for KDE, the settings UI, or config.
# NOTE: `find linux -type d -empty` used to be the recipe here, and on a fresh
# clone it returns NOTHING - which reads as a pass. Git does not track empty
# directories, so these three are ABSENT rather than empty: worse, not better.
ls linux/src/ui linux/src/platform/kde linux/config    # No such file or directory

# X11 backend: every method body is a comment
grep -c '//' linux/src/platform/x11/X11Adapter.cpp

# There is no test suite
find linux -type d -name tests
```

## Component status

| Component | File | State |
| --- | --- | --- |
| Animation scheduler | `src/core/AnimationScheduler.cpp` | **Implemented.** Keyed callbacks, `bool(float dt)` retires the animation, one **unconditional** `flush()` per frame, `dt` clamped to three frames, and per-window channel ownership (`claim`/`release`/`owner`). Runs its own `std::thread` and parks when idle. |
| Render arbitration | `src/core/RenderQueue.cpp` | **Implemented.** Per-window coalescing with `Ambient < Animation < Drag < User` priority held **per attribute**, composed alpha (a user base times named modifier layers), and `removeWindow()` eviction. Wrapped in `beginBatch()`/`commitBatch()`. |
| Snap math | `src/core/SnapGeometry.cpp` | **Partial.** Independent X/Y resolution, `cornerBoost`, like-edge alignment, perpendicular-overlap gating, speed-adaptive reach and edge hysteresis are all present and aligned with `SnapCore.ahk`. Still missing obstacle collection (nothing enumerates windows) and all window-eligibility filtering. |
| Glide physics | `src/core/Physics.cpp` | **Partial.** Easing sign corrected, `<cmath>` included, and the kinetic-friction model replaced with the Windows pair: `predictThrow()` (ballistic, px/s, tunable gain) plus `glideDurationMs()`, with `settleBump()` for the landing overshoot. Still has no caller: nothing captures drag-release velocity. |
| Weather fetch | `src/core/WeatherFetcher.cpp` | **Implemented.** `QNetworkAccessManager` on a `QTimer`, emits `weatherUpdated`. |
| D-Bus service | `src/platform/wayland/DBusDaemon.cpp` | **Implemented.** Registers `org.tweakforeveryone.Daemon`, re-emits weather. Declares the geometry/alpha signals but never emits them. |
| Backend interface | `src/core/PlatformAdapter.h` | **Interface only** — by design. |
| X11 backend | `src/platform/x11/X11Adapter.cpp` | **Not implemented.** Every method body is a comment. There is no `#include <xcb/xcb.h>`; `xcb_connect` is commented out; `getWindowState()` returns a hardcoded 800x600 rect. |
| GNOME extension | `src/platform/gnome/extension.js` | **Panel clock only.** Replaces the date-menu label with time/date/weather. It declares `SetWindowGeometry` and `SetWindowAlpha` in its interface XML and handles neither. |
| KWin script | `src/platform/kde/` | **Does not exist.** Empty directory. |
| Settings UI / tray | `src/ui/` | **Does not exist.** Empty directory, yet named by `CMakeLists.txt`. |
| Configuration | `config/` | **Does not exist.** Empty directory. There is no Linux equivalent of `settings.ini`; tuning constants are hardcoded. |
| Tests | — | **Do not exist.** No `tests/` directory anywhere. |
| Daemon wiring | `src/main.cpp` | **Partial.** Constructs `DBusDaemon` and runs the Qt event loop. No `PlatformAdapter` is ever created, so no window is ever touched. |

## Feature status

Of the 34 features listed in `FEATURE-MATRIX.md`, **none are reachable today.** There is no
code path from any input event to any window: no hotkey is registered on any platform, and
the only implemented backend method set (`X11Adapter`) is inert.

Two features have platform-independent math in place and are the natural first targets once
a backend exists:

| Feature | What exists | What is missing |
| --- | --- | --- |
| **Magnetic snapping** | `SnapGeometry::computeSnap` resolves each axis independently, with `cornerBoost`, like-edge alignment, overlap gating, speed-adaptive reach and hysteresis. | Obstacle collection (nothing enumerates windows), eligibility filtering, and a backend able to apply the result. |
| **Ice glide** | `Physics::predictThrow` extrapolates a release, `glideDurationMs` sizes the animation and `quinticEaseOut`/`settleBump` shape it; `AnimationScheduler` can drive frames. | Drag-release velocity capture, configuration, and a backend able to move a window. |

One feature works end to end, and only on GNOME:

| Feature | Path |
| --- | --- |
| **Panel clock + weather** | `WeatherFetcher` -> `DBusDaemon` emits `WeatherUpdated` -> `extension.js` rewrites the GNOME date-menu label. Mirrors the Windows Custom Taskbar Clock. Requires the daemon to be running and the extension enabled. |

Everything else — position memory, PiP, roll-up, tray minimize, boss key, tiling, centering,
transparency, focus mode, smart caps lock, text expander, spotlight, quick look, mic kill
switch, grab & pan, hot corners, cursor wrap, active border, dimmer, magnetic groups,
stealth panic — exists only as a row in `FEATURE-MATRIX.md`.

## Known defects

These are recorded so they are not rediscovered. Fixing them is a code task, not a docs task.

1. ~~**`Physics.h` easing function is wrong.**~~
   **Fixed.** It was `1.0f - (--t) * t * t * t * t`, which evaluates to `1 + (1-t)^5` and
   returns **2.0 at t=0**. It is now `1.0f + (--t) * t * t * t * t`, matching the Windows
   `e := 1 - (1 - t) ** 5`. Left in this list, struck through, so the sign is not
   "corrected" back by someone reading the expression without evaluating it.
2. ~~**`Physics.cpp` calls `std::sqrt` without including `<cmath>`.**~~ **Fixed.**
3. **`CMakeLists.txt` names two sources that do not exist** — `src/ui/SettingsWindow.cpp` and
   `src/ui/TrayIcon.cpp`. CMake fails at configure time with "Cannot find source file".
4. **`find_package(XCB)` has no finder module.** CMake does not ship `FindXCB.cmake` and the
   repository does not provide one. Configure fails on a clean machine.
5. **`install(DESTINATION ~/...)` does not expand `~`.** CMake treats it literally and creates
   a directory named `~` under the install prefix.
6. **`install.sh`'s KDE branch aborts.** It runs `cp -r src/platform/kde/*` on an empty
   directory under `set -e`.
7. **Frame period.** The scheduler sleeps 16 ms. The Windows original documents a measured
   reason for using 15 ms (at 16 ms the Windows timer produced 39.8 fps with 59% of frames
   over 20 ms). The number was copied without the reasoning; whether it matters on Linux is
   untested, but do not "correct" 15 to 16 elsewhere on the assumption that 16 means 60 fps.
8. **GNOME `metadata.json` claims `shell-version` 42-46.** The code is ESM
   (`export default class`), which is GNOME 45+. Shell 42-44 require the older
   `imports.misc.extensionUtils` style and would fail to load.
9. **The D-Bus interface XML is duplicated** in `src/platform/wayland/DBusDaemon.h` (as
   annotations) and `src/platform/gnome/extension.js` (as a literal XML string), with no
   authoritative copy. They will drift.

## What "done" would require

For the port to reach parity with the Windows engine's core, in dependency order:

1. A working `X11Adapter` (XCB connection, `_NET_*` atom reads/writes, `xcb_grab_key`).
2. Window enumeration, so `SnapGeometry` has obstacles.
3. A config parser, so tuning values stop being hardcoded.
4. Drag detection and velocity sampling, so glide has an input.
5. A KWin script and a real GNOME extension for the Wayland paths.
6. Settings UI and SNI tray.
