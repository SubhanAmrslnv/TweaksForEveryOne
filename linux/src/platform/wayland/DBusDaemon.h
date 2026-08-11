#ifndef DBUSDAEMON_H
#define DBUSDAEMON_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QString>
#include "core/WeatherFetcher.h"

class DBusDaemon : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.tweakforeveryone.Daemon")

public:
    explicit DBusDaemon(QObject *parent = nullptr);
    bool start();

public slots:
    void Ping();

signals:
    void SetWindowGeometry(uint windowId, int x, int y, int width, int height);
    void SetWindowAlpha(uint windowId, double alpha);
    void WeatherUpdated(const QString& weather);

private:
    TweakCore::WeatherFetcher* weatherFetcher;
};

#endif // DBUSDAEMON_H
