/*
 * diagnostics.cpp
 * Implementation of diagnostic event logging system
 */

#include "diagnostics.h"

DiagnosticsManager::DiagnosticsManager()
    : queueHead(0),
      queueTail(0),
      queueSize(0),
      crashEventCount(0),
      disconnectEventCount(0),
      reconnectSuccessCount(0),
      reconnectFailedCount(0),
      queueOverflowCount(0),
      heapWarningCount(0),
      influxErrorCount(0),
      restartCount(0),
      totalEvents(0) {
    
    // Initialize spam prevention timestamps
    for (int i = 0; i < 10; i++) {
        lastEventTime[i] = 0;
    }
}

void DiagnosticsManager::begin(const String& devId) {
    deviceId = devId;
    Serial.println(F("[Diagnostics] System initialized"));
}

void DiagnosticsManager::logCrashDetected(uint8_t resetReason, const String& resetReasonStr) {
    crashEventCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_CRASH_DETECTED;
    event.reason = resetReasonStr + " (code: " + String(resetReason) + ")";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = crashEventCount;
    
    Serial.printf("[Diagnostics] 🚨 Crash detected: %s\n", event.reason.c_str());
    
    // Send immediately if WiFi connected, otherwise queue
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::logWifiDisconnect(uint8_t reason, const String& reasonStr) {
    // Prevent spam
    if (millis() - lastEventTime[EVENT_WIFI_DISCONNECT] < EVENT_SPAM_THRESHOLD) {
        return;
    }
    lastEventTime[EVENT_WIFI_DISCONNECT] = millis();
    
    disconnectEventCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_WIFI_DISCONNECT;
    event.reason = reasonStr + " (code: " + String(reason) + ")";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = -100;  // Not connected
    event.queueSize = 0;
    event.eventCount = disconnectEventCount;
    
    Serial.printf("[Diagnostics] 📡 WiFi disconnect: %s\n", event.reason.c_str());
    
    // Can't send immediately (no WiFi), will be sent after reconnect
}

void DiagnosticsManager::logWifiReconnectSuccess(int attempts) {
    reconnectSuccessCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_WIFI_RECONNECT_SUCCESS;
    event.reason = "Reconnected after " + String(attempts) + " attempts";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = reconnectSuccessCount;
    
    Serial.printf("[Diagnostics] ✓ WiFi reconnect success: %s\n", event.reason.c_str());
    
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::logWifiReconnectFailed(int attempts) {
    reconnectFailedCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_WIFI_RECONNECT_FAILED;
    event.reason = "Failed after " + String(attempts) + " attempts - restarting";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = -100;
    event.queueSize = 0;
    event.eventCount = reconnectFailedCount;
    
    Serial.printf("[Diagnostics] ✗ WiFi reconnect failed: %s\n", event.reason.c_str());
    
    // This is critical - try to send before restart
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::logQueueOverflow(int currentQueueSize) {
    // Prevent spam
    if (millis() - lastEventTime[EVENT_QUEUE_OVERFLOW] < EVENT_SPAM_THRESHOLD) {
        return;
    }
    lastEventTime[EVENT_QUEUE_OVERFLOW] = millis();
    
    queueOverflowCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_QUEUE_OVERFLOW;
    event.reason = "Reading queue full - data loss";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = currentQueueSize;
    event.eventCount = queueOverflowCount;
    
    Serial.printf("[Diagnostics] ⚠️  Queue overflow: %d readings lost\n", queueOverflowCount);
    
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::logHeapLowWarning(int freeHeap, int threshold) {
    // Prevent spam
    if (millis() - lastEventTime[EVENT_HEAP_LOW_WARNING] < EVENT_SPAM_THRESHOLD) {
        return;
    }
    lastEventTime[EVENT_HEAP_LOW_WARNING] = millis();
    
    heapWarningCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_HEAP_LOW_WARNING;
    event.reason = "Free heap: " + String(freeHeap) + " bytes (threshold: " + String(threshold) + ")";
    event.timestamp = time(nullptr);
    event.freeHeap = freeHeap;
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = heapWarningCount;
    
    Serial.printf("[Diagnostics] ⚠️  Low heap: %s\n", event.reason.c_str());
    
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::logInfluxDBError(int httpCode, const String& error) {
    // Prevent spam
    if (millis() - lastEventTime[EVENT_INFLUXDB_ERROR] < EVENT_SPAM_THRESHOLD) {
        return;
    }
    lastEventTime[EVENT_INFLUXDB_ERROR] = millis();
    
    influxErrorCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_INFLUXDB_ERROR;
    event.reason = "HTTP " + String(httpCode) + ": " + error;
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = influxErrorCount;
    
    Serial.printf("[Diagnostics] ✗ InfluxDB error: %s\n", event.reason.c_str());
    
    // Don't try to send InfluxDB errors to InfluxDB (infinite loop)
}

void DiagnosticsManager::logSystemRestart(const String& reason) {
    restartCount++;
    
    DiagnosticEvent event;
    event.type = EVENT_SYSTEM_RESTART;
    event.reason = reason;
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = restartCount;
    
    Serial.printf("[Diagnostics] 🔄 System restart: %s\n", event.reason.c_str());
    
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
        delay(1000);  // Give time to send before restart
    }
}

void DiagnosticsManager::logBootComplete(unsigned long bootTime) {
    DiagnosticEvent event;
    event.type = EVENT_BOOT_COMPLETE;
    event.reason = "Boot completed in " + String(bootTime) + " ms";
    event.timestamp = time(nullptr);
    event.freeHeap = ESP.getFreeHeap();
    event.rssi = WiFi.RSSI();
    event.queueSize = 0;
    event.eventCount = 1;
    
    Serial.printf("[Diagnostics] ✓ Boot complete: %s\n", event.reason.c_str());
    
    if (WiFi.status() == WL_CONNECTED) {
        sendEvent(event);
    }
}

void DiagnosticsManager::loop() {
    // Process queued events (not implemented in v1 - events sent immediately)
    // Future: implement event queue for offline periods
}

String DiagnosticsManager::getEventTypeString(DiagnosticEventType type) {
    switch (type) {
        case EVENT_CRASH_DETECTED:          return "crash_detected";
        case EVENT_WIFI_DISCONNECT:         return "wifi_disconnect";
        case EVENT_WIFI_RECONNECT_SUCCESS:  return "wifi_reconnect_success";
        case EVENT_WIFI_RECONNECT_FAILED:   return "wifi_reconnect_failed";
        case EVENT_QUEUE_OVERFLOW:          return "queue_overflow";
        case EVENT_HEAP_LOW_WARNING:        return "heap_low_warning";
        case EVENT_INFLUXDB_ERROR:          return "influxdb_error";
        case EVENT_SYSTEM_RESTART:          return "system_restart";
        case EVENT_BOOT_COMPLETE:           return "boot_complete";
        default:                            return "unknown";
    }
}

String DiagnosticsManager::buildLineProtocol(const DiagnosticEvent& event) {
    // InfluxDB Line Protocol:
    // sensor_diagnostics,device_id=X,location=Y,event_type=Z event_reason="...",event_count=N,free_heap=M,rssi=R timestamp
    
    String payload = "sensor_diagnostics,device_id=" + deviceId;
    
    #ifdef DEVICE_LOCATION
    payload += ",location=" + String(DEVICE_LOCATION);
    #endif
    
    payload += ",event_type=" + getEventTypeString(event.type);
    payload += " ";
    
    // Fields
    payload += "event_reason=\"" + event.reason + "\",";
    payload += "event_count=" + String(event.eventCount) + "i,";
    payload += "free_heap=" + String(event.freeHeap) + "i,";
    payload += "rssi=" + String(event.rssi) + "i,";
    payload += "queue_size=" + String(event.queueSize) + "i";
    
    // Timestamp
    payload += " " + String(event.timestamp);
    
    return payload;
}

bool DiagnosticsManager::sendEvent(const DiagnosticEvent& event) {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }
    
    #if !USE_REMOTE_DB
    return false;  // Diagnostics disabled if remote DB disabled
    #endif
    
    String payload = buildLineProtocol(event);
    
    // Build URL
    String url = String(DB_SERVER_URL);
    url += "?org=" + String(INFLUX_ORG);
    url += "&bucket=" + String(INFLUX_BUCKET);
    url += "&precision=s";
    
    http.setTimeout(5000);
    http.begin(wifiClient, url);
    http.addHeader("Content-Type", "text/plain; charset=utf-8");
    http.addHeader("Authorization", "Token " + String(INFLUX_TOKEN));
    
    int httpCode = http.POST(payload);
    http.end();
    
    if (httpCode == 204 || httpCode == 200) {
        totalEvents++;
        return true;
    }
    
    return false;
}
