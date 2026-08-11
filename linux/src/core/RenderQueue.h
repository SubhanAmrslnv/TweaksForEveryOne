#pragma once

#include "PlatformAdapter.h"
#include <map>
#include <memory>
#include <mutex>

namespace TweakCore {

enum class RenderPriority {
    Ambient = 0,
    Animation = 1,
    Drag = 2,
    User = 3
};

struct QueuedState {
    RenderPriority priority;
    bool hasGeometry;
    int x, y, width, height;
    bool hasAlpha;
    float alpha;
};

class RenderQueue {
public:
    RenderQueue(std::shared_ptr<PlatformAdapter> adapter);

    void setGeometry(uint32_t windowId, int x, int y, int w, int h, RenderPriority priority);
    void setAlpha(uint32_t windowId, float alpha, RenderPriority priority);
    
    // Called by the AnimationScheduler every 16ms
    void flush();

private:
    std::shared_ptr<PlatformAdapter> m_adapter;
    std::map<uint32_t, QueuedState> m_queue;
    std::mutex m_mutex;
};

} // namespace TweakCore
