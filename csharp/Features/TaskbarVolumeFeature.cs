using System;
using System.Text;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Scroll the wheel over the taskbar to change the volume, with a readout that shows the change.
/// Middle-click the taskbar to mute.
///
/// WHY IT NO LONGER SENDS THE VOLUME KEYS. The first version synthesised VK_VOLUME_UP and
/// VK_VOLUME_DOWN and relied on Windows to draw its own flyout. That is what "the change is not
/// visible" was about: the shell's volume OSD is drawn by explorer, it is not guaranteed for
/// injected input, and it does not appear at all when the taskbar has been replaced - and the
/// installer in this repo explicitly waits for ExplorerPatcher, so a replaced taskbar is the
/// expected case here, not an edge case. Setting the endpoint volume directly always works, and
/// this app then draws its own readout, so the feedback cannot depend on a shell that may not be
/// the stock one.
///
/// The other benefit is resolution: the volume keys move in fixed 2% steps that the user cannot
/// change, and a notch of the wheel now moves by a configurable amount.
///
/// WHERE THE WORK HAPPENS. The wheel event arrives on the hook thread, where the budget is
/// microseconds. Deciding whether the pointer is over a taskbar is cheap and stays there; the volume
/// change is COM and the readout is WPF, so both hop to the dispatcher.
/// </summary>
public class TaskbarVolumeFeature : IDisposable
{
    private const string HookOwner = nameof(TaskbarVolumeFeature);

    private OsdWindow? _osd;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            SoundEngine.Prewarm(
                TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile),
                TuningRegistry.Int(TuningRegistry.VolumeTickVolume),
                SoundId.VolumeTick);

            // Wheel and buttons only. Subscribing to moves as well would call this handler a hundred
            // times a second to do nothing.
            MouseHook.Subscribe(HookOwner, MouseEvents.Wheel | MouseEvents.Buttons, OnMouse);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            OsdWindow.RunOnUi(TearDown);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        if (e.Message == NativeMethods.WM_MOUSEWHEEL)
        {
            // Grab and pan scrolls by injecting wheel events. Panning a window that happens to sit
            // under the pointer near the taskbar must not also change the volume.
            if (e.IsOurs) return false;

            if (!IsOverTaskbar(e.X, e.Y)) return false;

            int notches = e.WheelDelta / 120;
            if (notches == 0) notches = e.WheelDelta > 0 ? 1 : -1;

            int step = TuningRegistry.Int(TuningRegistry.VolumeWheelStep);
            int x = e.X;
            int y = e.Y;

            OsdWindow.Post(() => ApplyVolume(notches, step, x, y));

            // Swallowed, so the shell does not also act on the scroll - on some builds a wheel over
            // the taskbar cycles windows.
            return true;
        }

        if (e.Message == NativeMethods.WM_MBUTTONDOWN)
        {
            if (!TuningRegistry.Is(TuningRegistry.VolumeMiddleClickMute, "on")) return false;

            // Same arbitration as middle-click-to-close: grab and pan owns the physical press while
            // it is on and replays a tagged click if the gesture turned out to be a click, so act on
            // the replay rather than acting twice. See MiddleClickCloseFeature.OnMouse.
            if (!e.IsOurs && FeatureRegistry.IsEnabled(FeatureKeys.GrabPan)) return false;

            if (!IsOverTaskbar(e.X, e.Y)) return false;

            int x = e.X;
            int y = e.Y;
            OsdWindow.Post(() => ApplyMute(x, y));
            return true;
        }

        return false;
    }

    /// <summary>
    /// True when a physical point is over the primary taskbar or any secondary one. Cheap enough for
    /// the hook thread: one WindowFromPoint, one GetAncestor and one GetClassName, all in the
    /// single-digit microseconds, and only for a wheel or middle-click event.
    /// </summary>
    private static bool IsOverTaskbar(int x, int y)
    {
        try
        {
            NativeMethods.POINT pt = new() { X = x, Y = y };

            IntPtr hwnd = NativeMethods.WindowFromPoint(pt);
            if (hwnd == IntPtr.Zero) return false;

            IntPtr root = NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
            if (root == IntPtr.Zero) return false;

            StringBuilder sb = new(64);
            NativeMethods.GetClassName(root, sb, sb.Capacity);
            string cls = sb.ToString();

            // Shell_SecondaryTrayWnd is the taskbar on every monitor other than the primary. It was
            // already handled here; it is called out because the smart auto-hide feature had a bug
            // that came from forgetting those bars exist.
            return cls is "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";
        }
        catch
        {
            return false;
        }
    }

    private void ApplyVolume(int notches, int stepPercent, int x, int y)
    {
        if (!IsEnabled) return;

        float level = AudioManager.NudgeMasterVolume(notches, stepPercent);
        if (level < 0) return;

        SoundEngine.Play(SoundId.VolumeTick,
            TuningRegistry.Choice(TuningRegistry.KeyboardSoundProfile),
            TuningRegistry.Int(TuningRegistry.VolumeTickVolume));

        Announce(FormatLevel(level, false), level, x, y);
    }

    private void ApplyMute(int x, int y)
    {
        if (!IsEnabled) return;

        int state = AudioManager.ToggleMasterMute();
        if (state < 0) return;

        bool muted = state == 1;

        if (!AudioManager.TryGetMasterVolume(out float level, out _)) level = 0;

        Announce(FormatLevel(level, muted), muted ? 0 : level, x, y);
    }

    private static string FormatLevel(float level, bool muted)
    {
        int percent = (int)Math.Round(level * 100);

        // U+266A is in the Basic Multilingual Plane, so font fallback finds it in Segoe UI. The
        // obvious speaker emoji (U+1F50A and friends) are astral-plane, need Segoe UI Emoji, and
        // render as tofu when it is missing - the same trap the taskbar clock documents.
        return muted ? "♪  Muted" : "♪  " + percent + "%";
    }

    private void Announce(string text, float fraction, int x, int y)
    {
        _osd ??= new OsdWindow(200);

        // Anchored to the pointer, which is over the taskbar, so the readout appears just above the
        // bar the user is scrolling - including on a secondary monitor, where the shell's own flyout
        // would have appeared on the primary.
        _osd.Show(text, x, y - 96, 1100, fraction);
    }

    private void TearDown()
    {
        try
        {
            _osd?.Dispose();
            _osd = null;
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
