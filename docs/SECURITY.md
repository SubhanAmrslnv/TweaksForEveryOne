# Security and system footprint

This document lists everything Window Tweaks does that a security product, an IT
department or a careful user would want to know about. It describes behaviour in
the current source and installers. It is not a certification: **no claim is made
that any antivirus product, including Bitdefender, approves or will not flag this
software.** The program and its installer exe are unsigned.

## Privileges

- **No administrator rights.** The program, `Install.bat`, `Uninstall.bat`,
  `build\Setup.cs` and the tuning scripts run as the signed-in user and write
  only under the user profile (`HKCU`, `%LOCALAPPDATA%`, the Start Menu and
  Startup folders).
- **No third-party shell extensions.** The program and its installers do not
  download, install or configure ExplorerPatcher or any other shell replacement.
  (Older versions could, as an opt-in. If you installed it that way, it stays
  installed and keeps its own settings; uninstall it through its own setup.)
- Hotkeys and window effects do not work against elevated windows unless the
  program itself is elevated. That is a Windows rule, and the program does not
  try to get around it.

## Network

| When | Endpoint | What is sent |
|---|---|---|
| Install, only if AutoHotkey v2 is missing | winget community source (`winget install AutoHotkey.AutoHotkey`) | winget's own traffic |
| Taskbar clock, only when weather is enabled **and** a city is set | `geocoding-api.open-meteo.com`, `api.open-meteo.com` | the city name once, then its coordinates about every 15 minutes |
| Spotlight, only when the user presses Enter on text that is not a file or command | the default browser opens a Google search | the typed text, by the browser |

With the default settings and no city configured, the program makes **no network
requests**. There is no telemetry, no update check and no analytics.

## Input hooks

| Hook | Why | Active when |
|---|---|---|
| AutoHotkey keyboard and mouse hooks | global `Shift+Alt+<key>` hotkeys, mouse gestures | always while running |
| `InputHook` with key-down notification | typing sounds, smooth caret, Spotlight/mic double-tap timing | only while one of those features is on |
| `SetWinEventHook` (move/size start and end, menu popup) | magnetic snapping, glide, context-menu animation | always while running; out-of-context, no DLL is injected |
| `RegisterShellHookWindow` | per-window cleanup, position memory, open animations | always while running |
| `SetWinEventHook` (`EVENT_OBJECT_UNCLOAKED`) | start the open animation for windows that are created cloaked (Edge, Explorer, UWP apps) | always while running; out-of-context, no DLL is injected |

The pointer itself is moved in exactly one place outside a gesture the user
started: Infinite Cursor Wrap (off by default) calls `MouseMove`/`SetCursorPos` to
carry it across an outer desktop edge or across the dead strip where two monitors
of different height meet. It switches only its own thread to per-monitor DPI
awareness (`SetThreadDpiAwarenessContext`) while it measures, so the coordinates
are real pixels; nothing is changed process-wide or system-wide.

No keystroke, clipboard content or window title is written to disk. The key hook
uses only the virtual-key code, for timing and sound selection. The diagnostic
log (`snap.log`, off unless "debug log" is ticked) records window classes,
geometry and handles.

There is no code injection: no `WriteProcessMemory`, `CreateRemoteThread`,
`VirtualAllocEx`, `SetWindowsHookEx` DLL hook or `LoadLibrary` into another
process. Process access is `PROCESS_QUERY_LIMITED_INFORMATION`, used only to read
an executable name.

## Changes to other windows

Opacity, position, size, z-order and clipping region of other applications'
windows are changed only through `src\RenderCore.ahk`, and every one of them is
restored when the program exits normally, including tray -> Restart. Nothing
re-parents another application's window, and nothing moves, hides or resizes
Explorer's own surfaces (the taskbar, notifications, the desktop).
`Shift+Alt+Y` restores every window the program is holding at any time. A forced
kill (`Stop-Process -Force`, `taskkill /F`) skips that restore. Close the program
from the tray, or with `taskkill` without `/F`.

## Registry

All writes are under `HKCU`; nothing is written under `HKLM`.

| Key | Written by | Reversible by |
|---|---|---|
| `Control Panel\Desktop\DragFullWindows` | optional animation tuning, required for the glide | the tuning restore script restores the backed-up value |
| `Control Panel\Desktop`, `Mouse`, `WindowMetrics`, `Explorer\Advanced`, `Explorer`, `Themes\Personalize`, `DWM` | `scripts\Apply-Windows-Tuning.bat`, only when tuning is chosen | `scripts\Restore-Windows-Tuning.bat` (backup kept in `%LOCALAPPDATA%\Window Tweaks Backup`) |

The running program reads Windows preferences from the registry. It
never changes the taskbar's auto-hide state, style or icon size.

## Startup and persistence

One shortcut in the user's Startup folder (`Window Tweaks.lnk`, created by the
installer or the "Start with Windows" checkbox). The standalone Stealth Panic
install adds `Stealth Panic Mode.lnk`. There are **no** Run keys, scheduled tasks,
services or drivers. The uninstallers remove every shortcut they created.

## Processes started

- **AutoHotkey**, to run the program. The settings GUI for Stealth Panic is a second
  AutoHotkey process.
- **Applications the user configured:** Stealth Panic "safe apps", the hot-corner
  actions, Spotlight commands.
- **`explorer.exe` restart:** only at install, after Explorer tuning was applied.
  The installer asks first and relaunches Explorer if Windows does not. The
  program itself never kills or restarts Explorer.
- **Installers:** `winget` and the bundled tuning BAT.
  `Setup.exe` runs tuning visibly. The BAT files contain the PowerShell logic
  and use a process-scoped execution-policy setting for the temporary script.
  `Apply-Windows-Tuning.bat` and `Uninstall.bat` compile a tiny
  `SystemParametersInfo` P/Invoke with `Add-Type`, so that Windows applies the
  restored settings immediately rather than at the next sign-in.

The Spotlight calculator evaluates arithmetic natively (`src\ArithmeticEval.ahk`).
No script engine is used.

## Files

| File | Location |
|---|---|
| `settings.ini`, `window-positions.ini`, `snap.log`, `StealthPanic.ini`, `StealthPanicApps.txt`, `StealthPanic_Launch.log` | the program folder |
| backups of changed system settings | `%LOCALAPPDATA%\Window Tweaks Backup` |

A fresh install seeds `settings.ini` from `build\baseline-settings.ini` only
when no `settings.ini` exists; an existing one is never overwritten by an install
or an update. The uninstaller removes the program but KEEPS `settings.ini`,
`window-positions.ini` and the Stealth Panic config, so a reinstall picks them up;
`Uninstall.bat -RemoveSettings` deletes those too.

If Windows tuning restoration is skipped or fails, the uninstaller keeps the
backup and the available recovery scripts so you can retry. The standalone
Stealth Panic uninstaller also keeps its configuration by default and accepts
`-RemoveSettings`.

## If Bitdefender (or another product) blocks it

Do **not** disable protection or add exclusions yourself on a managed machine.

1. Record the **detection name**, the **file path** and the file's **SHA-256**
   (`Get-FileHash <file>`), and note which action triggered it (install, startup,
   a specific feature).
2. Give those details to your IT/security team. They decide whether an exclusion
   is acceptable under company policy.
3. To report a false positive to Bitdefender, use its official sample-submission
   process with the same details. Unsigned AutoHotkey scripts and self-built
   setup executables are a common source of heuristic detections.
4. If a single feature is the trigger, switch that feature off in the settings
   window. Every feature is independent.

The development machine runs Bitdefender Endpoint Security Tools. No scan result
is claimed here: an on-demand scan of the source and the built setup is
something to run and record, for example (Bitdefender's own console tool, no
exclusions, no policy change):

    & "C:\Program Files\Bitdefender\Endpoint Security\product.console.exe" /c FileScan.OnDemand.RunScanTask custom path="<repo>\src"

Exact command syntax depends on the installed version and on what the company
policy allows from the console; if it is not permitted, ask IT to scan the files.
