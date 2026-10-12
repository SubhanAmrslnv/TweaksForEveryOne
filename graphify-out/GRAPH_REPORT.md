# Graph Report - .  (2026-10-12)

## Corpus Check
- 114 files · ~68,631 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1055 nodes · 2576 edges · 69 communities (63 shown, 6 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 261 edges (avg confidence: 0.87)
- Token cost: 759,373 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Render & Animation Core|Render & Animation Core]]
- [[_COMMUNITY_Drag, Snap & Glide|Drag, Snap & Glide]]
- [[_COMMUNITY_Settings & Tuning Registry|Settings & Tuning Registry]]
- [[_COMMUNITY_Media-Aware Ambient Dimming|Media-Aware Ambient Dimming]]
- [[_COMMUNITY_Hotkeys & Input Bindings|Hotkeys & Input Bindings]]
- [[_COMMUNITY_Stealth Panic Mode|Stealth Panic Mode]]
- [[_COMMUNITY_Keystroke Sound Synthesis|Keystroke Sound Synthesis]]
- [[_COMMUNITY_Linux X11 Adapter|Linux X11 Adapter]]
- [[_COMMUNITY_Linux Render Queue|Linux Render Queue]]
- [[_COMMUNITY_Custom Taskbar Clock|Custom Taskbar Clock]]
- [[_COMMUNITY_Linux Animation Scheduler|Linux Animation Scheduler]]
- [[_COMMUNITY_Settings Window GUI|Settings Window GUI]]
- [[_COMMUNITY_Pinned Window Modes|Pinned Window Modes]]
- [[_COMMUNITY_Tray & Feature Toggles|Tray & Feature Toggles]]
- [[_COMMUNITY_Linux Port Guidance|Linux Port Guidance]]
- [[_COMMUNITY_Module Split Rules|Module Split Rules]]
- [[_COMMUNITY_Boot & Feature Sync|Boot & Feature Sync]]
- [[_COMMUNITY_Quick Look & Spotlight|Quick Look & Spotlight]]
- [[_COMMUNITY_Linux Render Pipeline Design|Linux Render Pipeline Design]]
- [[_COMMUNITY_Linux Architecture Plan|Linux Architecture Plan]]
- [[_COMMUNITY_Volume & Mic OSD|Volume & Mic OSD]]
- [[_COMMUNITY_Windows Animation Settings|Windows Animation Settings]]
- [[_COMMUNITY_Tuning Backup Example|Tuning Backup Example]]
- [[_COMMUNITY_Keyboard Window Layout|Keyboard Window Layout]]
- [[_COMMUNITY_Win32 Shell Internals|Win32 Shell Internals]]
- [[_COMMUNITY_Animation Roadmap|Animation Roadmap]]
- [[_COMMUNITY_Linux Test Harness|Linux Test Harness]]
- [[_COMMUNITY_Shell Surface Watcher|Shell Surface Watcher]]
- [[_COMMUNITY_Focus  Cinema Mode|Focus / Cinema Mode]]
- [[_COMMUNITY_Linux Core Headers|Linux Core Headers]]
- [[_COMMUNITY_Linux CMake Build|Linux CMake Build]]
- [[_COMMUNITY_Tray Minimize & Restore|Tray Minimize & Restore]]
- [[_COMMUNITY_Effect Taste Constraints|Effect Taste Constraints]]
- [[_COMMUNITY_Linux Install & Wayland|Linux Install & Wayland]]
- [[_COMMUNITY_Hotkey Reference Docs|Hotkey Reference Docs]]
- [[_COMMUNITY_Linux Geometry Types|Linux Geometry Types]]
- [[_COMMUNITY_Icon Generator Script|Icon Generator Script]]
- [[_COMMUNITY_Linux Clipboard Manager|Linux Clipboard Manager]]
- [[_COMMUNITY_Linux Snap Geometry|Linux Snap Geometry]]
- [[_COMMUNITY_Linux Feature Matrix|Linux Feature Matrix]]
- [[_COMMUNITY_MCP Server Config|MCP Server Config]]
- [[_COMMUNITY_Magnetic Snap Geometry|Magnetic Snap Geometry]]
- [[_COMMUNITY_Alt-Drag & Close Effects|Alt-Drag & Close Effects]]
- [[_COMMUNITY_Engineering Guidelines|Engineering Guidelines]]
- [[_COMMUNITY_Linux Keystroke Sounds|Linux Keystroke Sounds]]
- [[_COMMUNITY_Linux Physics|Linux Physics]]
- [[_COMMUNITY_Linux Velocity Sampler|Linux Velocity Sampler]]
- [[_COMMUNITY_Linux Weather Fetcher|Linux Weather Fetcher]]
- [[_COMMUNITY_Volume Wheel & Morph Paste|Volume Wheel & Morph Paste]]
- [[_COMMUNITY_Window Roll-Up|Window Roll-Up]]
- [[_COMMUNITY_Linux Layer Check Script|Linux Layer Check Script]]
- [[_COMMUNITY_Defensive Programming Rules|Defensive Programming Rules]]
- [[_COMMUNITY_Linux Game Mode|Linux Game Mode]]
- [[_COMMUNITY_GNOME Extension|GNOME Extension]]
- [[_COMMUNITY_GNOME Extension Metadata|GNOME Extension Metadata]]
- [[_COMMUNITY_Linux D-Bus Daemon|Linux D-Bus Daemon]]
- [[_COMMUNITY_Window Classification|Window Classification]]
- [[_COMMUNITY_Linux Install Script|Linux Install Script]]
- [[_COMMUNITY_Claude Local Settings|Claude Local Settings]]

## God Nodes (most connected - your core abstractions)
1. `CLAUDE.md (Windows Tweaks project guide)` - 79 edges
2. `RS_Commit()` - 44 edges
3. `RS_SetPos()` - 39 edges
4. `Linux port CLAUDE.md` - 36 edges
5. `QPC()` - 35 edges
6. `ApplyUi()` - 31 edges
7. `RegisterAnimation()` - 29 edges
8. `RS_SetAlpha()` - 28 edges
9. `CancelAnimation()` - 27 edges
10. `Tune()` - 26 edges

## Surprising Connections (you probably didn't know these)
- `Core Features (snap, glide, on-top, memory)` --semantically_similar_to--> `Magnetic Snapping`  [INFERRED] [semantically similar]
  docs/GUIDE.md → CLAUDE.md
- `Magnetic Snapping Design` --semantically_similar_to--> `Magnetic Snapping`  [INFERRED] [semantically similar]
  docs/TASKBAR-AND-INTERNALS.md → CLAUDE.md
- `Getting Out of Trouble (restore-all)` --references--> `RestoreAllWindows()`  [INFERRED]
  docs/GUIDE.md → src/CmdRestoreAll.ahk
- `Defensive Programming & Quality Guidelines (project)` --semantically_similar_to--> `Defensive Programming & Quality Guidelines`  [INFERRED] [semantically similar]
  CLAUDE.md → .agents/rules/defensive_programming.md
- `Architecture Rules (ownership, SSOT, layering)` --semantically_similar_to--> `SOLID / DRY / Separation of Concerns`  [INFERRED] [semantically similar]
  CLAUDE.md → .agents/rules/professional_engineering.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Render pipeline: animators queue RS_* state, scheduler flushes once per frame** — src_animationscheduler_renderframe, src_animationscheduler_registeranimation, src_rendercore_rs_setpos, src_rendercore_rs_setalphalayer, src_rendercore_rs_flush, src_rendercore_rs_apply [EXTRACTED 1.00]
- **Composed opacity: base times named layers** — src_rendercore_rs_setbasealpha, src_rendercore_rs_setalphalayer, src_rendercore_rs_clearalphalayer, src_rendercore_rs_recomposealpha, src_rendercore_rs_alphastate [EXTRACTED 1.00]
- **Settings load/clamp/persist generated from TUNE_SPEC** — src_settingsstore_loadsettings, src_settingsstore_writesettings, src_tuningregistry_tuneload, src_tuningregistry_tunesave, src_tuningregistry_tune_spec, src_settingsstore_inicache [INFERRED 0.85]
- **Keyboard layout actions funnel through ApplyLayout** — src_cmdwindowgeometry_centerwindow, src_cmdwindowgeometry_cyclewindowsize, src_cmdwindowgeometry_tilewindow, src_cmdwindowgeometry_movetonextmonitor, src_cmdwindowgeometry_applylayout, src_rendercore_rs_commit [EXTRACTED 1.00]
- **Toggle flow: hotkey/tray -> ToggleFeatureFlag -> SaveSettings + Sync*** — src_featuretoggles_togglefeatureflag, src_featuretoggles_togglehotcorners, src_featuretoggles_togglecursorwrap, src_featuretoggles_toggledimmer, src_settingsstore_savesettings, src_acoustickeystrokes_playhotkeysound [EXTRACTED 1.00]
- **Game Mode in-memory suppression overlay** — src_gamemode_game_mode_features, src_gamemode_entergamemode, src_gamemode_exitgamemode, src_gamemode_gamemodeunsuspendforwrite, src_gamemode_gamemoderesuspend, src_gamemode_gamemodesyncfeatures [INFERRED 0.85]
- **Drag release to landing flow** — src_dragpipeline_winevent, src_dragpipeline_samplevelocitystep, src_dragpipeline_finishdrag, src_dropplacement_snapwindow, src_dropplacement_glide, src_dropplacement_onsnaplanded, src_dropplacement_verifysnap [EXTRACTED 1.00]
- **New window detection, restore and open animation** — src_shellhook_shellevent, src_shellhook_handlenewwindow, src_windowopenanim_willanimateopen, src_positionmemory_restoreposition, src_windowopenanim_unrollwindow, src_windowopenanim_ghostslidein, src_windowopenanim_portalscalein [EXTRACTED 1.00]
- **Sync* + SetTimer polling monitor pattern** — src_ambientdimming_syncbreathingtimers, src_ambientdimming_syncdimmertimer, src_screenedgegestures_synchotcornerstimer, src_screenedgegestures_synccursorwraptimer, src_ambientdimming_syncmediacore [INFERRED 0.85]
- **Pinned window modes requiring exit-time restoration** — src_pinnedwindowmodes_closepip, src_pinnedwindowmodes_restorefrombottom, src_pinnedwindowmodes_unghostwindow, src_processlifecycle_bye [INFERRED 0.85]
- **Keystroke sound pipeline: sync, render, emit** — src_acoustickeystrokes_synckeysounds, src_acoustickeystrokes_ak_buildbank, src_acoustickeystrokes_ak_render, src_acoustickeystrokes_ak_emit, src_acoustickeystrokes_ak_bank [EXTRACTED 1.00]
- **Notch OSD show/hide via NotchAnim and negative SetTimer** — src_audioosd_showvolumeosd, src_audioosd_hidevolumeosd, src_audioosd_showmicosd, src_audioosd_hidemicosd, src_overlaygui_notchanim [EXTRACTED 1.00]
- **Spectacle FX restore-on-exit contract** — src_fxcurtain_restorecurtain, src_fxshatter_restoreshatters, src_fxgravity_gravityclose, src_fxcurtain_curtaindropdown [INFERRED 0.85]
- **StealthCall runtime-resolved feature sync** — src_stealthpanic_stealthcall, src_stealthpanic_stealthsyncfeatures, src_stealthpanic_suspendstealthfeatures, src_stealthpanic_restorestealthfeatures [EXTRACTED 1.00]
- **Safe-app list sidecar storage** — src_stealthpanicconfig_stealthpanicconfig_readapplist, src_stealthpanicconfig_stealthpanicconfig_writeapplist, src_stealthpanicconfig_stealthpanicconfig_writefileatomic, src_stealthpanicconfig_stealthpanicconfig_migratetosidecar, src_stealthpanicui_savesettings [EXTRACTED 1.00]
- **Render pipeline contract: queue, compose, flush** — claude_render_pipeline, claude_composed_alpha, claude_who_flushes_rule, claude_animation_scheduler, claude_anim_channel_ownership, src_rendercore, src_animationscheduler [EXTRACTED 1.00]
- **Drag release to snap and glide landing** — claude_drag_pipeline_flow, claude_velocity_px_per_second, claude_magnetic_snapping, claude_ice_glide, claude_dragfullwindows_dependency, src_dragpipeline_finishdrag, src_dropplacement_snapwindow, src_dropplacement_glide [EXTRACTED 1.00]
- **Single-source-of-truth settings/teardown registries** — claude_tuning_registry, docs_modularization_feature_spec, docs_modularization_teardown_spec, claude_enum_membership_validation, src_tuningregistry [INFERRED 0.85]
- **Render arbitration and scheduler ported from Windows** — linux_src_core_renderqueue_h_core_renderqueue, linux_src_core_animationscheduler_h_core_animationscheduler, src_rendercore, src_animationscheduler, linux_claude_composed_opacity, linux_claude_channel_ownership [EXTRACTED 1.00]
- **Panel clock weather end-to-end path** — linux_src_core_weatherfetcher_h_core_weatherfetcher, linux_src_platform_wayland_dbusdaemon_h_wayland_dbusdaemon, gnome_extension, docs_architecture_weather_path [EXTRACTED 1.00]
- **Wayland compute-publish-apply model** — linux_claude_tweaksd_daemon, linux_claude_dbus_contract, linux_claude_wayland_dbus_strategy, docs_wayland_limitations_core_daemon_extension_model, linux_claude_kwin_compiled_plugin [INFERRED 0.85]

## Communities (69 total, 6 thin omitted)

### Community 0 - "Render & Animation Core"
Cohesion: 0.05
Nodes (119): 15 ms Frame Period, Animation Channel Ownership (geom/alpha/region), Animation Scheduler (single frame loop), Composed Opacity (base x layers), Parameterise Animation on Elapsed Time, Gui Lifetime Must Cover Its Animation, Morph Maximize, Window Positions Deliberately Not Cached (+111 more)

### Community 1 - "Drag, Snap & Glide"
Cohesion: 0.08
Nodes (55): Drag Parallax Endpoint-Calibrated Ramp, Drag Pipeline Flow, Low-Level Mouse Hook Trade-off, Never Touch Disk on an Input Path, Measured Operation Costs, Position Memory, Velocity in Pixels per Second, AltDragMove() (+47 more)

### Community 2 - "Settings & Tuning Registry"
Cohesion: 0.08
Nodes (48): Enum Settings Validated by Membership, Game Mode, Space-Semicolon Comment Trap in Strings, Tuning Registry (TUNE_SPEC), Window Tweaks User Guide, Core Features (snap, glide, on-top, memory), Getting Out of Trouble (restore-all), Settings Window and Its Numbers (+40 more)

### Community 3 - "Media-Aware Ambient Dimming"
Cohesion: 0.11
Nodes (42): BreathingAnimatorStep(), BreathingMonitorStep(), MC_Tick(), MonitorDimmerTickStep(), SyncBreathingTimers(), SyncDimmerTimer(), SyncMediaCore(), ToggleBreathing() (+34 more)

### Community 4 - "Hotkeys & Input Bindings"
Cohesion: 0.07
Nodes (36): TileWindow(), CLIP_BACKUP_MS, CLIP_DOUBLE_MS, GetActiveExplorerPath(), CapsLock, Ctrl+Alt+v, Ctrl+g, Double-tap Ctrl (Spotlight) (+28 more)

### Community 5 - "Stealth Panic Mode"
Cohesion: 0.10
Nodes (33): Stealth Panic Mode, Safe-App List Sidecar File, ActivateExistingInstance(), ActivateExplorer(), DerefEnv(), EnterStealthPanic(), FindVisualStudio(), LaunchSafeApps() (+25 more)

### Community 6 - "Keystroke Sound Synthesis"
Cohesion: 0.11
Nodes (33): Synthesised Keystroke and Hotkey Sounds, InputHook OnKeyDown Needs Notify Option, Map.Delete Throws on Missing Key, Purge Playback Before Freeing Sound Buffer, Acoustic Keystrokes & Ripples, AK_ACTION_VOICES, AK_BANK, AK_BankHotVol (+25 more)

### Community 7 - "Linux X11 Adapter"
Cohesion: 0.07
Nodes (18): Capability, supports(Capability) honest backend query, Rect, RegionSpec, string, ZOrderSpec, Point, WindowState (+10 more)

### Community 8 - "Linux Render Queue"
Cohesion: 0.13
Nodes (24): AlphaCommand, applyOnce(), clearAlphaLayer(), clearRegion(), commit(), flush(), queueAlphaLocked(), recomposeAlphaLocked() (+16 more)

### Community 9 - "Custom Taskbar Clock"
Cohesion: 0.13
Nodes (27): Clock Anchor Setting (TrayEdge vs Clock), Custom Taskbar Clock, open-meteo over Async WinHttp, Overlay Must Forward WM_CLOSE to ExitApp, Paint Taskbar Colour Instead of Colour-Keying, CLOCK_GAP, ClockUrlPart(), CustomClockBuiltFor (+19 more)

### Community 10 - "Linux Animation Scheduler"
Cohesion: 0.16
Nodes (23): AnimationCallback, AnimChannel, AnimationScheduler(), cancelAnimation(), cancelLocked(), claim(), forgetOwnershipLocked(), loop() (+15 more)

### Community 11 - "Settings Window GUI"
Cohesion: 0.15
Nodes (20): Inputs Need Both Background and Text Colour, Settings Window Scroll Affordance, Shift+Alt+w, Box(), BuildWin(), CloseWin(), Gui_Size(), Head() (+12 more)

### Community 12 - "Pinned Window Modes"
Cohesion: 0.15
Nodes (19): Off Only for Structurally Neutral Alpha Record, Shift+Alt+b, Shift+Alt+g, Shift+Alt+p, ClosePiP(), GetDesktopHwnd(), GetDistToRect(), GhostMonitorStep() (+11 more)

### Community 13 - "Tray & Feature Toggles"
Cohesion: 0.16
Nodes (21): FlushTransNotify(), Notify(), BuildTray(), Shift+Alt+o, SyncTray(), ToggleCursorWrap(), ToggleDimmer(), ToggleFeatureFlag() (+13 more)

### Community 14 - "Linux Port Guidance"
Cohesion: 0.11
Nodes (19): TweakCore(), RenderQueue(), TweakCore(), Linux port CLAUDE.md, Composed opacity (base x named layers), D-Bus contract org.tweakforeveryone.Daemon, Early scaffold status (does not manage windows), GNOME 45 ESM extension API break (+11 more)

### Community 15 - "Module Split Rules"
Cohesion: 0.14
Nodes (19): Pure ASCII No-BOM .ahk Source, Check-Split.ps1 Structural Checks, Flat src/ and No-Underscore Filename Rule, #HotIf Is Positional and Bleeds Across Includes, Module Include Contract (no top-level calls), Motion Proof Hash, Packaging (Install.ps1 + Setup.cs), ExitApp-Prepended Parse Check (+11 more)

### Community 16 - "Boot & Feature Sync"
Cohesion: 0.26
Nodes (17): Infinite Cursor Wrap Intent Model, GameModeSyncFeatures(), SyncTextExpander(), UpdateKeyboardHook(), SyncCursorFxTimer(), SyncShakeDetector(), Boot(), CursorWrapMonitorStep() (+9 more)

### Community 17 - "Quick Look & Spotlight"
Cohesion: 0.19
Nodes (15): Enter, Escape, Shift+Alt+q, Space, CheckMagDrag(), CheckQuickLookFocusStep(), CloseQuickLook(), GetSelectedExplorerFile() (+7 more)

### Community 18 - "Linux Render Pipeline Design"
Cohesion: 0.16
Nodes (13): TweakCore(), TweakCore(), Central Render Pipeline, Render priorities ambient < animation < drag < user, 16 ms frame period (vs 15 ms on Windows), Structural alpha off for neutral record, Swap-and-release flush pattern, Threads::Threads link requirement (+5 more)

### Community 19 - "Linux Architecture Plan"
Cohesion: 0.17
Nodes (14): TweakCore(), Linux Architecture doc, Common Core + Platform Adapters, ConfigParser tuning registry (planned), LayoutEngine (planned), Shift+Alt single-chord hotkey scheme, StateManager (planned), Weather end-to-end path (+6 more)

### Community 20 - "Volume & Mic OSD"
Cohesion: 0.24
Nodes (13): GetMicOSDPos(), GetSpeakerIcon(), GetVolumeOSDPos(), HideMicOSD(), HideVolumeOSD(), ShowMicOSD(), ShowVolumeOSD(), ToggleDefaultMic() (+5 more)

### Community 21 - "Windows Animation Settings"
Cohesion: 0.15
Nodes (15): DragFullWindows Hard Dependency, Ice Glide, Windows Snap Assist Wins at Screen Edges, Windows Animation Settings for Window Tweaks, Show Window Contents While Dragging (required), Deliberately Not Recommended Tweaks, Recommended Animation Settings (MinAnimate, TaskbarAnimations, UserPreferencesMask), Windows Snap Assist Conflict (+7 more)

### Community 22 - "Tuning Backup Example"
Cohesion: 0.13
Nodes (14): Computer, Created, DragFullWindows, EnableAeroPeek, EnableTransparency, LaunchTo, ListviewAlphaSelect, ListviewShadow (+6 more)

### Community 23 - "Keyboard Window Layout"
Cohesion: 0.40
Nodes (13): Keyboard Window Layout via ApplyLayout, Window Layout Hotkeys, ApplyLayout(), CenterWindow(), CycleWindowSize(), MoveToNextMonitor(), RememberLayout(), SIZE_CYCLE (+5 more)

### Community 24 - "Win32 Shell Internals"
Cohesion: 0.16
Nodes (13): Taskbar Height Engine Removed, SendMessage Only With Timeout, Shell Hook Re-registration on TaskbarCreated, Two Coordinate Spaces (DWM frame vs WinGetPos), Win32 Gotchas, Snapping Design and Taskbar Research, ExplorerPatcher Integration, Resource Use (~18 MB, shell hook not polling) (+5 more)

### Community 25 - "Animation Roadmap"
Cohesion: 0.16
Nodes (13): Future Animations Roadmap (Azerbaijani), Black Hole Suck, Breathe Cursor, Cursor Yawn, Dynamic Notch, Taskbar Icon Wave, Momentum Tilt, Ripple Click (+5 more)

### Community 26 - "Linux Test Harness"
Cohesion: 0.16
Nodes (6): namespace, namespace, TweakTest(), main(), waitFrames(), TweakTest()

### Community 27 - "Shell Surface Watcher"
Cohesion: 0.23
Nodes (12): ToggleSmartTaskbar(), Shift+Alt+t, CheckTaskbarAndUI(), CheckToasts(), KnownToasts, RenderTaskbarWave(), SetTaskbarAutoHide(), SmartTaskbarLastState (+4 more)

### Community 28 - "Focus / Cinema Mode"
Cohesion: 0.45
Nodes (12): FocusAnimatorStep(), FocusBounds, FocusFeather, FocusGuis, FocusModeEnabled, FocusMonitorStep(), FocusTargetHwnd, SpotlightCurrent (+4 more)

### Community 29 - "Linux Core Headers"
Cohesion: 0.17
Nodes (8): TweakCore(), TweakCore(), TweakCore(), TweakCore(), namespace, namespace, namespace, namespace

### Community 30 - "Linux CMake Build"
Cohesion: 0.24
Nodes (12): Absent-not-empty directory check, core -> PlatformAdapter -> backend dependency flow, Linux CMakeLists.txt, TweakCore library target, TweakPlatformWayland library target, TweakPlatformX11 library target, tweaksd executable target, TweakUI target removed (+4 more)

### Community 31 - "Tray Minimize & Restore"
Cohesion: 0.23
Nodes (10): PlayHotkeySound(), RestoreAllWindows(), AskWindowIcon(), HideToTray(), RestoreFromTray(), ToggleBossKey(), TrayIconClick(), Shift+Alt+Esc (+2 more)

### Community 33 - "Effect Taste Constraints"
Cohesion: 0.20
Nodes (10): Linux Qt6 Port (linux/), Opacity-Only Effects Taste Constraint, Rejected roadmap effects (Lightsaber Glow, Privacy Blur, Carousel, Motion Blur, Depth of Field, Spark Typing, Slide-Up Blur), README: Tweaks For Everyone, FAQ (Magnet/FancyZones alternatives, admin rights, Windows 10), Full Feature Suite (40+ Tweaks & Animations), Optional Windows Tuning, Shadow & Ambient Effects Modification Report (+2 more)

### Community 34 - "Linux Install & Wayland"
Cohesion: 0.22
Nodes (10): Linux Installation Guide, Per-distro build dependencies, install.sh guided installer, Session detection (XDG_SESSION_TYPE), Wayland Limitations doc, Core Daemon + Extension model, Wayland feature support table, Wayland client sandbox constraints (+2 more)

### Community 35 - "Hotkey Reference Docs"
Cohesion: 0.31
Nodes (9): Keypad Tiling Dead With NumLock Off, Single Shift+Alt Hotkey Chord, Stale Win+Ctrl Tray Labels, Hotkeys Reference (source of truth), Feature-Gated #HotIf Hotkeys, Gestures and Other Keys, Keypad-Shaped 3x3 Tiling Grid, Hotkeys Delegate to Named Functions (+1 more)

### Community 36 - "Linux Geometry Types"
Cohesion: 0.25
Nodes (6): TweakCore(), TweakCore(), namespace, namespace, vector, listWindows()

### Community 37 - "Icon Generator Script"
Cohesion: 0.43
Nodes (5): Add-Window(), Clear-Gap(), New-Frame(), New-RoundedPath(), New-UnitRect()

### Community 38 - "Linux Clipboard Manager"
Cohesion: 0.29
Nodes (4): ClipboardManager(), handleClipboardAppend(), shared_ptr, string

### Community 39 - "Linux Snap Geometry"
Cohesion: 0.46
Nodes (7): collectLines(), computeSnap(), snapAxis(), SnapGeometry(), Rect, vector, SnapParams

### Community 40 - "Linux Feature Matrix"
Cohesion: 0.25
Nodes (7): Linux Feature Matrix, Implement against Cinnamon/X11 first, Native vs extension-required legend, 34-feature x 5-environment matrix, Cinnamon extension requirement, namespace, TweakPlatform()

### Community 41 - "MCP Server Config"
Cohesion: 0.32
Nodes (7): npx, filesystem, git, playwright, @cyanheads/git-mcp-server, @modelcontextprotocol/server-filesystem, @playwright/mcp

### Community 42 - "Magnetic Snap Geometry"
Cohesion: 0.43
Nodes (5): Magnetic Snapping, Component status table, CollectEdges(), IsCloaked(), IsSnappable()

### Community 43 - "Alt-Drag & Close Effects"
Cohesion: 0.33
Nodes (3): Curtain Drop (Win+D), AltDragResize(), Alt+RButton

### Community 44 - "Engineering Guidelines"
Cohesion: 0.33
Nodes (6): Architecture Rules (ownership, SSOT, layering), Coupling by Shared Globals, Professional Engineering Guidelines, Analyze Before Implementing, Self Code Review Before Completion, SOLID / DRY / Separation of Concerns

### Community 46 - "Linux Physics"
Cohesion: 0.40
Nodes (3): parallaxAlpha(), ParallaxRamp, ParallaxResult

### Community 47 - "Linux Velocity Sampler"
Cohesion: 0.67
Nodes (5): begin(), emaFactor(), sample(), smoothAlpha(), speed()

### Community 48 - "Linux Weather Fetcher"
Cohesion: 0.47
Nodes (5): fetchWeather(), onReplyFinished(), start(), WeatherFetcher(), QNetworkReply

### Community 49 - "Volume Wheel & Morph Paste"
Cohesion: 0.40
Nodes (6): ChangeVolumeOSD(), HideMorphPreview(), Ctrl+v, WheelDown, WheelUp, MorphString()

### Community 50 - "Window Roll-Up"
Cohesion: 0.40
Nodes (5): CaptionHeight(), ToggleRollUp(), MButton, Shift+Alt+r, IsMouseOverTaskbar()

### Community 51 - "Linux Layer Check Script"
Cohesion: 0.70
Nodes (4): check-layers.sh script, bad(), note(), ok()

### Community 52 - "Defensive Programming Rules"
Cohesion: 0.40
Nodes (5): Defensive Programming & Quality Guidelines (project), Defensive Programming & Quality Guidelines, Defensive Code & Edge-Case Handling, Non-Destructive Integration, Simple and Robust Logic

### Community 55 - "GNOME Extension Metadata"
Cohesion: 0.40
Nodes (4): description, name, shell-version, uuid

### Community 58 - "Window Classification"
Cohesion: 0.70
Nodes (4): ClassifyWindowImpl(), GetProcessCommandLine(), IsMainApplicationWindow(), WindowCmdLineCache

## Ambiguous Edges - Review These
- `Opacity-Only Effects Taste Constraint` → `Full Feature Suite (40+ Tweaks & Animations)`  [AMBIGUOUS]
  README.md · relation: conceptually_related_to
- `Check-Split.ps1 Structural Checks` → `Note: Never Write Tests Into Project`  [AMBIGUOUS]
  docs/claude.md · relation: conceptually_related_to

## Knowledge Gaps
- **115 isolated node(s):** `enabledMcpjsonServers`, `@modelcontextprotocol/server-filesystem`, `@cyanheads/git-mcp-server`, `@playwright/mcp`, `shared_ptr` (+110 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Opacity-Only Effects Taste Constraint` and `Full Feature Suite (40+ Tweaks & Animations)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Check-Split.ps1 Structural Checks` and `Note: Never Write Tests Into Project`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CLAUDE.md (Windows Tweaks project guide)` connect `Module Split Rules` to `Render & Animation Core`, `Drag, Snap & Glide`, `Settings & Tuning Registry`, `Media-Aware Ambient Dimming`, `Hotkeys & Input Bindings`, `Stealth Panic Mode`, `Keystroke Sound Synthesis`, `Custom Taskbar Clock`, `Settings Window GUI`, `Pinned Window Modes`, `Tray & Feature Toggles`, `Boot & Feature Sync`, `Quick Look & Spotlight`, `Volume & Mic OSD`, `Windows Animation Settings`, `Keyboard Window Layout`, `Win32 Shell Internals`, `Animation Roadmap`, `Shell Surface Watcher`, `Focus / Cinema Mode`, `Tray Minimize & Restore`, `Effect Taste Constraints`, `Hotkey Reference Docs`, `Magnetic Snap Geometry`, `Alt-Drag & Close Effects`, `Engineering Guidelines`, `Window Roll-Up`, `Defensive Programming Rules`, `Window Classification`?**
  _High betweenness centrality (0.299) - this node is a cross-community bridge._
- **Why does `vector` connect `Linux Geometry Types` to `Linux X11 Adapter`, `Linux Render Queue`, `Linux Animation Scheduler`, `Linux Render Pipeline Design`, `Linux Test Harness`, `Linux Core Headers`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Why does `Linux port CLAUDE.md` connect `Linux Port Guidance` to `Linux Install & Wayland`, `Linux Geometry Types`, `Linux Feature Matrix`, `Linux Animation Scheduler`, `Linux Render Pipeline Design`, `Linux Architecture Plan`, `Linux Core Headers`, `Linux CMake Build`?**
  _High betweenness centrality (0.057) - this node is a cross-community bridge._
- **What connects `enabledMcpjsonServers`, `@modelcontextprotocol/server-filesystem`, `@cyanheads/git-mcp-server` to the rest of the system?**
  _137 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Render & Animation Core` be split into smaller, more focused modules?**
  _Cohesion score 0.050666666666666665 - nodes in this community are weakly interconnected._