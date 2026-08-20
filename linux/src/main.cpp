#include <QCoreApplication>
#include <QTimer>

#include <csignal>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

#include "core/AnimationScheduler.h"
#include "core/RenderQueue.h"
#include "platform/wayland/DBusDaemon.h"
#include "platform/x11/X11Adapter.h"

namespace {

// Written by the signal handler, read by a timer on the Qt main thread.
//
// The handler must not call QCoreApplication::quit(), std::cout, or anything
// else that is not async-signal-safe - only a write to a volatile
// sig_atomic_t is guaranteed legal here. A self-pipe with a QSocketNotifier is
// the more responsive form of this and is what the daemon should end up with;
// a 200 ms poll is enough while the only thing shutdown has to do is stop two
// objects.
volatile std::sig_atomic_t g_quitRequested = 0;

void onSignal(int) {
    g_quitRequested = 1;
}

std::string envOr(const char* name, const char* fallback) {
    const char* v = std::getenv(name);
    return (v && *v) ? std::string(v) : std::string(fallback);
}

} // namespace

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);

    std::cout << "Starting TweakForEveryone Linux Daemon (tweaksd)...\n";

    // Session detection. There was none: the daemon built a DBusDaemon
    // unconditionally, including on X11 where the native backend is both
    // available and unrestricted.
    const std::string sessionType = envOr("XDG_SESSION_TYPE", "");
    const std::string desktop = envOr("XDG_CURRENT_DESKTOP", "");
    const bool wayland = (sessionType == "wayland") || !envOr("WAYLAND_DISPLAY", "").empty();

    std::cout << "  session: " << (sessionType.empty() ? "unknown" : sessionType)
              << ", desktop: " << (desktop.empty() ? "unknown" : desktop) << "\n";

    // Construct the real graph: adapter -> RenderQueue -> AnimationScheduler.
    //
    // None of these were ever constructed. main.cpp included RenderQueue.h and
    // AnimationScheduler.h and then instantiated neither, so the frame loop
    // never ran and nothing could reach a window even in principle.
    std::shared_ptr<TweakCore::PlatformAdapter> adapter;
    if (!wayland) {
        adapter = std::make_shared<TweakPlatform::X11Adapter>();
        if (!adapter->init()) {
            // Keep running rather than exiting. The weather/clock path below
            // does not need an adapter, and RenderQueue drops its queue safely
            // when there is nothing to apply it to.
            std::cerr << "  X11 backend unavailable - window management is disabled.\n";
        }
    } else {
        // There is no WaylandAdapter yet. DBusDaemon is a sibling class, not a
        // PlatformAdapter, so RenderQueue has nothing to flush into on Wayland -
        // and a Wayland client may not move or fade another window anyway
        // without a compositor extension. See docs/WAYLAND-LIMITATIONS.md.
        std::cerr << "  Wayland session: window management needs a compositor "
                     "extension and is not wired up yet.\n";
    }

    auto renderQueue = std::make_shared<TweakCore::RenderQueue>(adapter);
    auto scheduler = std::make_shared<TweakCore::AnimationScheduler>(renderQueue);

    // Without a sink, an animation that throws is retired in total silence -
    // which is precisely what made the equivalent failure undiagnosable on the
    // Windows side: a clean parse, an empty log, and a feature that did nothing.
    scheduler->setLogSink([](const std::string& line) {
        std::cerr << "[anim] " << line << "\n";
    });

    DBusDaemon daemon;
    if (!daemon.start()) {
        std::cerr << "Failed to start DBus daemon. Exiting.\n";
        return 1;
    }

    std::signal(SIGINT, onSignal);
    std::signal(SIGTERM, onSignal);
    // A compositor going away closes the bus socket. That must not kill the
    // daemon with an unhandled SIGPIPE.
    std::signal(SIGPIPE, SIG_IGN);

    QTimer quitPoll;
    QObject::connect(&quitPoll, &QTimer::timeout, [&]() {
        if (g_quitRequested) {
            QCoreApplication::quit();
        }
    });
    quitPoll.start(200);

    // Ordered teardown, and it is ordered on purpose: stop producing first, then
    // undo. A scheduler still running while the queue shuts down can re-queue
    // state that shutdown has just dropped.
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&]() {
        std::cout << "Stopping...\n";
        scheduler->stop();
        renderQueue->resetAllAlphaState(TweakCore::RenderPriority::User);
        renderQueue->commit();
        renderQueue->shutdown();
        if (adapter) {
            adapter->shutdown();
        }
    });

    scheduler->start();

    std::cout << "Daemon running. Press Ctrl+C to stop.\n";
    return app.exec();
}
