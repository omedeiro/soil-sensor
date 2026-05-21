# Technical Documentation

Deep-dive references for the soil moisture monitoring system. For setup instructions see the [root README](../README.md).

---

## WiFi Stability

The firmware uses a multi-layer approach to keep sensors online:

### Connect sequence (`wifi_manager.cpp`)
1. Scan all networks and print RSSI — confirms the target SSID is visible before attempting
2. `WiFi.persistent(false)` → `WiFi.mode(WIFI_STA)` → `WiFi.disconnect(true)` — clean slate each time
3. **3-attempt retry loop** — each attempt gets `WIFI_CONNECT_TIMEOUT / 3` seconds (default 30s each)
4. On success: disable sleep (`WIFI_NONE_SLEEP`), max TX power (20.5 dBm), enable auto-reconnect

### Reconnect watchdog (`wifi_stability.cpp`)
Exponential backoff on disconnect — restarts ESP8266 after 10 failed attempts:

| Attempts | Backoff |
|----------|---------|
| 1–2 | 5s |
| 3–4 | 10s |
| 5–6 | 30s |
| 7+ | 60s |

Backoff resets after 5 minutes of stable connection.

### WiFi disconnect reason codes
Logged on every disconnect for diagnostics:

| Code | Reason |
|------|--------|
| 1 | AUTH_EXPIRE — authentication expired |
| 2 | AUTH_LEAVE — de-authenticated |
| 200 | BEACON_TIMEOUT — lost AP beacon |
| 201 | NO_AP_FOUND — SSID not visible |
| 205 | AUTH_FAIL — wrong password / rate-banned |

> **Router rate-ban**: If a sensor floods the router with rapid auth attempts (e.g. caused by `resetSettings()` on every boot), the router may temporarily reject the MAC. Fix: power cycle the router. The firmware no longer calls `resetSettings()`.

### Config flags (`config.h`)
```cpp
#define WIFI_STABILITY_ENABLED    true
#define WIFI_RECONNECT_ENABLED    true
#define WIFI_POWER_MGMT_ENABLED   true
#define READING_QUEUE_ENABLED     true
#define READING_QUEUE_SIZE        20     // ~1.5h of offline storage at 5min interval
```

---

## Offline Reading Queue

When InfluxDB is unreachable, readings are buffered in a circular RAM queue (`reading_queue.cpp`):

- **Capacity**: 20 readings × ~24 bytes = 480 bytes
- **Overflow**: oldest reading is dropped
- **Drain**: automatically replayed when connectivity is restored
- **Persistence**: survives soft reset, lost on power cycle

---

## Public Dashboard Access

The system now supports **public HTTPS access** via **Cloudflare Tunnel**, eliminating the need for Grafana Cloud migration or VPN.

### Current Solution: Cloudflare Tunnel ✅ Deployed

```
[ESP8266 sensors] ──► [InfluxDB on Pi] ──► [Grafana on Pi]
                                                 │
                                                 ▼
                                        [Cloudflare Tunnel]
                                                 │
                                                 ▼
                                  https://grafana.owenmedeiros.com
```

**Features:**
- ✅ **Public HTTPS access** — anyone can view dashboards from anywhere
- ✅ **Anonymous read-only viewing** — no login required, Viewer role only
- ✅ **Automatic SSL/TLS** — managed by Cloudflare
- ✅ **No port forwarding** — no firewall changes needed
- ✅ **Local data stays local** — all sensor data remains on the Raspberry Pi

**Setup:**
```bash
cd rpi-setup
./install-cloudflare-tunnel.sh      # One-time setup
./configure-grafana-anonymous.sh    # Enable anonymous viewing
```

**Public URL:** https://grafana.owenmedeiros.com

---

## Grafana Cloud (Alternative Public Access - Deprecated)

> **Note:** With Cloudflare Tunnel deployed, Grafana Cloud is no longer needed for public access. This section is kept for reference only.

The goal was to push sensor metrics from the Pi to Grafana Cloud so dashboards could be shared publicly from anywhere — no VPN or home network required.

### Architecture (Not Currently Used)

```
[ESP8266 sensors] ──► [InfluxDB on Pi] ──► [Grafana Alloy on Pi] ──► [Grafana Cloud metrics store]
                                                                                 ↓
                                                                    [Public dashboard URL]
```

### Current Status (as of May 2026)

| Component | Status | Notes |
|---|---|---|
| InfluxDB 2.7.12 | ✅ Running | org: `soil-monitoring`, bucket: `sensor-readings` |
| Grafana Alloy v1.16.1 | ✅ Running | linux/arm64, enabled on boot |
| Alloy → Cloud forwarding | ⚠️ Partial | Pushing InfluxDB internal metrics only — not sensor data yet |
| Sensor data in Cloud | ❌ Pending | Alloy config needs updating to query `sensor-readings` bucket |
| **Cloudflare Tunnel** | ✅ **Active** | **Current public access solution** |

**Status:** Grafana Cloud setup is incomplete. Cloudflare Tunnel is the preferred solution for public access.

---

### Step 1 — Get Grafana Cloud credentials ✅ Done

Stack: **medeirosowen** at `medeirosowen.grafana.net`

Credentials used during Alloy install:
- **Metrics Remote Write URL:** `https://prometheus-prod-56-prod-us-east-2.grafana.net/api/prom/push`
- **Metrics Stack ID:** `3168076`
- **Logs URL:** `https://logs-prod-036.grafana.net/loki/api/v1/push`
- **Logs Stack ID:** `1579713`

> ⚠️ The API key (`GCLOUD_RW_API_KEY`) was exposed in chat — **regenerate it** at grafana.com → your stack → API Keys.

---

### Step 2 — Install Grafana Alloy on Pi ✅ Done

Alloy v1.16.1 (linux/arm64) installed and running. The Grafana installer script was used with `ARCH="arm64"` — **make sure to always use `arm64`**, not `amd64`, for the Pi 5.

```bash
# Verify
alloy --version
systemctl status alloy
```

---

### Step 3 — Current Alloy config ⚠️ Partial

`/etc/alloy/config.alloy` currently pushes only InfluxDB's internal Prometheus metrics (health, memory, etc.) — **not** the actual soil sensor readings.

```hcl
// Current config — pushes InfluxDB internal metrics only
prometheus.scrape "influxdb_metrics" {
  targets = [{ __address__ = "localhost:8086" }]
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
  scrape_interval = "60s"
}

loki.write "grafana_cloud" {
  endpoint {
    url = "https://logs-prod-036.grafana.net/loki/api/v1/push"
    basic_auth {
      username = "1579713"
      password = "<GCLOUD_RW_API_KEY>"
    }
  }
}

prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-56-prod-us-east-2.grafana.net/api/prom/push"
    basic_auth {
      username = "3168076"
      password = "<GCLOUD_RW_API_KEY>"
    }
  }
}
```

After editing the config, restart Alloy:
```bash
sudo systemctl restart alloy
sudo systemctl status alloy
```

---

### TODO — Push sensor readings to Grafana Cloud

To push actual `moisture`, `temperature`, and other sensor fields from InfluxDB to Grafana Cloud, Alloy needs to use `prometheus.exporter.influxdb` or a custom `loki`/`otelcol` pipeline to query the `sensor-readings` bucket and convert Flux results to Prometheus metrics.

InfluxDB details for config:
- **URL:** `http://localhost:8086`
- **Org:** `soil-monitoring`
- **Bucket:** `sensor-readings`
- **Token:** stored in `firmware/src/config.h` as `INFLUX_TOKEN`
- **Measurement:** `sensor_reading`
- **Fields:** `moisture`, `free_heap`, `crashes`, `wifi_reconnects`, `rssi`
- **Tags:** `device_id`, `location`

---

### Step 4 — Import dashboard to Grafana Cloud

Once sensor data is flowing, import the dashboard:

```bash
# Upload soil-sensor dashboard to Cloud Grafana (replace token)
curl -X POST \
  -H "Authorization: Bearer <service-account-token>" \
  -H "Content-Type: application/json" \
  -d @grafana-dashboards/soil-sensor.json \
  https://medeirosowen.grafana.net/api/dashboards/db
```

Or manually: log in to `medeirosowen.grafana.net` → **Dashboards** → **Import** → upload `grafana-dashboards/soil-sensor.json`.

### Step 5 — Share publicly (view-only)

1. Open the dashboard in Grafana Cloud
2. Click **Share** → **Public dashboard** tab
3. Enable public access → copy the link

Anyone with the link can view it — no login required.

---

## InfluxDB Notes

- **Pinned to 2.7.12** — v2.9+ has ARM64 Flux query regressions
- Data stored on USB drive at `/mnt/sensor-data/influxdb`
- Retention policy: 365 days (set at bucket creation)
- Upgrade: `sudo apt-get install influxdb2=2.7.12`

### Useful commands

```bash
# Check InfluxDB health
curl http://localhost:8086/health

# List buckets
influx bucket list --token <token>

# Query last 10 readings for sensor-1
influx query --token <token> '
from(bucket:"sensor-readings")
  |> range(start:-1h)
  |> filter(fn:(r) => r.device_id == "sensor-1")
  |> tail(n:10)
'
```
