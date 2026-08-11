# Feature Matrix

> **Nothing in this table is implemented.** Every row's Status column reads *Planned*, and that
> is accurate — there is currently no code path from any input to any window on any desktop.
> The ✅ / 🔌 marks describe the **intended mechanism** for each environment, not present-day
> support. `IMPLEMENTATION-AUDIT.md` records what actually exists.
>
> The one feature that does work end to end — the GNOME panel clock with weather — is not a
> window-management feature and is deliberately absent from this table.

The following table documents every feature present in the original Windows implementation and its intended status across Linux desktop environments and protocols.

Desktop columns name the three supported targets: **Cinnamon** (Linux Mint, X11),
**GNOME** (Wayland by default), and **KDE** (Plasma 6 / KDE Neon, Wayland by default).

| Feature | Windows implementation | Linux implementation | X11 | Wayland | Cinnamon (Mint) | GNOME | KDE (Neon) | Status |
| ------- | ---------------------- | -------------------- | --- | ------- | --------------- | ----- | ---------- | ------ |
| **Magnetic Snapping** | Screen-edge, monitor work-area, window-to-window snapping | Ported via daemon physics engine, applied via platform extensions. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Ice Glide** | Drag-release velocity physics, quintic ease-out, screen containment | Ported via daemon physics engine, applied via platform extensions. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Position Memory** | Save/restore pos/size based on application identity | Ported. Uses WM_CLASS on X11 and desktop-app-id on Wayland. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Always on Top** | Pin window above others | Native WM state (e.g. `_NET_WM_STATE_ABOVE`). | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Always on Bottom** | Pin window behind others | Native WM state (e.g. `_NET_WM_STATE_BELOW`). | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Proximity Ghost** | Fades window based on mouse distance | Custom daemon logic reading global pointer and setting window alpha. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Live PiP** | Promotes window to scaled PiP overlay | XComposite / KDE Effect / GNOME Extension texture scaling. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Roll-up (Shade)** | Rolls window up to title bar | Native WM shading (`_NET_WM_STATE_SHADED`) or custom geometry hack. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Minimize to Tray** | Hides window, adds tray icon | Unmaps window, registers SNI (StatusNotifierItem) tray icon. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Boss Key** | Hide everything and mute | Daemon mutes PipeWire/Pulse, minimizes all managed windows. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Center Window** | Geometry math | Daemon calculates center, extensions apply geometry. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Cycle Size** | 50% -> 75% -> 90% | Daemon calculates bounds, extensions apply geometry. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Next Monitor** | Hop relative size to next work area | Daemon geometry logic. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Numpad 3x3 Tiling**| Tile to grid corners/halves | Daemon geometry logic. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Maximize/Restore** | Toggle maximized state | Native WM state (`_NET_WM_STATE_MAXIMIZED_VERT`, etc). | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Undo Layout** | Revert last change | Daemon state history. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Restore All** | Unhide, unroll, unghost | Daemon recovery loop. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Transparency Wheel**| `Alt+Ctrl+Wheel` sets opacity | `_NET_WM_WINDOW_OPACITY` on X11, specific extension APIs on Wayland. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Focus/Cinema Mode** | Dims background windows | Set opacity on all other windows or draw overlay behind active window. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Smart Caps Lock** | Tap=Esc, Hold=Caps | `evdev` / `uinput` interception (requires `input` group or compositor help). | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Global Text Paste** | Paste as plain text | Clipboard manager interception. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Text Expander** | `@@time` etc | `evdev` interception and injection. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Spotlight Launcher**| Centered search/launch GUI | Qt6/QML frameless window, Wayland Layer Shell. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Quick Look** | Spacebar preview in file mgr | D-Bus integration with Nautilus/Dolphin + overlay window. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Mic Kill Switch** | Hard mute default mic + OSD | PipeWire/PulseAudio API + Layer Shell OSD. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Notifications** | OSD for state changes | Desktop notifications via `org.freedesktop.Notifications`. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Tray Functionality**| SNI Tray for toggles/settings | AppIndicator / SNI standard. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Grab & Pan** | Middle-click drag to pan | Requires global pointer capture (challenging on Wayland). | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Hot Corners** | Pointer hits corner -> action | Daemon reads global pointer or DE native hot corner integration. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Cursor Wrap** | Pointer wrap between monitors | Daemon sets pointer pos (requires X11 `XTest` / `wlr-virtual-pointer`). | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Active Window Border**| Draw border over active window | X11 overlay / Wayland Layer Shell / KWin effect. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Multi-Monitor Dimmer**| Dim inactive monitors | Transparent Layer Shell overlay on inactive monitors. | ✅ | ✅ | ✅ | ✅ | ✅ | Planned |
| **Magnetic Groups** | Snapped windows move together| Daemon topology tracking. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |
| **Stealth Panic Mode**| Triple Esc -> hide & mute | Daemon input interception + PipeWire mute + window minimization. | ✅ | 🔌 | ✅ | 🔌 | 🔌 | Planned |

### Legend

These marks describe the **planned mechanism**, not current support.

* ✅ = Achievable natively via X11, Wayland Layer Shell, or D-Bus, with no compositor extension.
* 🔌 = Requires a Desktop Environment Extension (GNOME Shell Extension, KWin Script). Will not work on barebones Wayland compositors without custom protocols.
* ❌ = Unsupported / Impossible on Linux.

### Reality check

| Environment | Extension needed | Extension state |
| --- | --- | --- |
| Cinnamon (Mint), and any X11 session | No — native XCB backend | `X11Adapter` is stubs; every method body is a comment |
| GNOME (Wayland) | Yes | Exists, but implements only the panel clock |
| KDE Neon / Plasma 6 (Wayland) | Yes | **No KWin script exists** — `src/platform/kde/` is empty |

Because the X11 backend is the shortest path to a working feature — it needs no compositor
cooperation — Cinnamon/Mint is the sensible environment to implement against first.

> Note on Roadmap Features: Features described in `FUTURE-ANIMATIONS.md` (e.g., Ripple Click, Morph Maximize) are excluded from this matrix unless they were confirmed implemented in the original source audit.
