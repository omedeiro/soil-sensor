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
4. **(fixed in v2.4.0)** Static-IP false positive — with `USE_STATIC_IP true`,
   `WiFi.localIP().isSet()` was true without a real association, so a sensor
   that booted before the router was ready "thought it was connected forever"
   and never reconnected. v2.4.0 uses DHCP only and mode-aware connectivity
   checks. If a sensor on pre-2.4.0 firmware goes silent after a power event,
   suspect this first; the fix is reflashing to ≥2.4.0.

## Identifying an offline board

- All sensors are DHCP; if the documented IP doesn't respond, ping-sweep the
  subnet and match the MAC (see AGENTS.md for MAC list):
  `for i in $(seq 1 254); do ping -c1 -t1 192.168.99.$i >/dev/null 2>&1 & done; wait; arp -a | grep -i <mac>`
- No ARP entry = board is unpowered or crash-looping before WiFi join → needs
  a physical power cycle (any USB power adapter; no computer needed).
- ARP entry but no InfluxDB posts = network/token/InfluxDB problem, not power.
- To identify a board on USB, read its MAC:
  `~/.platformio/penv/bin/python ~/.platformio/packages/tool-esptoolpy/esptool.py --port /dev/cu.usbserial-0001 read_mac`

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
1. **Immediate:** Power cycle the ESP8266 (unplug power, wait 5 seconds, replug).
   There is no over-the-air *restart* — but if the board is reachable on the
   network, it doesn't need one; if it's unreachable, only a physical power
   cycle works.
2. **If issue persists:**
   - Check power supply (use quality USB adapter ≥1A, short USB cable)
   - Reflash firmware — OTA if reachable:
     `cd ~/soil-sensor/firmware && pio run -e esp8266-ota --target upload --upload-port <sensor-ip>`
     (password `soilmon2026`; set DEVICE_ID/DEVICE_LOCATION/DEVICE_TYPE in config.h first),
     or USB if not: `pio run --target upload`
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
- v2.4.0+: DHCP-only, persisted credentials, no captive-portal dead-end —
  sensors recover from power cycles and outlet moves unattended

## Prevention
- **Install sensor health monitoring** (automated alerts)
- Use quality power supply and short USB cables
- Place ESP8266 within good WiFi range (RSSI > -70 dBm)
- Monitor Grafana alerts dashboard regularly

For firmware flashing/config details and serial-monitor decoding, see the
`soil-sensor-firmware` skill.
