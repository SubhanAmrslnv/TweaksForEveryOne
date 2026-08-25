#include "AcousticKeystrokes.h"

namespace TweakCore {

AcousticKeystrokes::AcousticKeystrokes(std::shared_ptr<PlatformAdapter> adapter)
    : m_adapter(std::move(adapter)) {}

void AcousticKeystrokes::playKeystroke() {
    // TODO: Stub for playing keystroke sound (e.g. via ALSA or PipeWire).
}

void AcousticKeystrokes::playHotkeySound(bool enabled) {
    // TODO: Stub for playing hotkey sound.
}

void AcousticKeystrokes::setVolume(float volume) {
    m_volume = volume;
}

} // namespace TweakCore
