using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Mutes and unmutes the default recording device, from Shift+Alt+A or a double-tap of Alt.
///
/// IT HAS TO SAY WHAT IT DID. A kill-switch with no feedback is worse than no kill-switch: both
/// triggers are invisible (one is a chord, the other is a gesture on a key that is not swallowed),
/// the microphone has no state a user can see, and Windows draws nothing of its own for a
/// programmatic endpoint mute. So the only thing distinguishing "muted" from "the hotkey did not
/// register" was whether the person on the other end of the call could still hear you.
///
/// THE STATE IS READ BACK, not assumed. SetMicMute swallows its COM failures by design (no default
/// recording device, an endpoint being removed), so the readout reports what GetMicMute says
/// afterwards rather than the value that was requested - otherwise a silent failure would announce
/// a mute that never happened.
///
/// Both triggers arrive on the UI thread, which is what OsdWindow requires.
/// </summary>
public class MicMuteFeature : IDisposable
{
    private OsdWindow? _osd;

    public void Toggle()
    {
        bool wasMuted = AudioManager.GetMicMute();
        AudioManager.SetMicMute(!wasMuted);

        // Read back rather than trusting the write.
        bool nowMuted = AudioManager.GetMicMute();

        Announce(nowMuted);
    }

    /// <summary>
    /// Shows the resulting state at the cursor, the same anchor the copy/paste readout uses.
    ///
    /// The glyphs are BMP circles from Segoe UI, not the microphone emoji: U+1F3A4 is astral-plane,
    /// needs Segoe UI Emoji, and shows tofu when font fallback misses it. The taskbar clock and the
    /// volume readout document the same trap.
    /// </summary>
    private void Announce(bool muted)
    {
        try
        {
            if (!NativeMethods.GetCursorPos(out NativeMethods.POINT pt)) return;

            _osd ??= new OsdWindow(200);
            _osd.Show(muted ? "○  Mic muted" : "●  Mic on", pt.X, pt.Y, 1100);
        }
        catch
        {
            // Cosmetic. The mute itself has already happened.
        }
    }

    public void Dispose()
    {
        OsdWindow.RunOnUi(() =>
        {
            try
            {
                _osd?.Dispose();
                _osd = null;
            }
            catch
            {
            }
        });
    }
}
