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

## Grafana Cloud (Public Access)

Since `medeirosowen.grafana.net` already exists, the simplest approach is to push metrics from the Pi directly to Grafana Cloud using **Grafana Alloy** (the modern agent). The local Grafana instance stays for LAN use; the Cloud instance is publicly accessible from anywhere.

### Architecture with Cloud

```
[ESP8266 sensors] ──► [InfluxDB on Pi] ──► [Grafana Alloy on Pi] ──► [Grafana Cloud]
                              │
                         [Local Grafana :3000]  (LAN only)
```

### Step 1 — Get Grafana Cloud credentials

1. Log in to [grafana.com](https://grafana.com) → **My Account**
2. Go to your stack **medeirosowen** → **Details**
3. Under **Prometheus** (or **Metrics**), note the **Remote Write URL** and generate an **API key** with `MetricsPublisher` role

### Step 2 — Install Grafana Alloy on Pi

SSH into the Pi, then:

```bash
# Add Grafana repo
wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install -y alloy
```

### Step 3 — Configure Alloy to scrape InfluxDB and forward to Cloud

Create `/etc/alloy/config.alloy`:

```hcl
// Read from local InfluxDB via Prometheus-compatible scrape
prometheus.scrape "influxdb" {
  targets = [{ __address__ = "localhost:8086" }]
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
  scrape_interval = "60s"
}

// Forward to Grafana Cloud
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-XX-prod-XX-X.grafana.net/api/prom/push"  // your stack URL

    basic_auth {
      username = "<your-stack-user-id>"
      password = "<your-api-key>"
    }
  }
}
```

> Get the exact URL and user ID from: grafana.com → your stack → **Details** → Prometheus section.

```bash
sudo systemctl enable --now alloy
sudo systemctl status alloy
```

### Step 4 — Import dashboard to Grafana Cloud

```bash
# Upload soil-sensor dashboard to Cloud Grafana (replace token and stack URL)
curl -X POST \
  -H "Authorization: Bearer <service-account-token>" \
  -H "Content-Type: application/json" \
  -d @grafana-dashboards/soil-sensor.json \
  https://medeirosowen.grafana.net/api/dashboards/db
```

Or manually: log in to `medeirosowen.grafana.net` → **Dashboards** → **Import** → paste `grafana-dashboards/soil-sensor.json`.

### Step 5 — Share publicly (view-only)

In Grafana Cloud, dashboards can be shared via a public link:

1. Open the dashboard
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
