#pragma once

#include <string>
#include <memory>
#include "PlatformAdapter.h"

namespace TweakCore {

class ClipboardManager {
public:
    explicit ClipboardManager(std::shared_ptr<PlatformAdapter> adapter);
    
    // Intercepted plain text paste
    void handlePlainTextPaste();
    
    // Handle Morphing Paste (cycle casing)
    void handleMorphingPaste();

    // Handle appending to clipboard (Double Ctrl+C)
    void handleClipboardAppend(const std::string& textToAppend);
    
    // Show visual cues for copy actions
    void triggerCopyFeedback();

private:
    std::shared_ptr<PlatformAdapter> m_adapter;
};

} // namespace TweakCore
