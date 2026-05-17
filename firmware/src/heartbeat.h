/*
 * heartbeat.h
 * Lightweight heartbeat system to detect silent sensor failures
 * Sends periodic "I'm alive" messages to InfluxDB
 */

#ifndef HEARTBEAT_H
#define HEARTBEAT_H

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include "config.h"

class HeartbeatManager {
public:
    HeartbeatManager();
    
    // Initialize heartbeat system
    void begin(const String& deviceId, unsigned long interval);
    
    // Call in loop() - sends heartbeat if interval elapsed
    void loop();
    
    // Force send heartbeat immediately
    bool sendNow();
    
    // Get statistics
    unsigned long getLastHeartbeatTime() const { return lastHeartbeatTime; }
    int getHeartbeatCount() const { return heartbeatCount; }
    int getFailedCount() const { return failedCount; }
    
private:
    // Send heartbeat to InfluxDB
    bool sendHeartbeat();
    
    // Build InfluxDB line protocol
    String buildLineProtocol();
    
    // Device identification
    String deviceId;
    
    // Timing
    unsigned long heartbeatInterval;
    unsigned long lastHeartbeatTime;
    
    // Statistics
    int heartbeatCount;
    int failedCount;
    
    // HTTP client
    WiFiClient wifiClient;
    HTTPClient http;
};

#endif // HEARTBEAT_H
