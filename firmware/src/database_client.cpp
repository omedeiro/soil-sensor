/*
 * database_client.cpp
 * HTTP client for sending sensor readings to remote database
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
        Serial.println("[DB] Warning: DEVICE_ID is empty, using MAC address");
        String mac = getMacAddress();
        return "esp8266-" + mac;
    }
#endif
}

bool DatabaseClient::sendReading(
    const String& deviceId,
    unsigned long timestamp,
    int raw,
    float moisture,
    unsigned long uptime,
    int crashes
) {
    // Build JSON payload
    String payload = "{";
    payload += "\"device_id\":\"" + deviceId + "\",";
    payload += "\"timestamp\":" + String(timestamp) + ",";
    payload += "\"raw\":" + String(raw) + ",";
    payload += "\"moisture\":" + String(moisture, 1) + ",";
    payload += "\"uptime\":" + String(uptime) + ",";
    payload += "\"crashes\":" + String(crashes);
    payload += "}";
    
    // Send HTTP POST request
    http.begin(wifiClient, DB_SERVER_URL);
    http.addHeader("Content-Type", "application/json");
    
    int httpCode = http.POST(payload);
    
    bool success = false;
    
    if (httpCode > 0) {
        if (httpCode == HTTP_CODE_CREATED || httpCode == HTTP_CODE_OK) {
            String response = http.getString();
            Serial.printf("[DB] ✓ Reading sent successfully (HTTP %d)\n", httpCode);
            Serial.printf("[DB]   Response: %s\n", response.c_str());
            success = true;
        } else {
            Serial.printf("[DB] ✗ Server returned HTTP %d\n", httpCode);
            String response = http.getString();
            Serial.printf("[DB]   Error: %s\n", response.c_str());
        }
    } else {
        Serial.printf("[DB] ✗ Connection failed: %s\n", http.errorToString(httpCode).c_str());
    }
    
    http.end();
    return success;
}
