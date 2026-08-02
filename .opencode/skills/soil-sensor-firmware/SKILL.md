---
name: soil-sensor-firmware
description: Build, flash, configure, and calibrate the ESP8266 soil/climate sensor firmware. Use when running `pio run`, `pio run --target upload`, or `pio device monitor`, editing `firmware/src/config.h`, setting DEVICE_ID/DEVICE_LOCATION/DEVICE_TYPE, calibrating a capacitive probe, wiring a DHT22/AM2302, adding a new sensor board, interpreting serial monitor output, or debugging WiFi provisioning / reconnection on the ESP8266.
---

# ESP8266 Soil Sensor Firmware

Firmware lives in `/firmware` (PlatformIO/Arduino). It reads a sensor and POSTs to
InfluxDB every 5 minutes.

## Build / Deploy Commands (from `/firmware`)

```bash
pio run                        # build only (default USB env)
pio run --target upload        # flash via USB
pio device monitor             # serial output at 115200 baud

# OTA (preferred for deployed sensors — no USB needed):
pio run -e esp8266-ota --target upload --upload-port <sensor-ip>
# OTA password: soilmon2026 (set in platformio.ini upload_flags + main.cpp)
```

Two PlatformIO environments exist: `esp8266` (USB/esptool) and `esp8266-ota`
(espota). Never edit platformio.ini to switch — just pick the env.
`flash-all-ota.sh` loops over all soil sensors in `sensors-config.json`
(per-sensor `DEVICE_ID`/`DEVICE_LOCATION`/`DEVICE_TYPE` rewrite + OTA flash);
climate boards (sensor-8/9) are not in that config and must be flashed
individually with `DEVICE_TYPE_CLIMATE`.

After USB upload run `pio device monitor` to verify WiFi/DB connection. After
OTA upload verify via InfluxDB (fresh low `uptime`, heartbeats) — note that
opening the USB serial port resets the board, so don't probe serial while
diagnosing WiFi issues remotely.

## config.h — single source of truth

`firmware/src/config.h` holds all ESP8266 settings:

- `DB_SERVER_URL` must point to InfluxDB: `http://<pi-ip>:8086/api/v2/write`
- `INFLUX_TOKEN` must be a **write** token from InfluxDB (generated in UI)
- `INFLUX_ORG` defaults to `soil-monitoring`
- `INFLUX_BUCKET` defaults to `sensor-readings`
- `READ_INTERVAL_MS` is 300000 (5 min) despite some legacy docs saying 1 min — trust the code
- `DEVICE_ID_AUTO` can be false for multi-sensor deployments; use `DEVICE_ID` to name sensors (sensor-1, sensor-2, etc.)
- `DEVICE_LOCATION` tags sensor location for Grafana filtering (e.g., "backyard", "greenhouse")

`DEVICE_ID` / `DEVICE_LOCATION` must match `sensors-config.json` (see the
`grafana-dashboard-config` skill).

### Device type (soil vs. climate)

- `DEVICE_TYPE` selects the board's sensor: `DEVICE_TYPE_SOIL` (default, sensors 1-7, capacitive probe on A0) or `DEVICE_TYPE_CLIMATE` (sensor-8 living-room, sensor-9 guest-room; DHT22/AM2302 on `DHT_PIN`=D2/GPIO4).
- Only one path is compiled in, so the unused sensor adds no runtime cost. Keep `DEVICE_TYPE_SOIL` as the default when reflashing soil sensors.
- Climate devices write the **`climate_reading`** measurement (not `sensor_reading`) with float fields `temperature_c`, `temperature_f`, `humidity` plus `uptime`/`rssi`/`free_heap` diagnostics. Tags: `device_id`, `location`.
- DHT22 needs libs `adafruit/DHT sensor library` + `adafruit/Adafruit Unified Sensor` (in `platformio.ini`). Wire DATA→D2, VCC→3.3V, GND→GND (bare AM2302 needs a 10kΩ pull-up DATA↔VCC).

### WiFi stability features (v2.4.0+)

- WiFi stability manager is always enabled and always initialized at boot, even
  if WiFi wasn't available (automatic reconnection with exponential backoff 5s → 60s,
  full `ESP.restart()` after 10 failed attempts)
- **DHCP only** (`USE_STATIC_IP false`). Do not re-enable static IP: with a
  static IP, `WiFi.localIP().isSet()` reads true without a real association,
  so the device can "think it's connected forever" after a power cycle and
  never recover. Use router DHCP reservations for stable IPs instead.
- Credentials persist in SDK flash (`WiFi.persistent(true)` + `WiFi.disconnect(false)`),
  and runtime reconnects use explicit `WiFi.begin(WIFI_SSID, ...)`.
- With hardcoded credentials the WiFiManager captive portal is **never**
  entered — failed boots return to the stability manager instead of blocking
  180 s in the `SoilSensor-Setup` portal. The portal only appears when
  `WIFI_SSID` is empty.
- `ENABLE_WIFI_DIAGNOSTICS` enables detailed WiFi logging (disconnect reasons, RSSI)
- `QUEUE_FAILED_READINGS` queues up to 20 readings during database outages
- `MAX_QUEUE_SIZE` sets maximum queued readings (default: 20)
- Net effect: sensors survive power cycles and can be unplugged/moved to any
  outlet; they rejoin WiFi automatically.

### IP addresses

- Raspberry Pi InfluxDB: `192.168.99.134:8086` (update to match your Pi if different)
- Raspberry Pi Grafana: `192.168.99.134:3000`
- Update `DB_SERVER_URL` in `config.h` if Raspberry Pi IP changes

## Calibration

Sensor returns raw ADC values (0-1023). Two calibration points needed:

- `SENSOR_AIR_VALUE` — probe in open air (dry, ~780)
- `SENSOR_WATER_VALUE` — probe submerged (~360)

Calibrate via:
1. Edit `config.h` and reflash, **or**
2. HTTP API: `curl -X POST "http://192.168.99.70/api/calibrate?air=780&water=360"`

## WiFi Provisioning Flow

Credentials are normally hardcoded in `firmware/src/secrets.h` (`WIFI_SSID`,
`WIFI_PASSWORD`); as of v2.4.0 the captive portal is only used when
`WIFI_SSID` is empty:
1. ESP8266 creates AP named `SoilSensor-Setup`
2. User connects, captive portal appears
3. User selects network + password
4. Device reboots, connects to WiFi

With hardcoded credentials the device never opens the portal — if WiFi is
down at boot it retries in the background (backoff 5s→60s) and restarts after
10 failures, repeating until the network returns.

## Serial Monitor Key Messages

**Good signs:**
- `✅ Clean boot` — no crashes detected
- `[WiFi] ✓ Connected to <SSID>` — WiFi working
- `[WiFi] RSSI: -45 dBm (excellent)` — strong WiFi signal
- `[DB] Using InfluxDB: http://192.168.99.134:8086` — InfluxDB configured
- `[DB] ✓ Posted to InfluxDB (HTTP 204)` — successful write (note: 204 not 201)
- `[Queue] ✓ Queue empty` — no queued readings

**Warning signs:**
- `⚠️ CRASH DETECTED!` — power supply issue (try different cable/adapter)
- `⚠️ WiFi disconnected (reason: 200 - beacon timeout)` — lost WiFi connection
- `⏳ Reconnection attempt 1/10 (backoff: 5s)` — attempting to reconnect
- `[DB] ✗ POST failed (connection refused)` — InfluxDB not running or wrong URL
- `[DB] ✗ POST failed (HTTP 401)` — invalid InfluxDB token
- `[Queue] ⬆️ Queued reading (5/20)` — database unreachable, queueing readings

**WiFi reconnection flow:**
- Automatic reconnection with exponential backoff: 5s → 10s → 30s → 60s
- After 10 failed attempts, ESP8266 performs full restart
- Backoff resets after 5 minutes of stable connection
- Queued readings automatically drained when connection restored

**Critical failure (restart required):**
- `⚠️ 10 reconnection attempts failed - restarting ESP8266` — full restart initiated

## Multi-Sensor Setup (5-10 sensors supported)

1. Set `DEVICE_ID_AUTO = false` in `config.h`
2. Assign unique `DEVICE_ID` for each sensor: `sensor-1`, `sensor-2`, etc.
3. Set `DEVICE_LOCATION` for each sensor: `backyard`, `greenhouse`, etc.
4. Flash each ESP8266 individually
5. Calibrate each sensor (soil moisture varies by location)
6. All sensors POST to same InfluxDB instance
7. Grafana dashboards auto-detect new sensors

**Example config for sensor-2:**
```cpp
#define DEVICE_ID_AUTO      false
#define DEVICE_ID           "sensor-2"
#define DEVICE_LOCATION     "greenhouse"
```

See `docs/MULTI_SENSOR_GUIDE.md` for the complete deployment guide.

## ESP8266 HTTP API (port 80, optional, can be disabled)

- `GET /` — live dashboard HTML (if `WEB_SERVER_ENABLED`)
- `GET /api/latest` — latest reading JSON
- `GET /api/history` — in-memory readings (last 50)
- `POST /api/calibrate?air=780&water=360` — calibrate sensor remotely

## Firmware File Organization (`/firmware/src/`)

- `main.cpp` — entry point (setup/loop), watchdog, WiFi stability integration
- `config.h` — **all configuration constants** (InfluxDB URL, tokens, WiFi settings)
- `sensor.{h,cpp}` — ADC reading + moisture calculation
- `database_client.{h,cpp}` — InfluxDB line protocol, HTTP POST, retry logic, queue drain
- `wifi_manager.{h,cpp}` — WiFi + captive portal, power management tuning
- `wifi_stability.{h,cpp}` — reconnection logic, event handlers, diagnostics
- `reading_queue.{h,cpp}` — circular buffer for failed readings (max 20)
- `web_server.{h,cpp}` — local HTTP server (optional, can disable)
- `data_logger.{h,cpp}` — in-memory ring buffer (reduced to 50 entries)

## Hardware Constraints

- ESP8266 has **~40KB free heap** — avoid large buffers
- ADC is **10-bit** (0-1023), max input **1.0V** — sensor must use 3.3V power, not 5V
- WiFiManager library version pinned: `tzapu/WiFiManager@^0.16.0`
- ArduinoJson library: `bblanchon/ArduinoJson@^6.21.3`
