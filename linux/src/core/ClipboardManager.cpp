#include "ClipboardManager.h"

namespace TweakCore {

ClipboardManager::ClipboardManager(std::shared_ptr<PlatformAdapter> adapter)
    : m_adapter(std::move(adapter)) {}

void ClipboardManager::handlePlainTextPaste() {
    // TODO: Stub. Read clipboard via m_adapter, strip formatting, write plain text back.
}

void ClipboardManager::handleMorphingPaste() {
    // TODO: Stub. Read text via m_adapter, cycle cases, write back.
}

void ClipboardManager::handleClipboardAppend(const std::string& textToAppend) {
    // TODO: Stub. Append to current clipboard contents via m_adapter.
}

void ClipboardManager::triggerCopyFeedback() {
    // TODO: Stub. Trigger visual cue (e.g., overlay).
}

} // namespace TweakCore
