---
name: rpi-server-ops
description: Set up and operate the Raspberry Pi 5 server backend for the soil sensor project — InfluxDB, Grafana install, tokens, buckets, write tests, end-to-end testing flow, and the legacy Flask/SQLite database server. Use when running `rpi-setup/install.sh`, configuring InfluxDB org/bucket/tokens, running `tests/test_influx_write.sh`, verifying the full data flow, or working with the deprecated `/database` Flask server on port 5001.
---

# Raspberry Pi Server Operations

Server: `omedeiro@192.168.99.134`. InfluxDB `:8086`, Grafana `:3000`, data on
`/mnt/sensor-data` (256GB USB drive).

## One-Time Installation

```bash
# On Raspberry Pi 5:
ssh omedeiro@192.168.99.134   # or: ssh pi@raspberrypi.local
cd ~/rpi-setup
sudo ./install.sh          # installs InfluxDB, Grafana, systemd services
```

**Post-installation:**
1. Configure InfluxDB: `http://<pi-ip>:8086` (create org, bucket, tokens)
2. Configure Grafana: `http://<pi-ip>:3000` (add data source, import dashboards)
3. Update ESP8266 `config.h` with InfluxDB token and URL (see `soil-sensor-firmware` skill)

## InfluxDB Configuration (one-time)
- Open `http://<pi-ip>:8086`
- Create org: `soil-monitoring`, bucket: `sensor-readings`
- Generate **write** token for ESP8266
- Generate **read** token for Grafana

## Grafana Configuration (one-time)
- Open `http://<pi-ip>:3000` (admin/admin)
- Add InfluxDB data source (Flux, localhost:8086)
- Import dashboards from `grafana-dashboards/` (see `grafana-dashboard-config` skill)

## InfluxDB Write Test

```bash
cd tests
export INFLUX_TOKEN="your_write_token"
./test_influx_write.sh     # verify InfluxDB connectivity and token
```

## InfluxDB / Grafana API Endpoints

**InfluxDB (port 8086):**
- `POST /api/v2/write?org=<org>&bucket=<bucket>&precision=s` — ESP8266 writes here (requires token)
- `POST /api/v2/query?org=<org>` — Flux queries (requires token)
- `GET /health` — health check
- `GET /ping` — connectivity test

**Grafana (port 3000):**
- `GET /` — dashboard UI (login required)
- `GET /api/health` — health check
- `GET /api/dashboards/` — list dashboards
- `POST /api/annotations` — create annotations (alerts)

## End-to-End Testing Flow (NEW SYSTEM)

1. **Install Raspberry Pi** (one-time): `sudo ./install.sh` (above)
2. **Configure InfluxDB** (one-time): org/bucket/tokens (above)
3. **Configure Grafana** (one-time): data source + dashboards (above)
4. **Flash ESP8266:**
   ```bash
   cd firmware
   # Edit src/config.h with InfluxDB token and Pi IP
   pio run --target upload
   pio device monitor
   ```
5. **Verify data flow:**
   - Watch serial for: `[DB] ✓ Posted to InfluxDB: <device> @ <moisture>%`
   - Open Grafana dashboard
   - Run: `cd tests && export INFLUX_TOKEN="your_token" && ./test_influx_write.sh`
6. **WiFi stability test:**
   - Manually disconnect WiFi (router admin or power off router)
   - Watch serial for reconnection attempts
   - Verify queued readings drain after reconnection

If the ESP8266 is offline, check for the `SoilSensor-Setup` AP and reconfigure WiFi.

## Raspberry Pi Setup File Organization (`/rpi-setup/`)
- `install.sh` — one-command installer for InfluxDB + Grafana
- `install-cloudflare-tunnel.sh` — Cloudflare Tunnel setup for public access
- `configure-grafana-anonymous.sh` — Configure Grafana for anonymous viewing
- `install-logging.sh` — enhanced startup/health logging
- `install-sensor-monitoring.sh` — sensor offline health checks
- `install-panel-health-monitor.sh` — Grafana panel health monitor
- `systemd/` — service files for health monitor, backup timer
- `scripts/` — health monitor and backup bash scripts
- `README.md` — installation guide

## Legacy Database Server (`/database` — deprecated, being phased out)

```bash
cd database
./start.sh                 # starts Flask server on port 5001
python3 server.py          # direct invocation
```

**Legacy testing flow:**
1. Start database: `cd database && ./start.sh`
2. Connect ESP8266 via USB
3. Monitor serial: `cd firmware && pio device monitor`
4. Wait for `[DB] ✓ Posted to database (HTTP 201)`
5. Open `database/dashboard.html` in browser

**Legacy files:**
- `server.py` — Flask app (being phased out)
- `dashboard.html` — web UI (replaced by Grafana)
- `sensor_data.db` — SQLite database (migrating to InfluxDB)
- `start.sh` — startup wrapper
- Legacy endpoints on port 5001 — see `/database/README.md`

**Note:** InfluxDB is on 8086, not 5001. 5001 was the legacy SQLite server.
InfluxDB returns HTTP 204 (not 201) on a successful write.
