# Hotkeys

Everything lives in one program, and **Ctrl + Alt** or **Shift + Alt** drives all of it, in two tiers:

- **Ctrl + Alt + key** — *do something* to the active window.
- **Shift + Alt + key** — *turn a feature on or off*.

## Always available

| Hotkey | Action |
|---|---|
| **Ctrl + Alt + W** | Open the **settings window** |
| **Shift + Alt + S** | **Magnetic snapping** on / off |
| **Shift + Alt + M** | **Position memory** on / off |
| **Shift + Alt + E** | **Breathing windows** on / off |
| **Shift + Alt + F** | **Focus mode** (cinema) on / off |
| **Ctrl + Alt + T** | Pin / unpin the active window **always on top** |
| **Ctrl + Alt + R** | **Roll up** / unroll the active window |
| **Ctrl + Alt + H** | **Minimize to tray** |
| **Ctrl + Alt + Esc** | **Boss key** — hide everything and mute |
| **Ctrl + Alt + Wheel** | **Transparency** of the active window |
| **Alt + F4** | Close, with the gravity-drop animation |

## Window layout

| Hotkey | Action |
|---|---|
| **Ctrl + Alt + C** | **Centre** the active window, keeping its size |
| **Ctrl + Alt + U** | **Cycle its size**: 50% → 75% → 90% of the work area, centred |
| **Ctrl + Alt + J** | Move it to the **next monitor**, keeping its relative size and position |
| **Ctrl + Alt + Numpad 1–9** | **Tile** to that cell of a 3×3 grid — see below |
| **Ctrl + Alt + Numpad 0** | **Maximize / restore** |
| **Ctrl + Alt + Z** | **Undo** the last layout change to this window |

The tiling grid is shaped like the numeric keypad, so the key you press is where
the window goes. It works with NumLock on or off.

```
 7  top-left ¼   8  top half      9  top-right ¼
 4  left half    5  centred half  6  right half
 1  bottom-left ¼ 2 bottom half   3  bottom-right ¼
```

Left and right halves are deliberately the only ones without an arrow-key alias:
Windows' own **Win + ←/→** already does that.

## Utility

| Hotkey | Action |
|---|---|
| **Ctrl + Alt + X** | Reset the active window to **fully opaque** |
| **Ctrl + Alt + Y** | **Restore everything** — unroll, un-ghost and un-hide every window the program is holding |
| **Shift + Alt + R** | Restart the program |
| **Shift + Alt + Q** | Quit the program |

`Ctrl + Alt + Y` is the panic key. If a window is rolled up to its title bar,
ghosted so clicks pass through it, or hidden into the tray, this brings all of
them back in one press.

## Feature toggles

Each of these was previously reachable only through the settings window. The new
state is saved, so it survives a restart.

| Hotkey | Feature |
|---|---|
| **Shift + Alt + C** | Hot corners |
| **Shift + Alt + A** | Smart active border |
| **Shift + Alt + W** | Infinite cursor wrap |
| **Shift + Alt + D** | Multi-monitor focus dimmer |
| **Shift + Alt + T** | Smart auto-hide taskbar |
| **Shift + Alt + G** | Magnetic window groups |
| **Shift + Alt + P** | Universal grab & pan |

## Only when their feature is switched on

| Hotkey | Action | Setting |
|---|---|---|
| **Ctrl + Alt + B** | Always on bottom (desktop widget) | Power Features |
| **Ctrl + Alt + G** | Proximity ghost window | Power Features |
| **Ctrl + Alt + P** | Live PiP thumbnail | Power Features |
| **Ctrl + Alt + L** | Spotlight launcher | Power Features |
| **Ctrl + Alt + A** | Microphone mute / unmute | System & Media |
| **Ctrl + Alt + I** | In Explorer: Quick Look preview | Power Features |
| **Ctrl + Alt + V** | Paste as plain text | System & Media |
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

The three double-tap gestures keep working; `Ctrl + Alt + L`, `A` and `I` are
simply an unambiguous way to reach the same actions, which matters because a
double-tap has to be told apart from two ordinary shortcuts pressed in a row.

Every toggle shows a tray notification so you can tell which state you're in.
The tray icon menu has entries for snapping, position memory and breathing with
tick marks, and double-clicking the tray icon opens the settings window.

`Ctrl + Alt + Wheel` is the one exception to the notification rule: it shows a
single tray tip once you stop scrolling, not one per notch.

---

## Windows shortcuts these override

AutoHotkey hooks the keyboard before Windows does, so where a tweak claims a
combination, Windows' own use of it stops working while the program is running.

| Combination | Windows normally | Now |
|---|---|---|
| Win + Alt + D | Opens the calendar flyout | Drops the curtain (CurtainDrop feature) |
| Alt + F4 | Closes the window | Still closes it, after a 320 ms animation |
| CapsLock | Toggles Caps | Tap sends Esc / Backspace, hold toggles Caps |

Unlike the previous `Win + Ctrl` scheme, this new hotkey design explicitly avoids `Win` modifiers entirely (except for very specific exceptions like `Win + Alt + D`) to prevent conflicting with or feeling too similar to standard Windows 11 system shortcuts.

## Changing a hotkey

Open `WindowTweaks.ahk`, edit the hotkey line, then restart the program from its
tray icon. The symbols are:

| Symbol | Key |
|---|---|
| `#` | Win |
| `^` | Ctrl |
| `!` | Alt |
| `+` | Shift |

So `^!t::` is Ctrl+Alt+T. To move always-on-top to Win+Alt+P, change it to `#!p::`.

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
