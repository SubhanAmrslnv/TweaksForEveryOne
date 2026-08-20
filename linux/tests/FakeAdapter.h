#pragma once

#include "core/PlatformAdapter.h"

#include <map>
#include <set>
#include <vector>

namespace TweakTest {

// A PlatformAdapter that records instead of rendering.
//
// This is what makes RenderQueue testable without a display, and it is the only
// way to assert the things that actually broke on Windows: that "off" is emitted
// rather than a rounded 1.0, that a redundant write is suppressed, and that a
// FAILED call does not get recorded in the last-applied cache.
class FakeAdapter : public TweakCore::PlatformAdapter {
public:
    struct AlphaCall {
        uint32_t id;
        bool off;
        float value;
    };
    struct GeometryCall {
        uint32_t id;
        int x, y, w, h;
    };

    std::vector<AlphaCall> alphaCalls;
    std::vector<GeometryCall> geometryCalls;
    std::vector<std::pair<uint32_t, TweakCore::RegionSpec>> regionCalls;
    std::vector<std::pair<uint32_t, TweakCore::ZOrderSpec>> zOrderCalls;
    int batchDepth = 0;
    int batchesOpened = 0;

    // Make the next call for this window fail, so a test can prove the
    // last-applied cache is not poisoned by a failure.
    std::set<uint32_t> failFor;
    // Anything not listed here is reported dead, which is what drives sweepDead.
    std::set<uint32_t> alive;

    bool supports(TweakCore::Capability) const override { return true; }

    bool init() override { return true; }
    void pollEvents() override {}
    void shutdown() override {}

    bool setWindowGeometry(uint32_t id, int x, int y, int w, int h) override {
        if (failFor.count(id)) {
            return false;
        }
        geometryCalls.push_back({id, x, y, w, h});
        return true;
    }

    bool setWindowAlpha(uint32_t id, float alpha) override {
        if (failFor.count(id)) {
            return false;
        }
        alphaCalls.push_back({id, false, alpha});
        return true;
    }

    bool clearWindowAlpha(uint32_t id) override {
        if (failFor.count(id)) {
            return false;
        }
        alphaCalls.push_back({id, true, 1.0f});
        return true;
    }

    bool setWindowRegion(uint32_t id, const TweakCore::RegionSpec& r) override {
        if (failFor.count(id)) {
            return false;
        }
        regionCalls.emplace_back(id, r);
        return true;
    }

    bool setWindowZOrder(uint32_t id, const TweakCore::ZOrderSpec& z) override {
        if (failFor.count(id)) {
            return false;
        }
        zOrderCalls.emplace_back(id, z);
        return true;
    }

    bool setWindowState(uint32_t, bool, bool, bool) override { return true; }

    void beginBatch() override {
        ++batchDepth;
        ++batchesOpened;
    }
    void commitBatch() override { --batchDepth; }

    bool isWindowAlive(uint32_t id) const override { return alive.count(id) > 0; }

    TweakCore::WindowState getWindowState(uint32_t id) const override {
        TweakCore::WindowState s;
        s.windowId = id;
        return s;
    }
    uint32_t getActiveWindow() const override { return 0; }
    std::vector<uint32_t> listWindows() const override { return {}; }
    std::string windowAppId(uint32_t) const override { return {}; }
    std::vector<TweakCore::Rect> monitors() const override { return {}; }
    TweakCore::Rect workArea(int) const override { return {}; }
    TweakCore::Point pointerPosition() const override { return {}; }
    bool warpPointer(int, int) override { return true; }
};

} // namespace TweakTest
