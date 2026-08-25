#pragma once

#include <memory>
#include "PlatformAdapter.h"

namespace TweakCore {

class GameMode {
public:
    explicit GameMode(std::shared_ptr<PlatformAdapter> adapter);
    
    // Check if Game Mode is currently active
    bool isActive() const;

    // Evaluate the state (e.g., check if foreground window is a fullscreen game)
    void evaluate();

private:
    std::shared_ptr<PlatformAdapter> m_adapter;
    bool m_active = false;
};

} // namespace TweakCore
