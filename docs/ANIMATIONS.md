# Windows animation settings for Window Tweaks

Which Windows settings this program needs, which make it look better, and which
one actively fights it.

Run `scripts\Apply-Windows-Tuning.ps1 -Animations` to set all of these at once.
It writes to `HKCU` only, needs no admin rights, and
`scripts\Restore-Windows-Tuning.ps1` puts everything back exactly as it was.

---

## 1. Required — the program looks broken without it

### Show window contents while dragging

**Settings → Accessibility → Visual effects**, or *Performance Options →
Visual Effects → "Show window contents while dragging"*.
Registry: `HKCU\Control Panel\Desktop` → `DragFullWindows = 1`

**This is the only setting Window Tweaks genuinely requires.** With it off,
Windows drags a hollow outline and only moves the real window when you let go.
You would see nothing of the ice glide — the window would simply appear at its
destination.

*Check yours with the snippet at the bottom of this page. `Install.bat` turns
this one on for you if it's off, because the program's headline feature is
invisible without it.*

---

## 2. Recommended — makes the tweak feel like part of Windows

These don't change what the program does, they make the rest of the system move
at the same quality so the glide doesn't stand out as the only smooth thing.

| Setting | Registry | Why it matters here |
|---|---|---|
| Animate windows when minimizing and maximizing | `Control Panel\Desktop\WindowMetrics` → `MinAnimate = 1` | Minimise/restore gets the same easing feel as the glide. Without it windows *pop*, which looks abrupt next to a sliding window. |
| Animations in the taskbar | `...\Explorer\Advanced` → `TaskbarAnimations = 1` | Taskbar buttons animate when you drag a window between monitors. |
| Smooth-scroll list boxes | `UserPreferencesMask` bit | Explorer and dialogs scroll rather than jump. |
| Fade or slide menus into view | `UserPreferencesMask` bit | Context menus match the motion language. |
| Fade out menu items after clicking | `UserPreferencesMask` bit | Same. |
| Slide open combo boxes | `UserPreferencesMask` bit | Same. |

*`scripts\Apply-Windows-Tuning.ps1 -Animations` sets all of these. If you prefer minimal RAM and CPU usage, run `scripts\Apply-Windows-Tuning.ps1 -MinimalAnimations` to set only the absolute essentials while disabling heavier features. See
[WINDOWS-TUNING.md](WINDOWS-TUNING.md) for what else it changes.*

---

## 3. The one that fights the program

### "When I drag a window to the edge of the screen, snap it"

**Settings → System → Multitasking → Snap windows**
Registry: `HKCU\Control Panel\Desktop` → `WindowArrangementActive`

**This is ON by default on a fresh Windows 11 install.**

This is Windows' own Snap Assist. Drag a window to a screen edge and Windows
maximises it or fills half the screen — *before* Window Tweaks ever sees the
release. The program deliberately steps aside when this happens (it skips any
window Windows has maximised), so the two never corrupt each other, but it does
mean **Windows wins at screen edges**.

You have a genuine choice here:

| | Keep it ON *(default)* | Turn it OFF |
|---|---|---|
| Drag to a **screen edge** | Windows half-snaps / maximises | Window Tweaks snaps it flush, keeping its size |
| Drag near **another window** | Window Tweaks — unaffected either way | Window Tweaks |
| Corner magnetism | Only away from screen edges | Everywhere |
| `Win + ←/→` keyboard snapping | Works | **Stops working** |

**Recommendation: leave it ON.** Half-screen snapping is genuinely useful and the
keyboard shortcuts are worth keeping. Window Tweaks' real contribution is
window-to-window magnetism, which works regardless.

Turn it off only if you want edge drags to keep the window's size instead of
resizing it to half the screen. `Apply-Windows-Tuning.ps1` does **not** touch
this — it's your call, and the script would be making it for you.

### Snap Assist suggestions

**Settings → System → Multitasking → Snap windows → "Show snap layouts when I
drag a window to the top of my screen"**

Worth turning off even if you keep snapping. The layout flyout appears mid-drag
and delays the release by a beat, which you feel as lag in the glide.

---

## 4. Deliberately not recommended

| Often suggested | Why not |
|---|---|
| Visual Effects → "Adjust for best performance" | Turns off `DragFullWindows`, which **breaks** the glide. This is the single worst thing you can do to this program. |
| Disabling all animations for speed | Your machine had this done already, and it's why Windows felt abrupt rather than fast. Animations cost almost nothing on a modern GPU. |
| `MenuShowDelay = 0` | Already 0 here. Fine to set, but it's a delay, not an animation — it won't make anything smoother. |
| Disabling DWM / composition | Not possible on Windows 11, and it would break the glide, Mica, and rounded corners. |

---

## Quick check

```powershell
# What matters, at a glance
$d = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
"DragFullWindows        = $($d.DragFullWindows)   (must be 1)"
"WindowArrangementActive= $($d.WindowArrangementActive)   (1 = Windows wins at screen edges)"
"MinAnimate             = $((Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics').MinAnimate)"
"TaskbarAnimations      = $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').TaskbarAnimations)"
"EnableTransparency     = $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize').EnableTransparency)"
```
