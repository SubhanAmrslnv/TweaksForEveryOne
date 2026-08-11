#include "DBusDaemon.h"
#include <iostream>

DBusDaemon::DBusDaemon(QObject *parent) : QObject(parent)
{
    weatherFetcher = new TweakCore::WeatherFetcher(this);
    connect(weatherFetcher, &TweakCore::WeatherFetcher::weatherUpdated, this, &DBusDaemon::WeatherUpdated);
}

bool DBusDaemon::start()
{
    QDBusConnection connection = QDBusConnection::sessionBus();
    if (!connection.registerService("org.tweakforeveryone.Daemon")) {
        std::cerr << "Failed to register DBus service.\n";
        return false;
    }

    if (!connection.registerObject("/org/tweakforeveryone/Daemon", this, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        std::cerr << "Failed to register DBus object.\n";
        return false;
    }
    
    std::cout << "DBusDaemon started successfully.\n";
    weatherFetcher->start();
    return true;
}

void DBusDaemon::Ping()
{
    std::cout << "Ping received via DBus!\n";
}
