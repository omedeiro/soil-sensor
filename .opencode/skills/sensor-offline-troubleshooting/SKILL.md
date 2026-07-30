---
name: sensor-offline-troubleshooting
description: Diagnose and recover an ESP8266 soil sensor that has stopped posting to InfluxDB and needs a power cycle. Use when a sensor is offline, hasn't reported in, shows stale data, keeps crashing/rebooting, or when checking sensor connectivity via InfluxDB queries or installing automated sensor-health monitoring on the Raspberry Pi. Covers power-supply, firmware-crash, and WiFi-disconnect-loop root causes.
---

# Sensor Offline Troubleshooting

**Problem:** ESP8266 sensor stops posting to InfluxDB and requires a power cycle to recover.

## Root Causes
1. **Power supply issues** — insufficient voltage/current during WiFi transmission (most common)
2. **Firmware crash** — unhandled exception or watchdog timeout
3. **WiFi disconnect loop** — lost connection, failed to recover (auto-restart after 10 failed attempts)

## Detection Methods

**1. Manual check (InfluxDB query):**
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

**2. Automated monitoring (recommended):**
```bash
ssh omedeiro@192.168.99.134
cd ~/rpi-setup
./install-sensor-monitoring.sh
# Installs:
# - Health check script (runs every 10 minutes)
# - Alerts when sensor offline for 15+ minutes
# - Logs to system journal

systemctl status sensor-health-check.timer
journalctl -u sensor-health-check -f
```

**3. Grafana Alerts Dashboard:**
- Open `http://soil.owenmedeiros.com` or `http://192.168.99.134:3000`
- Navigate to "⚠️ Alerts & Notifications" dashboard
- Check "Sensor Status" panel for offline sensors
- Configure alert notifications in Grafana settings

## Recovery Steps
1. **Immediate:** Power cycle the ESP8266 (unplug USB, wait 5 seconds, replug)
2. **If issue persists:**
   - Check power supply (use quality USB adapter ≥1A, short USB cable)
   - Reflash firmware: `cd ~/soil-sensor/firmware && pio run --target upload`
   - Check WiFi signal strength (RSSI should be > -70 dBm)
3. **Long-term fix:**
   - Use dedicated 5V 2A power adapter (not a computer USB port)
   - Reduce WiFi distance to router or add a WiFi extender
   - Enable automatic health monitoring (see above)

## Firmware Recovery Features
- Hardware watchdog (auto-restart if hung for 8 seconds)
- Crash detection (logs to InfluxDB diagnostics)
- WiFi auto-reconnect (10 attempts with exponential backoff, then full restart)
- Reading queue (stores up to 20 failed readings during outages)

## Prevention
- **Install sensor health monitoring** (automated alerts)
- Use quality power supply and short USB cables
- Place ESP8266 within good WiFi range (RSSI > -70 dBm)
- Monitor Grafana alerts dashboard regularly

For firmware flashing/config details and serial-monitor decoding, see the
`soil-sensor-firmware` skill.
