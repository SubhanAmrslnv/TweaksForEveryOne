#ifndef WEATHER_FETCHER_H
#define WEATHER_FETCHER_H

#include <QObject>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>

namespace TweakCore {

class WeatherFetcher : public QObject {
    Q_OBJECT
public:
    explicit WeatherFetcher(QObject* parent = nullptr);
    void start();

signals:
    void weatherUpdated(const QString& weather);

private slots:
    void fetchWeather();
    void onReplyFinished(QNetworkReply* reply);

private:
    QNetworkAccessManager* manager;
    QTimer* timer;
    QString lastWeather;
};

} // namespace TweakCore

#endif // WEATHER_FETCHER_H
