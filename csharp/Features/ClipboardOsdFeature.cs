using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using WindowTweaks.Core;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace WindowTweaks.Features;

/// <summary>
/// Feedback for the editing chords: Ctrl+C, Ctrl+V, Ctrl+X, Ctrl+A, Ctrl+Z and Ctrl+Y each get their
/// own sound and their own coloured pulse at the cursor.
///
/// Undo and redo live HERE rather than in ShortcutSoundsFeature, which owns the Windows chords,
/// because they are the same kind of thing as copy and paste: an editing command the focused
/// application carries out, not a shell gesture. They also want the ring and the word at the cursor,
/// which this feature already builds - a second implementation of Announce would be the whole point
/// of that method wasted.
///
/// THE POINT IS THAT THE FOUR ARE DISTINGUISHABLE. The first version played one sound - the shared
/// Windows asterisk - for all four, and showed a label, so the only way to tell a copy from a cut was
/// to read it. Now each action has a pitched sound (copy rises, paste falls, cut is a dry snip,
/// select-all is a chord) and a ring in its own colour, so the confirmation lands without looking.
///
/// Two implementation notes that are easy to get wrong:
///
///   - MODIFIER STATE IS READ, NOT TRACKED. Tracking Ctrl-down from the hook looks simpler and is
///     wrong: the key-up is missed whenever it happens while the hook is not installed, while
///     another window has an input queue of its own, or during a lock-screen transition - after
///     which the feature believes Ctrl is held forever and pulses on every bare C. GetAsyncKeyState
///     asks the OS for the truth instead.
///
///   - THE SOUND DOES NOT GO THROUGH THE DISPATCHER. Only the visual does. SoundEngine is safe to
///     call from the hook thread, and a UI-thread hop per keystroke is exactly the queue pressure
///     that made this app feel wedged.
/// </summary>
public class ClipboardOsdFeature : IDisposable
{
    private const string HookOwner = nameof(ClipboardOsdFeature);

    private const int VK_CONTROL = 0x11;
    private const int VK_C = 0x43, VK_V = 0x56, VK_X = 0x58, VK_A = 0x41;
    private const int VK_Z = 0x5A, VK_Y = 0x59;

    /// <summary>Ctrl+Shift+Z is redo wherever Ctrl+Y is not.</summary>
    private const int VK_SHIFT = 0x10;

    /// <summary>
    /// Ctrl+C twice in quick succession is one gesture to a person, not two. Without this a held
    /// Ctrl+V (auto-repeat) fires a pulse thirty times a second.
    /// </summary>
    private const double MinIntervalMs = 180.0;

    private long _lastShown;

    private OsdWindow? _osd;
    private Window? _pulseWindow;
    private Ellipse? _pulseRing;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            // Built off the input path, so the first Ctrl+C of the session does not pay for
            // synthesising a sound on the hook thread.
            SoundEngine.Prewarm(
                TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile),
                TuningRegistry.Int(TuningRegistry.ClipboardSoundVolume),
                SoundId.Copy, SoundId.Paste, SoundId.Cut, SoundId.SelectAll, SoundId.Transform,
                SoundId.Undo, SoundId.Redo);

            KeyboardHook.Subscribe(HookOwner, OnKey);
        }
        else
        {
            KeyboardHook.Unsubscribe(HookOwner);

            // Teardown of the overlays belongs on the dispatcher, and the flag test belongs here
            // rather than at the call site: switching a feature off must be able to take down the
            // window it owns.
            OsdWindow.RunOnUi(TearDownVisuals);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnKey(KeyboardHook.KeyEvent e)
    {
        if (!e.IsKeyDown || e.IsInjected) return false;

        // Cheapest test first: six keys out of a hundred and five.
        if (e.VirtualKey is not (VK_C or VK_V or VK_X or VK_A or VK_Z or VK_Y)) return false;

        if ((NativeMethods.GetAsyncKeyState(VK_CONTROL) & 0x8000) == 0) return false;

        long now = Stopwatch.GetTimestamp();
        double sinceMs = (now - _lastShown) / (double)Stopwatch.Frequency * 1000.0;
        if (_lastShown != 0 && sinceMs < MinIntervalMs) return false;
        _lastShown = now;

        // Ctrl+Shift+Z is redo in the applications that do not use Ctrl+Y, so the same key means
        // opposite things depending on Shift. Read, not tracked, like every other modifier here.
        bool shift = (NativeMethods.GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

        (string label, SoundId sound, Color colour) = e.VirtualKey switch
        {
            VK_C => ("Copied", SoundId.Copy, Color.FromRgb(0x9A, 0xD4, 0xFF)),
            VK_V => ("Pasted", SoundId.Paste, Color.FromRgb(0xA8, 0xE6, 0xA0)),
            VK_X => ("Cut", SoundId.Cut, Color.FromRgb(0xFF, 0xC1, 0x8A)),
            VK_A => ("All selected", SoundId.SelectAll, Color.FromRgb(0xD8, 0xB4, 0xFF)),

            // The pair reads as one axis: undo is the cooler colour, redo the warmer one, and their
            // sounds are the same glide in opposite directions.
            VK_Z when shift => ("Redone", SoundId.Redo, Color.FromRgb(0xC7, 0xE8, 0xB0)),
            VK_Z => ("Undone", SoundId.Undo, Color.FromRgb(0xB6, 0xC6, 0xE8)),
            _ => ("Redone", SoundId.Redo, Color.FromRgb(0xC7, 0xE8, 0xB0))
        };

        Announce(label, sound, colour);

        // Never suppress. The chord has to reach the application - this feature only comments on it.
        return false;
    }

    /// <summary>
    /// Shows the label and the pulse, and plays the sound. Internal rather than private because the
    /// camelCase formatter reuses it to confirm its own transformation - and internal rather than
    /// public because SoundId is, and the feature classes themselves are public only by convention.
    /// </summary>
    internal void Announce(string label, SoundId sound, Color colour)
    {
        // The switch is honoured here rather than only at the hook, because the camelCase formatter
        // calls in from outside. Without this the sound still played while this feature was off - so
        // switching "copy and paste feedback" off silenced three of the four confirmations and left
        // camelCase making a noise with nothing on screen to explain it. A feature that is off does
        // nothing at all.
        if (!IsEnabled) return;

        SoundEngine.Play(sound,
            TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile),
            TuningRegistry.Int(TuningRegistry.ClipboardSoundVolume));

        if (!TuningRegistry.Is(TuningRegistry.ClipboardShowOsd, "on")) return;

        // The cursor position is read on the dispatcher rather than passed in from the hook: by the
        // time the pulse is drawn the hand has already moved, and the pulse belongs where the
        // pointer IS.
        OsdWindow.Post(() =>
        {
            if (!IsEnabled) return;

            if (!NativeMethods.GetCursorPos(out NativeMethods.POINT pt)) return;

            Pulse(pt.X, pt.Y, colour);

            _osd ??= new OsdWindow();
            _osd.Show(label, pt.X, pt.Y, 700);
        });
    }

    /// <summary>
    /// A ring that expands and fades at the cursor - the same visual language as Ripple Click, and
    /// deliberately a fade rather than a pulse or a glow. See the owner's taste in CLAUDE.md.
    /// </summary>
    private void Pulse(int physicalX, int physicalY, Color colour)
    {
        try
        {
            const int Diameter = 84;

            double scale = OverlayPlacement.ScaleAt(physicalX, physicalY);

            if (_pulseWindow == null)
            {
                _pulseRing = new Ellipse
                {
                    StrokeThickness = 3,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    IsHitTestVisible = false
                };

                _pulseWindow = new Window
                {
                    WindowStyle = WindowStyle.None,
                    AllowsTransparency = true,
                    Background = Brushes.Transparent,
                    Topmost = true,
                    ShowActivated = false,
                    ShowInTaskbar = false,
                    ResizeMode = ResizeMode.NoResize,
                    IsHitTestVisible = false,
                    Content = _pulseRing,
                    Opacity = 0,
                    Left = -10000,
                    Top = -10000
                };

                _pulseWindow.SourceInitialized += (_, _) => OverlayPlacement.MakeClickThrough(_pulseWindow);
            }

            if (_pulseRing == null) return;

            // Width and Height are WPF units, so the physical size has to be divided by the scale of
            // the monitor the pulse is landing on - otherwise the ring is 150% too big at 150%.
            _pulseWindow.Width = Diameter / scale;
            _pulseWindow.Height = Diameter / scale;

            _pulseRing.Stroke = new SolidColorBrush(colour);
            _pulseRing.Fill = new SolidColorBrush(Color.FromArgb(0x20, colour.R, colour.G, colour.B));

            if (!_pulseWindow.IsVisible) _pulseWindow.Show();

            OverlayPlacement.CentreOn(_pulseWindow, physicalX, physicalY);
            OverlayPlacement.MakeClickThrough(_pulseWindow);

            double target = Diameter / scale;
            Duration duration = new(TimeSpan.FromMilliseconds(420));
            IEasingFunction ease = new CubicEase { EasingMode = EasingMode.EaseOut };

            DoubleAnimation grow = new(target * 0.25, target, duration) { EasingFunction = ease };
            DoubleAnimation fade = new(0.9, 0.0, duration) { EasingFunction = ease };

            // Hide on completion rather than closing: this window is reused, and creating a layered
            // WPF window per keystroke is tens of milliseconds of UI-thread work each time.
            fade.Completed += (_, _) =>
            {
                try { if (_pulseWindow != null && _pulseWindow.Opacity <= 0.01) _pulseWindow.Hide(); } catch { }
            };

            _pulseRing.BeginAnimation(FrameworkElement.WidthProperty, grow);
            _pulseRing.BeginAnimation(FrameworkElement.HeightProperty, grow);
            _pulseWindow.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        catch
        {
            // Cosmetic.
        }
    }

    private void TearDownVisuals()
    {
        try
        {
            _osd?.Dispose();
            _osd = null;

            if (_pulseWindow != null)
            {
                _pulseWindow.BeginAnimation(UIElement.OpacityProperty, null);
                _pulseWindow.Close();
                _pulseWindow = null;
            }

            _pulseRing = null;
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
