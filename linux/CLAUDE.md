# CLAUDE.md — Linux port

This file provides guidance to Claude Code (claude.ai/code) when working with the Linux port
in `linux/`. The root `..\CLAUDE.md` covers the Windows implementation; the two share **no
code**, only design.

**The AutoHotkey tree this port was designed against has been DELETED.** The Windows
implementation is now `..\csharp\` (.NET 10 / WPF), and every `src/*.ahk` path referenced
below — `RenderCore.ahk`, `AnimationScheduler.ahk`, `SnapCore.ahk`, `DropPlacement.ahk`,
`DragPipeline.ahk` — is a **historical** reference, recoverable from git history at commit
`3a6fa68` and its parents. The design lessons those rows carry are still the reason this port
is shaped the way it is, so they are kept rather than stripped; just do not expect the files to
exist in the working tree, and do not compare line counts against a tree that is gone. AHK is
banned for new work (see `..\GEMINI.md`).

## Read this first

**This is an early scaffold. It does not manage windows.**

The two configure-time build failures are fixed (see *Commands*), and the pure core now has a
headless test suite and a structural checker. It has **not** been compiled or run on a real
Linux box from this tree - there is no C++ toolchain on the machine the fixes were written on -
so treat "builds" as "the known blockers are removed", not as "verified".

`linux/docs/IMPLEMENTATION-AUDIT.md` is the authority on what exists — it was written against
the files and lists every gap. `ARCHITECTURE.md`, `FEATURE-MATRIX.md` and
`WAYLAND-LIMITATIONS.md` describe *intent*: sound design, not current behaviour. An earlier
revision of the audit claimed the port was complete across the board; that is why this warning
is at the top of every one of those files now. **Do not add a completion claim to any doc here
without pointing at the code that backs it.**

Roughly: ~2,300 lines here, of which the platform layer is still 0% implemented, against
~11,400 lines of shipping AutoHotkey on the Windows side. The gap is not going to close by
writing more `core/`; it closes by implementing `X11Adapter`.

## What this is

A C++20 daemon (`tweaksd`) plus per-desktop compositor extensions, intended to reproduce the
Windows tray utility's window management on Linux across X11 and Wayland, targeting Linux Mint
(Cinnamon), GNOME, and KDE Plasma / KDE Neon.

Toolchain: CMake 3.16+, C++20, Qt6 (`Core Gui Widgets DBus Network`), XCB. GNOME extension is
GJS/ESM. KWin script would be QML/JS.

## Commands

```bash
# Configure and build. CURRENTLY FAILS - see below.
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Guided install: deps check, build, DE extension, autostart
chmod +x install.sh && ./install.sh

# Run the daemon in the foreground
./build/tweaksd
```

```bash
# Headless tests and the structural checks. Neither needs a display.
ctest --test-dir build --output-on-failure
./scripts/check-layers.sh
```

**The two configure-time failures are fixed.** For the record, so nobody reintroduces them:

1. `add_library(TweakUI src/ui/SettingsWindow.cpp src/ui/TrayIcon.cpp)` named sources in a
   directory that does not exist. The target is **deleted** until those files are real; do not
   paper over it with `file(GLOB)`, which would silently produce an empty library. `Qt6 Gui`
   and `Widgets` went with it, so a headless box needs only Core/DBus/Network.
2. `find_package(XCB REQUIRED COMPONENTS ...)` — CMake ships no `FindXCB.cmake` and this
   repository provides none. Now `pkg_check_modules(XCB REQUIRED IMPORTED_TARGET ...)`. Do not
   vendor a finder into `cmake/`: every xcb component ships a `.pc`, and a hand-written finder
   would drift.

Two more that would have bitten immediately afterwards: `std::thread` with no
`Threads::Threads` (fails to link on several toolchains, not on all), and
`install(DIRECTORY ... DESTINATION ~/...)`, which creates a literal `~` directory because
**CMake does not expand `~`**.

There is no CI and no linter. `./scripts/check-layers.sh` is the closest thing to
`scripts\Check-Split.ps1` on the Windows side, and `ls linux/src/ui linux/src/platform/kde
linux/config` is still the fastest honest status check - those three are ABSENT, not empty, and
git does not track empty directories, so `find -type d -empty` returns nothing and reads as a
pass.

## Architecture

Dependency flow is one-way: **`core/` -> `PlatformAdapter` -> backend**. `core/` is
platform-independent and must never include a platform or Qt GUI header; it is the only place
geometry and physics live. A backend applies state; it never computes it.

| Path | Role |
| --- | --- |
| `src/core/AnimationScheduler.*` | One thread, one frame loop, keyed callbacks. `registerAnimation(key, cb)` overwrites the same key; `cb` returns `false` to retire. Calls `RenderQueue::flush()` once per frame. |
| `src/core/RenderQueue.*` | The only thing that talks to a `PlatformAdapter`. Coalesces per window, arbitrates by priority **per attribute**, batches. Four attributes: geometry, alpha, region, z-order. Caches the last applied alpha and region so a redundant write is skipped - and records it **only when the adapter call succeeded**. |
| `src/core/SnapGeometry.*` | `computeSnap(moving, obstacles, workArea, &dx, &dy)`. Each axis resolved independently. |
| `src/core/Physics.*` | Glide math: quintic ease-out, settle bump, `glideDurationMs`, `predictThrow`, and `parallaxAlpha` (the drag opacity ramp). Pure, no state. |
| `src/core/VelocitySampler.*` | Drag velocity in **px/s**, smoothed by a time constant rather than a per-frame ratio, plus the drag-opacity smoothing. This is the input `predictThrow()` had no caller for. |
| `src/core/Geometry.h` | `Rect`, `Point`, `RegionSpec`, `ZOrderSpec`, `AlphaCommand`. Depends on nothing, so `RenderQueue` can use a rectangle without depending on snapping. |
| `src/core/WeatherFetcher.*` | `QNetworkAccessManager` + `QTimer`, emits `weatherUpdated`. |
| `src/core/PlatformAdapter.h` | The backend contract. `init`, `pollEvents`, `setWindowGeometry`, `setWindowAlpha`, `setWindowState`, `beginBatch`/`commitBatch`, `getWindowState`, `getActiveWindow`. |
| `src/platform/x11/` | XCB backend. Stubs only. |
| `src/platform/wayland/` | `DBusDaemon` — the Wayland strategy is D-Bus, not direct protocol access. |
| `src/platform/gnome/` | GNOME Shell extension (GJS, ESM). Panel clock only. |
| `src/platform/kde/` | KWin script. **Empty.** |
| `src/ui/` | Qt6 settings window + SNI tray. **Absent** - the CMake target that named it is deleted until the sources exist. |
| `tests/` | Headless unit tests for the pure core, plus `FakeAdapter`. No Catch2/FetchContent: the tree must configure with no network. |
| `scripts/check-layers.sh` | Structural checks - the `Check-Split.ps1` analogue. Wired into `ctest`. |
| `config/` | Default configuration. **Empty** — tuning values are hardcoded today. |

Namespaces: `TweakCore` for `core/`, `TweakPlatform` for backends.

### Correspondence to the Windows engine

The three pillars were ported deliberately; keep them aligned when changing either side.

| Linux | Windows | Invariant that must hold on both |
| --- | --- | --- |
| `RenderQueue` | `src/RenderCore.ahk` | Nothing outside this layer mutates window state. Priority arbitration is **per flush**: `Ambient(0) < Animation(1) < Drag(2) < User(3)` mirrors `RS_PRI_*` 10/20/30/40. |
| `AnimationScheduler` | `src/AnimationScheduler.ahk` | Produce from every callback, then flush **exactly once** per frame. A callback that always returns `true` is a polling monitor and does not belong here. |
| `SnapGeometry` | `src/SnapCore.ahk` | Pure geometry, no side effects. Axes resolve independently. |
| `Physics`, `VelocitySampler` | `Glide()` in `src/DropPlacement.ahk`, `ParallaxAlpha()`/`SampleVelocityStep()` in `src/DragPipeline.ahk` | Parameterise on elapsed time, never on frame count. Velocity is **pixels per second** on both sides, and the throw gain (0.18 px per px/s at unit gain) is shared. Smoothing constants are **time constants** (`1 - exp(-dt/tau)`), never per-frame ratios. |

Both of the invariants that used to be listed here as "not yet expressible" now are, and both
were ported from the Windows side rather than invented:

- **Two animations must never drive the same property of the same window.**
  `AnimationScheduler::claim(windowId, channel, key, cb)` gives one animation sole ownership of
  a `(window, channel)` slot and cancels whoever held it; `release()` and `owner()` are the
  other half. Channels are `Geometry`, `Alpha`, `Region`. On Windows this replaced five
  hand-written cancel lists that had drifted apart, and the absence of it there produced real
  bugs - the worst being a 400 ms wobble that kept resizing a window the user had already
  grabbed again, because no list named it.
- **A window handle we touched must be evicted when the window dies.**
  `RenderQueue::removeWindow(id)` drops both the pending state and the composed alpha record.
  Without it a recycled window id inherits a stranger`s opacity.

A third invariant came with them. **Opacity is composed, never absolute.** `RenderQueue` holds
a base the user chose times any number of named modifier layers, and only it computes the
committed value; `setAlpha()` remains for surfaces we own ourselves, where one owner is
guaranteed by construction. Every feature used to write an absolute, so anything that finished
by clearing transparency silently destroyed the opacity another feature had asked for.
**One owner per layer name** - the compiler cannot enforce it. Names in use on both platforms:
`drag`, `ghost`, `breathe`, `depth`, `open`, `gravity`.

### Wayland strategy

A Wayland client cannot move another window, set its opacity, read the global pointer, or grab
keys. So the daemon never tries: it computes, then publishes over D-Bus, and a compositor
extension applies the result.

Service `org.tweakforeveryone.Daemon` at `/org/tweakforeveryone/Daemon`:

| Member | Signature | Direction |
| --- | --- | --- |
| `Ping` | method | in |
| `SetWindowGeometry` | signal `(u windowId, i x, i y, i width, i height)` | daemon -> extension |
| `SetWindowAlpha` | signal `(u windowId, d alpha)` | daemon -> extension |
| `WeatherUpdated` | signal `(s weather)` | daemon -> extension |

**This contract is duplicated** — as Qt annotations in `src/platform/wayland/DBusDaemon.h` and
as a literal XML string in `src/platform/gnome/extension.js`. Treat `DBusDaemon.h` as
authoritative and update the extension to match; a KWin script would be a third copy, so
generating all of them from one file is the better fix.

Only `WeatherUpdated` is currently emitted or handled. The geometry and alpha signals are
declared on both sides and wired on neither.

`WAYLAND-LIMITATIONS.md` closes with an explicit refusal to bypass Wayland security via
`LD_PRELOAD`, running as root on `/dev/input`, or abusing accessibility APIs. **Keep that
constraint.** If a feature cannot be done through a supported compositor API, it is documented
as unsupported, not hacked in.

## Per-desktop notes

| Target | Session | Path |
| --- | --- | --- |
| **Linux Mint / Cinnamon** | X11 | Native backend for window management, no extension needed. This is the simplest path to a working feature and the best place to start. A **Cinnamon extension is still required** for anything panel-level or actor-level (the taskbar clock, the taskbar wave) - a plain X11 client cannot reach those either. |
| **GNOME** | Wayland by default | Extension at `~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local`, enabled with `gnome-extensions enable`. |
| **KDE Neon / Plasma 6** | Wayland by default | Nothing exists, so this path is entirely inert - and what has to be written is a **compiled KWin plugin**, not the JS script these docs keep promising: the KWin scripting API cannot receive D-Bus signals at all, so a script could never have driven anything from the daemon. |

**Plasma 6 renamed the tooling.** On KDE Neon (Plasma 6) `kpackagetool5` and `qdbus` are
`kpackagetool6` and `qdbus6`. `install.sh` now detects both and falls back to the 5 names;
`INSTALLATION.md` already documented the correct ones. Keep the detection rather than picking a
side - one script has to serve Plasma 5 and 6.

## Traps

- **`install.sh` must stay LF.** The repository's `.gitattributes` pins several types to CRLF
  for the Windows motion-proof check. A CRLF shebang fails on Linux with
  `bad interpreter: /usr/bin/env bash^M`, and it fails only at run time on a real Linux box —
  never on the machine that committed it. Verify with `git ls-files --eol linux/install.sh`.
- **No module filename here may contain an underscore** if it is ever shipped by the Windows
  installer path — that constraint belongs to `build/Setup.cs`. It does not currently apply to
  `linux/`, but do not assume the two trees are packaged the same way.
- **CMake does not expand `~`.** The `install(DIRECTORY ... DESTINATION ~/...)` rules create a
  literal `~` directory. Per-user files should be placed by `install.sh`, not by CMake.
- **GNOME extension API changed at 45.** `metadata.json` declares `shell-version` 42-46 while
  the code uses ESM `export default class`, which is 45+ only. Shell 42-44 need the old
  `imports.misc.extensionUtils` / `init()` form.
- **The frame period is 16 ms here and 15 ms on Windows.** That is not a typo on the Windows
  side: it is a measured compensation for the ~15.6 ms Windows timer tick, documented with
  benchmarks in the AHK source. Whether Linux needs the same trick is untested. Do not
  "harmonise" the two without measuring.
- **`AnimationScheduler` runs its own `std::thread`** while `RenderQueue` is mutex-guarded and
  `DBusDaemon` lives on the Qt main thread. Anything reaching from the frame loop into Qt
  objects needs to cross threads properly.

## Defects to be aware of

Recorded so they are not rediscovered. Struck-through entries have been fixed and are kept
because the fix is easy to undo by accident. Full list with reproduction in
`docs/IMPLEMENTATION-AUDIT.md`.

- ~~**`Physics.h` easing is mathematically wrong.**~~ **Fixed.** It was
  `1.0f - (--t)*t*t*t*t`, which is `1 + (1-t)^5` and returns **2.0 at t=0**. It is now
  `1.0f + (--t)*t*t*t*t`. Kept in this list, struck through, so nobody "corrects" the sign
  back after reading the expression without evaluating it.
- ~~**`Physics.cpp` uses `std::sqrt` with no `<cmath>` include.**~~ **Fixed.**
- ~~**`Physics::calculateGlide` implements the wrong model.**~~ **Replaced.** The kinetic-friction
  resting-position solver is gone. `predictThrow()` extrapolates a release ballistically in px/s
  with a tunable gain, and `glideDurationMs()` sizes the animation from the distance, which is
  what the Windows side does. Neither has a caller yet: nothing captures drag-release velocity.
- ~~**`SnapGeometry` has no `cornerBoost`.**~~ **Fixed**, along with three other gaps against
  `SnapCore.ahk`: like-edge alignment (it only ever matched a window edge to the OPPOSITE
  obstacle edge, so two windows could never be aligned flush along the same side),
  perpendicular-overlap gating (every obstacle contributed to both axes, so a window at the top
  of the screen could snap to a window at the bottom), speed-adaptive reach, and edge hysteresis.
  Obstacle collection is still missing - nothing enumerates windows.
- ~~**`main.cpp` never constructs a `PlatformAdapter`**~~ **Fixed.** It now detects the session,
  builds the adapter, the `RenderQueue` and the `AnimationScheduler`, installs a log sink and
  tears them down in order. It still cannot reach a window, because `X11Adapter` is stubs.
- ~~**`install.sh`'s KDE branch aborts** under `set -e`~~ **Fixed.** Guarded on the payload
  existing, and it now detects `kpackagetool6`/`qdbus6` with a fallback to the Plasma 5 names.
- ~~**Composed alpha never emitted a neutral state.**~~ **Fixed.** `recomposeAlphaLocked` queued
  `composed()` - `1.0f` - for a neutral record, where Windows emits "Off". Fully opaque and
  still layered is not the same thing: on X11 it leaves `_NET_WM_WINDOW_OPACITY` set to
  `0xFFFFFFFF` rather than deleting the property. Alpha is now `AlphaCommand{off, value}`, and
  `off` is emitted only on the **structural** test - base 1.0 and zero layers - never because a
  product rounded to 1.0.
- ~~**A throwing animation callback killed the daemon.**~~ **Fixed.** The callback ran
  unguarded on a `std::thread` with no handler above it, so one exception called
  `std::terminate`. It is now caught, the animation is retired, and the failure is logged once
  per second per key through an injected sink - emitted **outside** the mutex, since a sink that
  touched the scheduler would otherwise deadlock.
- ~~**`RenderQueue::flush()` held its mutex across every adapter call.**~~ **Fixed** by the
  swap-and-release pattern from `RS_Apply`: the pending map is swapped for a fresh one under the
  lock and applied outside it, so a backend blocking on the X server or the session bus can no
  longer stall every producer in the process.
- **`X11Adapter` is still entirely stubs.** Every mutator returns `false` and every query
  returns empty - honestly, which is the change: `supports()` reports nothing as available, and
  `getWindowState()` no longer returns a hardcoded 800x600 rect that looked like a real answer.
- **KDE needs a compiled KWin plugin, not a script.** The KWin JS scripting API cannot receive
  D-Bus signals at all, so the `src/platform/kde/` script this tree keeps promising could never
  have worked. Budget a `kwin_add_plugin` target.
- **Cinnamon needs its own extension.** Mint/Cinnamon is the primary X11 target, but panel-level
  and actor-level features - the taskbar clock, the taskbar wave - are not reachable from a
  plain X11 client either. That is a fourth backend surface nothing in these docs accounts for.
- **The D-Bus contract is one-way.** `DBusDaemon` declares signals only, daemon to extension, so
  an extension has no way to report window lists, hotkey presses or drag events back. Every
  Wayland feature is blocked by construction, not merely unwritten.

## Docs

`docs/IMPLEMENTATION-AUDIT.md` (what exists — start here), `docs/ARCHITECTURE.md` (design),
`docs/FEATURE-MATRIX.md` (34 features x 5 environments, all planned),
`docs/WAYLAND-LIMITATIONS.md` (why the D-Bus split exists; the strongest doc here),
`docs/INSTALLATION.md` (per-distro dependencies and per-DE steps).

These are **not** shipped by the Windows installer, which has its own hardcoded five-document
payload list in `Install.ps1` and `build/Build-Installer.ps1`. Adding a doc here does not
change that, and should not.
