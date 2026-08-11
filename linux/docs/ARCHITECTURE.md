# Architecture

> **This document describes design intent, not current behaviour.** Most of what follows is
> not implemented; the port does not build. See `IMPLEMENTATION-AUDIT.md` for the verified
> state of every component before relying on anything here.

The Linux port of Window Tweaks is designed around the principles of the original Windows implementation:
- **SOLID** & **DRY**
- Separation of concerns
- Single source of truth
- Centralized rendering pipeline and animation scheduling

However, because Linux is fragmented across Display Servers (X11 vs Wayland) and Desktop Environments (GNOME, KDE, Cinnamon), the architecture relies on a **Common Core** combined with **Platform Adapters**.

## High-Level Architecture

Legend: `[x]` present in the tree, `[~]` present but incomplete, `[ ]` **planned, does not exist**.

```text
linux/
├── src/
│   ├── core/                  # Platform-independent core logic
│   │   ├── AnimationScheduler # [x] 16ms animation multiplexer
│   │   ├── RenderQueue        # [x] Priority arbitration (ambient, anim, drag, user)
│   │   ├── WeatherFetcher     # [x] Panel clock weather source
│   │   ├── SnapGeometry       # [~] Snapping math; no cornerBoost, no obstacle collection
│   │   ├── Physics            # [~] Ice Glide math; wrong model, broken easing
│   │   ├── LayoutEngine       # [ ] 3x3 tiling, center, cycle sizes
│   │   ├── ConfigParser       # [ ] Centralized tuning registry
│   │   └── StateManager       # [ ] Position memory, toggle states
│   │
│   ├── platform/              # Desktop Environment & Display Server Adapters
│   │   ├── x11/               # [ ] Native XCB backend - signatures only, every body commented out
│   │   ├── wayland/           # [~] DBusDaemon; registers the service, emits weather only
│   │   ├── gnome/             # [~] GNOME Shell Extension; panel clock only
│   │   ├── kde/               # [ ] KWin Script - empty directory
│   │   └── common/            # [ ] Shared DBus, PipeWire, and Input logic
│   │
│   ├── ui/                    # [ ] Settings Application & System Tray - empty directory
│   │
│   └── tests/                 # [ ] Automated tests - directory does not exist
```

`config/` is likewise empty, so there is no Linux equivalent of `settings.ini` yet and tuning
constants are hardcoded at their use sites.

## The Render Pipeline

To prevent individual features from fighting over window state (e.g., Ice Glide trying to move a window while Proximity Ghost is trying to fade it), the Linux implementation preserves the **Central Render Pipeline**:

1. **Feature Action**: A hotkey is pressed or a drag is released.
2. **Desired State**: The feature calculates the desired state (e.g., target X/Y, target Alpha).
3. **Render Queue**: The feature pushes the target state into the `RenderQueue` with a specific priority:
   - `ambient` (Breathing)
   - `animation` (Ice Glide, Ghost)
   - `drag` (User actively dragging)
   - `user` (Hard user command, e.g., Tile)
4. **Arbitration**: If multiple features queue a state for the same window, the highest priority wins.
5. **Frame Commit**: Every 16ms, the `AnimationScheduler` triggers a `Flush()`. The `RenderQueue` sends the final arbitrated state to the Platform Adapter.
6. **Platform Adapter**: The X11 backend (or the GNOME/KWin extension) applies the actual geometry or opacity changes.

## Single Source of Truth

- **Snapping Math**: Lives entirely in `src/core/SnapGeometry`. Neither the X11 backend nor the GNOME extension calculates distances or intersections. *(Holds today, though the implementation is missing `cornerBoost` and nothing yet supplies it with obstacles.)*
- **Physics**: Velocity and easing logic belong in `src/core/Physics`. *(**Does not hold today.** The shipped code is a kinetic-friction resting-position model, not the duration-based lerp the Windows engine uses, and its `quinticEaseOut` helper is mathematically wrong — it returns 2.0 at t=0. See `IMPLEMENTATION-AUDIT.md`.)*
- **Configuration**: A single tuning registry should handle validation, defaults, bounds, and loading. *(**Not implemented.** No parser exists and `config/` is empty; constants such as `friction = 500.0f` are hardcoded.)*
- **D-Bus contract**: Currently duplicated between `platform/wayland/DBusDaemon.h` and `platform/gnome/extension.js`, with a third copy implied for KWin. This violates the rule above and should be generated from one definition.

## Display Server Strategy

### X11
The X11 adapter uses **XCB** and **XComposite**. It has full access to the window hierarchy, can intercept global hotkeys, and can set `_NET_WM_WINDOW_OPACITY` directly. The core daemon handles everything natively.

### Wayland
Wayland clients are sandboxed. Therefore, the daemon acts as a central **D-Bus Server**. 
- The GNOME Shell Extension or KWin Script subscribes to the D-Bus signals.
- When the daemon calculates that Window `0x123` needs to move to `[X, Y]` with opacity `0.8`, it broadcasts this via D-Bus.
- The compositor extension applies the change natively.
- Conversely, when the user presses a feature-toggle hotkey such as `Shift+Alt+S` on Wayland, the compositor extension intercepts it and signals the daemon. (Hotkeys follow the Windows scheme: `Ctrl+Alt+<key>` acts on the active window, `Shift+Alt+<key>` toggles a feature.)

### What actually runs on this path today

One feature is wired end to end, and it is not a window-management feature:

```text
WeatherFetcher (QNetworkAccessManager + QTimer)
  -> DBusDaemon emits WeatherUpdated(s)
    -> extension.js rewrites the GNOME date-menu label with time | date | weather
```

This mirrors the Windows Custom Taskbar Clock. The `SetWindowGeometry` and `SetWindowAlpha`
signals are declared on both ends of the bus and emitted by neither, so no window is moved or
faded on any desktop.
