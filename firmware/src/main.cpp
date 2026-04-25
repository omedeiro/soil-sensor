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

unsigned long lastReadTime = 0;

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
    }
    Serial.println();
    if (now >= 1609459200L) {
        Serial.printf("[NTP] Time synced: %s", ctime(&now));
    } else {
        Serial.println(F("[NTP] Sync failed — timestamps will be 0"));
    }
}

// ─── setup() ─────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(SERIAL_BAUD);
    delay(200);
    Serial.println();
    Serial.println(F("═══════════════════════════════════════"));
    Serial.println(F("  🌱  Soil Moisture Monitoring System"));
    Serial.printf("  Version: %s\n", FIRMWARE_VERSION);
    Serial.printf("  Built: %s %s\n", BUILD_DATE, BUILD_TIME);
    Serial.println(F("═══════════════════════════════════════"));

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
    Serial.printf("[Sensor] moisture=%.1f%%  raw=%d\n", r.moisturePct, r.rawValue);
    lastReadTime = millis();
}

// ─── loop() ──────────────────────────────────────────────────────────────────
void loop() {
    // Handle OTA updates
    ArduinoOTA.handle();
    
    // Handle HTTP clients
    if (webServer) {
        webServer->handleClient();
    }

    // Periodic sensor reading
    if (millis() - lastReadTime >= READ_INTERVAL_MS) {
        SensorReading r = sensor.read();
        logger.addReading(r);

        Serial.printf("[Sensor] moisture=%.1f%%  raw=%d  (logged %zu readings)\n",
                       r.moisturePct, r.rawValue, logger.count());

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

    yield();  // ESP8266 watchdog
}
