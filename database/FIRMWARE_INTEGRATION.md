# Firmware Integration Guide

This guide shows how to integrate database logging into your ESP8266 firmware.

## Quick Start

### 1. Enable Database Logging

Edit `firmware/src/config.h`:

```cpp
// ─── Remote Database (Multi-Sensor Support) ──────────────────────────────────
#define USE_REMOTE_DB       true   // Enable database logging
#define DB_SERVER_URL       "http://192.168.99.188:5001/api/reading"

// Device identification
#define DEVICE_ID_AUTO      false  // Use custom ID
#define DEVICE_ID           "garden-bed-a"  // Your unique sensor name
```

### 2. Add Database Client to main.cpp

```cpp
// At the top of main.cpp, add:
#include "database_client.h"

// Add global instance:
#if USE_REMOTE_DB
DatabaseClient dbClient;
String deviceId;
#endif

// In setup(), after WiFi connection:
#if USE_REMOTE_DB
    deviceId = DatabaseClient::getDeviceId();
    Serial.printf("[DB] Device ID: %s\n", deviceId.c_str());
    Serial.printf("[DB] Server: %s\n", DB_SERVER_URL);
#endif

// In your sensor reading loop (where you log data):
void loop() {
    // ... existing sensor reading code ...
    
    // Get the reading
    int rawValue = sensor.read();
    float moisture = sensor.getMoisture();
    unsigned long timestamp = getTime();  // Your NTP time function
    
    // Store locally
    dataLogger.addReading(timestamp, rawValue, moisture);
    
#if USE_REMOTE_DB
    // Also send to database
    unsigned long uptime = millis() / 1000;
    int crashes = 0;  // Or track actual crashes
    
    bool sent = dbClient.sendReading(
        deviceId,
        timestamp,
        rawValue,
        moisture,
        uptime,
        crashes
    );
    
    if (sent) {
        Serial.println("[DB] Reading uploaded to database");
    } else {
        Serial.println("[DB] Failed to upload reading (will retry next time)");
    }
#endif
    
    // ... rest of loop ...
}
```

## Complete Integration Example

Here's a minimal working example for `main.cpp`:

```cpp
#include <Arduino.h>
#include <time.h>
#include "config.h"
#include "wifi_manager.h"
#include "sensor.h"
#include "data_logger.h"
#include "web_server.h"

#if USE_REMOTE_DB
#include "database_client.h"
DatabaseClient dbClient;
String deviceId;
#endif

WiFiManager wifiMgr;
Sensor sensor;
DataLogger dataLogger;
WebServer webServer;

unsigned long lastReadTime = 0;

void setup() {
    Serial.begin(SERIAL_BAUD);
    delay(100);
    
    Serial.println("\n═══════════════════════════════════════");
    Serial.println("  🌱  Soil Moisture Monitoring System");
    Serial.println("═══════════════════════════════════════\n");
    
    // Initialize WiFi
    if (!wifiMgr.connect()) {
        Serial.println("[ERROR] Failed to connect to WiFi");
        delay(5000);
        ESP.restart();
    }
    
    Serial.printf("[WiFi] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
    
    // Initialize NTP for timestamps
    configTime(UTC_OFFSET_SEC, UTC_OFFSET_DST_SEC, NTP_SERVER);
    
#if USE_REMOTE_DB
    // Initialize database client
    deviceId = DatabaseClient::getDeviceId();
    Serial.printf("[DB] Device ID: %s\n", deviceId.c_str());
    Serial.printf("[DB] Database URL: %s\n", DB_SERVER_URL);
#endif
    
    // Initialize sensor
    sensor.begin();
    
    // Start web server
    webServer.begin();
    
    Serial.println("\n✓ System ready!\n");
}

void loop() {
    // Handle web requests
    webServer.handleClient();
    
    // Check if it's time to read the sensor
    unsigned long now = millis();
    if (now - lastReadTime >= READ_INTERVAL_MS) {
        lastReadTime = now;
        
        // Read sensor
        int raw = sensor.read();
        float moisture = sensor.getMoisture();
        unsigned long timestamp = time(nullptr);
        
        // Log locally
        dataLogger.addReading(timestamp, raw, moisture);
        
        Serial.printf("[Sensor] Raw: %d, Moisture: %.1f%%\n", raw, moisture);
        
#if USE_REMOTE_DB
        // Send to database
        unsigned long uptime = millis() / 1000;
        
        if (dbClient.sendReading(deviceId, timestamp, raw, moisture, uptime, 0)) {
            Serial.println("[DB] ✓ Sent to database");
        } else {
            Serial.println("[DB] ✗ Failed to send (will retry next reading)");
        }
#endif
    }
    
    yield();  // Let ESP8266 do WiFi housekeeping
}
```

## Build Configuration

Update `platformio.ini` to include the new files:

```ini
[env:nodemcuv2]
platform = espressif8266
board = nodemcuv2
framework = arduino

lib_deps =
    ESP8266WiFi
    ESP8266WebServer
    ESP8266HTTPClient  ; Add this for database client
    WiFiManager
    ArduinoJson

build_flags =
    -DUSE_REMOTE_DB=1  ; Optional: override config.h
```

## Testing

### 1. Build and Upload

```bash
cd firmware
pio run --target upload
pio device monitor
```

### 2. Watch Serial Output

You should see:
```
[WiFi] Connected! IP: 192.168.99.70
[DB] Device ID: garden-bed-a
[DB] Database URL: http://192.168.99.188:5001/api/reading
[Sensor] Raw: 520, Moisture: 61.9%
[DB] ✓ Reading sent successfully (HTTP 201)
[DB]   Response: {"id":1,"status":"ok","timestamp":1714000000}
```

### 3. Verify in Database

```bash
# Check if device registered
curl http://192.168.99.188:5001/api/devices

# Check latest reading
curl "http://192.168.99.188:5001/api/latest?device_id=garden-bed-a"
```

## Error Handling

The database client includes automatic error handling:

- **Connection timeout**: Reading is skipped, will retry on next interval
- **HTTP error**: Error is logged to serial, local logging continues
- **Invalid response**: Error is logged, next reading will retry

**Important**: Local web dashboard and data logging continue to work even if database is unreachable!

## Deployment Checklist

For each new sensor:

- [ ] Set unique `DEVICE_ID` in `config.h`
- [ ] Verify `DB_SERVER_URL` matches your server IP/hostname
- [ ] Build and upload firmware: `pio run --target upload`
- [ ] Monitor first reading: `pio device monitor`
- [ ] Verify device appears in database: `curl http://<server>/api/devices`
- [ ] Label device with metadata using API `PUT /api/devices/<id>`
- [ ] Document sensor location for future reference

## Troubleshooting

### "Connection failed" errors

**Symptom**: `[DB] ✗ Connection failed: connection refused`

**Solutions**:
1. Ping the database server: `ping 192.168.99.188`
2. Check server is running: `curl http://192.168.99.188:5001/health`
3. Verify ESP8266 can reach server from same network
4. Check firewall rules on server machine

### "HTTP 400 Bad Request"

**Symptom**: `[DB] ✗ Server returned HTTP 400`

**Solutions**:
1. Verify `device_id` is set and not empty
2. Check JSON payload is valid in serial output
3. Ensure all required fields are present (device_id, raw, moisture)

### "device_id is empty"

**Symptom**: `[DB] Warning: DEVICE_ID is empty, using MAC address`

**Solutions**:
1. Set `DEVICE_ID_AUTO = true` to use MAC (recommended for testing)
2. Or set `DEVICE_ID = "your-id"` with a non-empty string

## Next Steps

- ✅ Configure multiple sensors with unique IDs
- ✅ Set up database server (see `MULTI_SENSOR_SETUP.md`)
- 🔲 Create dashboard to visualize all sensors
- 🔲 Set up alerts for low/high moisture levels
- 🔲 Export data for analysis
