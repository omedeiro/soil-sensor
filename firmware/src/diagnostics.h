/*
 * diagnostics.h
 * Diagnostic event logging system for ESP8266 sensors
 * Sends events to InfluxDB for historical analysis and alerting
 */

#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include "config.h"

// Diagnostic event types
enum DiagnosticEventType {
    EVENT_CRASH_DETECTED,
    EVENT_WIFI_DISCONNECT,
    EVENT_WIFI_RECONNECT_SUCCESS,
    EVENT_WIFI_RECONNECT_FAILED,
    EVENT_QUEUE_OVERFLOW,
    EVENT_HEAP_LOW_WARNING,
    EVENT_INFLUXDB_ERROR,
    EVENT_SYSTEM_RESTART,
    EVENT_BOOT_COMPLETE
};

// Diagnostic event structure
struct DiagnosticEvent {
    DiagnosticEventType type;
    String reason;          // Human-readable reason or error code
    unsigned long timestamp;
    int freeHeap;
    int rssi;
    int queueSize;
    int eventCount;         // Incrementing counter for this event type
};

class DiagnosticsManager {
public:
    DiagnosticsManager();
    
    // Initialize the diagnostics system
    void begin(const String& deviceId);
    
    // Log diagnostic events
    void logCrashDetected(uint8_t resetReason, const String& resetReasonStr);
    void logWifiDisconnect(uint8_t reason, const String& reasonStr);
    void logWifiReconnectSuccess(int attempts);
    void logWifiReconnectFailed(int attempts);
    void logQueueOverflow(int queueSize);
    void logHeapLowWarning(int freeHeap, int threshold);
    void logInfluxDBError(int httpCode, const String& error);
    void logSystemRestart(const String& reason);
    void logBootComplete(unsigned long bootTime);
    
    // Process queued diagnostic events (non-blocking)
    void loop();
    
    // Get event counts
    int getCrashCount() const { return crashEventCount; }
    int getDisconnectCount() const { return disconnectEventCount; }
    int getTotalEvents() const { return totalEvents; }
    
private:
    // Send event to InfluxDB
    bool sendEvent(const DiagnosticEvent& event);
    
    // Build InfluxDB line protocol for diagnostic event
    String buildLineProtocol(const DiagnosticEvent& event);
    
    // Get event type as string
    String getEventTypeString(DiagnosticEventType type);
    
    // Queue for diagnostic events
    DiagnosticEvent eventQueue[DIAGNOSTIC_QUEUE_SIZE];
    size_t queueHead;
    size_t queueTail;
    size_t queueSize;
    
    // Device identification
    String deviceId;
    
    // Event counters
    int crashEventCount;
    int disconnectEventCount;
    int reconnectSuccessCount;
    int reconnectFailedCount;
    int queueOverflowCount;
    int heapWarningCount;
    int influxErrorCount;
    int restartCount;
    int totalEvents;
    
    // HTTP client for sending events
    WiFiClient wifiClient;
    HTTPClient http;
    
    // Prevent event spam
    unsigned long lastEventTime[10];  // One per event type
    const unsigned long EVENT_SPAM_THRESHOLD = 10000;  // 10 seconds minimum between same events
};

#endif // DIAGNOSTICS_H
