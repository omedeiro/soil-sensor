# 🌱 Soil Moisture Monitoring System — v2.12.0

A production-grade, multi-sensor soil moisture monitoring system built with **ESP8266** microcontrollers, **InfluxDB**, and **Grafana**, hosted on a **Raspberry Pi 5**.

Each soil sensor reads moisture every 5 minutes and posts data to a central time-series database. Dedicated **DHT22 climate sensors** also report ambient temperature and humidity from multiple rooms. A live Grafana dashboard visualizes all sensors simultaneously.

---

## 📊 Live Dashboard Access

**Public Dashboard** (no login required):

🌐 **https://grafana.owenmedeiros.com** — View all dashboards live from anywhere

**Local Network Access:**
- http://192.168.99.134:3000 — Full dashboard access on local network
- Admin login available for editing dashboards

> **Note:** Public URL has anonymous read-only access. Only admins can edit dashboards.

---

## Architecture

```
[Capacitive Sensor] ──► [ESP8266 NodeMCU]
                               │  WiFi (WPA2)
                               ▼
                    [Raspberry Pi 5 Server]
                    ├── InfluxDB 2.x  (:8086)
                    ├── Grafana       (:3000)
                    └── Cloudflare Tunnel
                              │
                              ▼
                    https://grafana.owenmedeiros.com
```

---

## Features

### ESP8266 Firmware (v2.3.0)
- **Multi-sensor support** — unlimited ESP8266 sensors, each identified by `DEVICE_ID`
- **Soil or climate boards** — compile-time `DEVICE_TYPE` switch selects a capacitive soil probe (A0) or a **DHT22/AM2302** ambient temperature + humidity sensor (writes the `climate_reading` measurement)
- **WiFi stability** — scan-before-connect, exponential backoff reconnect (5s→60s), max TX power
- **Offline queue** — up to 20 readings buffered in RAM when WiFi/server is unavailable
- **Hardware watchdog** — 8-second ESP8266 hardware watchdog prevents infinite loops
- **OTA updates** — flash firmware remotely via WiFi (no USB cable needed)
- **Heartbeat telemetry** — 60-second heartbeat with uptime, free heap, WiFi RSSI, queue status
- **Diagnostic events** — crash detection, WiFi events, InfluxDB errors tracked in dedicated measurement
- **NTP timestamps** — every reading is UTC-timestamped
- **Boot diagnostics** — device ID, MAC address, crash reason printed on every boot

### Raspberry Pi Server (v2.12.0)
- **InfluxDB 2.x backend** — time-series storage on USB drive, 365-day retention
- **Grafana dashboards (6 total)** — soil moisture with **Pi uptime panel** plus **ambient temperature/humidity panels**, sensor details, system health, alerts, mobile view, Pi health
- **Cloudflare Tunnel** — public HTTPS access via `grafana.owenmedeiros.com` (anonymous read-only viewing)
- **Enhanced logging system** — boot tracking, filesystem corruption detection, Grafana failure logging, log rotation
- **Anonymous access** — view-only Grafana dashboards without login (Viewer role)
- **System metrics** — CPU, RAM, disk, temperature monitoring via Python collector (60s interval)
- **Automated backups** — daily Pi backup via systemd timer
- **Health monitoring** — auto-restart InfluxDB/Grafana on failure (3 failures in 10 min triggers reboot)

---

## Project Structure

```
soil-sensor/
├── sensors-config.json           # ← Centralized sensor configuration (single source of truth)
├── AGENTS.md                     # Agent instructions & technical reference
├── README.md                     # This file
├── scripts/                      # Dashboard generation & deployment tools
│   ├── generate-dashboard.py     # Auto-generate Grafana dashboard from config
│   ├── validate-config.py        # Validate sensors-config.json before generation
│   ├── upload-dashboard-to-pi.sh # Deploy dashboard to Grafana on Pi
│   ├── bump-version.sh           # Version bump automation
│   ├── check-grafana-panels.py   # Panel health checker
│   ├── debug-grafana-query.sh    # Query debugger for "No Data" panels
│   └── repair-grafana-panels.sh  # Automated panel repair
├── firmware/                     # ESP8266 PlatformIO firmware
│   ├── platformio.ini
│   ├── lib/
│   │   └── config-helpers.sh     # Shared config loader for flash scripts
│   ├── flash-usb-interactive.sh  # USB flash: one sensor at a time
│   ├── flash-all-sensors.sh      # USB flash: all sensors sequentially
│   ├── flash-all-ota.sh          # OTA flash: all sensors over WiFi
│   ├── flash-ota-canary.sh       # OTA flash: canary + production rollout
│   └── src/
│       ├── config.h              # ← Edit this per sensor
│       ├── main.cpp
│       ├── sensor.h/.cpp         # ADC driver & moisture %
│       ├── dht_sensor.h/.cpp     # DHT22 temperature/humidity driver
│       ├── wifi_manager.h/.cpp   # WiFi connect, scan, retry
│       ├── wifi_stability.h/.cpp # Reconnect watchdog, exponential backoff
│       ├── database_client.h/.cpp# InfluxDB line protocol HTTP POST
│       ├── heartbeat.h/.cpp      # 60s health telemetry
│       ├── diagnostics.h/.cpp    # Event tracking (crash, WiFi, errors)
│       ├── data_logger.h/.cpp    # In-RAM ring buffer
│       ├── reading_queue.h/.cpp  # Offline queue (max 20 readings)
│       └── web_server.h/.cpp     # Local HTTP server (optional)
├── grafana-dashboards/
│   ├── soil-moisture-main.json   # Main overview dashboard (auto-generated, don't edit)
│   ├── sensor-details.json       # Individual sensor deep-dive
│   ├── watering-history.json     # Watering event detection & visualization
│   ├── system-health.json        # ESP8266 diagnostics & events
│   ├── alerts-overview.json      # Critical alerts & notifications
│   ├── mobile-summary.json       # Mobile-optimized view
│   ├── rpi-health.json           # Raspberry Pi system metrics
│   ├── import-all-dashboards.sh  # Bulk import to Grafana
│   ├── deploy-watering-dashboard.sh
│   └── README.md                 # Dashboard installation guide
├── rpi-setup/
│   ├── install.sh                # Full Pi setup script (InfluxDB + Grafana)
│   ├── install-cloudflare-tunnel.sh  # Cloudflare Tunnel installer
│   ├── install-logging.sh        # Enhanced logging system installer
│   ├── install-panel-health-monitor.sh  # Panel health monitoring
│   ├── install-sensor-monitoring.sh     # Sensor health monitoring
│   ├── configure-grafana-anonymous.sh   # Anonymous viewing setup
│   ├── LOGGING_README.md         # Logging documentation
│   ├── scripts/
│   │   ├── sensor-backup.sh
│   │   ├── sensor-health-monitor.sh
│   │   ├── startup-logger.sh
│   │   └── system-metrics-collector.py
│   └── systemd/                  # Service files for Pi services
├── hardware/                     # Wiring diagrams & BOM
│   ├── BOM.md
│   └── SCHEMATIC.md
├── tests/                        # Integration tests
│   ├── test_influx_write.sh
│   └── test-watering-detection.sh
└── docs/                         # Documentation
    ├── CHANGELOG.md
    ├── README.md                 # WiFi stability, Grafana Cloud, InfluxDB notes
    ├── reference/QUICK_REFERENCE.md
    ├── guides/TROUBLESHOOTING_NO_DATA.md
    └── archive/                  # Historical records & reports
```

---

## Hardware

### Components (per sensor)

| Component | Notes |
|-----------|-------|
| ESP8266 NodeMCU v2 | Any ESP8266 board with ADC works |
| Capacitive Soil Moisture Sensor v1.2 | Do **not** use resistive sensors |
| Micro-USB cable + 5V charger | For deployment power |
| Jumper wires (F-F) | 3 wires |

### Wiring

```
Sensor VCC  ──► ESP8266 3V3
Sensor GND  ──► ESP8266 GND
Sensor AOUT ──► ESP8266 A0
```

> ⚠️ Use **3.3V** power — not 5V. The ESP8266 ADC max input is 1.0V (NodeMCU has a built-in voltage divider).

---

## Raspberry Pi Setup

### Requirements

- Raspberry Pi 5 (4 GB+ RAM recommended)
- Raspberry Pi OS Trixie (Debian 13) 64-bit
- 256 GB USB drive (for InfluxDB + Grafana data)

### Install

```bash
git clone https://github.com/omedeiro/soil-sensor.git
cd soil-sensor/rpi-setup
sudo ./install.sh
```

The script installs and configures:
- InfluxDB 2.7.12 (pinned — v2.9+ has ARM64 Flux query issues)
- Grafana (latest stable)
- systemd services for auto-start, health monitoring, and daily backups
- UFW firewall (ports 22, 8086, 3000)
- Static IP via NetworkManager

### After Install

1. **Configure InfluxDB** at `http://<pi-ip>:8086`
   - Create org: `soil-monitoring`
   - Create bucket: `sensor-readings` (365-day retention)
   - Generate write token for ESP8266 sensors
   - Generate read token for Grafana

2. **Configure Grafana** at `http://<pi-ip>:3000`
   - Login: `admin` / `admin` (change on first login)
   - Add InfluxDB datasource (Flux mode, URL: `http://localhost:8086`)
   - Copy dashboards to `/mnt/sensor-data/grafana/dashboards/` (auto-provisioned)
   - Or import manually via UI from `grafana-dashboards/*.json`

3. **Enable anonymous access and public URL** (optional, for read-only public viewing)
   ```bash
   cd rpi-setup
   ./install-cloudflare-tunnel.sh      # Set up public HTTPS access
   ./configure-grafana-anonymous.sh    # Enable anonymous viewing
   ```
   Dashboards will be viewable at `https://grafana.owenmedeiros.com` (replace with your domain)

---

## Firmware Setup

### Prerequisites

- [PlatformIO](https://platformio.org/) (VS Code extension or CLI)
- USB-to-serial driver for your board (CP2102 or CH340)

### Configure secrets (`firmware/src/secrets.h`)

WiFi credentials and the InfluxDB write token are **not** stored in git. Copy the
template and fill in your real values:

```bash
cp firmware/src/secrets.h.example firmware/src/secrets.h
# then edit firmware/src/secrets.h
```

```cpp
#define WIFI_SSID     "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#define INFLUX_TOKEN  "YOUR_INFLUXDB_WRITE_TOKEN"   // needs WRITE on sensor-readings
```

`secrets.h` is gitignored — never commit it. `config.h` includes it automatically.

### Configure `firmware/src/config.h`

Change these two lines per sensor before flashing:

```cpp
#define DEVICE_ID        "sensor-1"     // unique per sensor
#define DEVICE_LOCATION  "living-room"  // human-readable location
```

Full settings reference:

| Setting | Default | Description |
|---------|---------|-------------|
| `WIFI_SSID` | — | Your 2.4 GHz WiFi network name (**in `secrets.h`**) |
| `WIFI_PASSWORD` | — | WiFi password (**in `secrets.h`**) |
| `INFLUX_TOKEN` | — | InfluxDB write token (**in `secrets.h`**) |
| `WIFI_CONNECT_TIMEOUT` | `90` | Seconds to wait for connection |
| `DB_SERVER_URL` | — | `http://<pi-ip>:8086/api/v2/write` |
| `INFLUX_ORG` | `soil-monitoring` | InfluxDB organisation |
| `INFLUX_BUCKET` | `sensor-readings` | InfluxDB bucket |
| `DEVICE_ID` | `sensor-1` | **Change per sensor** |
| `DEVICE_LOCATION` | `test-bench` | **Change per sensor** |
| `SENSOR_AIR_VALUE` | `780` | Raw ADC in open air (calibrate!) |
| `SENSOR_WATER_VALUE` | `360` | Raw ADC submerged in water (calibrate!) |
| `READ_INTERVAL_MS` | `300000` | Posting interval (5 min) |

### Build & Flash

```bash
cd firmware
pio run --target upload --upload-port /dev/cu.usbserial-XXXX
pio device monitor --port /dev/cu.usbserial-XXXX --baud 115200
```

> ⚠️ Close the serial monitor before uploading — they share the same port.

### Expected Boot Output

```
═══════════════════════════════════════
  🌱  Soil Moisture Monitoring System
     InfluxDB + WiFi Stability v2.1.0
  Device: sensor-1  (bed-room)
  MAC:    68:C6:3A:F6:B3:AE
═══════════════════════════════════════
✅ Clean boot (no crashes detected)
[WiFi] Scanning for networks...
  Found: YourNetwork (-53 dBm)
[WiFi] Attempt 1/3 connecting to YourNetwork
[WiFi] ✓ Connected! IP: 192.168.x.x, RSSI: -45 dBm (excellent)
[NTP] Time synced
[DB] Using InfluxDB: http://192.168.99.134:8086
[DB] ✓ Posted to InfluxDB (HTTP 204): sensor-1 @ 62.4%
[Heartbeat] ✓ Posted (uptime: 8s, heap: 38KB, queue: 0/20)
Setup complete. Uptime: 8 s
```

### Adding a New Sensor

**Quick Method (Recommended):**

1. Edit `sensors-config.json` to add the new sensor:
   ```json
   {
     "id": "sensor-8",
     "plant": "Snake Plant",
     "location": "office",
     "ip": "192.168.99.XXX",
     "mac": "XX:XX:XX:XX:XX:XX",
     "color": "#00FF00",
     "thresholds": {"low": 33, "medium": 67},
     "colorSteps": [...]
   }
   ```
2. Generate and upload the dashboard:
   ```bash
   ./scripts/generate-dashboard.py
   ./scripts/upload-dashboard-to-pi.sh
   ```
3. Edit `firmware/src/config.h` with matching `DEVICE_ID` and `DEVICE_LOCATION`
4. Upload firmware to the new ESP8266

See **[QUICK_REFERENCE.md](docs/reference/QUICK_REFERENCE.md)** for detailed sensor management guide.

**Manual Method:**

1. Edit `config.h`: set a unique `DEVICE_ID` and `DEVICE_LOCATION`
2. Upload firmware to the new board via USB or OTA
3. The sensor appears automatically in the Grafana **Sensor** dropdown

### OTA (Over-The-Air) Firmware Updates

After the first USB flash, you can update sensors remotely:

```bash
# From firmware/ directory
pio run --target upload --upload-port <sensor-ip>
# Password: soilmon2026
```

Find sensor IPs in Grafana or via router DHCP leases.

---

## Sensor Calibration

The ESP8266 ADC is 10-bit (0–1023). Capacitive sensors read **high when dry** and **low when wet**.

1. **Air value**: Hold sensor in open air → read `raw=XXX` from serial → set `SENSOR_AIR_VALUE`
2. **Water value**: Submerge probe tip in water → read `raw=XXX` → set `SENSOR_WATER_VALUE`
3. Reflash with updated values

---

## Grafana Dashboards

### Dashboard Suite (6 dashboards)

| Dashboard | Tags | Description |
|-----------|------|-------------|
| **Soil Moisture Main** | overview, sensors | Main overview with all sensors, moisture gauges, trend plots |
| **Sensor Details** | sensors, diagnostics | Individual sensor deep-dive with uptime, heap, WiFi |
| **System Health** | diagnostics, system | ESP8266 diagnostic events, WiFi stability, critical events |
| **Alerts Overview** | alerts, monitoring | Critical alerts, watering needed, sensor offline detection |
| **Mobile Summary** | mobile, overview | Mobile-optimized quick view |
| **Raspberry Pi Health** | system, server | Pi CPU, RAM, disk, temperature monitoring |

### Features
- **Centralized configuration** — `sensors-config.json` manages all sensor info, colors, and labels
- **Auto-generated dashboards** — Run `./scripts/generate-dashboard.py` to update from config
- **High-contrast colors** — Each sensor has a unique color for easy identification
- **Moisture gradients** — Dark to bright within each color family (0% dry → 100% wet)
- **Plant name labels** — "Rubber Tree", "Monstera" (no "sensor-1" IDs in display)
- **Dropdown filtering** — Select individual sensors or view all at once
- **Location filtering** — 'backyard' location filtered out from all dashboards
- **Time-adaptive** — Panel titles adjust to selected time window (no hardcoded "24h")
- **Anonymous access** — View dashboards without login (optional, Viewer role)
- **Auto-refresh** — 5-minute refresh, 10-second dashboard provisioning reload

### Import Dashboards

**Automated (via provisioning):**
```bash
# Copy to Pi's Grafana provisioning directory
scp grafana-dashboards/*.json pi@<pi-ip>:/mnt/sensor-data/grafana/dashboards/
# Auto-imported within 10 seconds
```

**Manual (via API):**
```bash
curl -X POST -u admin:admin \
  -H 'Content-Type: application/json' \
  -d @grafana-dashboards/soil-moisture-main.json \
  http://<pi-ip>:3000/api/dashboards/db
```

### Remote Access

**Public Access (Cloudflare Tunnel)**
```bash
cd rpi-setup
./install-cloudflare-tunnel.sh
./configure-grafana-anonymous.sh
```
Dashboards publicly accessible at `https://grafana.owenmedeiros.com` (anonymous read-only, no login required).

**Local Anonymous Access**
```bash
cd rpi-setup
./configure-grafana-anonymous.sh
```
Dashboards viewable at `http://<pi-ip>:3000` without login (Viewer role, read-only).

**Public Snapshot** (static snapshot)
1. Open dashboard → Share icon → Snapshot tab
2. Set expiry → Publish to snapshot.raintank.io
3. Copy public URL (no login required, static snapshot)

> For **Grafana Cloud** live public dashboards, see [docs/README.md](docs/README.md#grafana-cloud-public-access).

---

## InfluxDB Data Schema

### Measurements

**1. `sensor_reading`** — Soil moisture and telemetry (every 5 minutes)

| Tag | Example | Description |
|-----|---------|-------------|
| `device_id` | `sensor-1` | Sensor identifier |
| `location` | `bed-room` | Physical location |

| Field | Type | Description |
|-------|------|-------------|
| `moisture` | float | Soil moisture % (0–100) |
| `raw_adc` | int | Raw ADC value (0–1023) |
| `rssi` | int | WiFi signal dBm |
| `uptime` | int | Seconds since boot |
| `free_heap` | int | Available RAM bytes |
| `crashes` | int | Crash counter |

**2. `sensor_heartbeat`** — Health telemetry (every 60 seconds)

| Tag | Example | Description |
|-----|---------|-------------|
| `device_id` | `sensor-1` | Sensor identifier |
| `location` | `bed-room` | Physical location |

| Field | Type | Description |
|-------|------|-------------|
| `uptime` | int | Seconds since boot |
| `free_heap` | int | Available RAM bytes |
| `rssi` | int | WiFi signal dBm |
| `queue_size` | int | Offline queue depth (0-20) |

**3. `sensor_diagnostics`** — Event tracking (on-demand)

| Tag | Example | Description |
|-----|---------|-------------|
| `device_id` | `sensor-1` | Sensor identifier |
| `location` | `bed-room` | Physical location |
| `event_type` | `wifi_disconnect` | Event category |

| Field | Type | Description |
|-------|------|-------------|
| `event_reason` | string | Human-readable reason |
| `event_count` | int | Cumulative event count |
| `free_heap` | int | RAM at event time |
| `rssi` | int | WiFi signal at event time |
| `queue_size` | int | Queue depth at event time |

**4. `rpi_system_metrics`** — Raspberry Pi health (every 60 seconds)

| Field | Type | Description |
|-------|------|-------------|
| `cpu_percent` | float | CPU usage % |
| `cpu_temp` | float | CPU temperature °C |
| `ram_percent` | float | RAM usage % |
| `ram_used_mb` | int | Used RAM MB |
| `ram_free_mb` | int | Free RAM MB |
| `disk_percent` | float | Disk usage % |
| `disk_used_gb` | float | Used disk GB |
| `disk_free_gb` | float | Free disk GB |
| `uptime_seconds` | int | System uptime |
| `load_1min` | float | 1-min load average |
| `load_5min` | float | 5-min load average |
| `load_15min` | float | 15-min load average |

**Example Flux query:**

```flux
from(bucket: "sensor-readings")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.device_id == "sensor-1")
```

---

## 🔐 Secrets Management

No secrets are committed to this repository. They live in gitignored/local files only:

| Secret | Location | Notes |
|--------|----------|-------|
| WiFi SSID/password | `firmware/src/secrets.h` (gitignored) | Copy from `secrets.h.example` |
| InfluxDB write token (firmware) | `firmware/src/secrets.h` (gitignored) | Compiled into firmware |
| InfluxDB token + Grafana creds (Pi) | `/mnt/sensor-data/config/panel-health.env` (chmod 600) | Loaded by systemd `EnvironmentFile=` |
| Slack webhook URL | `/mnt/sensor-data/config/slack_webhook_url` (chmod 600) | Read at runtime by `send-slack-alert.sh` |

`.gitignore` blocks `*.env`, `*.token`, `*secret*`, `*webhook*`, `*.backup`, and
`firmware/src/secrets.h`. To rotate the Slack webhook, revoke it in Slack and
overwrite the file — no redeploy needed. To rotate the InfluxDB token, generate a
new one in InfluxDB, update `secrets.h` + `panel-health.env` + the Grafana
datasource, reflash sensors, then revoke the old token.

---

## Pi Services

| Service | Description |
|---------|-------------|
| `influxdb` | Time-series database (auto-restart on failure) |
| `grafana-server` | Dashboard server (auto-restart on failure) |
| `cloudflared` | Cloudflare Tunnel for public HTTPS access |
| `sensor-health-monitor` | Monitors InfluxDB/Grafana, alerts on failure |
| `sensor-backup.timer` | Daily backup at 3:00 AM |
| `system-metrics-collector` | Pi CPU/RAM/disk monitoring (60s interval) |

```bash
# Check service status
sudo systemctl status influxdb grafana-server cloudflared system-metrics-collector

# View logs
journalctl -u influxdb -f
journalctl -u cloudflared -f
journalctl -u system-metrics-collector -f

# Restart services
sudo systemctl restart influxdb grafana-server cloudflared
```

---

## Development & Releases

### Version Bump Automation

Use the automated version bump script to update all version references consistently:

```bash
# Bump minor version for system/infrastructure updates
./scripts/bump-version.sh minor system  # 2.5.0 → 2.6.0

# Bump minor version for firmware updates
./scripts/bump-version.sh minor firmware  # 2.2.0 → 2.3.0

# Bump patch version for docs/bug fixes
./scripts/bump-version.sh patch docs  # 2.5.0 → 2.5.1
```

**What it updates automatically:**
- `CHANGELOG.md` — Adds new version entry
- `README.md` — Updates version headers
- `firmware/src/config.h` — Updates firmware version (if firmware bump)
- `grafana-dashboards/README.md` — Updates dashboard suite version

**After running the script:**
1. Edit `CHANGELOG.md` and replace "TODO: Add changes here" with actual changes
2. Review changes: `git diff`
3. Commit and create PR: See [docs/BRANCH_PROTECTION.md](docs/BRANCH_PROTECTION.md)

### Branch Protection

The `main` branch should be protected to prevent direct pushes and enforce PR workflow.

**Setup instructions:** See [docs/BRANCH_PROTECTION.md](docs/BRANCH_PROTECTION.md)

**Quick setup via GitHub CLI:**

```bash
gh api repos/omedeiro/soil-sensor/branches/main/protection \
  --method PUT \
  --field required_pull_request_reviews[required_approving_review_count]=0 \
  --field enforce_admins=true \
  --field allow_force_pushes=false
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** | Quick reference for common sensor management tasks |
| **[grafana-dashboards/README.md](grafana-dashboards/README.md)** | Dashboard setup and customization |
| **[rpi-setup/README.md](rpi-setup/README.md)** | Raspberry Pi installation guide |
| **[firmware/README.md](firmware/README.md)** | ESP8266 firmware guide |
| **[docs/README.md](docs/README.md)** | Technical documentation |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history and release notes |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Upload times out | Serial monitor holding port | Close monitor, retry |
| WiFi `Status: 7` | Router auth reject / temp ban | Power cycle router |
| WiFi `Status: 0` | Board never saw router | Check 2.4 GHz band, move closer |
| `⚠️ CRASH DETECTED!` | Power supply issue | Try different USB cable/adapter |
| `[DB] ✗ POST failed (HTTP 401)` | Invalid InfluxDB token | Check `INFLUX_TOKEN` in config.h |
| `[DB] ✗ POST failed (connection refused)` | InfluxDB not running | `sudo systemctl status influxdb` |
| InfluxDB won't start | USB drive not mounted | `mount \| grep sensor-data` |
| Dashboard shows no data | Wrong time range | Set range to `Last 1 hour` |
| Grafana shows "NO DATA" | Normal for empty panels | E.g., no critical events = healthy |
| Chrome won't load InfluxDB | HSTS cache issue | Use Safari or clear HSTS cache |
| Public URL unreachable | Cloudflare Tunnel down | `sudo systemctl status cloudflared` |
| DNS not resolving | Propagation delay | Wait 1-5 minutes after tunnel setup |

---

## License

See [LICENSE](LICENSE) for details.