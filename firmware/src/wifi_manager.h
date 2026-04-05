/*
 * wifi_manager.h
 * WiFi connection management with captive-portal provisioning
 */

#ifndef WIFI_MANAGER_WRAPPER_H
#define WIFI_MANAGER_WRAPPER_H

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WiFiManager.h>   // tzapu/WiFiManager
#include "config.h"

class WifiConnection {
public:
    WifiConnection();

    /// Attempt to connect. If no saved credentials, launch a captive portal.
    bool connect();

    /// Returns true when the station is connected to an AP.
    bool isConnected();

    /// Return the local IP as a String.
    String localIP();

    /// Reset saved credentials (useful for a "factory reset" button).
    void resetSettings();

private:
    WiFiManager _wm;
};

#endif // WIFI_MANAGER_WRAPPER_H
