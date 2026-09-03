# Window Tweaks - Full Feature List

The following list contains all features present in the project, including both existing implementations and newly added ones (currently set up as stubs).

## 🛠 1. Power-User Tweaks
- **Smart Auto-Hide Taskbar**: Hides the taskbar only when a window is maximized or touches the bottom edge. *(Exists: SmartTaskbarFeature)*
- **macOS Quick Look**: Previews the selected file instantly in Explorer by pressing Space. *(Exists: QuickLookFeature)*
- **Multi-Monitor Focus Dimmer**: Automatically dims inactive monitors by 50% to reduce eye strain. *(Exists: MultiMonitorDimmerFeature)*
- **macOS Hot Corners**: Triggers commands (Task View, Hide Windows, etc.) by moving the mouse to screen corners. *(Exists: HotCornersFeature)*
- **Premium Volume OSD**: A macOS-style blurred volume indicator that appears when adjusting volume on the taskbar. *(Exists: TaskbarVolumeFeature)*
- **Live Window PiP (Shift+Alt+P)**: Creates a live, always-on-top Picture-in-Picture version of any window. *(Exists: LivePipFeature)*
- **Universal Grab & Pan**: Middle-click and drag to pan any window, similar to the Photoshop Hand Tool. *(Exists: GrabPanFeature)*
- **Global Mic Kill-Switch**: Mutes the microphone globally by double-tapping the Alt key. *(Exists: MicMuteFeature)*
- **Infinite Cursor Wrap**: Wraps the cursor around screen edges on multi-monitor or large setups (teleportation). *(Exists: InfiniteWrapFeature)*
- **Quick Spotlight Launcher**: Opens a minimalist search and launcher bar by double-tapping the Ctrl key. *(Exists: SpotlightFeature)*
- **Smart Active Border**: Draws a colorful, elegant border exclusively around the active window. *(Newly Added: SmartActiveBorderFeature)*
- **Always on Bottom (Shift+Alt+B)**: Pins any window to the background like a desktop widget. *(Exists: AlwaysOnBottomFeature)*
- **Global Text Expander**: Automatically expands abbreviations like @@mail or @@date into full text snippets. *(Newly Added: GlobalTextExpanderFeature)*
- **Middle-Click to Close**: Closes any window instantly by middle-clicking its title bar. *(Exists: MiddleClickCloseFeature)*
- **Proximity Ghost Window (Shift+Alt+G)**: Makes a window 80% transparent, becoming solid and clickable only when the cursor approaches. *(Exists: ProximityGhostFeature)*

## 🚀 2. Performance & OS Tuning
- **Zero-delay Menus**: Opens context menus instantly (0-50ms) mimicking macOS responsiveness. *(Newly Added: ZeroDelayMenusFeature)*
- **Snappy Taskbar Previews**: Accelerates taskbar window previews from the default 400ms down to 100ms. *(Newly Added: SnappyTaskbarPreviewsFeature)*
- **Smooth Scrolling**: Applies interpolated, buttery-smooth scrolling globally across all applications. *(Newly Added: SmoothScrollingFeature)*

## ✨ 3. Premium Window Animations
- **Fade In / Ease-Out**: Replaces abrupt window disappearance in Focus Mode with cinematic fade-in/out transitions. *(Newly Added: FadeInEaseOutFeature)*
- **Custom Text Caret**: Overrides the default text cursor with a thicker, smoother, eye-friendly caret. *(Newly Added: CustomTextCaretFeature)*
- **Bouncy Snapping**: Adds a rubber-band bounce effect when snapping windows to screen edges. *(Newly Added: BouncySnappingFeature)*
- **Gravity Drop Close (Alt+F4)**: Makes closing windows fall downwards with gravity before fading out. *(Exists: GravityCloseFeature)*
- **Breathing Backgrounds**: Slowly fades inactive windows to 70% transparency after 6 seconds of inactivity. *(Exists: BreathingFeature)*
- **Focus Pulse**: Gently swells and shrinks (2-3% scale) a window when focused via Alt+Tab to draw attention. *(Newly Added: FocusPulseFeature)*
- **Ghost Slide-In**: Animates new application windows sliding up smoothly from the bottom like a smartphone app. *(Newly Added: GhostSlideInFeature)*
- **Parallax Dragging**: Makes a window transparent based on how fast you drag it (faster equals more transparent). *(Exists: DragParallaxFeature)*
- **Magnetic Seam Flash**: Emits a brief neon flash effect where the borders of two windows magnetically snap together. *(Newly Added: MagneticSeamFlashFeature)*
- **Theater Spotlight**: Darkens the background and creates a spotlight effect following the cursor over the active window. *(Newly Added: TheaterSpotlightFeature)*
- **Fly-to-Mouse Minimize**: Sucks minimizing windows directly into the mouse cursor rather than the taskbar. *(Newly Added: FlyToMouseMinimizeFeature)*
- **Window Unrolling**: Unrolls new windows vertically from top to bottom like a window blind in 0.2 seconds. *(Newly Added: WindowUnrollingFeature)*

## 🌪 4. Next-Gen Physics & Tactile Animations
- **Ripple Click**: Creates a water ripple effect on every mouse click. *(Exists: RippleClickFeature)*
- **Context Menu Unfold**: Unfolds context menus downwards like origami instead of appearing instantly. *(Newly Added: ContextMenuUnfoldFeature)*
- **Elastic Drag (Ghost Drift)**: Creates a rubber-band stretching effect when dragging files and snaps back on release. *(Newly Added: ElasticDragFeature)*
- **Cursor Yawn & Breathe**: Makes an idle cursor subtly breathe and yawn when left untouched. *(Newly Added: CursorYawnBreatheFeature)*
- **Momentum Tilt**: Slightly tilts windows in the direction of movement while dragging and settles with inertia. *(Newly Added: MomentumTiltFeature)*
- **Black Hole Minimize & Delete**: Sucks minimizing windows and deleted files into a gravitational black hole effect. *(Newly Added: BlackHoleMinimizeFeature)*
- **Resistance Edge**: Simulates tactile rubber-like resistance when dragging a window against screen edges. *(Newly Added: ResistanceEdgeFeature)*
- **Focus Depth (Portal Scale-In)**: Pushes inactive windows into the background in 3D while scaling the active one forward. *(Newly Added: FocusDepthFeature)*
- **Spark Typing & Acoustic Keystrokes**: Generates MIDI ASMR clicks, neon cursor trails, and equalizers while typing. *(Exists: AcousticKeyboardFeature)*
- **Carousel Alt-Tab**: Replaces the flat Alt-Tab switcher with a rotating 3D carousel of windows. *(Newly Added: CarouselAltTabFeature)*
- **Dynamic Notch (OSD)**: Drops an iOS-style Dynamic Island from the top of the screen for volume and brightness. *(Newly Added: DynamicNotchFeature)*
- **Curtain Drop (Win+Alt+D)**: Drops all windows to the desktop using kinetic motion blur. *(Newly Added: CurtainDropFeature)*
- **Motion Blur Scroll**: Applies a vertical motion blur effect while scrolling fast for extreme perceived smoothness. *(Newly Added: MotionBlurScrollFeature)*
- **Overscroll Bounce**: Adds an Apple-style rubber-band bounce effect when reaching the top or bottom of a scrolling page. *(Newly Added: OverscrollBounceFeature)*
- **Taskbar Icon Wave & Elastic Toasts**: Makes taskbar icons wave and notifications bounce elastically on mouse hover like macOS. *(Newly Added: TaskbarIconWaveFeature)*
- **Start Menu Slide-Up Blur**: Generates a deep background blur effect transitioning smoothly as the Start Menu opens. *(Newly Added: StartMenuBlurFeature)*
- **Window Throw & Catch**: Allows throwing a window kinetically across monitors so it flies and lands on the other screen. *(Newly Added: WindowThrowCatchFeature)*
- **Shatter to Close (Shift+Alt+F4)**: Smashes the window into 3D glass shards when closing it. *(Exists: ShatterCloseFeature)*
- **Lightsaber Seam Glow**: Illuminates a glowing Jedi lightsaber edge when hovering over the seam of snapped windows. *(Newly Added: LightsaberSeamGlowFeature)*
- **Privacy Blur on Unfocus (Win+Alt+B)**: Overlays an unreadable frosted glass blur over private windows when they lose focus. *(Newly Added: PrivacyBlurFeature)*

## 📐 5. Layout & Tiling
- **Numpad Tiling**: Places windows into specific screen corners in a grid format using Shift+Alt+Numpad1..9. *(Exists: TileWindowFeature)*
- **Centre / Cycle Size**: Centers a window perfectly or cycles its size between 50/75/90%. *(Exists: CenterWindowFeature, CycleWindowSizeFeature)*
- **Next Monitor Move**: Moves a window to the next monitor while preserving its relative size. *(Exists: NextMonitorFeature)*
- **Restore Everything (Shift+Alt+Y)**: Restores all hidden, closed, or ghosted windows (including Panic Mode) with a single key. *(Exists: RestoreAllFeature)*

## 💼 6. Remaining Management Functions
- **Transparency Control**: Adjusts the transparency of the active window using the mouse wheel. *(Exists: ChangeTransparencyFeature)*
- **Window Shade / Roll-Up**: Rolls a window up like a blind with a middle-click, leaving only its title bar visible. *(Exists: RollUpFeature)*
- **Minimize to Tray**: Hides any application from the taskbar into the system tray (clock area). *(Exists: TrayMinimizeFeature)*
- **Stealth Panic Mode (Boss Key)**: Instantly locks the system, mutes audio, and opens a safe application by pressing ESC 3 times. *(Exists: BossKeyFeature)*

