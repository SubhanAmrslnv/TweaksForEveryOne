# Wayland Limitations & Architecture

> The constraints described here are properties of Wayland and are accurate. The *support
> levels* in the table below are the intended design — none of them are implemented yet, and
> the KWin script referred to throughout does not exist. See `IMPLEMENTATION-AUDIT.md`.

Wayland fundamentally changes the window management paradigm compared to X11. Under Wayland, the compositor (GNOME Shell, KWin, Sway) is the absolute authority over rendering, input, and window placement. Regular client applications operate in a sandboxed manner:
- They do not know their absolute position on the screen.
- They cannot move, resize, or alter the opacity of other windows.
- They cannot intercept global input events without an explicit protocol or compositor extension.

Due to these strict security policies, a standalone "Window Tweaks" daemon cannot function natively under Wayland. We must explicitly integrate with the compositor.

## Architectural Approach

The Linux implementation uses a **Core Daemon + Extension** model:
1. **Daemon (`tweaksd`)**: A background process handling physics (Ice Glide), snapping math, configuration parsing, and the 16ms animation scheduler.
2. **X11 Backend**: For X11 (including Cinnamon and Xorg sessions of KDE/GNOME), the daemon communicates directly with the X server (via XCB) to manipulate windows and intercept input.
3. **Wayland Extensions**: For Wayland, the daemon communicates over D-Bus with a compositor-specific extension (e.g., GNOME Shell Extension, KWin Script). The extension provides the raw window handles, acts as the "renderer" by applying the geometries computed by the daemon, and intercepts global hotkeys.

Hotkeys follow the Windows scheme, which is **one chord and no second tier**: every global
hotkey is `Shift+Alt+<key>`, whether it acts on the active window or toggles a feature. The sole
exception is `Ctrl+Alt+V` for plain-text paste. (A `Ctrl+Alt` tier was described here previously;
it was removed on the Windows side in commit `3dadac4` and no longer exists. `docs/HOTKEYS.md`
in the repository root is the source of truth.) On Wayland the compositor extension must grab
these and signal the daemon, since a client cannot grab keys for itself.

The bus is `org.tweakforeveryone.Daemon` at `/org/tweakforeveryone/Daemon`, carrying
`SetWindowGeometry(u,i,i,i,i)`, `SetWindowAlpha(u,d)` and `WeatherUpdated(s)`. Only the last of
those is currently emitted by the daemon or handled by any extension.

## Feature Status on Wayland

| Feature | Support Level | Implementation Details |
|---------|---------------|-------------------------|
| **Magnetic Snapping** | 🔌 Desktop-specific | Impossible for a normal Wayland client. Requires the compositor extension to push window geometries back to the daemon, let the daemon compute the snap, and then have the extension apply the new geometry. |
| **Ice Glide** | 🔌 Desktop-specific | The extension must detect the mouse release event and window velocity, pass it to the daemon, which then loops and pushes frame-by-frame geometry updates to the extension via D-Bus. |
| **Position Memory** | 🔌 Desktop-specific | Relies on the extension to report `desktop-app-id` (since WM_CLASS doesn't exist uniformly) and apply restored positions upon window creation. |
| **Always on Top / Bottom** | ✅ Fully supported | Supported via standard xdg-shell / Wayland protocols, or delegated to the extension. |
| **Ghost Mode / Breathing** | 🔌 Desktop-specific | Setting arbitrary opacity for other windows requires compositor privileges. Must be done by the extension. |
| **Live PiP** | 🔌 Desktop-specific | A normal Wayland client cannot capture the texture of another window. The compositor extension must draw the PiP texture. |
| **Roll-up (Shade)** | 🔌 Desktop-specific | Requires the extension to resize the window and clip its rendering. |
| **Minimize to Tray** | ✅ Fully supported | Uses the standard `StatusNotifierItem` (AppIndicator) D-Bus API, which works on Wayland (with DE support). |
| **Boss Key** | 🔌 Desktop-specific | The audio mute is handled via PipeWire (fully supported). Hiding all windows must be executed by the compositor extension. |
| **Window Tiling/Sizing** | 🔌 Desktop-specific | The extension applies the geometry changes. |
| **Transparency Wheel** | 🔌 Desktop-specific | Requires the extension to intercept the modifier+wheel event and set the target window's opacity. |
| **Focus/Cinema Mode** | 🔌 Desktop-specific | Requires the extension to dim all other windows or draw an overlay behind the active window. |
| **Smart Caps Lock** | 🔌 Desktop-specific | Input interception. Can be done via `evdev` (requires root or `input` group), or more safely via the compositor extension. |
| **Spotlight Launcher**| ✅ Fully supported | Can be implemented natively via `wlr-layer-shell` or standard Wayland popups, depending on the DE. |
| **Mic Kill Switch** | ✅ Fully supported | PipeWire API works perfectly on Wayland. |
| **Grab & Pan** | 🔌 Desktop-specific | Intercepting a middle click on a window and translating it to a pan requires compositor-level input routing. |
| **Hot Corners** | 🔌 Desktop-specific | Requires reading the global pointer position. Normal Wayland clients cannot read pointer coordinates outside their own surfaces. |
| **Cursor Wrap** | 🔌 Desktop-specific | Normal Wayland clients cannot warp the pointer. Requires compositor intervention. |

## Unsupported without Compositor Extension
To reiterate, running the daemon on Wayland *without* a corresponding GNOME Shell Extension or KWin Script will result in the following features failing completely:
- Magnetic Snapping
- Ice Glide
- Window Tiling / Centering / Resizing
- Ghost Mode / Breathing / Transparency changes
- Hot Corners & Cursor Wrap
- Grab & Pan

## Security Hacks
We explicitly **refuse** to bypass Wayland security using unsafe hacks (e.g., LD_PRELOAD injection, running as root to read `/dev/input` globally without user consent, or abusing accessibility APIs). All Wayland support is implemented through officially supported compositor extension APIs.
