#include "GameMode.h"

namespace TweakCore {

GameMode::GameMode(std::shared_ptr<PlatformAdapter> adapter) 
    : m_adapter(std::move(adapter)) {
}

bool GameMode::isActive() const {
    return m_active;
}

void GameMode::evaluate() {
    // TODO: Stub implementation. Will query adapter to determine if active window is a fullscreen game.
    m_active = false; 
}

} // namespace TweakCore
