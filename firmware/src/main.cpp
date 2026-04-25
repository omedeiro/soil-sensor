/*
 * main.cpp
 * ────────────────────────────────────────────────────────────────────
 * Soil Moisture Monitoring System — ESP8266 firmware
 *
 * Flow:
 *   1. Init serial + sensor
 *   2. Connect to WiFi (captive-portal provisioning via WiFiManager)
 *   3. Sync time via NTP
 *   4. Start HTTP server (dashboard + JSON API)
 *   5. Loop: read sensor at configured interval, log to ring buffer
 * ────────────────────────────────────────────────────────────────────
 */

#include <Arduino.h>
#include <time.h>
#include <ArduinoOTA.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#include "config.h"
#include "sensor.h"
#include "wifi_manager.h"
#include "data_logger.h"
#include "web_server.h"

// ─── Global objects ──────────────────────────────────────────────────────────
SoilSensor      sensor;
WifiConnection  wifi;
DataLogger      logger;
MonitorWebServer* webServer = nullptr;
WiFiClient      wifiClient;

unsigned long lastReadTime = 0;
unsigned long bootTime = 0;
unsigned long lastCrashTime = 0;
uint32_t      crashCount = 0;
uint32_t      totalReadings = 0;

// ─── NTP sync ────────────────────────────────────────────────────────────────
void syncTime() {
    Serial.print(F("[NTP] Syncing time…"));
    configTime(UTC_OFFSET_SEC, UTC_OFFSET_DST_SEC, NTP_SERVER);
    // Wait until we get a valid time (epoch > 2020)
    time_t now = time(nullptr);
    int retries = 0;
    while (now < 1609459200L && retries < 30) { // 2021-01-01
        delay(500);
        Serial.print('.');
        now = time(nullptr);
        retries++;
        yield();  // Feed watchdog
    }
    Serial.println();
    if (now >= 1609459200L) {
        Serial.printf("[NTP] Time synced: %s", ctime(&now));
    } else {
        Serial.println(F("[NTP] Sync failed — timestamps will be 0"));
    }
}

// ─── Crash detection ─────────────────────────────────────────────────────────
void checkForCrash() {
    rst_info* resetInfo = ESP.getResetInfoPtr();
    
    Serial.println(F("─────────────────────────────────────"));
    Serial.println(F("📊 Boot Information:"));
    Serial.printf("  Reason: %s\n", ESP.getResetReason().c_str());
    Serial.printf("  Reset Info: %d\n", resetInfo->reason);
    
    // Reset reasons:
    // 0 = normal startup
    // 1 = hardware watchdog reset
    // 2 = exception reset
    // 3 = software watchdog reset
    // 4 = software restart
    // 5 = wake from deep sleep
    // 6 = external reset
    
    if (resetInfo->reason == REASON_WDT_RST ||
        resetInfo->reason == REASON_EXCEPTION_RST ||
        resetInfo->reason == REASON_SOFT_WDT_RST) {
        crashCount++;
        Serial.printf("⚠️  CRASH DETECTED! Count: %u\n", crashCount);
        Serial.println(F("  This may indicate:"));
        Serial.println(F("    - Blocking code preventing watchdog feed"));
        Serial.println(F("    - Memory corruption"));
        Serial.println(F("    - Power supply issues"));
    } else {
        Serial.println(F("✅ Clean boot"));
    }
    Serial.println(F("─────────────────────────────────────"));
}

// ─── Post reading to remote database ─────────────────────────────────────────
bool postToDatabase(const SensorReading& reading) {
    if (!USE_REMOTE_DB || strlen(DB_SERVER_URL) == 0) {
        return false;  // Remote DB disabled
    }
    
    if (!wifi.isConnected()) {
        Serial.println(F("[DB] Skipping POST - no WiFi"));
        return false;
    }
    
    HTTPClient http;
    http.begin(wifiClient, DB_SERVER_URL);
    http.addHeader("Content-Type", "application/json");
    http.setTimeout(DB_POST_TIMEOUT_MS);
    
    // Build JSON payload
    String payload = "{";
    payload += "\"timestamp\":" + String(reading.timestamp) + ",";
    payload += "\"raw\":" + String(reading.rawValue) + ",";
    payload += "\"moisture\":" + String(reading.moisturePct, 1) + ",";
    payload += "\"uptime\":" + String(millis() / 1000) + ",";
    payload += "\"crashes\":" + String(crashCount);
    payload += "}";
    
    int httpCode = http.POST(payload);
    
    if (httpCode > 0) {
        if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED) {
            Serial.printf("[DB] ✓ Posted to database (HTTP %d)\n", httpCode);
            http.end();
            return true;
        } else {
            Serial.printf("[DB] ✗ Server returned HTTP %d\n", httpCode);
        }
    } else {
        Serial.printf("[DB] ✗ POST failed: %s\n", http.errorToString(httpCode).c_str());
    }
    
    http.end();
    return false;
}

// ─── setup() ─────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(SERIAL_BAUD);
    delay(200);
    Serial.println();
    Serial.println(F("═══════════════════════════════════════"));
    Serial.println(F("  🌱  Soil Moisture Monitoring System"));
    Serial.println(F("═══════════════════════════════════════"));
    
    bootTime = millis();
    
    // Check for crashes
    checkForCrash();

    // 1. Sensor
    sensor.begin();

    // 2. WiFi
    if (!wifi.connect()) {
        Serial.println(F("[!] Running in offline mode (no WiFi)"));
    }

    // 3. NTP
    if (wifi.isConnected()) {
        syncTime();
    }

    // 3.5. OTA Updates
    if (wifi.isConnected()) {
        ArduinoOTA.setHostname("soil-sensor");
        ArduinoOTA.setPassword("soilmon2026");  // Change this to your preferred password
        
        ArduinoOTA.onStart([]() {
            String type = (ArduinoOTA.getCommand() == U_FLASH) ? "firmware" : "filesystem";
            Serial.println("[OTA] Update started: " + type);
        });
        
        ArduinoOTA.onEnd([]() {
            Serial.println("\n[OTA] Update complete! Rebooting...");
        });
        
        ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
            Serial.printf("[OTA] Progress: %u%%\r", (progress / (total / 100)));
        });
        
        ArduinoOTA.onError([](ota_error_t error) {
            Serial.printf("[OTA] Error[%u]: ", error);
            if (error == OTA_AUTH_ERROR) Serial.println("Auth Failed");
            else if (error == OTA_BEGIN_ERROR) Serial.println("Begin Failed");
            else if (error == OTA_CONNECT_ERROR) Serial.println("Connect Failed");
            else if (error == OTA_RECEIVE_ERROR) Serial.println("Receive Failed");
            else if (error == OTA_END_ERROR) Serial.println("End Failed");
        });
        
        ArduinoOTA.begin();
        Serial.println(F("[OTA] Ready for wireless updates"));
    }

    // 4. Web server
    if (wifi.isConnected()) {
        webServer = new MonitorWebServer(logger, sensor);
        webServer->begin();
    }

    // 5. Take first reading immediately
    SensorReading r = sensor.read();
    logger.addReading(r);
    totalReadings++;
    
    Serial.printf("[Sensor] moisture=%.1f%%  raw=%d\n", r.moisturePct, r.rawValue);
    
    // Post to database
    if (USE_REMOTE_DB) {
        postToDatabase(r);
    }
    
    lastReadTime = millis();
    
    Serial.println(F("═══════════════════════════════════════"));
    Serial.printf("Setup complete. Uptime: %lu s\n", (millis() - bootTime) / 1000);
    Serial.printf("Reading interval: %d min\n", READ_INTERVAL_MS / 60000);
    Serial.printf("Remote DB: %s\n", USE_REMOTE_DB ? "enabled" : "disabled");
    Serial.println(F("═══════════════════════════════════════"));
}

// ─── loop() ──────────────────────────────────────────────────────────────────
void loop() {
    // Handle OTA updates (with watchdog feed)
    ArduinoOTA.handle();
    yield();
    
    // Handle HTTP clients (with watchdog feed)
    if (webServer) {
        webServer->handleClient();
        yield();
    }

    // Periodic sensor reading
    if (millis() - lastReadTime >= READ_INTERVAL_MS) {
        unsigned long readStart = millis();
        
        SensorReading r = sensor.read();
        logger.addReading(r);
        totalReadings++;

        Serial.println(F("─────────────────────────────────────"));
        Serial.printf("[Sensor] Reading #%u\n", totalReadings);
        Serial.printf("  Moisture: %.1f%%\n", r.moisturePct);
        Serial.printf("  Raw ADC: %d\n", r.rawValue);
        Serial.printf("  Logged: %zu readings\n", logger.count());
        Serial.printf("  Uptime: %lu s (%.1f min)\n", 
                      (millis() - bootTime) / 1000,
                      (millis() - bootTime) / 60000.0);
        Serial.printf("  Free heap: %u bytes\n", ESP.getFreeHeap());
        Serial.printf("  WiFi RSSI: %d dBm\n", WiFi.RSSI());
        
        // Post to database
        if (USE_REMOTE_DB) {
            bool posted = postToDatabase(r);
            if (!posted) {
                Serial.println(F("  [DB] Failed to post - will retry next reading"));
            }
        }
        
        Serial.printf("  Read duration: %lu ms\n", millis() - readStart);
        Serial.println(F("─────────────────────────────────────"));

        lastReadTime = millis();
    }

    // Reconnect WiFi if it drops
    if (!wifi.isConnected()) {
        static unsigned long lastReconnect = 0;
        if (millis() - lastReconnect > 30000) {
            Serial.println(F("[WiFi] Disconnected — attempting reconnect…"));
            wifi.connect();
            lastReconnect = millis();
        }
    }

    yield();  // ESP8266 watchdog - CRITICAL for stability
}
