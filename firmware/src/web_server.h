/*
 * web_server.h
 * Lightweight HTTP server for live monitoring & data export
 */

#ifndef WEB_SERVER_H
#define WEB_SERVER_H

#include <Arduino.h>
#include <ESP8266WebServer.h>
#include "data_logger.h"
#include "sensor.h"

class MonitorWebServer {
public:
    MonitorWebServer(DataLogger& logger, SoilSensor& sensor,
                     uint16_t port = HTTP_PORT);

    void begin();
    void handleClient();

private:
    ESP8266WebServer _server;
    DataLogger&      _logger;
    SoilSensor&      _sensor;

    void _handleRoot();
    void _handleLatest();
    void _handleHistory();
    void _handleCalibrate();
    void _handleReset();
    void _handleNotFound();

    String _buildDashboardHTML();
};

#endif // WEB_SERVER_H
