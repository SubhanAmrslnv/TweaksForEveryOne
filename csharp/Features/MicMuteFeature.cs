using System;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

public class MicMuteFeature
{
    public void Toggle()
    {
        bool isMuted = AudioManager.GetMicMute();
        AudioManager.SetMicMute(!isMuted);

        // We can add OSD notification here if needed in the future
        // bool newMuted = AudioManager.GetMicMute();
        // Console.WriteLine($"Microphone is now {(newMuted ? "Muted" : "Unmuted")}");
    }
}
