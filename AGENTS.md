# Agent Instructions — Soil Sensor Project

## Architecture

**NEW SYSTEM (InfluxDB + Grafana on Raspberry Pi 5):**
- **ESP8266 firmware** (PlatformIO/Arduino) — reads sensor, POSTs to InfluxDB every 5 min
- **InfluxDB** (Raspberry Pi 5) — time-series database for sensor readings
- **Grafana** (Raspberry Pi 5) — dashboards, alerts, visualization
- **Raspberry Pi 5** — dedicated server, 256GB USB storage, automated backups

**OLD SYSTEM (deprecated, being replaced):**
- **Database server** (Python/Flask/SQLite on macOS) — to be phased out
- See migration plan in `docs/MIGRATION_PLAN.md`

**Working directory:** 
- Firmware: `/firmware`
- Raspberry Pi setup: `/rpi-setup`
- Database (legacy): `/database`
- Documentation: `/docs`
- Tests: `/tests`

## Critical Build/Deploy Commands

### Firmware (from `/firmware`)
```bash
pio run                    # build only
pio run --target upload    # flash to ESP8266
pio device monitor         # serial output at 115200 baud
```

### Raspberry Pi Setup (one-time installation)
```bash
# On Raspberry Pi 5:
cd ~/rpi-setup
sudo ./install.sh          # installs InfluxDB, Grafana, systemd services
```

**Post-installation:**
1. Configure InfluxDB: `http://<pi-ip>:8086` (create org, bucket, tokens)
2. Configure Grafana: `http://<pi-ip>:3000` (add data source, import dashboards)
3. Update ESP8266 `config.h` with InfluxDB token and URL
4. See `docs/RPI_SETUP.md` for complete guide

### System Testing
```bash
# NEW: End-to-end InfluxDB + Grafana test
cd tests
export INFLUX_TOKEN="your_write_token"
./test_e2e.sh              # comprehensive system test

# WiFi stability tests
./test_wifi_reconnection.sh    # manual WiFi disconnect test
./test_queue_drain.sh          # reading queue functionality
./test_72h_stability.sh        # long-term stability (72 hours)

# Multi-sensor tests
./test_multi_sensor.sh         # simulate 5 sensors posting data
```

### Legacy Database Server (from `/database` - deprecated)
```bash
./start.sh                 # starts Flask server on port 5001
python3 server.py          # direct invocation
./test_system.sh           # old health check (use tests/test_e2e.sh instead)
```

## Configuration Gotchas

**`firmware/src/config.h`** is the single source of truth for ESP8266 settings:
- `DB_SERVER_URL` must point to InfluxDB: `http://<pi-ip>:8086/api/v2/write`
- `INFLUX_TOKEN` must be set to write token from InfluxDB (generated in UI)
- `INFLUX_ORG` defaults to `soil-monitoring`
- `INFLUX_BUCKET` defaults to `sensor-readings`
- `READ_INTERVAL_MS` is 300000 (5 min) despite some legacy docs saying 1 min — trust the code
- `DEVICE_ID_AUTO` can be false for multi-sensor deployments; use `DEVICE_ID` to name sensors (sensor-1, sensor-2, etc.)
- `DEVICE_LOCATION` tags sensor location for Grafana filtering (e.g., "backyard", "greenhouse")

**WiFi Stability Features (NEW):**
- `WIFI_STABILITY_ENABLED` enables auto-reconnection with exponential backoff
- `WIFI_RECONNECT_ENABLED` enables automatic WiFi reconnection (5s → 60s backoff)
- `READING_QUEUE_ENABLED` queues up to 20 readings during database outages
- `WIFI_DIAGNOSTICS_ENABLED` logs disconnect reasons and RSSI

**IP addresses:**
- Raspberry Pi InfluxDB: `192.168.99.134:8086` (update to match your Pi if different)
- Raspberry Pi Grafana: `192.168.99.134:3000`
- ESP8266: `192.168.99.70` (DHCP-assigned, may change)
- Update `DB_SERVER_URL` in `config.h` if Raspberry Pi IP changes

## WiFi Provisioning Flow

On first boot or if credentials invalid:
1. ESP8266 creates AP named `SoilSensor-Setup`
2. User connects, captive portal appears
3. User selects network + password
4. Device reboots, connects to WiFi

**Important:** After flashing new firmware, WiFi may need reconfiguration. Connect to serial monitor first to see status.

## Serial Monitor Key Messages

**Good signs:**
- `✅ Clean boot` — no crashes detected
- `[WiFi] ✓ Connected to <SSID>` — WiFi working
- `[WiFi] RSSI: -45 dBm (excellent)` — strong WiFi signal
- `[DB] Using InfluxDB: http://192.168.99.134:8086` — InfluxDB configured
- `[DB] ✓ Posted to InfluxDB (HTTP 204)` — successful write to InfluxDB (note: 204 not 201)
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

## Calibration

Sensor returns raw ADC values (0-1023). Two calibration points needed:
- `SENSOR_AIR_VALUE` — probe in open air (dry, ~780)
- `SENSOR_WATER_VALUE` — probe submerged (~360)

Can calibrate via:
1. Edit `config.h` and reflash, **or**
2. HTTP API: `curl -X POST "http://192.168.99.70/api/calibrate?air=780&water=360"`

## API Endpoints

**ESP8266 (port 80) - optional, can be disabled:**
- `GET /` — live dashboard HTML (if `WEB_SERVER_ENABLED`)
- `GET /api/latest` — latest reading JSON
- `GET /api/history` — in-memory readings (last 50)
- `POST /api/calibrate?air=780&water=360` — calibrate sensor remotely

**InfluxDB (Raspberry Pi port 8086):**
- `POST /api/v2/write?org=<org>&bucket=<bucket>&precision=s` — ESP8266 writes here (requires token)
- `POST /api/v2/query?org=<org>` — Flux queries (requires token)
- `GET /health` — health check
- `GET /ping` — connectivity test

**Grafana (Raspberry Pi port 3000):**
- `GET /` — dashboard UI (login required)
- `GET /api/health` — health check
- `GET /api/dashboards/` — list dashboards
- `POST /api/annotations` — create annotations (alerts)

**Legacy Database server (port 5001) - deprecated:**
- See `/database/README.md` for legacy endpoints (being phased out)

## Testing Flow (NEW SYSTEM)

1. **Install Raspberry Pi** (one-time):
   ```bash
   ssh pi@raspberrypi.local
   cd ~/rpi-setup
   sudo ./install.sh
   ```

2. **Configure InfluxDB** (one-time):
   - Open `http://<pi-ip>:8086`
   - Create org: `soil-monitoring`, bucket: `sensor-readings`
   - Generate write token for ESP8266
   - Generate read token for Grafana

3. **Configure Grafana** (one-time):
   - Open `http://<pi-ip>:3000` (admin/admin)
   - Add InfluxDB data source (Flux, localhost:8086)
   - Import dashboards from `grafana-dashboards/` (to be created)

4. **Flash ESP8266**:
   ```bash
   cd firmware
   # Edit src/config.h with InfluxDB token and Pi IP
   pio run --target upload
   pio device monitor
   ```

5. **Verify data flow**:
   - Watch serial for: `[DB] ✓ Posted to InfluxDB (HTTP 204)`
   - Open Grafana dashboard
   - Run: `cd tests && ./test_e2e.sh`

6. **WiFi stability test**:
   - Run: `cd tests && ./test_wifi_reconnection.sh`
   - Manually disconnect WiFi (router admin or power off router)
   - Watch serial for reconnection attempts
   - Verify queued readings drain after reconnection

**If ESP8266 offline:** check for `SoilSensor-Setup` AP and reconfigure WiFi.

## Testing Flow (LEGACY SYSTEM)

1. Start database: `cd database && ./start.sh`
2. Connect ESP8266 via USB
3. Monitor serial: `cd firmware && pio device monitor`
4. Wait for `[DB] ✓ Posted to database (HTTP 201)`
5. Open `database/dashboard.html` in browser

## Multi-Sensor Setup (5-10 Sensors Supported)

**Setup process:**
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

**See `docs/MULTI_SENSOR_GUIDE.md` for complete deployment guide.**

## File Organization

**Firmware (`/firmware/src/`):**
- `main.cpp` — entry point (setup/loop), watchdog, WiFi stability integration
- `config.h` — **all configuration constants** (InfluxDB URL, tokens, WiFi settings)
- `sensor.{h,cpp}` — ADC reading + moisture calculation
- `database_client.{h,cpp}` — InfluxDB line protocol, HTTP POST, retry logic, queue drain
- `wifi_manager.{h,cpp}` — WiFi + captive portal, power management tuning
- `wifi_stability.{h,cpp}` — **NEW:** reconnection logic, event handlers, diagnostics
- `reading_queue.{h,cpp}` — **NEW:** circular buffer for failed readings (max 20)
- `web_server.{h,cpp}` — local HTTP server (optional, can disable)
- `data_logger.{h,cpp}` — in-memory ring buffer (reduced to 50 entries)

**Raspberry Pi Setup (`/rpi-setup/`):**
- `install.sh` — one-command installer for InfluxDB + Grafana
- `systemd/` — service files for health monitor, backup timer
- `scripts/` — health monitor and backup bash scripts
- `README.md` — installation guide

**Tests (`/tests/`):**
- `test_e2e.sh` — comprehensive end-to-end system test
- `test_influx_write.sh` — InfluxDB write test (manual token verification)
- `test_multi_sensor.sh` — simulate 5 sensors posting data
- `test_wifi_reconnection.sh` — manual WiFi disconnect test
- `test_queue_drain.sh` — reading queue functionality test
- `test_72h_stability.sh` — long-term stability test (72 hours)

**Documentation (`/docs/`):**
- `RPI_SETUP.md` — Raspberry Pi installation and configuration guide
- `WIFI_IMPROVEMENTS.md` — WiFi stability features and troubleshooting
- `MULTI_SENSOR_GUIDE.md` — multi-sensor deployment guide (5-10 sensors)
- `MIGRATION_PLAN.md` — SQLite → InfluxDB migration plan (to be created)

**Grafana Dashboards (`/grafana-dashboards/`):**
- `soil-sensor.json` — Primary dashboard for soil moisture monitoring (individual sensor plots)
- `system-diagnostics.json` — Network/WiFi diagnostics and hardware health monitoring
- `README.md` — Dashboard installation and customization guide

**Legacy Database (`/database/` - deprecated):**
- `server.py` — Flask app (being phased out)
- `dashboard.html` — web UI (replaced by Grafana)
- `sensor_data.db` — SQLite database (migrating to InfluxDB)
- `start.sh` — startup wrapper

## Constraints

- ESP8266 has **~40KB free heap** — avoid large buffers
- ADC is **10-bit** (0-1023), max input **1.0V** — sensor must use 3.3V power, not 5V
- WiFiManager library version pinned: `tzapu/WiFiManager@^0.16.0`
- ArduinoJson library: `bblanchon/ArduinoJson@^6.21.3`

## Common Mistakes to Avoid

1. **Wrong InfluxDB port:** InfluxDB is on 8086, not 5001 (5001 was legacy SQLite server)
2. **Wrong HTTP status code:** InfluxDB returns 204 (not 201) on successful write
3. **IP mismatch:** `DB_SERVER_URL` in `config.h` must match Raspberry Pi IP (not Mac IP)
4. **Missing/invalid token:** `INFLUX_TOKEN` must be set in `config.h` after InfluxDB setup
5. **Token permissions:** ESP8266 token needs **write** permission, Grafana token needs **read** permission
6. **Sensor voltage:** Must power sensor from 3.3V pin, not 5V (ADC max is 1.0V)
7. **Flashing without serial check:** Always run `pio device monitor` after upload to verify WiFi/DB connection
8. **Duplicate device IDs:** Each sensor must have unique `DEVICE_ID` in multi-sensor setup
9. **WiFi stability disabled:** Set `WIFI_STABILITY_ENABLED = true` to enable auto-reconnection
10. **Queue disabled:** Set `READING_QUEUE_ENABLED = true` to survive network outages

## Status Files Reference

**New Documentation:**
- `docs/RPI_SETUP.md` — Raspberry Pi 5 installation and InfluxDB/Grafana configuration
- `docs/WIFI_IMPROVEMENTS.md` — WiFi stability features, reconnection logic, diagnostics
- `docs/MULTI_SENSOR_GUIDE.md` — deploying 5-10 sensors with device IDs and location tags
- `grafana-dashboards/README.md` — dashboard installation, customization, and alert setup
- `docs/MIGRATION_PLAN.md` — SQLite → InfluxDB migration (to be created)

**Legacy Documentation:**
- `STATUS.md` — last known system state (legacy Flask server)
- `TESTING.md` — step-by-step testing procedure (legacy)
- `DEPLOYMENT.md` — physical deployment guide, moisture level chart
- `QUICK_REFERENCE.txt` — user-facing cheat sheet (legacy)
- `START_HERE.sh` — interactive startup guide (legacy)

**Testing:**
Run `cd tests && ./test_e2e.sh` for comprehensive system health check (InfluxDB, Grafana, ESP8266).
