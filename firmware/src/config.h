/*
 * config.h
 * Configuration constants for the Soil Moisture Monitoring System
 */

#ifndef CONFIG_H
#define CONFIG_H

// ─── Version ─────────────────────────────────────────────────────────────────
#define FIRMWARE_VERSION    "2.1.0"
#define BUILD_DATE          __DATE__
#define BUILD_TIME          __TIME__

// ─── WiFi ────────────────────────────────────────────────────────────────────
// If WiFiManager captive portal times out, these are the fallback credentials.
// Leave empty to rely solely on the captive-portal flow.
#define WIFI_SSID           "Starry00920"
#define WIFI_PASSWORD       "8T3UYT4334"
#define WIFI_CONNECT_TIMEOUT 90    // seconds

// WiFiManager access-point name (shown when device is unconfigured)
#define AP_NAME             "SoilSensor-Setup"
#define AP_PASSWORD         ""     // leave empty for open AP

// ─── Sensor ──────────────────────────────────────────────────────────────────
#define SENSOR_PIN          A0     // ADC pin (ESP8266 has one: A0)
#define SENSOR_READ_COUNT   10     // number of readings to average
#define SENSOR_READ_DELAY   50     // ms between individual ADC reads

// Calibration: raw ADC values (10-bit: 0-1023)
// Measure these with your specific sensor:
//   AIR_VALUE   → sensor in open air (dry, high ADC value)
//   WATER_VALUE → sensor submerged in water (wet, low ADC value)
#define SENSOR_AIR_VALUE    780
#define SENSOR_WATER_VALUE  360

// ─── Logging / Timing ────────────────────────────────────────────────────────
#define READ_INTERVAL_MS    300000  // how often to read sensor (ms) — 5 minutes
#define LOG_BUFFER_SIZE     50      // max entries kept in RAM (reduced for memory savings)

// ─── Remote Database (InfluxDB) ──────────────────────────────────────────────
// Enable to send readings to InfluxDB on Raspberry Pi
#define USE_REMOTE_DB       true

// InfluxDB Configuration
// NOTE: Update these after setting up InfluxDB on Raspberry Pi!
#define DB_SERVER_URL       "http://192.168.99.134:8086/api/v2/write"
#define INFLUX_TOKEN        "fNL1d7Eg__QMxP_vGqR2Ekw16ADxYO8gDdDxXqEFGs-t3j03sRpHKDY8R7pz0kRIaQ35yWlU3NXhXX9ra0YWNA=="  // Operator token
#define INFLUX_ORG          "soil-monitoring"
#define INFLUX_BUCKET       "sensor-readings"

// Device identification for multi-sensor deployments
// Option 1: Auto-generate from MAC address (e.g., "esp8266-40915141d997")
// Option 2: Set DEVICE_ID_AUTO=false and provide custom ID below
#define DEVICE_ID_AUTO      false
#define DEVICE_ID           "sensor-1"          // Change for each sensor: sensor-1, sensor-2, etc.
#define DEVICE_LOCATION     "bed-room"          // Optional location tag for Grafana filtering

// ─── WiFi Stability & Queue ──────────────────────────────────────────────────
#define ENABLE_WIFI_DIAGNOSTICS  true   // Enable detailed WiFi logging
#define QUEUE_FAILED_READINGS    true   // Queue readings when network is down
#define MAX_QUEUE_SIZE           20     // Maximum queued readings

// ─── Diagnostics & Reliability ───────────────────────────────────────────────
#define ENABLE_DIAGNOSTICS        true    // Send diagnostic events to InfluxDB
#define ENABLE_HEARTBEAT          true    // Send periodic heartbeat messages
#define HEARTBEAT_INTERVAL_MS     60000   // Heartbeat interval (1 minute)
#define ENABLE_HARDWARE_WATCHDOG  true    // Auto-reset if firmware hangs
#define WATCHDOG_TIMEOUT_SEC      8       // Hardware watchdog timeout
#define MAX_DRAIN_TIME_MS         10000   // Max time for queue drain per loop
#define MAX_DRAIN_PER_LOOP        5       // Max readings to drain per loop
#define DIAGNOSTIC_QUEUE_SIZE     10      // Max queued diagnostic events
#define HEAP_LOW_THRESHOLD        10240   // Free heap warning threshold (bytes)

// ─── HTTP Server ─────────────────────────────────────────────────────────────
#define HTTP_PORT           80

// ─── NTP Time Sync ───────────────────────────────────────────────────────────
#define NTP_SERVER          "pool.ntp.org"
#define UTC_OFFSET_SEC      0      // adjust for your timezone (e.g. -18000 for EST)
#define UTC_OFFSET_DST_SEC  0      // daylight-saving offset

// ─── Serial ──────────────────────────────────────────────────────────────────
#ifndef SERIAL_BAUD
#define SERIAL_BAUD         115200
#endif

#endif // CONFIG_H
