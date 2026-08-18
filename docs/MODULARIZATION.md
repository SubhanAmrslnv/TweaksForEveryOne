# Modularizing WindowTweaks.ahk under the SOLID / single-source-of-truth rules

> **STATUS: DONE.** Phases 0-10 have landed. `src/WindowTweaks.ahk` went from
> 10,447 lines to 99 - an entry point holding process directives, a 29-line
> `#Include` manifest and one `Boot()` call - across eleven commits, ten of them
> verifiably pure code motion. There are now 32 modules, flat in `src/`, and the
> largest is 979 lines.
>
> **Read the rest of this document as the design record, not as a to-do list.**
> Several details in it were already stale when the work started and are
> corrected here:
>
> - **The installers no longer hardcode the `.ahk` list.** `Install.ps1` and
>   `build/Build-Installer.ps1` both glob `src/*.ahk` excluding `test_*`, so
>   adding a module needs no installer edit. The flat-`src/` and no-underscore
>   rules still hold.
> - **Every line range quoted below was captured at 9,281 lines** and is off by
>   more than a thousand. They were re-derived per phase.
> - **The layout shipped as 24 new modules, not 23.** `TaskbarClock.ahk` was
>   added: the custom taskbar clock did not exist when this was written, and at
>   546 lines with a geocoder and a retry back-off it does not belong inside
>   `ShellSurfaceWatcher.ahk`.
> - **`QPC()` went to `AnimationScheduler.ahk`**, which already owns the frame
>   timebase. It was the one function with no feature home.
> - **`TEARDOWN_SPEC` and `FEATURE_SPEC` were deliberately NOT built.** Both are
>   behavioural refactors rather than motion, and defining `TEARDOWN_SPEC`
>   activates Check-Split's timer-drift check, which currently skips and would
>   fail immediately. `Bye()` moved unchanged. They belong with the phase-11
>   convergence work, which remains outstanding along with (c) through (g) in
>   the phase table.
>
> Verification that actually ran, after every phase: `scripts/Check-Split.ps1`,
> with the motion proof byte-identical at 9,065 code lines for phases 2-10, and
> `-IniCheck` regenerating a `settings.ini` identical to the pre-split
> reference. The installer was rebuilt and its payload confirmed to match
> `src/` exactly.

## Context

`src/WindowTweaks.ahk` is **9,445 lines** — 33 sections, ~230 functions, ~140 top-level globals. (The line ranges quoted throughout this document were captured at 9,281 lines and drift as the file grows; treat them as approximate anchors, not exact offsets.) That is rule 14's "architectural problem" band, and the duplication it hides is measurable, not theoretical:

| Symptom | Evidence |
|---|---|
| Three-way manual mirror for every boolean setting | global declaration (lines 53-156) ↔ ~70 `IniStr` lines in `LoadSettings` (467-570) ↔ 68 `PutIni` calls in `WriteSettings` (589-680). `TUNE_SPEC` already solved this for the 46 *numeric* settings; booleans/strings were never migrated. |
| God functions | `ApplyUi` 164 lines and `WriteSettings` 92 lines, both declared bare `global` (assume-global) — they touch the whole namespace by design. `BuildWin` 404 lines. `Bye()` 160 lines naming 25 timers, 8 Gui containers, 8 state Maps by hand. |
| Render-pipeline rule violated | **59** direct `WinSetTransparent`/`SetWindowPos`/`WinMove`/`WinSetRegion`/`WinSetExStyle` calls outside `RenderCore.ahk`; 4 of them inside registered animation callbacks, which breaks the produce/render split. |
| Window validation re-implemented | The shell-class skip list is written **8 times** and the eight lists **disagree** (3141 and 5924 omit `Shell_SecondaryTrayWnd`). 82 inline `DllCall("IsWindow")` in 4 spellings, no shared predicate. `WinExist("A")` at 28 sites, no accessor. |
| Geometry conversion duplicated | The frame-space→WinMove-space identity written 4 times in 3 incompatible shapes (`ApplyLayout` 2137, `SnapWindow` 3956, `ThrowToMonitor` 4316, SmartGrid 7578 — the last applies it with a raw `WinMove`). |
| Overlay lifecycle duplicated | 24 near-identical overlay Gui implementations with gratuitously divergent option strings; 26 `.Destroy()` sites but only 14 `RS_RemoveHwnd`. A correct helper `GuiDestroy()` exists at 3355 and is used at **4** sites. |
| Scheduler bypassed | 11 private 16 ms `SetTimer` FX loops. The same QPC-units bug was fixed three times independently because the timebase isn't shared. |

**Outcome wanted:** the module layout from rule 20 — clear ownership, one authoritative definition per setting/state/rule, dependencies flowing toward stable infrastructure — reached by *incremental, behaviour-preserving* steps (rule 17), never a rewrite.

**Decisions taken:** staged full split; **motion first, converge second** — each phase is pure code motion with zero behaviour delta, and the convergence fixes land as separate, individually revertable commits in Phase 11.

---

## Two constraints that shape everything

**1. The installers hardcode the file list.** `Install.ps1:147` and `build/Build-Installer.ps1:50-64` each enumerate the `.ahk` payload by name, and `build/Setup.cs:335` reverses subdirectory flattening with `Replace("_", "\\")`. Therefore:

- The split stays **flat in `src\`** — no `src\features\`, no `src\ui\`. Names carry the grouping.
- **No underscore in any module filename.** `Window_Commands.ahk` extracts as `Window\Commands.ahk` and the app fails to load — on end-user machines only, never when you run from `src\`.
- A module missing from those two lists is a **load-time** failure of the installed copy, invisible during development. This is why manifest de-hardcoding is Phase 0.

**2. File order is currently semantically load-bearing.** Top-level `global X := ...` initialisers run in file order in the auto-execute thread, so a `Sync*` called before a global's declaration line gets clobbered when execution reaches it — documented at lines 266-272 and 9269-9277, which is why four calls are pinned to the file bottom. Phase 1 removes this hazard rather than working around it (see below).

---

## Target module layout — 23 modules + entry, flat in `src\`

Existing `SnapCore.ahk`, `RenderCore.ahk`, `AnimationScheduler.ahk`, `MediaCore.ahk`, `StealthPanic*.ahk` are **untouched**.

### Substrate — no feature knowledge

| File | Responsibility | From lines |
|---|---|---|
| `WindowTweaks.ahk` | Entry only: process directives, the `#Include` manifest, one `Boot()` call | 1-27 + new |
| `FeatureFlags.ahk` | Declared default of every boolean/string/enum setting + the enum lists (`OPEN_ANIMS`, `CAPS_ACTIONS`, `CORNER_ACTIONS`, `EP_STYLES`, `EP_ICON_SIZES`) | 51-165 |
| `TuningRegistry.ahk` | `TUNE_SPEC` + the numeric load/clamp/persist/render runtime; owns `Clamp()` | 167-252, 330-466, 4395 |
| `SettingsStore.ahk` | settings.ini read/write, `IniCache`, `LoadSettings`/`WriteSettings`/`SaveSettings`, Start-with-Windows | 31-38, 259, 276-329, 467-680, 738-751 |
| `DiagnosticsLog.ahk` | Buffered log, rotation, `Notify` | 42-49, 681-737 |
| `ProcessLifecycle.ahk` | `Boot()` and `Bye()` + `TEARDOWN_SPEC` | 6756-6913 + new |

### UI and input

| File | Responsibility | From lines |
|---|---|---|
| `FeatureToggles.ahk` | Tray menu + the 11 `Toggle*` hotkey handlers | 752-779, 3550-3636 |
| `SettingsWindow.ahk` | Settings Gui: chrome, nav, 7 pages, `ApplyUi`. **Sole owner of `C`, `Win`, `Pages`, `NavItems`, `CurPage`** | 253-258, 780-1558 |
| `InputBindings.ahk` | All keyboard intake: hotkeys, every `#HotIf`, the keyboard hook, hotstring expander | 1559-2028, 3637-3656, 6544-6592, 7986-8098 |

### Cross-cutting services

| File | Responsibility | From lines |
|---|---|---|
| `MonitorGeometry.ahk` | Monitor index / work-area lookup, cached screen metrics | 2029-2089, 5442-5462 |
| `OverlayGui.ahk` | One lifecycle for every transient overlay: `GuiDestroy`, `FadeGui`, `NotchAnim` | 3355-3362, 3485-3549, 7945-7985 |

### Features

| File | Responsibility | From lines |
|---|---|---|
| `WindowCommands.ahk` | What `Shift+Alt+<key>` does to the active window: place, tile, cycle, monitor-hop, opacity, roll-up, tray-hide, boss key | 2090-2904 |
| `AmbientDimming.ahk` | Breathing windows + monitor dimmer + the MediaCore bridge that suspends them | 2905-3126, 5159-5218, 6917-6958 |
| `FocusEmphasis.ahk` | Three ways to emphasise the active window: cinema dim, focus depth, active border | 3286-3484, 6254-6436, 7819-7944 |
| `DragPipeline.ahk` | MOVESIZE/menu hooks, velocity sampling, drag end, magnetic groups | 3658-3918, 7184-7237 |
| `DropPlacement.ahk` | Where a released window lands and how it travels: snap targets, verify, seam flash, glide, bounce, throw, tiling grid | 3919-4425, 7479-7611 |
| `WindowLifecycle.ahk` | Classify / remember / restore / animate-in a window. Owns the shell hook | 4426-5158 |
| `OnDemandOverlays.ahk` | Summoned-and-dismissed overlays: Quick Look, Spotlight, text magnifier | 5219-5313, 6154-6253, 7341-7478 |
| `ScreenEdgeGestures.ahk` | Pointer reaching a screen boundary: hot corners, infinite wrap | 5420-5712 |
| `AudioOsd.ahk` | Volume + mic OSDs and their input | 5713-5867, 6032-6153 |
| `PinnedWindowModes.ahk` | Modes a user opts a *specific* window into and that must be released on exit: PiP, always-on-bottom, ghost, privacy blur | 5868-6031, 6437-6543, 6593-6755, 9124-9265 |
| `MouseGestureFx.ahk` | Pointer-motion/idle/wheel driven: breathe cursor, ripples, drag trail, shake-find, yawn, elastic scroll, motion blur | 6959-7183, 7238-7340, 7612-7818, 8388-8465 |
| `ShellSurfaceWatcher.ahk` | The one poll that watches shell surfaces: taskbar auto-hide, wave, Start blur, toasts, lightsaber seam | 5314-5419, 8466-8845 |
| `WindowSpectacleFx.ahk` | One-shot desktop takeovers: gravity close, curtain drop, carousel Alt-Tab, black-hole delete, shatter | 3127-3285, 8099-8387, 8846-9123 |

Names deliberately rejected per rule 3: `Utils`, `Common`, `Helpers`, `Misc`, and — the one that will tempt around Phase 10 — `Effects.ahk`. The three FX files are split by *what drives the effect*, which is also the axis the Phase 11 convergence commits operate along.

---

## Phase 1 removes the file-order hazard instead of preserving it

Twenty top-level executable statements are scattered through the monolith (261-264, 274, 2741, 2966, 3673-3682, 4632-4640, 5173, 5328, 5428, 5437, 5462, 5869, 6285, 6591, 6756, 9278-9281). They are the **only** reason include order is load-bearing. Hoist all twenty into `Boot()` in `ProcessLifecycle.ahk`, called as the last line of the entry file after every `#Include`. Then every module's declarations have run before any `Sync*`/`OnMessage`/`OnExit` executes, and include order becomes documentation.

```ahk
Boot() {
    static done := false      ; Reload() starts the new process before the old exits;
    if done                   ; a second call would stack OnMessage handlers and
        return                ; register OnExit(Bye) twice.
    done := true
    LoadSettings(), RotateLog(), SyncTray(), BuildTray()
    WriteLog("=== Window Tweaks " VERSION " started ===")
    ; ... the remaining 15 statements IN THEIR CURRENT ORDER ...
    ; The former deferred-init tail. Its reason has been generalised, not removed:
    ; Boot() runs after every module's declarations, so nothing here can be clobbered.
    SyncShakeDetector(), SyncCursorFxTimer(), SyncTaskbarUiTimer(), UpdateKeyboardHook()
}
```

**Be explicit: Phase 1 is the one phase that is not zero-delta.** Today `SyncBreathingTimers()` at 2966 arms a timer while `DragHwnd` (3664) and `FocusModeEnabled` (3275) have not yet been declared — the same latent bug the deferred-init comment describes, merely not yet observed. Boot extraction eliminates the class. It gets its own commit and its own smoke test so no later regression is ever confused with it.

The only part beyond cut-and-paste: the five side-effecting "declarations" — `WinEventCb`/`WinEventHook`/`MenuEventCb`/`MenuEventHook` (3673-3682) and `SparkHook.OnKeyDown` (7991) — become plain `global ... := 0` declarations plus an `InstallDragHooks()` call and one line inside `UpdateKeyboardHook()`.

Two rules keep the manifest honest, both grep-enforceable: a module's top-level initialisers may only read globals declared **earlier in the same module** (nothing violates this today), and **every `#Include` lives in the entry file** — nested includes rebase relative paths.

---

## Breaking the `Bye()` / `ApplyUi()` / `WriteSettings()` / `C[]` coupling

**Features move first; the registries land after.** In AHK v2 a top-level `global X := ...` is a **super-global**, visible inside every function in the whole script including functions in other files defined textually earlier. So moving `ToggleHotCorners()` out does not break `C["corners_en"]`, and moving `SyncDimmerTimer()` out does not break `ApplyUi`'s bare `global`. Motion does not require decoupling — but writing 70 `FEATURE_SPEC` rows against 23 stable files is reviewable, and writing them against a moving 9,281-line file is not.

**Hard rule during every motion phase: do not touch the `global` line in `ApplyUi`, `LoadSettings` or `WriteSettings`.** A partial declaration list silently creates locals. They stay assume-global until `FEATURE_SPEC` has removed the last name that needs it.

### `C[]` — the one decoupling done during motion (Phase 4, six lines)

```ahk
; The ONLY place outside BuildWin that touches C. Toggle hotkeys fire whether or
; not the settings window is open, and Win may be a stale handle, so this does
; nothing in the common case rather than making all eleven callers guard.
SettingsControlSet(key, value) {
    global Win, C
    if (!Win || !C.Has(key) || !WinExist("ahk_id " Win.Hwnd))
        return
    try C[key].Value := value
}
```

`ToggleFeatureFlag` (3577), `ToggleSnap` (3550) and `ToggleMemory` (3559) call it; `C` never leaves `SettingsWindow.ahk`.

### `FEATURE_SPEC` — the boolean/string sibling of `TUNE_SPEC` (Phase 11b)

Modelled on `TS()` at line 197, using **getter/setter closure pairs, not `%name%` deref**: with no test runner, a typo in `() => SnapEnabled` is a load-time error caught on first run, while a typo in `"SnapEnabled"` is a runtime no-op that ships.

```ahk
;   key      C[] control key, and this row's identity
;   get/set  backing global as a closure pair (load-checked, unlike a name string)
;   sec/ini  settings.ini section and key
;   kind     "bool" | "enum" | "text";  list = legal values when kind="enum"
;   page     which settings page builds the control; "" = ini-only or tray-only
;   sync     the feature's Sync* function - a Func, not a name
;   release  called on true->false. This is ApplyUi's uiOld* block, made data.
FS(key, get, set, sec, ini, def, kind, page, label, hint := "", sync := "", release := "", list := "") =>
    {key:key, get:get, set:set, sec:sec, ini:ini, def:def, kind:kind
    , page:page, label:label, hint:hint, sync:sync, release:release, list:list}

global FEATURE_SPEC := [
  FS("snap"      , () => SnapEnabled          , (v) => SnapEnabled := v          , "snap"   , "enabled", true , "bool", "win"    , "Enable magnetic snapping")
, FS("corners_en", () => HotCornersEnabled    , (v) => HotCornersEnabled := v    , "corners", "enabled", false, "bool", "corners", "Enable hot corners", "", SyncHotCornersTimer)
, FS("ghost"     , () => ProximityGhostEnabled, (v) => ProximityGhostEnabled := v, "memory" , "ghost"  , true , "bool", "power"  , "Proximity Ghost Window (Shift+Alt+G)"
                 , "Fades a window out until the mouse comes near it.", SyncMediaCore, UnGhostAllWindows)
, FS("openanim"  , () => OpenAnim             , (v) => OpenAnim := v             , "memory" , "openanim", "Ghost Slide-In", "enum", "anim", "New window animation", "", "", "", OPEN_ANIMS)
; ... ~70 rows
]
```

`LoadSettings`, `WriteSettings`, `ApplyUi`'s read+release block, `BuildWin`'s hand-written `Box`+`Sub` pairs, and `ToggleFeatureFlag`'s eleven callers all collapse to loops over this table — exactly the way `TuneRow()` replaced the hand-written number rows. About 8 rows stay hand-written because they are genuinely not registry-shaped: `EP_Style`/`EP_IconSize` read the registry rather than the ini, and `BorderColor` is validated by shape, not membership.

**Migration invariant, grep-checkable:** a settings.ini key appears in *exactly one* of `FEATURE_SPEC` or the hand-written lines — never both. Extract every `(sec, ini)` pair from the table and every `IniStr(`/`PutIni(` literal pair; the intersection must be empty and the union unchanged. Migrate ~10 rows per commit in settings-page order, so each commit's smoke test is "open that page and round-trip it".

### `TEARDOWN_SPEC` — replaces `Bye()`'s hand-maintained list

`Bye()`'s 160 lines are three phases in a load-bearing order, and its own header comment already says why: *stop producing before you start undoing*. Encode the phase; preserve within-phase order.

```ahk
; phase 1 = stop producing (Bye calls SetTimer(run, 0))
;       2 = hand foreign-window state back      (Bye calls run())
;       3 = destroy our own Guis                (Bye calls run())
; owner the module that owns the row - the grep target for the drift check
; run   a Func, never a name. A row naming a function that no longer exists is a
;       LOAD error, which is the point: Bye() silently skipping a cleanup is the
;       exact failure mode this table exists to remove.
TD(phase, owner, run, guard := "") => {phase:phase, owner:owner, run:run, guard:guard}

global TEARDOWN_SPEC := [
  TD(1, "AnimationScheduler",  StopSchedulerForExit)
, TD(1, "AmbientDimming",      BreathingMonitorStep)
; ... 24 more phase-1 rows, one per timer ...
, TD(2, "ShellSurfaceWatcher", RestoreTaskbarAutoHide, () => SmartTaskbarEnabled && OriginalTaskbarState != -1)
, TD(2, "PinnedWindowModes",   UnGhostAllWindows)
; ... phase-2 rows ...
, TD(3, "AudioOsd",            DestroyVolumeOsd)
; ... phase-3 rows ...
]

Bye(*) {
    global TEARDOWN_SPEC
    loop 3 {
        for row in TEARDOWN_SPEC {
            if (row.phase != A_Index) || (row.guard && !row.guard())
                continue
            try (A_Index == 1) ? SetTimer(row.run, 0) : row.run()
        }
    }
    RS_Commit(), RS_Flush(), RS_Shutdown()
    ReleaseWinEventHooks()
    try DllCall("DeregisterShellHookWindow", "ptr", A_ScriptHwnd)
    try WriteSettings(), WritePositions(), FlushLog()   ; no idle on the way out
    return 0
}
```

**This one rides along with the split rather than blocking it.** Phase 3 transcribes the existing `Bye()` body into the table *in its current order*, with 1:1 wrapper functions still defined next to `Bye()` — identical behaviour, `Bye()` drops to ~20 lines, nothing has moved. Each later feature commit re-homes its own wrappers into its module and updates the `owner` column; the rows never change.

---

## Phase order

Risk rises monotonically. The two phases that are not pure motion (0 and 1) come first and alone.

| # | Content | Smoke test |
|---|---|---|
| **0** | `Install.ps1:147` and `Build-Installer.ps1:50-64` switch from hardcoded lists to `Get-ChildItem src\*.ahk -Exclude test_*`. Add `.gitattributes` (`*.ahk text eol=crlf`). Add `scripts\Check-Split.ps1` (the seven checks below). No `.ahk` change. | Build setup.exe, install to a scratch dir, confirm it launches and `snap.log` gets the started line; run the uninstaller. |
| **1** | Boot extraction (above). No files added. | Cold start; settings window; toggle 3 features; **tray → Restart ×5 consecutively** (duplicate tray icons / doubled hotkeys / leaked shell hook); tray → Exit; no orphaned overlay, no window left dimmed/ghosted/rolled-up. |
| **2** | `MonitorGeometry`, `OverlayGui`, `DiagnosticsLog` | Smallest, most-depended-on, no hotkeys, no `#HotIf` — proves the include+encoding+installer pipeline at minimum blast radius. Layout op; volume OSD + dimmer fade; `DEBUG` on → log grows and rotates past 256 KB. |
| **3** | `FeatureFlags`, `TuningRegistry`, `SettingsStore`, `ProcessLifecycle` (+ `TEARDOWN_SPEC` transcribed 1:1) | **Delete settings.ini, cold start, diff the regenerated ini against one captured pre-split — must be byte-identical.** Then change 5 values across 3 pages, restart, confirm persistence. |
| **4** | `SettingsWindow`, `FeatureToggles`, `SettingsControlSet()` | All 17 non-ASCII lines that double as `Pages` map keys live here — concentrating the encoding hazard in one commit is deliberate. Click all 7 nav pages (mojibake shows as a page that never appears); resize; wheel-scroll; type `330` into a max-120 field and tab away (write-back); then fire all 11 toggle hotkeys **with the window open** and confirm each checkbox follows. |
| **5** | `InputBindings` | First file containing `#HotIf` — establish the bracket rule here once. Flag-context hotkeys (Shift+Alt+B/G/P) with flags on *and* off; function-context ones (taskbar wheel, Explorer Quick Look, file-dialog jump, Spotlight-active); double-press; a hotstring. **And confirm Win+D still does Windows' own show-desktop when Curtain Drop is off** — that binding is in another module and must not inherit a leaked context. |
| **6** | `WindowCommands` | All 9 keypad tiles **with NumLock on and off**; centre; cycle (3 sizes); next-monitor; undo; Shift+Alt+wheel both directions and the floor; roll-up; hide-to-tray then restore via the injected icon; boss key on/off. |
| **7** | `DragPipeline`, `DropPlacement` | Highest-risk runtime code (`SetWinEventHook` callbacks, RS_* pipeline) — its own phase, nothing else in flight. Drag-snap each edge and corner; throw + glide; throw across a monitor boundary; tiling grid; magnetic-group drag; seam flash; **parallax opacity returns to 255 after release**; exit mid-drag leaves nothing transparent. |
| **8** | `WindowLifecycle` | Open Notepad / Explorer / a browser, confirm restore; all four `OpenAnim` values; focus pulse; "Forget positions"; inspect `window-positions.ini`. |
| **9** | One commit each: `AmbientDimming`, `ScreenEdgeGestures`, `AudioOsd`, `OnDemandOverlays`, `FocusEmphasis`, `PinnedWindowModes` — least to most entangled; each carries its own `TEARDOWN_SPEC` re-homing | Per module: enable, use, disable via checkbox (the release path), disable via hotkey, exit while active and confirm nothing left behind. `PinnedWindowModes` last because it owns four of `ApplyUi`'s `uiOld*` release paths — ghost a window then clear the checkbox: it must become clickable and non-topmost again. |
| **10** | `MouseGestureFx`, `ShellSurfaceWatcher`, `WindowSpectacleFx` | Seven off-by-default effects; lowest user impact, highest line count. Each turned on one at a time; verify Alt+Tab is normal when Carousel is off. |
| **11** | **Convergence**, each independently revertable: (a) finish `TEARDOWN_SPEC` re-homing; (b) `FEATURE_SPEC`, ~10 rows/commit in page order; (c) unify the 8 shell-class lists (1749, 2883, 3141, 5365, 5924, 6311, 6466, 6616) into `IsShellSurface()` in `WindowLifecycle`; (d) route the 59 direct render calls through `RS_*`; (e) the 12 missing `RS_RemoveHwnd`; (f) the 11 private 16 ms loops onto `AnimationScheduler`; (g) extract the shared `DWM_THUMBNAIL_PROPERTIES` helper that PiP, Carousel, MotionBlur, TaskbarWave and StartMenuBlur each open-code | Each is now a change inside one or two named files instead of a search across 9,281 lines — that is the payoff. (b) the ini round-trip diff per page; (c) one commit per call site, verify the feature that used the narrower list still skips the taskbar; (d)/(e) no window left with a stale alpha after exit. |

---

## Verification

**No build system, no test runner, no CI exists** — and CLAUDE.md records that AHK 2.0 has no `/validate` (that is 2.1+). The documented parse check stands: copy `src\*.ahk` to a scratch dir, prepend `ExitApp` to the copy of the entry file, run with `/ErrorStdOut`. AHK parses the whole script before executing anything, so exit code 0 with no output means it parses and no hook, timer or tray icon was installed.

Build `scripts\Check-Split.ps1` in Phase 0 with seven checks, run after every phase:

1. **Parse check** — the `ExitApp` + `/ErrorStdOut` trick above.
2. **Motion proof (the important one)** — textually resolve every `#Include` into one stream, sort the lines, hash. *A pure-motion commit must not change that hash.* Catches in one check: a dropped line, a PowerShell re-encode, a CRLF flip, a mangled emoji, a reflowed continuation block. Whitelist the banner comments and `#HotIf` bracket lines you legitimately add, and require the diff to contain only comment/blank/`#HotIf` additions.
3. **Default-ini diff** — run in a scratch dir with no settings.ini, kill after 3 s, diff against a reference captured before Phase 0. The strongest end-to-end check, and the guard over the whole `FEATURE_SPEC` migration.
4. **Timer-drift check** — collect the first argument of every `SetTimer(` across `src\*.ahk`, subtract the phase-1 `TEARDOWN_SPEC` rows; the difference must be empty (modulo negative-period one-shots). This is the check that would have caught the fourteen timers `Bye()` used to leave running.
5. **`#HotIf` bracket check** — per file, `count(#HotIf <expr>) == count(bare #HotIf)`, and the last `#HotIf`-family line in any file containing one must be bare.
6. **Case-collision check** — case-fold every top-level `global` name and every function name across all files; any duplicate is a load error waiting to happen. Ten lines, catches the whole `TUNE` / `Tune()` class.
7. **Duplicate-hotkey check** — extract every column-0 `::` binding across modules and report duplicates before AHK does. Once bindings live in four files you can no longer see them all at once.

Manual smoke tests are per-phase in the table above. Run from source with:
`& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" src\WindowTweaks.ahk`

---

## AHK v2 traps this split will hit

1. **`#HotIf` bleeds across `#Include` boundaries.** It is a positional directive, not a scope — a module ending with an open `#HotIf` silently applies that context to the first hotkeys of the next included file. Live risk: `#HotIf CurtainDropEnabled` (8105-8139) and `#HotIf CarouselAltTabEnabled` (8217-8277), both buried inside the 1,234-line FX section. Same for `#UseHook`, `#InputLevel`, `#MaxThreadsPerHotkey`, `#SuspendExempt`, `#Warn`. **Every module that defines a hotkey opens and closes with a bare `#HotIf`.**
2. **Super-globals make motion safe — and a mistake silent.** Name resolution cannot break when a feature moves out. The inverse is the hazard: a declaration accidentally duplicated in two modules raises **no error**; the later `#Include` wins at runtime. Grep for duplicate `^global \w+` across files.
3. **Never wrap a module's declarations in an `Init()` as tidy-up.** It is the obvious-looking cleanup and it is catastrophic — it demotes super-globals to function locals, turning one load error into hundreds of scattered runtime ones.
4. **Assume-global functions manufacture super-globals from their locals.** Inside `ApplyUi`/`LoadSettings`/`WriteSettings` *every* assignment creates a global — which is why the existing `uiAutoStart`/`uiOldSmartTb` temporaries carry a prefix. A `FEATURE_SPEC` loop written inside one of them makes its loop variable `s` a super-global. **Keep the registry loops in separate, non-assume-global helpers** that `ApplyUi` calls.
5. **A closure captures the scope it is written in.** `() => SnapEnabled` at top level reads the super-global; the same text inside a `BuildFeatureSpec()` helper captures that function's locals and reads nothing, silently. `FEATURE_SPEC` must be a top-level `global FEATURE_SPEC := [...]`, exactly like `TUNE_SPEC`.
6. **Continuation blocks must not be split.** `TUNE_SPEC` uses leading-comma continuation, `TS()` a multi-line expression, several class checks leading `||`. A file boundary or an editor reflow landing inside one changes parsing — sometimes into something that still parses and means something else.
7. **Encoding.** v2 reads a BOM-less `.ahk` as UTF-8 and none of your files has a BOM, but **Windows PowerShell 5.1 destroys that**: `Set-Content`/`Out-File`/`>` default to UTF-16LE (fails to load) and `-Encoding utf8` writes UTF-8 *with* BOM. Do the split with editor edits or `[IO.File]::WriteAllText` + `[Text.UTF8Encoding]::new($false)` — never a PowerShell text pipeline. Pin line endings via `.gitattributes` or check 2 fires spuriously forever.
8. **No underscore in module filenames** (`Setup.cs:335`).
9. **`SetTimer` identity is per-`Func`-object.** `SetTimer(CheckMouseIdle, 0)` only stops the timer if the same Func object was registered — wrapping a timer body in a closure or `.Bind()` makes the stop silently miss, and it survives `Reload()`. **Every registered timer stays a plain named function.** Conversely a `TEARDOWN_SPEC` row naming a function that no longer exists is a *load* error, not a silent skip — that property is what makes the table trustworthy.
10. **`Boot()` must be idempotent.** `OnMessage` with a fresh closure *stacks* handlers and `OnExit(Bye)` registered twice runs `Bye` twice; tray Restart calls `Reload()`, which starts the new process before the old exits. Hence `static done`, hence the five-consecutive-Restarts smoke test.
11. **Error dialogs now cite modules, not `WindowTweaks.ahk`.** `A_ScriptDir` is unchanged (it is the entry file's directory, so `INI := A_ScriptDir "\settings.ini"` still resolves), but every note referencing "line 6756" becomes unmappable.
12. **Case-insensitivity is script-wide, not file-scoped** — and *more* likely to bite with 23 files, since each module shows only its own names. Check 6 covers it.

---

## Documentation, kept in the same commits

`CLAUDE.md` documents the current file table and the include contract, and `Build-Installer.ps1` **ships the docs as installer payload** — so a stale doc ships to users. Each phase updates CLAUDE.md's Architecture section in the same commit, otherwise the next agent reads a section map that is off by 9,000 lines. Add to CLAUDE.md at Phase 0: the flat-`src\`/no-underscore/both-installer-lists rule, and the SOLID rules themselves as binding architecture policy.

Branch protection applies — this work goes on a feature branch, not `main`.
