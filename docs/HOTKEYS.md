# Hotkeys

Every program-wide command is **Shift + Alt + key**. Commit `3dadac4` collapsed
the old `Win + Ctrl` scheme into this one chord. A handful of other keys exist,
each tied to a feature and listed below: `Ctrl + Alt + V`, `Alt + F4`,
`Win + Alt + D`, the clipboard keys, `Delete`, `CapsLock`, `Esc Esc Esc` and
mouse gestures.

This file is the reference the other documents defer to. The bindings live in the
`; ====== Hotkeys ======` block in `src\InputBindings.ahk`, plus the few declared
next to their feature (see **Changing a hotkey**). If a key changes, change it
there and here.

**Game Mode** (`Shift + Alt + F12`) switches off every hotkey and gesture below
except itself and the Stealth Panic triple-Esc.

## Always available

| Hotkey | Action |
|---|---|
| **Shift + Alt + W** | Open the **settings window** |
| **Shift + Alt + S** | **Magnetic snapping** on / off |
| **Shift + Alt + M** | **Position memory** on / off |
| **Shift + Alt + E** | **Breathing windows** on / off |
| **Shift + Alt + F** | **Focus mode** (cinema) on / off |
| **Shift + Alt + O** | Pin / unpin the active window **always on top** |
| **Shift + Alt + R** | **Roll up** / unroll the active window |
| **Shift + Alt + H** | **Minimize to tray** |
| **Shift + Alt + Esc** | **Boss key** — hide everything and mute |
| **Shift + Alt + Wheel** | **Transparency** of the active window |
| **Shift + Alt + F12** | **Game Mode** on / off - suspends effects and gestures while gaming |

## Window layout

| Hotkey | Action |
|---|---|
| **Shift + Alt + K** | **Centre** the active window, keeping its size |
| **Shift + Alt + U** | **Cycle its size**: 50% → 75% → 90% of the work area, centred |
| **Shift + Alt + N** | Move it to the **next monitor**, keeping its relative size and position |
| **Shift + Alt + Numpad 1–9** | **Tile** to that cell of a 3×3 grid — see below |
| **Shift + Alt + Numpad 0** | **Maximize / restore** |
| **Shift + Alt + ↑** / **↓** | Top half / bottom half (laptop alias for Numpad 8 / 2) |
| **Shift + Alt + Z** | **Undo** the last layout change to this window |

The tiling grid is shaped like the numeric keypad, so the key you press is where
the window goes.

```
 7  top-left ¼    8  top half      9  top-right ¼
 4  left half     5  centred half  6  right half
 1  bottom-left ¼ 2  bottom half   3  bottom-right ¼
```

Both names of every keypad key are bound (`Numpad7` and `NumpadHome`, and so on),
so tiling works with NumLock on or off.

Left and right halves are deliberately the only ones without an arrow-key alias:
Windows' own **Win + ←/→** already does that.

## Utility

| Hotkey | Action |
|---|---|
| **Shift + Alt + X** | Reset the active window to **fully opaque** |
| **Shift + Alt + Y** | **Restore everything** — unroll, un-ghost and un-hide every window the program is holding |
| **Shift + Alt + F5** | Restart the program |
| **Shift + Alt + F6** | Quit the program |

`Shift + Alt + Y` is the panic key. If a window is rolled up to its title bar,
ghosted so clicks pass through it, or hidden into the tray, this brings all of
them back in one press.

## Feature toggles

Each flips a flag, saves it, updates the settings window if it is open, and shows
a tray notification.

| Hotkey | Feature |
|---|---|
| **Shift + Alt + C** | Hot corners |
| **Shift + Alt + I** | Infinite cursor wrap |
| **Shift + Alt + D** | Multi-monitor dimmer |
| **Shift + Alt + T** | Smart auto-hide taskbar |
| **Shift + Alt + J** | Magnetic window groups |
| **Shift + Alt + Space** | Universal grab & pan |

## Only when the feature is switched on

These are declared under a `#HotIf` guard, so the key does nothing — and stays
available to whatever app you are using — until the feature is enabled in
settings.

| Hotkey | Action | Requires |
|---|---|---|
| **Shift + Alt + B** | Always on bottom (desktop widget) | Always on Bottom |
| **Shift + Alt + G** | Proximity ghost window | Proximity Ghost |
| **Shift + Alt + P** | Live PiP thumbnail | Live PiP |
| **Shift + Alt + L** | Spotlight launcher | Spotlight |
| **Shift + Alt + A** | Microphone kill-switch | Mic Kill Switch |
| **Shift + Alt + Q** | Quick Look preview | Quick Look, and Explorer focused |
| **Shift + Alt + F4** | Shatter-to-close | Shatter to Close |
| **Alt + F4** | Close with the gravity-drop animation | Gravity Drop on Close |
| **Ctrl + Alt + V** | Paste as plain text | Global Plain-Text Paste |
| **Win + Alt + D** | Curtain drop: show the desktop with a drop animation | Curtain Drop |
| **Delete** in Explorer or on the desktop | Black-hole delete animation (the delete still happens) | Black Hole Delete |
| **Hold Ctrl + V**, then **wheel** | Morphing paste: pick a transformed version of the clipboard before it pastes | Morphing Paste |
| **Ctrl + C** twice quickly | Append the new selection to what was already copied | Clipboard Append |

## Gestures and other keys

| Input | Action | Requires |
|---|---|---|
| **Esc Esc Esc** | Stealth Panic Mode on / off | Stealth Panic (on by default) |
| **Double-tap Ctrl** | Spotlight launcher | Spotlight |
| **Double-tap Alt** | Microphone kill-switch | Mic Kill Switch |
| **Alt + Left-drag** | Move a window from anywhere on it | Alt-Drag |
| **Alt + Right-drag** | Resize from the nearest edge | Alt-Drag |
| **Middle-click title bar** | Roll up, or close | Roll-Up / Middle-Click Close |
| **Hold middle-click** | Grab & pan | Grab & Pan |
| **Wheel over the taskbar** | Volume; middle-click mutes | Taskbar Scroll |
| **Ctrl + G** in a file dialog | Jump to the last Explorer folder | Quick Folder Jump |
| **CapsLock** | Tap = Esc or Backspace, hold = real CapsLock | Smart CapsLock |
| **Space** in Explorer | Quick Look preview; **Space** or **Esc** closes it | Quick Look |
| **Enter** / **Esc** in Spotlight | Run / close | Spotlight |
| **Wheel** at the end of a scrollable window | Elastic overscroll bounce | Elastic Scroll |
| **@@mail**, **@@date**, ... | Text expander snippets, from `[snippets]` in `settings.ini` | Text Expander |

Triple-Escape is bound as `~Esc`, so Escape still reaches the focused window.

## Windows shortcuts this overrides

While the program runs, AutoHotkey sees these keys first:

- **Shift + Alt + S** no longer opens Speech Recognition.

Nothing else in the `Shift + Alt` range is claimed by Windows 11, which is why
the whole program moved here. Deliberately untouched: `Win + Ctrl + ←/→`
(virtual desktops), `Win + Ctrl + D`, `Win + Ctrl + C` (colour filters),
`Win + Ctrl + N` / `Enter` (Narrator), `Win + Ctrl + O` (on-screen keyboard),
`Win + ↑/↓`, `Win + Tab`, `Win + D`, `Win + E`. Several are accessibility
features.

## Changing a hotkey

Hotkeys live in one block in `src\InputBindings.ahk` (search for
`=== Hotkeys ===`), with a few declared next to their feature instead:
always-on-top (`+!o`, `src\FeatureToggles.ahk`), gravity close (`$!F4`) and
curtain drop (`#!d`, both `src\FxGravity.ahk`), shatter close (`+!F4`,
`src\FxShatter.ahk`), black-hole delete (`~Delete`, `src\FxBlackHole.ahk`) and
triple-Esc (`~Esc`, `src\StealthPanic.ahk`).

AutoHotkey modifier symbols:

| Symbol | Key |
|---|---|
| `+` | Shift |
| `!` | Alt |
| `^` | Ctrl |
| `#` | Win |
| `~` | pass the key through to the app as well |
| `$` | force the keyboard hook |

So `+!k::CenterWindow()` is Shift + Alt + K.

Each hotkey delegates to a **named function** that the tray menu and settings
window also call. Change the behaviour in the function, never in the hotkey line,
or the two drift apart.

**`#HotIf` is positional, not scoped.** A `#HotIf` left open applies to every
hotkey declared after it, including in files included later. Always close with a
bare `#HotIf`.

## Troubleshooting

| Problem | Cause |
|---|---|
| A hotkey does nothing on one window | It is elevated. AutoHotkey cannot touch an admin window unless it is elevated too |
| A `#HotIf` hotkey does nothing | Its feature is switched off in settings |
| Nothing responds at all | Game Mode is on - press `Shift + Alt + F12` |
