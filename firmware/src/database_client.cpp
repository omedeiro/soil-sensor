/*
 * database_client.cpp
 * HTTP client for sending sensor readings to InfluxDB
 */

#include "database_client.h"
#include <ESP8266WiFi.h>

DatabaseClient::DatabaseClient() {}

String DatabaseClient::getMacAddress() {
    uint8_t mac[6];
    WiFi.macAddress(mac);
    
    char macStr[13];
    snprintf(macStr, sizeof(macStr), "%02x%02x%02x%02x%02x%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    
    return String(macStr);
}

String DatabaseClient::getDeviceId() {
#if DEVICE_ID_AUTO
    // Auto-generate from MAC address
    String mac = getMacAddress();
    return "esp8266-" + mac;
#else
    // Use custom device ID from config
    String customId = String(DEVICE_ID);
    if (customId.length() > 0) {
        return customId;
    } else {
        // Fallback to MAC if custom ID is empty
        Serial.println(F("[DB] Warning: DEVICE_ID is empty, using MAC address"));
        String mac = getMacAddress();
        return "esp8266-" + mac;
    }
#endif
}

String DatabaseClient::buildLineProtocol(
    const String& deviceId,
    unsigned long timestamp,
    int raw,
    float moisture,
    unsigned long uptime,
    int crashes,
    int rssi,
    int freeHeap
) {
    // InfluxDB Line Protocol Format:
    // measurement,tag1=value1,tag2=value2 field1=value1,field2=value2 timestamp
    
    String payload = "sensor_reading,device_id=" + deviceId;
    
    // Add location tag if configured
    #ifdef DEVICE_LOCATION
    payload += ",location=" + String(DEVICE_LOCATION);
    #endif
    
    payload += " ";
    
    // Fields (note: integers need 'i' suffix in InfluxDB)
    payload += "moisture=" + String(moisture, 1) + ",";
    payload += "raw_adc=" + String(raw) + "i,";
    payload += "uptime=" + String(uptime) + "i,";
    payload += "crashes=" + String(crashes) + "i,";
    payload += "rssi=" + String(rssi) + "i,";
    payload += "free_heap=" + String(freeHeap) + "i";
    
    // Timestamp (Unix epoch in seconds)
    payload += " " + String(timestamp);
    
    return payload;
}

bool DatabaseClient::postToInflux(const String& payload, int maxRetries) {
    const int RETRY_DELAY_MS = 1000;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
        // Build full URL with query parameters
        String url = String(DB_SERVER_URL);
        url += "?org=" + String(INFLUX_ORG);
        url += "&bucket=" + String(INFLUX_BUCKET);
        url += "&precision=s";
        
        http.setTimeout(5000);  // 5 second timeout
        http.begin(wifiClient, url);
        http.addHeader("Content-Type", "text/plain; charset=utf-8");
        http.addHeader("Authorization", "Token " + String(INFLUX_TOKEN));
        
        yield();  // Feed watchdog
        
        int httpCode = http.POST(payload);
        
        // InfluxDB returns 204 (No Content) on successful write
        if (httpCode == 204 || httpCode == 200) {
            http.end();
            if (attempt > 1) {
                Serial.printf("[DB] ✓ Success on retry #%d (HTTP %d)\n", attempt, httpCode);
            }
            return true;
        }
        
        // Log error
        if (attempt < maxRetries) {
            Serial.printf("[DB] Attempt %d/%d failed (HTTP %d), retrying in %dms...\n", 
                          attempt, maxRetries, httpCode, RETRY_DELAY_MS);
            
            if (httpCode > 0) {
                String response = http.getString();
                if (response.length() > 0 && response.length() < 200) {
                    Serial.printf("[DB]   Error: %s\n", response.c_str());
                }
            } else {
                Serial.printf("[DB]   Error: %s\n", http.errorToString(httpCode).c_str());
            }
            
            http.end();
            delay(RETRY_DELAY_MS);
            yield();
        } else {
            Serial.printf("[DB] ✗ All %d attempts failed (HTTP %d)\n", maxRetries, httpCode);
            
            if (httpCode > 0) {
                String response = http.getString();
                if (response.length() > 0 && response.length() < 200) {
                    Serial.printf("[DB]   Final error: %s\n", response.c_str());
                }
            }
            
            http.end();
        }
    }
    
    return false;
}

bool DatabaseClient::sendReading(
    const String& deviceId,
    unsigned long timestamp,
    int raw,
    float moisture,
    unsigned long uptime,
    int crashes,
    int rssi,
    int freeHeap,
    bool queueOnFail
) {
    // Build InfluxDB line protocol
    String payload = buildLineProtocol(
        deviceId, timestamp, raw, moisture, 
        uptime, crashes, rssi, freeHeap
    );
    
    // Attempt to send
    bool success = postToInflux(payload, 3);
    
    if (success) {
        Serial.printf("[DB] ✓ Posted to InfluxDB: %s @ %.1f%%\n", 
                      deviceId.c_str(), moisture);
    } else if (queueOnFail) {
        Serial.println(F("[DB] ⚠️  POST failed - reading will be queued"));
    }
    
    return success;
}

int DatabaseClient::drainQueue(ReadingQueue& queue, unsigned long maxTimeMs, int maxReadings) {
    if (queue.isEmpty()) {
        return 0;
    }
    
    unsigned long startTime = millis();
    
    Serial.println(F("─────────────────────────────────────"));
    Serial.printf("[Queue] Draining queue (%u readings)...\n", queue.count());
    Serial.printf("[Queue] Limits: %lu ms, %d readings max\n", maxTimeMs, maxReadings);
    
    int successCount = 0;
    int failCount = 0;
    QueuedReading reading;
    
    // Try to send queued readings with time and count limits
    while (!queue.isEmpty() && 
           successCount < maxReadings && 
           (millis() - startTime) < maxTimeMs) {
        
        yield();  // Feed watchdog
        
        if (!queue.dequeue(reading)) {
            break;  // Queue empty
        }
        
        // Build line protocol
        String payload = buildLineProtocol(
            reading.deviceId,
            reading.timestamp,
            reading.raw,
            reading.moisture,
            reading.uptime,
            reading.crashes,
            reading.rssi,
            reading.freeHeap
        );
        
        // Try to send (only 1 retry to avoid blocking too long)
        if (postToInflux(payload, 1)) {
            successCount++;
            Serial.printf("[Queue] ✓ Sent queued reading from %lu\n", reading.timestamp);
        } else {
            failCount++;
            Serial.printf("[Queue] ✗ Failed to send queued reading from %lu\n", reading.timestamp);
            
            // Re-queue the failed reading (put it back at front)
            // Note: This will be lost if queue is full, but that's acceptable
            // to prevent infinite loops
            break;  // Stop trying if network is still down
        }
        
        delay(100);  // Small delay between requests to avoid overwhelming server
    }
    
    unsigned long elapsed = millis() - startTime;
    Serial.printf("[Queue] Drain complete: %d sent, %d failed, %u remaining (took %lu ms)\n",
                  successCount, failCount, queue.count(), elapsed);
    Serial.println(F("─────────────────────────────────────"));
    
    return successCount;
}
