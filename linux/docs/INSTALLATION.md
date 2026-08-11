# Installation Guide

> **The daemon does not currently build.** `cmake` fails at configure time for two independent
> reasons, both listed under *Known build failures* below. This guide is accurate about the
> intended process, but you will not get a working `tweaksd` from it today. See
> `IMPLEMENTATION-AUDIT.md` for what exists.

This guide covers building and installing the native Linux port of **TweakForEveryone** on its
three supported desktops: **Linux Mint (Cinnamon)**, **GNOME**, and **KDE Plasma 6 / KDE Neon**.

## Which path applies to you

The display server matters more than the distribution.

| Session | How the daemon reaches windows | Extension required |
| --- | --- | --- |
| **X11** (Linux Mint/Cinnamon default; "Xorg" login option on GNOME and Plasma) | Directly, via XCB | No |
| **Wayland** (GNOME and Plasma 6 default) | Indirectly, via D-Bus to a compositor extension | **Yes** |

Check yours:

```bash
echo "$XDG_SESSION_TYPE"      # x11 or wayland
echo "$XDG_CURRENT_DESKTOP"   # X-Cinnamon, GNOME, KDE
```

On Wayland, without the matching extension, the daemon cannot move, resize or fade any window —
this is a Wayland security property, not a bug. `WAYLAND-LIMITATIONS.md` explains it in full.

## Prerequisites

The daemon needs a C++20 compiler, CMake 3.16+, Qt6 (`Core`, `Gui`, `Widgets`, `DBus`,
`Network`) and the XCB development headers. On Debian-family systems the single `qt6-base-dev`
package provides all five Qt modules, `Network` included.

### Debian / Ubuntu / Linux Mint / KDE Neon

```bash
sudo apt update
sudo apt install build-essential cmake pkg-config \
    qt6-base-dev libgl1-mesa-dev \
    libxcb1-dev libxcb-composite0-dev libxcb-damage0-dev \
    libxcb-render0-dev libxcb-randr0-dev libxcb-xfixes0-dev
```

Notes:
- **Linux Mint 22** is built on Ubuntu 24.04 and **Mint 21** on Ubuntu 22.04; `qt6-base-dev` is
  available on both.
- **KDE Neon** tracks an Ubuntu LTS base, so this same list applies.
- `libgl1-mesa-dev` is needed by Qt6 Widgets even for a headless daemon build.

### Fedora / RHEL

```bash
sudo dnf install gcc-c++ cmake qt6-qtbase-devel \
    libxcb-devel xcb-util-devel
```

### Arch Linux

```bash
sudo pacman -S base-devel cmake qt6-base libxcb xcb-util
```

## Quick install

The included script detects your package manager and desktop, offers to build, and installs the
appropriate extension and an autostart entry. Every step prompts first.

```bash
chmod +x install.sh
./install.sh
```

Be aware of two rough edges: the `dnf` and `pacman` branches only print the distro name and
install nothing, and the KDE branch fails outright (see *KDE* below).

## Manual installation

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
sudo cmake --install build
```

### Known build failures

Both are in `CMakeLists.txt` and both stop configuration before compiling begins:

1. **Missing sources.** `add_library(TweakUI src/ui/SettingsWindow.cpp src/ui/TrayIcon.cpp)`
   references an empty directory. CMake reports *"Cannot find source file"*. Removing the
   `TweakUI` target and its entry in `target_link_libraries(tweaksd ...)` gets you past this.
2. **No XCB finder.** `find_package(XCB REQUIRED COMPONENTS ...)` needs a `FindXCB.cmake` that
   CMake does not ship and this repository does not provide. The usual fix is `pkg_check_modules`
   from `FindPkgConfig`.

Even after working around both, `Physics.cpp` fails to compile — it calls `std::sqrt` without
including `<cmath>` — and the resulting daemon would register its D-Bus service and manage no
windows, because `main.cpp` never constructs a platform adapter.

Also note the `install(DIRECTORY ... DESTINATION ~/...)` rules do not work as written: CMake
does not expand `~`, so these create a directory literally named `~`. Install per-user files
with `install.sh` instead.

## Desktop-specific setup

### Linux Mint (Cinnamon)

Cinnamon runs on X11, so **no extension is required** — the daemon is designed to drive windows
directly through XCB, and this is the shortest path to a working feature.

```bash
./build/tweaksd
```

`install.sh` reaches Mint through its fall-through branch ("DE is neither GNOME nor KDE,
assuming X11/Cinnamon"). There is no Cinnamon- or Muffin-specific code, and none is planned;
Cinnamon is supported as a generic X11 session.

Caveat: the X11 backend is entirely stubbed today, so nothing happens yet.

### GNOME

GNOME defaults to Wayland, so the Shell extension is required. To use the X11 path instead,
choose "GNOME on Xorg" at the login screen.

```bash
mkdir -p ~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local
cp -r src/platform/gnome/* ~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local/
gnome-extensions enable tweakforeveryone@linux.local
```

Then restart the Shell: log out and back in on Wayland, or `Alt+F2` -> `r` -> Enter on X11.

Two limitations worth knowing before you install it:

- The extension currently implements **only the panel clock and weather**. It declares the
  `SetWindowGeometry` and `SetWindowAlpha` D-Bus signals and handles neither, so no window
  management reaches GNOME.
- `metadata.json` declares `shell-version` `42`-`46`, but the code is written in the ESM style
  (`export default class`) introduced in **GNOME 45**. On Shell 42-44 it will fail to load
  despite the declared compatibility.

Check it loaded:

```bash
gnome-extensions info tweakforeveryone@linux.local
journalctl --user -b -o cat /usr/bin/gnome-shell | tail -50
```

### KDE Plasma 6 / KDE Neon

**There is no KWin script.** `src/platform/kde/` is an empty directory, so on a Plasma Wayland
session nothing will work, and `install.sh`'s KDE branch fails immediately — it runs
`cp -r src/platform/kde/*` on an empty directory under `set -e`.

When a script does exist, the Plasma 6 install is:

```bash
mkdir -p ~/.local/share/kwin/scripts/tweakforeveryone
cp -r src/platform/kde/* ~/.local/share/kwin/scripts/tweakforeveryone/
kpackagetool6 --type=KWin/Script -i ~/.local/share/kwin/scripts/tweakforeveryone
qdbus6 org.kde.KWin /KWin reconfigure
```

**Plasma 6 renamed these tools.** `install.sh` still calls the Plasma 5 names `kpackagetool5`
and `qdbus`, which do not exist on KDE Neon; use `kpackagetool6` and `qdbus6`. On a Plasma 5
system, keep the `5` names.

In the meantime, a Plasma **X11** session ("Plasma (X11)" at the login screen) is the only
usable path on KDE, since it needs no compositor extension.

## Autostart

`install.sh` writes `~/.config/autostart/tweaksd.desktop` so the daemon starts at login. There
is no systemd unit and no packaged `.desktop` file in the repository — the entry is generated at
install time.

To create it by hand:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/tweaksd.desktop <<'EOF'
[Desktop Entry]
Type=Application
Exec=tweaksd
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=TweakForEveryone Daemon
Comment=Native Linux daemon for window tweaks
EOF
```

## Uninstalling

There is no uninstall script.

```bash
sudo rm -f /usr/local/bin/tweaksd
rm -f ~/.config/autostart/tweaksd.desktop
rm -rf ~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local
rm -rf ~/.local/share/kwin/scripts/tweakforeveryone
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Cannot find source file: src/ui/SettingsWindow.cpp` | Expected — see *Known build failures*. |
| `Could not find a package configuration file provided by "XCB"` | Expected — no `FindXCB.cmake` exists. |
| `'sqrt' is not a member of 'std'` | `Physics.cpp` is missing its `<cmath>` include. |
| `bad interpreter: /usr/bin/env bash^M` | `install.sh` was checked out with CRLF endings. Run `dos2unix install.sh`, or fix `.gitattributes` to pin `*.sh` to `eol=lf`. |
| Errors finding Qt6 during CMake | Install `qt6-base-dev` (or your distro's equivalent). It provides Network too. |
| Snapping / glide do nothing on Wayland | Expected on every desktop today: the geometry signals are never emitted, and no compositor extension consumes them. |
| Snapping / glide do nothing on X11 | Expected: `X11Adapter` is entirely stubbed. |
| `kpackagetool5: command not found` on KDE Neon | Plasma 6 renamed it to `kpackagetool6` (and `qdbus` to `qdbus6`). |
