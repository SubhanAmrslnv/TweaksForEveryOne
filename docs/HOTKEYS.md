# Hotkeys

All four tweaks live in one program. **Win + Ctrl** drives the window tweaks,
**Win + Alt** drives the taskbar.

| Hotkey | Action |
|---|---|
| **Win + Ctrl + W** | Open the **tools window** |
| **Win + Ctrl + T** | Pin / unpin the active window **always on top** |
| **Win + Ctrl + S** | **Magnetic snapping** on / off |
| **Win + Ctrl + M** | **Position memory** on / off |
| **Win + Alt + ↑** | Taskbar one step **taller** |
| **Win + Alt + ↓** | Taskbar one step **shorter** |
| **Win + Alt + 0** | **Restore** the original taskbar |

Every toggle shows a tray notification so you can tell which state you're in.
The tray icon menu has the same entries with tick marks, and double-clicking the
tray icon opens the tools window.

Taskbar steps are 24 → 28 → 32 → 36 → 40 → 44 → 48 px, 48 being the native
height. Below 32 px it clamps unless **Allow clipping** is ticked, and the
notification tells you the height it actually used — see `README.md` for why
that limit exists, and why the primary bar may refuse outright.

---

## Windows shortcuts these override

AutoHotkey hooks the keyboard before Windows does, so where a tweak claims a
combination, Windows' own use of it stops working while the program is running.

| Combination | Windows normally | Now |
|---|---|---|
| Win + Ctrl + S | Opens Speech Recognition (on builds that ship it) | Toggles snapping |
| Win + Ctrl + W | Nothing standard | Tools window |
| Win + Ctrl + T | Nothing standard | Always on top |
| Win + Ctrl + M | Nothing standard | Position memory |
| Win + Alt + ↑ ↓ 0 | Nothing standard | Taskbar height |

Deliberately **not** touched: `Win + Ctrl + ←/→` (virtual desktops),
`Win + ↑/↓` (maximise / minimise), `Win + Tab`, `Win + D`, `Win + E`.

## Changing a hotkey

Open `WindowTweaks.ahk`, edit the hotkey line, then restart the program from its
tray icon. The symbols are:

| Symbol | Key |
|---|---|
| `#` | Win |
| `^` | Ctrl |
| `!` | Alt |
| `+` | Shift |

So `#^t::` is Win+Ctrl+T. To move always-on-top to Win+Alt+P, change it to `#!p::`.

## If a hotkey does nothing

1. **Is the program running?** Look for its tray icon (check the hidden-icons
   arrow). If not, run `Window Tweaks.lnk`.
2. **Is the focused window elevated?** A non-elevated program cannot send keys
   to a window running as administrator. Run Window Tweaks as administrator too,
   or click a normal window first.
3. **Something else claimed the combination first.** Change it as above.
