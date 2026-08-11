# CLAUDE.md — Linux port

This file provides guidance to Claude Code (claude.ai/code) when working with the Linux port
in `linux/`. The root `..\CLAUDE.md` covers the Windows implementation; the two share **no
code**, only design.

## Read this first

**This is an early scaffold. It does not build, and if it built it would not manage windows.**

`linux/docs/IMPLEMENTATION-AUDIT.md` is the authority on what exists — it was written against
the files and lists every gap. `ARCHITECTURE.md`, `FEATURE-MATRIX.md` and
`WAYLAND-LIMITATIONS.md` describe *intent*: sound design, not current behaviour. An earlier
revision of the audit claimed the port was complete across the board; that is why this warning
is at the top of every one of those files now. **Do not add a completion claim to any doc here
without pointing at the code that backs it.**

Roughly: ~1,100 lines here, of which the platform layer is 0% implemented, against ~11,600
lines of shipping AutoHotkey on the Windows side.

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

**The build fails at configure time, for two independent reasons.** Both are in
`CMakeLists.txt`:

1. `add_library(TweakUI src/ui/SettingsWindow.cpp src/ui/TrayIcon.cpp)` — `src/ui/` is an
   empty directory. CMake reports "Cannot find source file".
2. `find_package(XCB REQUIRED COMPONENTS ...)` — CMake ships no `FindXCB.cmake` and this
   repository provides none. Use `pkg_check_modules` via `FindPkgConfig` instead, or vendor a
   finder into `cmake/`.

There is no test runner, no linter and no CI. `find linux -type d -empty` is the fastest
honest status check in the tree.

## Architecture

Dependency flow is one-way: **`core/` -> `PlatformAdapter` -> backend**. `core/` is
platform-independent and must never include a platform or Qt GUI header; it is the only place
geometry and physics live. A backend applies state; it never computes it.

| Path | Role |
| --- | --- |
| `src/core/AnimationScheduler.*` | One thread, one frame loop, keyed callbacks. `registerAnimation(key, cb)` overwrites the same key; `cb` returns `false` to retire. Calls `RenderQueue::flush()` once per frame. |
| `src/core/RenderQueue.*` | The only thing that talks to a `PlatformAdapter`. Coalesces per window, arbitrates by priority, batches. |
| `src/core/SnapGeometry.*` | `computeSnap(moving, obstacles, workArea, &dx, &dy)`. Each axis resolved independently. |
| `src/core/Physics.*` | Glide math. Currently a friction model — see *Defects*. |
| `src/core/WeatherFetcher.*` | `QNetworkAccessManager` + `QTimer`, emits `weatherUpdated`. |
| `src/core/PlatformAdapter.h` | The backend contract. `init`, `pollEvents`, `setWindowGeometry`, `setWindowAlpha`, `setWindowState`, `beginBatch`/`commitBatch`, `getWindowState`, `getActiveWindow`. |
| `src/platform/x11/` | XCB backend. Stubs only. |
| `src/platform/wayland/` | `DBusDaemon` — the Wayland strategy is D-Bus, not direct protocol access. |
| `src/platform/gnome/` | GNOME Shell extension (GJS, ESM). Panel clock only. |
| `src/platform/kde/` | KWin script. **Empty.** |
| `src/ui/` | Qt6 settings window + SNI tray. **Empty.** |
| `config/` | Default configuration. **Empty** — tuning values are hardcoded today. |

Namespaces: `TweakCore` for `core/`, `TweakPlatform` for backends.

### Correspondence to the Windows engine

The three pillars were ported deliberately; keep them aligned when changing either side.

| Linux | Windows | Invariant that must hold on both |
| --- | --- | --- |
| `RenderQueue` | `src/RenderCore.ahk` | Nothing outside this layer mutates window state. Priority arbitration is **per flush**: `Ambient(0) < Animation(1) < Drag(2) < User(3)` mirrors `RS_PRI_*` 10/20/30/40. |
| `AnimationScheduler` | `src/AnimationScheduler.ahk` | Produce from every callback, then flush **exactly once** per frame. A callback that always returns `true` is a polling monitor and does not belong here. |
| `SnapGeometry` | `src/SnapCore.ahk` | Pure geometry, no side effects. Axes resolve independently. |
| `Physics` | `Glide()` in `src/WindowTweaks.ahk` | Parameterise on elapsed time, never on frame count. |

Two invariants from the Windows side are **not yet expressible here** and will matter as soon
as the backend is real: two animations must never drive the same property of the same window at
the same priority, and any window handle we touched must be evicted from cached state when the
window dies.

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
| **Linux Mint / Cinnamon** | X11 | Native backend, no extension needed. This is the simplest path to a working feature and the best place to start. |
| **GNOME** | Wayland by default | Extension at `~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local`, enabled with `gnome-extensions enable`. |
| **KDE Neon / Plasma 6** | Wayland by default | KWin script at `~/.local/share/kwin/scripts/tweakforeveryone`. **No script exists**, so this path is entirely inert. |

**Plasma 6 renamed the tooling.** `install.sh` and `INSTALLATION.md` still use the Plasma 5
names `kpackagetool5` and `qdbus`; on KDE Neon (Plasma 6) these are `kpackagetool6` and
`qdbus6`. Support both, or detect.

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

Documented rather than fixed, so they are not rediscovered. Full list with reproduction in
`docs/IMPLEMENTATION-AUDIT.md`.

- **`Physics.h` easing is mathematically wrong.** `1.0f - (--t)*t*t*t*t` is `1 + (1-t)^5`,
  returning **2.0 at t=0**. Windows uses `1 - (1-t)**5`. The fix is the sign:
  `1.0f + (--t)*t*t*t*t`.
- **`Physics.cpp` uses `std::sqrt` with no `<cmath>` include** — a compile error on its own.
- **`Physics::calculateGlide` implements the wrong model** — kinetic friction with a hardcoded
  `friction = 500.0f`, where Windows lerps toward a known target over a computed duration.
- **`SnapGeometry` has no `cornerBoost`**, so the corner-pull behaviour that defines the
  Windows feel is absent.
- **`main.cpp` never constructs a `PlatformAdapter`**, so nothing can reach a window.
- **`install.sh`'s KDE branch aborts** under `set -e`, copying from an empty directory.

## Docs

`docs/IMPLEMENTATION-AUDIT.md` (what exists — start here), `docs/ARCHITECTURE.md` (design),
`docs/FEATURE-MATRIX.md` (34 features x 5 environments, all planned),
`docs/WAYLAND-LIMITATIONS.md` (why the D-Bus split exists; the strongest doc here),
`docs/INSTALLATION.md` (per-distro dependencies and per-DE steps).

These are **not** shipped by the Windows installer, which has its own hardcoded five-document
payload list in `Install.ps1` and `build/Build-Installer.ps1`. Adding a doc here does not
change that, and should not.
