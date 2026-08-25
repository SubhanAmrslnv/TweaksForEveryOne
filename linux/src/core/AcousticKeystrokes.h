#pragma once

#include <memory>
#include "PlatformAdapter.h"

namespace TweakCore {

class AcousticKeystrokes {
public:
    explicit AcousticKeystrokes(std::shared_ptr<PlatformAdapter> adapter);
    
    // Play a generic mechanical keystroke sound
    void playKeystroke();
    
    // Play a distinct sound for hotkey actions
    void playHotkeySound(bool enabled);

    // Update volume settings
    void setVolume(float volume);
    
private:
    std::shared_ptr<PlatformAdapter> m_adapter;
    float m_volume = 1.0f;
};

} // namespace TweakCore
