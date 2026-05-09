# 🌱 Soil Moisture Monitoring System — v2.0

A production-grade, multi-sensor soil moisture monitoring system built with **ESP8266** microcontrollers, **InfluxDB**, and **Grafana**, hosted on a **Raspberry Pi 5**.

Each sensor reads soil moisture every 5 minutes and posts data to a central time-series database. A live Grafana dashboard visualizes all sensors simultaneously.

---

## Architecture

```
[Capacitive Sensor] ──► [ESP8266 NodeMCU]
                               │  WiFi (WPA2)
                               ▼
                    [Raspberry Pi 5 Server]
                    ├── InfluxDB 2.x  (:8086)
                    └── Grafana       (:3000)
```

---

## Features

- **Multi-sensor support** — unlimited ESP8266 sensors, each identified by `DEVICE_ID`
- **InfluxDB 2.x backend** — time-series storage on USB drive, 365-day retention
- **Grafana dashboard** — live charts, gauges, per-sensor filtering, auto-refresh every 5 min
- **WiFi stability** — scan-before-connect, 3-attempt retry, auto-reconnect, max TX power
- **Offline queue** — up to 20 readings buffered in RAM when WiFi/server is unavailable
- **NTP timestamps** — every reading is UTC-timestamped
- **Boot diagnostics** — device ID, MAC address, crash reason printed on every boot
- **Health telemetry** — free heap, uptime, WiFi RSSI, crash count sent to InfluxDB
- **Automated backups** — daily Pi backup via systemd timer

---

## Project Structure

```
soil-sensor/
├── firmware/                     # ESP8266 PlatformIO firmware
│   ├── platformio.ini
│   └── src/
│       ├── config.h              # ← Edit this per sensor
│       ├── main.cpp
│       ├── sensor.h/.cpp         # ADC driver & moisture %
│       ├── wifi_manager.h/.cpp   # WiFi connect, scan, retry
│       ├── wifi_stability.h/.cpp # Reconnect watchdog
│       ├── database_client.h/.cpp# InfluxDB line protocol HTTP POST
│       ├── data_logger.h/.cpp    # In-RAM ring buffer
│       ├── reading_queue.h/.cpp  # Offline queue
│       └── web_server.h/.cpp     # Local HTTP server
├── grafana-dashboards/
│   └── soil-sensor.json          # Dashboard JSON (importable)
├── rpi-setup/
│   ├── install.sh                # Full Pi setup script
│   ├── scripts/
│   │   ├── sensor-backup.sh
│   │   └── sensor-health-monitor.sh
│   └── systemd/                  # Service/timer unit files
├── hardware/
│   ├── BOM.md
│   ├── SCHEMATIC.md
│   └── schematic.json
└── docs/
    └── README.md                 # WiFi stability, Cloudflare tunnel, InfluxDB notes
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

1. Open InfluxDB at `http://<pi-ip>:8086`
   - Create org: `soil-monitoring`
   - Create bucket: `sensor-readings` (365-day retention)
   - Generate an API token for the sensors

2. Open Grafana at `http://<pi-ip>:3000`
   - Login: `admin` / `admin` (change on first login)
   - Add InfluxDB datasource (Flux mode, URL: `http://localhost:8086`)
   - Import dashboard from `grafana-dashboards/soil-sensor.json`

---

## Firmware Setup

### Prerequisites

- [PlatformIO](https://platformio.org/) (VS Code extension or CLI)
- USB-to-serial driver for your board (CP2102 or CH340)

### Configure `firmware/src/config.h`

Change these two lines per sensor before flashing:

```cpp
#define DEVICE_ID        "sensor-1"     // unique per sensor
#define DEVICE_LOCATION  "living-room"  // human-readable location
```

Full settings reference:

| Setting | Default | Description |
|---------|---------|-------------|
| `WIFI_SSID` | `""` | Your 2.4 GHz WiFi network name |
| `WIFI_PASSWORD` | `""` | WiFi password |
| `WIFI_CONNECT_TIMEOUT` | `90` | Seconds to wait for connection |
| `DB_SERVER_URL` | — | `http://<pi-ip>:8086/api/v2/write` |
| `INFLUX_TOKEN` | — | InfluxDB API token |
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
     InfluxDB + WiFi Stability v2.0
  Device: sensor-1  (living-room)
  MAC:    68:C6:3A:F6:B3:AE
═══════════════════════════════════════
[WiFi] Scanning for networks...
  Found: YourNetwork (-53 dBm)
[WiFi] Attempt 1/3 connecting to YourNetwork
[WiFi] ✓ Connected! IP: 192.168.x.x
[NTP] Time synced
[DB] ✓ Posted to InfluxDB: sensor-1 @ 62.4%
Setup complete. Uptime: 8 s
```

### Adding a New Sensor

1. Edit `config.h`: set a unique `DEVICE_ID` and `DEVICE_LOCATION`
2. Upload firmware to the new board
3. The sensor appears automatically in the Grafana **Sensor** dropdown

---

## Sensor Calibration

The ESP8266 ADC is 10-bit (0–1023). Capacitive sensors read **high when dry** and **low when wet**.

1. **Air value**: Hold sensor in open air → read `raw=XXX` from serial → set `SENSOR_AIR_VALUE`
2. **Water value**: Submerge probe tip in water → read `raw=XXX` → set `SENSOR_WATER_VALUE`
3. Reflash with updated values

---

## Grafana Dashboard

### Import

```bash
# Push via API (replace IP and password)
curl -X POST -u admin:yourpassword \
  -H 'Content-Type: application/json' \
  -d @grafana-dashboards/soil-sensor.json \
  http://<pi-ip>:3000/api/dashboards/db
```

### Panels

| Panel | Type | Description |
|-------|------|-------------|
| Soil Moisture % | Gauge | Current moisture per sensor |
| WiFi Signal (RSSI) | Gauge | Current signal strength |
| Uptime | Stat | Seconds since last boot |
| Free Heap | Stat | ESP8266 available RAM |
| Crashes | Stat | Crash count since last flash |
| Soil Moisture Over Time | Time series | 24h history, all sensors |
| WiFi Signal Over Time | Time series | RSSI history |
| Free Heap Over Time | Time series | Memory health history |

### Remote Access (Public Snapshot)

To share a **read-only, login-free** view from anywhere:

1. Open the dashboard in Grafana
2. Click the **Share** icon → **Snapshot** tab
3. Set expiry (or "Never") → **Publish to snapshot.raintank.io**
4. Copy the public URL — anyone with the link can view it, no login required

> For a **live** public dashboard, see the [Cloudflare Tunnel setup](docs/README.md#cloudflare-tunnel-public-access) in `docs/README.md`.

---

## InfluxDB Data Schema

**Measurement**: `sensor_reading`

| Tag | Example | Description |
|-----|---------|-------------|
| `device_id` | `sensor-1` | Sensor identifier |
| `location` | `living-room` | Physical location |

| Field | Type | Description |
|-------|------|-------------|
| `moisture` | float | Soil moisture % (0–100) |
| `raw_adc` | int | Raw ADC value (0–1023) |
| `rssi` | int | WiFi signal dBm |
| `uptime` | int | Seconds since boot |
| `free_heap` | int | Available RAM bytes |
| `crashes` | int | Crash counter |

**Example Flux query:**

```flux
from(bucket: "sensor-readings")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.device_id == "sensor-1")
```

---

## Pi Services

| Service | Description |
|---------|-------------|
| `influxdb` | Time-series database |
| `grafana-server` | Dashboard server |
| `sensor-health-monitor` | Alerts if services go down |
| `sensor-backup.timer` | Daily backup at 3:00 AM |

```bash
sudo systemctl status influxdb grafana-server
journalctl -u influxdb -f
sudo systemctl restart influxdb
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Upload times out | Serial monitor holding port | Close monitor, retry |
| WiFi `Status: 7` | Router auth reject / temp ban | Power cycle router |
| WiFi `Status: 0` | Board never saw router | Check 2.4 GHz band, move closer |
| InfluxDB won't start | USB drive not mounted | `mount \| grep sensor-data` |
| Dashboard shows no data | Wrong time range | Set range to `Last 1 hour` |
| "All" sensor no data | Grafana variable misconfigured | Use `=~ /${device:regex}/`, not `contains()` |
| Chrome won't load InfluxDB | HSTS cache issue | Use Safari or clear HSTS cache |

---

## License

See [LICENSE](LICENSE) for details.