# Hotkeys

Everything lives in one program, and **Win + Ctrl** drives all of it.

## Always available

| Hotkey | Action |
|---|---|
| **Win + Ctrl + W** | Open the **settings window** |
| **Win + Ctrl + S** | **Magnetic snapping** on / off |
| **Win + Ctrl + M** | **Position memory** on / off |
| **Win + Ctrl + E** | **Breathing windows** on / off |
| **Win + Ctrl + F** | **Focus mode** (cinema) on / off |
| **Win + Ctrl + T** | Pin / unpin the active window **always on top** |
| **Win + Ctrl + R** | **Roll up** / unroll the active window |
| **Win + Ctrl + H** | **Minimize to tray** |
| **Win + Ctrl + Esc** | **Boss key** — hide everything and mute |
| **Win + Ctrl + Wheel** | **Transparency** of the active window |
| **Alt + F4** | Close, with the gravity-drop animation |

## Only when their feature is switched on

| Hotkey | Action | Setting |
|---|---|---|
| **Win + Ctrl + B** | Always on bottom (desktop widget) | Power Features |
| **Win + Ctrl + G** | Proximity ghost window | Power Features |
| **Win + Ctrl + P** | Live PiP thumbnail | Power Features |
| **Ctrl + Win + V** | Paste as plain text | System & Media |
| **Double-tap Alt** | Microphone mute / unmute | System & Media |
| **Double-tap Ctrl** | Spotlight launcher | Power Features |
| **CapsLock** | Tap = Esc or Backspace, hold = Caps | System & Media |
| **Alt + LeftDrag** | Move a window from anywhere | Window Management |
| **Alt + RightDrag** | Resize from the nearest edge | Window Management |
| **Middle-click** | Title bar: close or roll up; hold: grab & pan | Window Management |
| **Ctrl + G** | In a Save/Open dialog: jump to the last Explorer folder | Power Features |
| **Space** | In Explorer: Quick Look preview | Power Features |
| **Wheel / Middle-click** over the taskbar | Volume / mute | System & Media |
| **@@mail, @@tel, @@date, @@time** | Text expander snippets | System & Media |

Every toggle shows a tray notification so you can tell which state you're in.
The tray icon menu has entries for snapping, position memory and breathing with
tick marks, and double-clicking the tray icon opens the settings window.

`Win + Ctrl + Wheel` is the one exception to the notification rule: it shows a
single tray tip once you stop scrolling, not one per notch.

---

## Windows shortcuts these override

AutoHotkey hooks the keyboard before Windows does, so where a tweak claims a
combination, Windows' own use of it stops working while the program is running.

| Combination | Windows normally | Now |
|---|---|---|
| Win + Ctrl + S | Opens Speech Recognition (on builds that ship it) | Toggles snapping |
| Win + Ctrl + G | Opens the Xbox Game Bar overlay on some builds | Ghost window (only while that feature is on) |
| Alt + F4 | Closes the window | Still closes it, after a 320 ms animation |
| CapsLock | Toggles Caps | Tap sends Esc / Backspace, hold toggles Caps |
| Win + Ctrl + W / T / M / E / F / R / H / B / P / Esc | Nothing standard | As listed above |

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

Note that many hotkeys sit inside a `#HotIf <FeatureEnabled>` block, which is
what makes them exist only while that feature is ticked. Keep the hotkey inside
its block when you move it, or it will fire even with the feature switched off.

## If a hotkey does nothing

1. **Is the program running?** Look for its tray icon (check the hidden-icons
   arrow). If not, run `Window Tweaks.lnk`.
2. **Is the focused window elevated?** A non-elevated program cannot send keys
   to a window running as administrator. Run Window Tweaks as administrator too,
   or click a normal window first.
3. **Something else claimed the combination first.** Change it as above.
