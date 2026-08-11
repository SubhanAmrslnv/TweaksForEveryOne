#include <QCoreApplication>
#include <iostream>
#include <memory>
#include "core/RenderQueue.h"
#include "core/AnimationScheduler.h"
#include "platform/wayland/DBusDaemon.h"

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    
    std::cout << "Starting TweakForEveryone Linux Daemon (tweaksd)...\n";
    
    DBusDaemon daemon;
    if (!daemon.start()) {
        std::cerr << "Failed to start DBus daemon. Exiting.\n";
        return 1;
    }
    
    // In a full implementation, we'd also load the PlatformAdapter here
    
    std::cout << "Daemon running. Press Ctrl+C to stop.\n";
    return app.exec();
}
