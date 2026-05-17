/*
 * heartbeat.cpp
 * Implementation of heartbeat system
 */

#include "heartbeat.h"

HeartbeatManager::HeartbeatManager()
    : heartbeatInterval(HEARTBEAT_INTERVAL_MS),
      lastHeartbeatTime(0),
      heartbeatCount(0),
      failedCount(0) {
}

void HeartbeatManager::begin(const String& devId, unsigned long interval) {
    deviceId = devId;
    heartbeatInterval = interval;
    lastHeartbeatTime = millis();
    
    Serial.printf("[Heartbeat] Initialized (interval: %lu ms)\n", heartbeatInterval);
}

void HeartbeatManager::loop() {
    #if !ENABLE_HEARTBEAT
    return;
    #endif
    
    // Only send if interval has elapsed
    if (millis() - lastHeartbeatTime < heartbeatInterval) {
        return;
    }
    
    // Only send if WiFi connected (don't queue heartbeats)
    if (WiFi.status() != WL_CONNECTED) {
        return;
    }
    
    sendHeartbeat();
}

bool HeartbeatManager::sendNow() {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }
    
    return sendHeartbeat();
}

String HeartbeatManager::buildLineProtocol() {
    // InfluxDB Line Protocol:
    // sensor_heartbeat,device_id=X,location=Y uptime=N,free_heap=M,rssi=R,queue_size=Q timestamp
    
    String payload = "sensor_heartbeat,device_id=" + deviceId;
    
    #ifdef DEVICE_LOCATION
    payload += ",location=" + String(DEVICE_LOCATION);
    #endif
    
    payload += " ";
    
    // Fields (minimal to keep payload small)
    unsigned long uptime = millis() / 1000;
    int freeHeap = ESP.getFreeHeap();
    int rssi = WiFi.RSSI();
    
    payload += "uptime=" + String(uptime) + "i,";
    payload += "free_heap=" + String(freeHeap) + "i,";
    payload += "rssi=" + String(rssi) + "i,";
    payload += "heartbeat_count=" + String(heartbeatCount + 1) + "i";
    
    // Timestamp
    unsigned long timestamp = time(nullptr);
    payload += " " + String(timestamp);
    
    return payload;
}

bool HeartbeatManager::sendHeartbeat() {
    #if !USE_REMOTE_DB
    return false;
    #endif
    
    String payload = buildLineProtocol();
    
    // Build URL
    String url = String(DB_SERVER_URL);
    url += "?org=" + String(INFLUX_ORG);
    url += "&bucket=" + String(INFLUX_BUCKET);
    url += "&precision=s";
    
    http.setTimeout(3000);  // Shorter timeout for heartbeat
    http.begin(wifiClient, url);
    http.addHeader("Content-Type", "text/plain; charset=utf-8");
    http.addHeader("Authorization", "Token " + String(INFLUX_TOKEN));
    
    int httpCode = http.POST(payload);
    http.end();
    
    if (httpCode == 204 || httpCode == 200) {
        heartbeatCount++;
        lastHeartbeatTime = millis();
        
        // Only log every 10th heartbeat to avoid serial spam
        if (heartbeatCount % 10 == 0) {
            Serial.printf("[Heartbeat] ✓ Sent #%d (uptime: %lu min)\n", 
                          heartbeatCount, (millis() / 60000));
        }
        
        return true;
    } else {
        failedCount++;
        lastHeartbeatTime = millis();  // Update time even on failure to prevent spam
        
        if (httpCode > 0) {
            Serial.printf("[Heartbeat] ✗ Failed (HTTP %d)\n", httpCode);
        } else {
            Serial.printf("[Heartbeat] ✗ Failed (error: %s)\n", 
                          http.errorToString(httpCode).c_str());
        }
        
        return false;
    }
}
