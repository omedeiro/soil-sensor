/*
 * config.h
 * Configuration constants for the Soil Moisture Monitoring System
 */

#ifndef CONFIG_H
#define CONFIG_H

// ─── Secrets ─────────────────────────────────────────────────────────────────
// WiFi credentials and the InfluxDB write token live in secrets.h, which is
// gitignored. Copy secrets.h.example → secrets.h and fill in real values.
// (Provides WIFI_SSID, WIFI_PASSWORD, INFLUX_TOKEN.)
#include "secrets.h"

// ─── Version ─────────────────────────────────────────────────────────────────
#define FIRMWARE_VERSION    "2.4.0"
#define BUILD_DATE          __DATE__
#define BUILD_TIME          __TIME__

// ─── WiFi ────────────────────────────────────────────────────────────────────
// If WiFiManager captive portal times out, these are the fallback credentials.
// Leave empty to rely solely on the captive-portal flow.
// NOTE: WIFI_SSID and WIFI_PASSWORD are defined in secrets.h (gitignored).
#define WIFI_CONNECT_TIMEOUT 90    // seconds

// WiFiManager access-point name (shown when device is unconfigured)
#define AP_NAME             "SoilSensor-Setup"
#define AP_PASSWORD         ""     // leave empty for open AP

// ─── Device Type ─────────────────────────────────────────────────────────────
// Selects which kind of sensor is wired to this board. Only one path is
// compiled in, so the other sensor's code/libraries add no runtime cost.
//   DEVICE_TYPE_SOIL    → capacitive soil-moisture probe on A0 (sensors 1-7)
//   DEVICE_TYPE_CLIMATE → DHT22/AM2302 ambient temp + humidity (sensor-8)
#define DEVICE_TYPE_SOIL     0
#define DEVICE_TYPE_CLIMATE  1
// #ifndef-guarded so a per-device build can select the board type with -D.
// Leaving a CLIMATE value here bit us once: flashing a soil probe without
// overriding DEVICE_TYPE compiles the soil path OUT entirely, so the board
// reports no moisture and /api/latest returns {"error":"no data"}.
// The default is SOIL because 7 of 9 devices are soil probes.
#ifndef DEVICE_TYPE
#define DEVICE_TYPE          DEVICE_TYPE_SOIL      // ← override with -DDEVICE_TYPE=1 for climate
#endif

// DHT22 (AM2302) — only used when DEVICE_TYPE == DEVICE_TYPE_CLIMATE
#define DHT_PIN              D2                 // GPIO4 (data line)
#define DHT_TYPE             DHT22
#define CLIMATE_MEASUREMENT  "climate_reading"  // InfluxDB measurement for DHT data

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
// INFLUX_TOKEN is defined in secrets.h (gitignored).
#define DB_SERVER_URL       "http://192.168.99.134:8086/api/v2/write"
#define INFLUX_ORG          "soil-monitoring"
#define INFLUX_BUCKET       "sensor-readings"

// Device identification for multi-sensor deployments
// Option 1: Auto-generate from MAC address (e.g., "esp8266-40915141d997")
// Option 2: Set DEVICE_ID_AUTO=false and provide custom ID below
#define DEVICE_ID_AUTO      false
// DEVICE_ID / DEVICE_LOCATION are #ifndef-guarded so a per-sensor build can supply
// them with -D (PLATFORMIO_BUILD_FLAGS) without editing this file. Without the
// guard the value here silently WINS over -D (macro redefinition), which would
// flash every sensor with the same identity and collapse per-plant history.
#ifndef DEVICE_ID
#define DEVICE_ID           "sensor-9"          // Fallback for a plain USB build
#endif
#ifndef DEVICE_LOCATION
#define DEVICE_LOCATION     "guest-room"        // Fallback for a plain USB build
#endif

// ─── Static IP (use when DHCP fails) ──────────────────────────────────────────
// Set USE_STATIC_IP to true and fill in values below if the board cannot
// obtain an address via DHCP.  Set USE_STATIC_IP to false for normal DHCP.
// WARNING: with a static IP, WiFi.localIP().isSet() is true even when the
// device never associated with the router — DHCP is strongly recommended.
// Use DHCP reservations on the router if stable IPs are needed.
#define USE_STATIC_IP       false
#define STATIC_IP           "192.168.99.48"
#define STATIC_GATEWAY      "192.168.99.1"
#define STATIC_SUBNET       "255.255.255.0"
#define STATIC_DNS1         "192.168.99.1"
#define STATIC_DNS2         "8.8.8.8"

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
