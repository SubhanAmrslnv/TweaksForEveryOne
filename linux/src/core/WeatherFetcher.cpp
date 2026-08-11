#include "WeatherFetcher.h"
#include <QNetworkRequest>

namespace TweakCore {

WeatherFetcher::WeatherFetcher(QObject* parent) 
    : QObject(parent), lastWeather("☀️ Loading...") 
{
    manager = new QNetworkAccessManager(this);
    timer = new QTimer(this);
    
    connect(timer, &QTimer::timeout, this, &WeatherFetcher::fetchWeather);
    connect(manager, &QNetworkAccessManager::finished, this, &WeatherFetcher::onReplyFinished);
}

void WeatherFetcher::start() {
    fetchWeather(); // Fetch immediately
    timer->start(15 * 60 * 1000); // 15 minutes
}

void WeatherFetcher::fetchWeather() {
    QNetworkRequest request(QUrl("http://wttr.in/?format=%c+%t+%w"));
    manager->get(request);
}

void WeatherFetcher::onReplyFinished(QNetworkReply* reply) {
    if (reply->error() == QNetworkReply::NoError) {
        QString response = QString::fromUtf8(reply->readAll());
        response = response.remove('\n').remove('\r');
        if (!response.isEmpty()) {
            lastWeather = response;
            emit weatherUpdated(lastWeather);
        }
    }
    reply->deleteLater();
}

} // namespace TweakCore
