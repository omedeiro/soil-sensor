# Agent Instructions — Soil Sensor Project

## Communication Guidelines

**CRITICAL:** The phrase "You're absolutely right!" should NEVER be used in responses. Provide direct, objective technical information without validating language.

## Architecture

**NEW SYSTEM (InfluxDB + Grafana on Raspberry Pi 5):**
- **ESP8266 firmware** (PlatformIO/Arduino) — reads sensor, POSTs to InfluxDB every 5 min
- **InfluxDB** (Raspberry Pi 5) — time-series database for sensor readings
- **Grafana** (Raspberry Pi 5) — dashboards, alerts, visualization
- **Raspberry Pi 5** — dedicated server, 256GB USB storage, automated backups

**OLD SYSTEM (deprecated, being replaced):**
- **Database server** (Python/Flask/SQLite on macOS) — to be phased out

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

### System Testing
```bash
# InfluxDB write test
cd tests
export INFLUX_TOKEN="your_write_token"
./test_influx_write.sh     # verify InfluxDB connectivity and token
```

### Legacy Database Server (from `/database` - deprecated)
```bash
./start.sh                 # starts Flask server on port 5001
python3 server.py          # direct invocation
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

**WiFi Stability Features:**
- WiFi stability manager is always enabled (automatic reconnection with exponential backoff 5s → 60s)
- `ENABLE_WIFI_DIAGNOSTICS` enables detailed WiFi logging (disconnect reasons, RSSI)
- `QUEUE_FAILED_READINGS` queues up to 20 readings during database outages
- `MAX_QUEUE_SIZE` sets maximum queued readings (default: 20)

**IP addresses:**
- Raspberry Pi InfluxDB: `192.168.99.134:8086` (update to match your Pi if different)
- Raspberry Pi Grafana: `192.168.99.134:3000`
- ESP8266: `192.168.99.70` (DHCP-assigned, may change)
- Update `DB_SERVER_URL` in `config.h` if Raspberry Pi IP changes

## Dashboard Configuration Workflow (v2.7.0)

**CRITICAL: Auto-Generated Dashboards**

Starting in v2.7.0, the main Grafana dashboard is **auto-generated** from centralized configuration. Never manually edit `grafana-dashboards/soil-moisture-main.json`.

**Centralized Configuration System:**
- **`sensors-config.json`** — Single source of truth for all sensor information (plant names, IPs, MACs, colors, thresholds)
- **`generate-dashboard.py`** — Auto-generates `grafana-dashboards/soil-moisture-main.json` from config
- **`validate-config.py`** — Validates `sensors-config.json` before generation (checks syntax, duplicates, required fields)
- **`upload-dashboard-to-pi.sh`** — Deploys dashboard to Grafana on Raspberry Pi (uses SSH + Grafana API)

**Critical Workflow Rules:**
1. **NEVER manually edit `grafana-dashboards/soil-moisture-main.json`** — it's auto-generated and will be overwritten
2. **ALWAYS validate before generating:** Run `./validate-config.py` to catch errors early
3. **ALWAYS use `upload-dashboard-to-pi.sh`** for deployment (not manual curl or API calls)
4. **Deployment order is strict:** Edit config → Validate → Generate → Upload

**Adding a New Sensor (Dashboard Configuration):**
```bash
# 1. Edit sensors-config.json
vim sensors-config.json
# Add new sensor block (copy existing sensor, modify id/plant/location/ip/mac/color)

# 2. Validate configuration
./validate-config.py
# Output: ✓ Configuration is valid (8 sensors)

# 3. Generate dashboard
./generate-dashboard.py
# Output: ✓ Generated grafana-dashboards/soil-moisture-main.json

# 4. Deploy to Grafana
./upload-dashboard-to-pi.sh
# Output: ✓ Dashboard imported successfully

# 5. Configure and flash ESP8266 (see firmware section below)
cd firmware
# Edit src/config.h to match sensors-config.json (DEVICE_ID, DEVICE_LOCATION)
pio run --target upload
pio device monitor
```

**Changing Plant Names/Colors:**
```bash
# Quick workflow (3 commands):
vim sensors-config.json              # Edit plant name or color
./validate-config.py && \
./generate-dashboard.py && \
./upload-dashboard-to-pi.sh          # Validate, generate, deploy

# Dashboard updates in ~5 seconds (hard refresh browser: Cmd+Shift+R)
```

**sensors-config.json Structure:**
```json
{
  "sensors": [
    {
      "id": "sensor-X",              // Must match ESP8266 DEVICE_ID in config.h
      "plant": "Plant Name",         // Displayed in Grafana dropdown and labels
      "location": "room-name",       // Must match ESP8266 DEVICE_LOCATION in config.h
      "ip": "192.168.99.XXX",       // ESP8266 IP address (informational)
      "mac": "XX:XX:XX:XX:XX:XX",   // ESP8266 MAC address (informational)
      "color": "#RRGGBB",            // Hex color for time series graphs
      "thresholds": {
        "low": 33,                   // Low moisture threshold (%)
        "medium": 67                 // Medium moisture threshold (%)
      },
      "colorSteps": [                // Color gradient for bar gauges (dry → wet)
        {"value": null, "color": "#DARK"},   // Dry color
        {"value": 33, "color": "#MEDIUM"},   // Low moisture color
        {"value": 67, "color": "#LIGHT"}     // Wet color
      ]
    }
  ],
  "grafana": {
    "influxdb_datasource_uid": "cflk0i2e2nwu8d",  // Grafana datasource UID
    "bucket": "sensor-readings",                   // InfluxDB bucket name
    "measurement": "sensor_reading"                // InfluxDB measurement name
  }
}
```

**Dashboard Features (v2.7.0):**
- **7-day default time window** (not 24h) — shows last week of data by default
- **Dynamic plant name display** — Large heading shows "🌱 Rubber Tree" when specific sensor selected
- **Dropdown shows plant names** — "Rubber Tree" not "sensor-1" in dropdown
- **Functional filtering** — All panels filter when sensor selected from dropdown
- **Plant-only labels** — No room locations in labels (just "Rubber Tree")
- **Auto-generated from config** — All sensor info managed in sensors-config.json

**Validation Errors:**
```bash
# Common validation errors:
# - Missing comma after sensor block → JSON syntax error
# - Duplicate sensor IDs → "Duplicate sensor ID: sensor-3"
# - Invalid color format → "Invalid color format for sensor-2: #GGG"
# - Missing required fields → "Missing required field 'plant' for sensor-4"
# - threshold.low >= threshold.medium → "Invalid thresholds for sensor-1"

# Always run ./validate-config.py before generating!
```

**Deployment Troubleshooting:**
- **Dashboard upload fails with "Access denied":** Update credentials in `upload-dashboard-to-pi.sh` (default: admin/admin)
- **Dashboard not updating in Grafana:** Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)
- **Sensor not appearing in dropdown:** Sensor hasn't sent data yet, or `DEVICE_ID` in config.h doesn't match sensors-config.json
- **Colors not matching config:** Regenerate and upload dashboard, then hard refresh browser

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
   - Import dashboards from `grafana-dashboards/`

4. **Flash ESP8266**:
   ```bash
   cd firmware
   # Edit src/config.h with InfluxDB token and Pi IP
   pio run --target upload
   pio device monitor
   ```

5. **Verify data flow**:
   - Watch serial for: `[DB] ✓ Posted to InfluxDB: <device> @ <moisture>%`
   - Open Grafana dashboard
   - Run: `cd tests && export INFLUX_TOKEN="your_token" && ./test_influx_write.sh`

6. **WiFi stability test**:
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
- `install-cloudflare-tunnel.sh` — Cloudflare Tunnel setup for public access
- `configure-grafana-anonymous.sh` — Configure Grafana for anonymous viewing
- `systemd/` — service files for health monitor, backup timer
- `scripts/` — health monitor and backup bash scripts
- `README.md` — installation guide

**Tests (`/tests/`):**
- `test_influx_write.sh` — InfluxDB write test (manual token verification)

**Documentation (`/docs/`):**
- `README.md` — Technical documentation (WiFi stability, Grafana Cloud setup, InfluxDB notes)

**Grafana Dashboards (`/grafana-dashboards/`):**
- `soil-moisture-main.json` — Main overview dashboard (auto-generated, don't edit manually)
- `watering-history.json` — Watering event detection and tracking (v2.7.0)
- `sensor-details.json` — Individual sensor deep-dive
- `system-health.json` — ESP8266 diagnostics & events
- `alerts-overview.json` — Critical alerts & notifications
- `mobile-summary.json` — Mobile-optimized view
- `rpi-health.json` — Raspberry Pi system metrics
- `deploy-watering-dashboard.sh` — Deploy watering dashboard to Grafana
- `README.md` — Dashboard installation and customization guide

## Watering History Dashboard (v2.7.0)

**NEW FEATURE:** Automatic watering event detection and visualization.

**Location:** `grafana-dashboards/watering-history.json`

**Detection Algorithm:**
- **Threshold:** 15%+ moisture increase between consecutive readings (5-minute intervals)
- **Watered Status:** 2-hour window after detection
- **Noise Filtering:** Filters out sensor jitter, only detects sustained increases
- **Lookback:** 30 days for "last watered" stats, 7 days default timeline view

**Dashboard Panels:**
1. **Watering Events Timeline** — Green bars show 2-hour "watered" status after detection
2. **Moisture Trend with Markers** — Time series with red markers at watering events
3. **Time Since Last Watered** — 7 stat panels (color-coded: green <2d, yellow 2-5d, orange 5-7d, red >7d)
4. **Watering Frequency Heatmap** — Calendar view of patterns by day/hour

**Deployment (one-time):**
```bash
cd grafana-dashboards
./deploy-watering-dashboard.sh
# Dashboard imports automatically, available at https://grafana.owenmedeiros.com
```

**Testing:**
```bash
cd tests
./test-watering-detection.sh
# Simulates watering events and verifies detection logic
```

**Use Cases:**
- Track watering patterns ("Basil gets watered Sunday mornings")
- Identify forgotten plants ("Monstera hasn't been watered in 5 days")
- Verify watering events ("3 plants watered yesterday evening")

**How It Works:**
1. Flux query compares each moisture reading to previous reading (5 min apart)
2. If `current - previous >= 15%`, marks as watering event
3. Creates 2-hour "watered" status for timeline visualization
4. Calculates time since most recent watering event per sensor

**Troubleshooting:**
- **No watering events detected:** Check if moisture actually increases by 15%+ during watering
- **False positives:** Increase threshold in dashboard query (change `15.0` to `20.0`)
- **Missing data:** Ensure sensor readings are continuous (no gaps >5 minutes)

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
3. **IP mismatch:** `DB_SERVER_URL` in `config.h` must match Raspberry Pi IP (192.168.99.134)
4. **Missing/invalid token:** `INFLUX_TOKEN` must be set in `config.h` after InfluxDB setup
5. **Token permissions:** ESP8266 token needs **write** permission, Grafana token needs **read** permission
6. **Sensor voltage:** Must power sensor from 3.3V pin, not 5V (ADC max is 1.0V)
7. **Flashing without serial check:** Always run `pio device monitor` after upload to verify WiFi/DB connection
8. **Duplicate device IDs:** Each sensor must have unique `DEVICE_ID` in multi-sensor setup
9. **WiFi diagnostics disabled:** Set `ENABLE_WIFI_DIAGNOSTICS = true` in config.h for detailed logging
10. **Queue disabled:** Set `QUEUE_FAILED_READINGS = true` in config.h to survive network outages

## System Information

**Raspberry Pi 5 Server:**
- Username: `omedeiro`
- IP Address: `192.168.99.134`
- InfluxDB: `http://192.168.99.134:8086`
- Grafana (local): `http://192.168.99.134:3000`
- Grafana (public): `https://grafana.owenmedeiros.com`
- Data Storage: `/mnt/sensor-data` (256GB USB drive)
- Cloudflare Tunnel: `soil-sensor-grafana` (ID: ec9b412a-098a-45d2-8060-f2fa7b23b477)

**ESP8266 Sensors:**
- **sensor-1** (bed-room, Rubber Tree): `192.168.99.110` (MAC: 68:c6:3a:f6:b3:ae) - online
- **sensor-2** (living-room, Monstera): `192.168.99.149` (MAC: 48:3f:da:19:c0:86) - online
- **sensor-3** (living-room, Avocado): `192.168.99.70` (MAC: 40:91:51:4f:d9:97) - online
- **sensor-4** (guest-room, Basil - auk): `192.168.99.105` (MAC: 48:3f:da:aa:fe:d7) - online
- **sensor-5** (bed-room, ZZ Plant): `192.168.99.89` (MAC: 34:ab:95:16:51:d9) (ESP-1651D9, Wi-Fi 2.4GHz n) - online
- **sensor-6** (living-room, Ficus Elastica Ruby): `192.168.99.38` (MAC: 48:3f:da:62:f9:07) (Wi-Fi 2.4GHz n) - online
- **sensor-7** (guest-room, Basil - pot): `192.168.99.141` (MAC: 84:cc:a8:a7:96:32) (Wi-Fi 2.4GHz n) - online
- Web Dashboard: `http://<sensor-ip>` (e.g., `http://192.168.99.110`)
- Reading Interval: 5 minutes (300000ms)

## Troubleshooting Grafana Issues

**If Grafana dashboard is unreachable:**

1. **Check if public URL is working:**
   ```bash
   curl -I https://grafana.owenmedeiros.com
   ```

2. **Check Cloudflare Tunnel status:**
   ```bash
   ssh omedeiro@192.168.99.134 "sudo systemctl status cloudflared"
   ssh omedeiro@192.168.99.134 "cloudflared tunnel list"
   ```

3. **Check Grafana service status:**
   ```bash
   ssh omedeiro@192.168.99.134 "systemctl status grafana-server"
   ```

4. **Check if services are running:**
   ```bash
   ssh omedeiro@192.168.99.134 "systemctl is-active grafana-server influxdb cloudflared"
   ```

5. **Restart services if down:**
   ```bash
   ssh omedeiro@192.168.99.134 "sudo systemctl restart grafana-server"
   ssh omedeiro@192.168.99.134 "sudo systemctl restart cloudflared"
   ```

6. **Check for USB mount issues:**
   ```bash
   ssh omedeiro@192.168.99.134 "df -h | grep sensor-data"
   ssh omedeiro@192.168.99.134 "journalctl -u mnt-sensor\\x2ddata.mount --no-pager"
   ```

7. **Verify data is still being collected:**
   - ESP8266 continues writing to InfluxDB even if Grafana is down
   - Check ESP8266 status: `curl http://192.168.99.70/api/latest`
   - Check InfluxDB health: `curl http://192.168.99.134:8086/health`

8. **Check system logs for boot/failure reasons:**
   ```bash
   # View startup history (boot reasons, filesystem corruption, etc.)
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/startup_history.log"
   
   # View Grafana-specific failures
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/grafana_failures.log"
   
   # View reboot triggers
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/reboot_reasons.log"
   
   # Monitor health checks in real-time
   ssh omedeiro@192.168.99.134 "tail -f /mnt/sensor-data/logs/health-monitor.log"
   
   # View Cloudflare Tunnel logs
   ssh omedeiro@192.168.99.134 "sudo journalctl -u cloudflared -f"
   ```

**Common Grafana failure causes:**
- **Improper shutdown:** Filesystem corruption from power loss or hard reboot
- **USB drive unmounting:** `/mnt/sensor-data` not mounted at boot
- **Systemd restart loop:** Grafana exits cleanly (exit 0) so systemd won't auto-restart
- **Data directory corruption:** Grafana database files in `/mnt/sensor-data/grafana/data`

**Recovery steps after improper shutdown:**
1. Check startup log for boot reason: `ssh omedeiro@192.168.99.134 "tail -50 /mnt/sensor-data/logs/startup_history.log"`
2. Check filesystem: `ssh omedeiro@192.168.99.134 "sudo journalctl -b | grep -E '(fsck|Dirty|corrupt)'"`
3. Verify mount: `ssh omedeiro@192.168.99.134 "mount | grep sensor-data"`
4. Check Grafana logs: `ssh omedeiro@192.168.99.134 "sudo journalctl -u grafana-server --no-pager"`
5. Restart Grafana manually if needed: `sudo systemctl restart grafana-server`

**Enhanced Logging System:**
- See `/rpi-setup/LOGGING_README.md` for complete logging documentation
- Startup logger tracks all boot events and reasons
- Health monitor auto-restarts failed services
- Log rotation prevents disk space issues
- Install enhanced logging: `cd ~/rpi-setup && sudo ./install-logging.sh`

## Troubleshooting Sensor Offline Issues

**Problem:** ESP8266 sensor stops posting to InfluxDB and requires power cycle to recover.

**Root Causes:**
1. **Power supply issues** - Insufficient voltage/current during WiFi transmission (most common)
2. **Firmware crash** - Unhandled exception or watchdog timeout
3. **WiFi disconnect loop** - Lost connection and failed to recover (automatic restart after 10 failed attempts)

**Detection Methods:**

1. **Manual Check (InfluxDB query):**
   ```bash
   ssh omedeiro@192.168.99.134 'curl -s -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
     -H "Authorization: Token YOUR_READ_TOKEN" \
     -H "Content-Type: application/vnd.flux" \
     -d "from(bucket: \"sensor-readings\")
     |> range(start: -1h)
     |> filter(fn: (r) => r.device_id == \"sensor-1\")
     |> filter(fn: (r) => r._field == \"moisture\")
     |> last()"'
   ```

2. **Automated Monitoring (recommended):**
   ```bash
   # Install sensor health monitoring on Raspberry Pi
   ssh omedeiro@192.168.99.134
   cd ~/rpi-setup
   ./install-sensor-monitoring.sh
   
   # This installs:
   # - Health check script (runs every 10 minutes)
   # - Alerts when sensor offline for 15+ minutes
   # - Logs to system journal for troubleshooting
   
   # View monitoring status:
   systemctl status sensor-health-check.timer
   journalctl -u sensor-health-check -f
   ```

3. **Grafana Alerts Dashboard:**
   - Open `http://grafana.owenmedeiros.com` or `http://192.168.99.134:3000`
   - Navigate to "⚠️ Alerts & Notifications" dashboard
   - Check "Sensor Status" panel for offline sensors
   - Configure alert notifications in Grafana settings

**Recovery Steps:**

1. **Immediate:** Power cycle the ESP8266 (unplug USB, wait 5 seconds, replug)
2. **If issue persists:** 
   - Check power supply (use quality USB adapter ≥1A, short USB cable)
   - Reflash firmware: `cd ~/soil-sensor/firmware && pio run --target upload`
   - Check WiFi signal strength (RSSI should be > -70 dBm)
3. **Long-term fix:**
   - Use dedicated 5V 2A power adapter (not computer USB port)
   - Reduce WiFi distance to router or add WiFi extender
   - Enable automatic health monitoring (see above)

**Firmware Recovery Features:**
- Hardware watchdog (auto-restart if hung for 8 seconds)
- Crash detection (logs to InfluxDB diagnostics)
- WiFi auto-reconnect (10 attempts with exponential backoff, then full restart)
- Reading queue (stores up to 20 failed readings during outages)

**Prevention:**
- **Install sensor health monitoring** (automated alerts)
- Use quality power supply and short USB cables
- Place ESP8266 within good WiFi range (RSSI > -70 dBm)
- Monitor Grafana alerts dashboard regularly

## Status Files Reference

**Documentation:**
- `docs/README.md` — Technical documentation (WiFi stability, Grafana Cloud setup, InfluxDB notes)
- `grafana-dashboards/README.md` — Dashboard installation, customization, and alert setup
- `README.md` — Project overview and setup instructions
- `AGENTS.md` — This file (agent instructions and technical reference)
