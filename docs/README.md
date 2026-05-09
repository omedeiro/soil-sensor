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

## Cloudflare Tunnel (Public Access)

A Cloudflare Tunnel exposes Grafana to the internet without port forwarding.

### Install on Pi

```bash
# Install cloudflared
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared.deb

# Authenticate (opens browser — run on a machine with a browser, or use --url trick)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create soil-sensor

# Route traffic
cloudflared tunnel route dns soil-sensor grafana.yourdomain.com

# Create config
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: <TUNNEL_ID>
credentials-file: /home/omedeiros/.cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: grafana.yourdomain.com
    service: http://localhost:3000
  - service: http_status:404
EOF

# Install as systemd service
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### Grafana anonymous access (view-only, no login)

Edit `/etc/grafana/grafana.ini` on the Pi:

```ini
[auth.anonymous]
enabled = true
org_name = Main Org.
org_role = Viewer

[auth]
disable_login_form = false   # keep true login available for admin
```

Restart Grafana:
```bash
sudo systemctl restart grafana-server
```

Anyone hitting the tunnel URL will see the dashboard without a login prompt. Admin login still works via `http://localhost:3000`.

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
