/*
 * main.cpp
 * ────────────────────────────────────────────────────────────────────
 * Soil Moisture Monitoring System — ESP8266 firmware (InfluxDB version)
 *
 * Flow:
 *   1. Init serial + sensor
 *   2. Connect to WiFi (captive-portal provisioning via WiFiManager)
 *   3. Sync time via NTP
 *   4. Start HTTP server (dashboard + JSON API)
 *   5. Loop: read sensor at configured interval, send to InfluxDB
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
#include "wifi_stability.h"
#include "data_logger.h"
#include "web_server.h"

#if USE_REMOTE_DB
#include "database_client.h"
#include "reading_queue.h"
#endif

#if ENABLE_DIAGNOSTICS
#include "diagnostics.h"
#endif

#if ENABLE_HEARTBEAT
#include "heartbeat.h"
#endif

// ─── Global objects ──────────────────────────────────────────────────────────
SoilSensor          sensor;
WifiConnection      wifi;
WiFiStabilityManager wifiStability;
DataLogger          logger;
MonitorWebServer*   webServer = nullptr;
WiFiClient          wifiClient;

#if USE_REMOTE_DB
DatabaseClient  dbClient;
ReadingQueue    readingQueue;
String          deviceId;
#endif

#if ENABLE_DIAGNOSTICS
DiagnosticsManager diagnostics;
#endif

#if ENABLE_HEARTBEAT
HeartbeatManager heartbeat;
#endif

unsigned long lastReadTime = 0;
unsigned long bootTime = 0;
unsigned long lastCrashTime = 0;
unsigned long lastDiagnosticsTime = 0;
unsigned long lastHeapCheck = 0;
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
    
    bool isCrash = false;
    if (resetInfo->reason == REASON_WDT_RST ||
        resetInfo->reason == REASON_EXCEPTION_RST ||
        resetInfo->reason == REASON_SOFT_WDT_RST) {
        isCrash = true;
        crashCount++;
        Serial.printf("⚠️  CRASH DETECTED! Count: %u\n", crashCount);
        Serial.println(F("  This may indicate:"));
        Serial.println(F("    - Blocking code preventing watchdog feed"));
        Serial.println(F("    - Memory corruption"));
        Serial.println(F("    - Power supply issues"));
        
        #if ENABLE_DIAGNOSTICS
        // Log crash to diagnostics system (will be sent after WiFi connects)
        String resetReasonStr = ESP.getResetReason();
        // Note: diagnostics.logCrashDetected() will be called after WiFi connects
        #endif
    } else {
        Serial.println(F("✅ Clean boot"));
    }
    Serial.println(F("─────────────────────────────────────"));
}

// ─── WiFi Diagnostics (periodic) ─────────────────────────────────────────────
#if ENABLE_WIFI_DIAGNOSTICS
void logWiFiDiagnostics() {
    static unsigned long lastLog = 0;
    if (millis() - lastLog > 300000) {  // Every 5 minutes
        wifiStability.printDiagnostics();
        lastLog = millis();
    }
}
#endif

// ─── setup() ─────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(SERIAL_BAUD);
    delay(200);
    Serial.println();
    Serial.println(F("═══════════════════════════════════════"));
    Serial.println(F("  🌱  Soil Moisture Monitoring System"));
    Serial.println(F("     InfluxDB + WiFi Stability v2.1"));
    Serial.print(F("  Device: "));
    Serial.print(F(DEVICE_ID));
    Serial.print(F("  ("));
    Serial.print(F(DEVICE_LOCATION));
    Serial.println(F(")"));
    Serial.print(F("  MAC:    "));
    Serial.println(WiFi.macAddress());
    Serial.println(F("═══════════════════════════════════════"));
    
    bootTime = millis();
    
    // Enable hardware watchdog
    #if ENABLE_HARDWARE_WATCHDOG
    ESP.wdtEnable(WDTO_8S);
    Serial.printf("[Watchdog] Hardware watchdog enabled (%d seconds)\n", WATCHDOG_TIMEOUT_SEC);
    #endif
    
    // Check for crashes
    rst_info* resetInfo = ESP.getResetInfoPtr();
    bool wasCrash = (resetInfo->reason == REASON_WDT_RST ||
                     resetInfo->reason == REASON_EXCEPTION_RST ||
                     resetInfo->reason == REASON_SOFT_WDT_RST);
    checkForCrash();

    // 1. Sensor
    sensor.begin();

    // 2. WiFi
    if (!wifi.connect()) {
        Serial.println(F("[!] Running in offline mode (no WiFi)"));
    } else {
        // Initialize WiFi stability manager with event handlers
        wifiStability.begin();
    }

    // 3. NTP
    if (wifi.isConnected()) {
        syncTime();
    }

#if USE_REMOTE_DB
    // 3.2. Initialize database client
    if (wifi.isConnected()) {
        deviceId = DatabaseClient::getDeviceId();
        Serial.printf("[DB] Device ID: %s\n", deviceId.c_str());
        Serial.printf("[DB] Location: %s\n", DEVICE_LOCATION);
        Serial.printf("[DB] InfluxDB URL: %s\n", DB_SERVER_URL);
        Serial.printf("[DB] Organization: %s\n", INFLUX_ORG);
        Serial.printf("[DB] Bucket: %s\n", INFLUX_BUCKET);
        
        #if ENABLE_DIAGNOSTICS
        // Initialize diagnostics system
        diagnostics.begin(deviceId);
        
        // Log crash if detected
        if (wasCrash) {
            diagnostics.logCrashDetected(resetInfo->reason, ESP.getResetReason());
        }
        #endif
        
        #if ENABLE_HEARTBEAT
        // Initialize heartbeat system
        heartbeat.begin(deviceId, HEARTBEAT_INTERVAL_MS);
        #endif
    }
#endif

    // 3.5. OTA Updates
    if (wifi.isConnected()) {
        ArduinoOTA.setHostname(deviceId.c_str());
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

    // 4. Web server (optional - can disable to save memory)
    if (wifi.isConnected()) {
        webServer = new MonitorWebServer(logger, sensor);
        webServer->begin();
        Serial.println(F("[HTTP] Local web server started (can disable to save memory)"));
    }

    // 5. Take first reading immediately
    SensorReading r = sensor.read();
    logger.addReading(r);
    totalReadings++;
    
    Serial.printf("[Sensor] moisture=%.1f%%  raw=%d\n", r.moisturePct, r.rawValue);

#if USE_REMOTE_DB
    // Send first reading to InfluxDB
    if (wifi.isConnected()) {
        unsigned long uptime = (millis() - bootTime) / 1000;
        int rssi = WiFi.RSSI();
        int freeHeap = ESP.getFreeHeap();
        
        bool success = dbClient.sendReading(
            deviceId, 
            r.timestamp, 
            r.rawValue, 
            r.moisturePct, 
            uptime, 
            crashCount,
            rssi,
            freeHeap,
            QUEUE_FAILED_READINGS  // Queue on failure
        );
        
        if (!success && QUEUE_FAILED_READINGS) {
            // Add to queue if send failed
            QueuedReading qr = {deviceId, r.timestamp, r.rawValue, r.moisturePct, 
                                uptime, (int)crashCount, rssi, freeHeap};
            readingQueue.enqueue(qr);
        }
    }
#endif
    
    lastReadTime = millis();
    
    #if ENABLE_DIAGNOSTICS
    // Log boot complete event
    if (wifi.isConnected()) {
        diagnostics.logBootComplete(millis() - bootTime);
    }
    #endif
    
    Serial.println(F("═══════════════════════════════════════"));
    Serial.printf("Setup complete. Uptime: %lu s\n", (millis() - bootTime) / 1000);
    Serial.printf("Reading interval: %u min\n", (unsigned)(READ_INTERVAL_MS / 60000));
    Serial.printf("Remote DB: %s\n", USE_REMOTE_DB ? "enabled" : "disabled");
    Serial.printf("WiFi Diagnostics: %s\n", ENABLE_WIFI_DIAGNOSTICS ? "enabled" : "disabled");
    Serial.printf("Reading Queue: %s (%d max)\n", QUEUE_FAILED_READINGS ? "enabled" : "disabled", MAX_QUEUE_SIZE);
    Serial.printf("Diagnostics: %s\n", ENABLE_DIAGNOSTICS ? "enabled" : "disabled");
    Serial.printf("Heartbeat: %s (%lu s interval)\n", ENABLE_HEARTBEAT ? "enabled" : "disabled", HEARTBEAT_INTERVAL_MS / 1000);
    Serial.printf("Hardware Watchdog: %s\n", ENABLE_HARDWARE_WATCHDOG ? "enabled" : "disabled");
    Serial.printf("Free heap: %u bytes\n", ESP.getFreeHeap());
    Serial.println(F("═══════════════════════════════════════"));
}

// ─── loop() ──────────────────────────────────────────────────────────────────
void loop() {
    yield();  // Feed watchdog at start of loop
    
    #if ENABLE_HARDWARE_WATCHDOG
    ESP.wdtFeed();  // Explicitly feed hardware watchdog
    #endif
    
    // Handle OTA updates
    ArduinoOTA.handle();
    yield();
    
    // Handle HTTP clients (if web server enabled)
    if (webServer) {
        webServer->handleClient();
        yield();
    }
    
    // WiFi stability monitoring and reconnection
    wifiStability.loop();
    yield();
    
    #if ENABLE_HEARTBEAT
    // Send heartbeat
    heartbeat.loop();
    yield();
    #endif
    
    #if ENABLE_DIAGNOSTICS
    // Check for low heap condition
    if (millis() - lastHeapCheck > 60000) {  // Check every minute
        int freeHeap = ESP.getFreeHeap();
        if (freeHeap < HEAP_LOW_THRESHOLD) {
            diagnostics.logHeapLowWarning(freeHeap, HEAP_LOW_THRESHOLD);
        }
        lastHeapCheck = millis();
    }
    #endif
    
#if ENABLE_WIFI_DIAGNOSTICS
    logWiFiDiagnostics();
#endif

    // Periodic sensor reading
    if (millis() - lastReadTime >= READ_INTERVAL_MS) {
        unsigned long readStart = millis();
        
        SensorReading r = sensor.read();
        logger.addReading(r);
        totalReadings++;

#if USE_REMOTE_DB
        // Get additional metrics
        unsigned long uptime = (millis() - bootTime) / 1000;
        int rssi = WiFi.RSSI();
        int freeHeap = ESP.getFreeHeap();
        
        // Try to drain queue first if WiFi is connected
        if (wifi.isConnected() && !readingQueue.isEmpty()) {
            Serial.println(F("[Main] WiFi connected - attempting to drain queue"));
            int drained = dbClient.drainQueue(readingQueue);
            if (drained > 0) {
                Serial.printf("[Main] Successfully sent %d queued readings\n", drained);
            }
            yield();
        }
        
        // Send current reading to InfluxDB
        bool sent = false;
        if (wifi.isConnected()) {
            sent = dbClient.sendReading(
                deviceId,
                r.timestamp,
                r.rawValue,
                r.moisturePct,
                uptime,
                crashCount,
                rssi,
                freeHeap,
                false  // Don't queue yet - we'll do it manually below
            );
        }
        
        if (!sent) {
            Serial.println(F("[DB] Failed to send reading (WiFi down or server error)"));
            
            // Add to queue if enabled
            if (QUEUE_FAILED_READINGS) {
                QueuedReading qr = {
                    deviceId, 
                    r.timestamp, 
                    r.rawValue, 
                    r.moisturePct,
                    uptime, 
                    (int)crashCount, 
                    rssi, 
                    freeHeap
                };
                
                if (readingQueue.enqueue(qr)) {
                    Serial.printf("[Queue] Reading queued (%u in queue)\n", readingQueue.count());
                } else {
                    Serial.println(F("[Queue] ✗ Queue full - reading LOST!"));
                    
                    #if ENABLE_DIAGNOSTICS
                    // Log queue overflow event
                    diagnostics.logQueueOverflow(readingQueue.count());
                    #endif
                }
            }
        }
#endif

        // Log reading info to serial
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
        Serial.printf("  WiFi Status: %s\n", WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
        
#if QUEUE_FAILED_READINGS
        Serial.printf("  Queue size: %u / %u\n", readingQueue.count(), MAX_QUEUE_SIZE);
#endif
        
        Serial.printf("  Read duration: %lu ms\n", millis() - readStart);
        Serial.println(F("─────────────────────────────────────"));

        lastReadTime = millis();
    }

    yield();  // Feed watchdog at end of loop
}
