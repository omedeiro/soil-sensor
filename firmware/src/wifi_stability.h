/*
 * wifi_stability.h
 * WiFi stability manager with event handling and reconnection logic
 */

#ifndef WIFI_STABILITY_H
#define WIFI_STABILITY_H

#include <ESP8266WiFi.h>
#include <Arduino.h>

class WiFiStabilityManager {
public:
    WiFiStabilityManager();
    
    // Initialize WiFi event handlers
    void begin();
    
    // Call in loop() to handle reconnection logic
    void loop();
    
    // Check if WiFi is in a healthy state
    bool isHealthy();
    
    // Statistics
    unsigned long getConnectedTime();
    unsigned long getDisconnectedTime();
    unsigned long getTotalDisconnects();
    uint8_t getLastDisconnectReason();
    uint16_t getReconnectAttempts();
    
    // Diagnostics
    void printDiagnostics();
    
private:
    // Event handlers (static for ESP8266 WiFi events)
    static void onWiFiConnect(const WiFiEventStationModeGotIP& event);
    static void onWiFiDisconnect(const WiFiEventStationModeDisconnected& event);
    
    // Reconnection logic
    void attemptReconnect();
    
    // State tracking
    static unsigned long lastConnectTime;
    static unsigned long lastDisconnectTime;
    static unsigned long totalDisconnects;
    static uint8_t lastDisconnectReason;
    
    unsigned long reconnectDelay;       // Current reconnection delay (exponential backoff)
    unsigned long nextReconnectTime;    // When to attempt next reconnection
    uint16_t reconnectAttempts;         // Counter for consecutive reconnect attempts
    bool isReconnecting;
    
    // Constants
    static const unsigned long MIN_RECONNECT_DELAY = 5000;   // 5 seconds
    static const unsigned long MAX_RECONNECT_DELAY = 60000;  // 60 seconds
    static const unsigned long STABLE_CONNECTION_TIME = 300000; // 5 minutes
    static const uint16_t MAX_RECONNECT_ATTEMPTS = 10;
};

#endif // WIFI_STABILITY_H
