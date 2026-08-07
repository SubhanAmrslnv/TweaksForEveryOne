# Hotkeys

Everything lives in one program, and **Win + Ctrl** drives all of it, in two tiers:

- **Win + Ctrl + key** — *do something* to the active window.
- **Win + Ctrl + Shift + key** — *turn a feature on or off*.

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

## Window layout

| Hotkey | Action |
|---|---|
| **Win + Ctrl + K** | **Centre** the active window, keeping its size |
| **Win + Ctrl + U** | **Cycle its size**: 50% → 75% → 90% of the work area, centred |
| **Win + Ctrl + J** | Move it to the **next monitor**, keeping its relative size and position |
| **Win + Ctrl + Numpad 1–9** | **Tile** to that cell of a 3×3 grid — see below |
| **Win + Ctrl + Numpad 0** | **Maximize / restore** |
| **Win + Ctrl + ↑ / ↓** | Top half / bottom half (laptop alias for Numpad 8 / 2) |
| **Win + Ctrl + Z** | **Undo** the last layout change to this window |

The tiling grid is shaped like the numeric keypad, so the key you press is where
the window goes. It works with NumLock on or off.

```
 7  top-left ¼   8  top half      9  top-right ¼
 4  left half    5  centred half  6  right half
 1  bottom-left ¼ 2 bottom half   3  bottom-right ¼
```

Left and right halves are deliberately the only ones without an arrow-key alias:
Windows' own **Win + ←/→** already does that, and **Win + Ctrl + ←/→** belongs to
virtual desktops.

## Utility

| Hotkey | Action |
|---|---|
| **Win + Ctrl + X** | Reset the active window to **fully opaque** |
| **Win + Ctrl + Y** | **Restore everything** — unroll, un-ghost and un-hide every window the program is holding |
| **Win + Ctrl + Shift + R** | Restart the program |
| **Win + Ctrl + Shift + Q** | Quit the program |

`Win + Ctrl + Y` is the panic key. If a window is rolled up to its title bar,
ghosted so clicks pass through it, or hidden into the tray, this brings all of
them back in one press.

## Feature toggles

Each of these was previously reachable only through the settings window. The new
state is saved, so it survives a restart.

| Hotkey | Feature |
|---|---|
| **Win + Ctrl + Shift + C** | Hot corners |
| **Win + Ctrl + Shift + A** | Smart active border |
| **Win + Ctrl + Shift + W** | Infinite cursor wrap |
| **Win + Ctrl + Shift + D** | Multi-monitor focus dimmer |
| **Win + Ctrl + Shift + T** | Smart auto-hide taskbar |
| **Win + Ctrl + Shift + G** | Magnetic window groups |
| **Win + Ctrl + Shift + P** | Universal grab & pan |

## Only when their feature is switched on

| Hotkey | Action | Setting |
|---|---|---|
| **Win + Ctrl + B** | Always on bottom (desktop widget) | Power Features |
| **Win + Ctrl + G** | Proximity ghost window | Power Features |
| **Win + Ctrl + P** | Live PiP thumbnail | Power Features |
| **Win + Ctrl + L** | Spotlight launcher | Power Features |
| **Win + Ctrl + A** | Microphone mute / unmute | System & Media |
| **Win + Ctrl + I** | In Explorer: Quick Look preview | Power Features |
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

The three double-tap gestures keep working; `Win + Ctrl + L`, `A` and `I` are
simply an unambiguous way to reach the same actions, which matters because a
double-tap has to be told apart from two ordinary shortcuts pressed in a row.

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
| Win + Ctrl + K / U / J / Z / X / Y / A / I / L / Numpad / ↑ / ↓ | Nothing standard | As listed above |

Deliberately **not** touched, in either tier: `Win + Ctrl + ←/→` (virtual
desktops), `Win + Ctrl + D` (new virtual desktop), `Win + Ctrl + Q` (Quick
Assist), `Win + Ctrl + C` (colour filters), `Win + Ctrl + N` and
`Win + Ctrl + Enter` (Narrator), `Win + Ctrl + O` (on-screen keyboard),
`Win + Ctrl + Space` (previous input method), `Win + Ctrl + Shift + B` (reset
the graphics driver), `Win + Ctrl + <digit>`, `Win + ↑/↓` (maximise / minimise),
`Win + Tab`, `Win + D`, `Win + E`.

Those exclusions are why the new keys look scattered — `Win + Ctrl + C` would
have been the obvious choice for "centre", but it is Windows' accessibility
colour-filter toggle, so centring is on **K** instead.

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
