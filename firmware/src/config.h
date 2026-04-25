/*
 * config.h
 * Configuration constants for the Soil Moisture Monitoring System
 */

#ifndef CONFIG_H
#define CONFIG_H

// ─── Version ─────────────────────────────────────────────────────────────────
#define FIRMWARE_VERSION    "1.0.0"
#define BUILD_DATE          __DATE__
#define BUILD_TIME          __TIME__

// ─── WiFi ────────────────────────────────────────────────────────────────────
// If WiFiManager captive portal times out, these are the fallback credentials.
// Leave empty to rely solely on the captive-portal flow.
#define WIFI_SSID           ""
#define WIFI_PASSWORD       ""
#define WIFI_CONNECT_TIMEOUT 30    // seconds

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
#define READ_INTERVAL_MS    60000  // how often to read sensor (ms) — 1 minute
#define LOG_BUFFER_SIZE     1440   // max entries kept in RAM (~24 h at 1-min interval)

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
