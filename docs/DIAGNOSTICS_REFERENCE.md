# Diagnostics System Reference — v2.1

Complete reference for the ESP8266 and Raspberry Pi diagnostics, monitoring, and auto-recovery system.

---

## Table of Contents

1. [Overview](#overview)
2. [ESP8266 Diagnostic Events](#esp8266-diagnostic-events)
3. [Heartbeat System](#heartbeat-system)
4. [Hardware Watchdog](#hardware-watchdog)
5. [Raspberry Pi System Metrics](#raspberry-pi-system-metrics)
6. [Health Monitoring & Auto-Recovery](#health-monitoring--auto-recovery)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [InfluxDB Schema](#influxdb-schema)

---

## Overview

The v2.1 diagnostics system provides comprehensive monitoring and auto-recovery across three layers:

### Layer 1: ESP8266 Firmware
- **Hardware watchdog** — auto-reboot if firmware hangs (8s timeout)
- **Diagnostic events** — crash detection, WiFi issues, queue overflow, low memory
- **Heartbeat system** — 60s "I'm alive" messages with device health metrics
- **Non-blocking queue drain** — prevents watchdog triggers during database outages

### Layer 2: Raspberry Pi Server
- **System metrics collector** — CPU, RAM, disk, temperature (Python, 60s interval)
- **Health monitor** — checks services, disk, RAM, temp; auto-restarts services; auto-reboots after 3 failures
- **Automated backups** — daily InfluxDB + Grafana backups with 30-day retention

### Layer 3: Grafana Dashboards
- **5 provisioned dashboards** — soil moisture, system health, alerts, sensor details, mobile view
- **Real-time alerts** — Slack notifications for critical issues
- **1-year data retention** — complete historical record

---

## ESP8266 Diagnostic Events

All diagnostic events are sent to InfluxDB measurement: `sensor_diagnostics`

### Event Types

#### 1. `boot`
**Severity:** `info`  
**Message:** `"Clean boot"` or `"CRASH DETECTED! Last uptime: {uptime}s"`  
**When:** Sent on every boot after WiFi connects  
**Detail:** Includes previous uptime if crash detected

**Example InfluxDB line:**
```
sensor_diagnostics,device_id=sensor-1,location=backyard,event_type=boot,severity=info message="Clean boot",detail="Firmware v2.1"
```

**Troubleshooting:**
- **"CRASH DETECTED"** — indicates power issue, hardware failure, or watchdog timeout
  - Check power supply (use 5V 2A minimum, quality cable)
  - Check serial logs for stack trace before crash
  - Verify heap memory not exhausted (`free_heap` in heartbeat)

---

#### 2. `wifi_disconnect`
**Severity:** `warning`  
**Message:** `"WiFi disconnected"`  
**When:** WiFi connection lost  
**Detail:** Disconnect reason code (e.g., `reason: 200 - beacon timeout`)

**Example:**
```
sensor_diagnostics,device_id=sensor-1,event_type=wifi_disconnect,severity=warning message="WiFi disconnected",detail="reason: 200 - beacon timeout"
```

**Common Reason Codes:**
- `2` — Auth expired (wrong password)
- `8` — Disconnected by AP (router kicked device)
- `15` — 4-way handshake timeout (weak signal during auth)
- `200` — Beacon timeout (router unreachable, weak signal)
- `201` — No AP found (SSID changed or out of range)

**Troubleshooting:**
- **Beacon timeout (200)** — weak WiFi signal, move sensor closer to router or add WiFi extender
- **Auth expired (2)** — wrong WiFi password, reconfigure via captive portal
- **No AP found (201)** — SSID changed, router offline, or sensor moved out of range

---

#### 3. `wifi_reconnect_attempt`
**Severity:** `info`  
**Message:** `"WiFi reconnection attempt {attempt}/10"`  
**When:** Automatic WiFi reconnection in progress  
**Detail:** Includes backoff time (5s → 10s → 30s → 60s)

**Troubleshooting:**
- Normal after brief WiFi outages
- If >10 attempts, ESP8266 will reboot (full restart)
- Check router stability if frequent reconnections

---

#### 4. `wifi_reconnect_failed`
**Severity:** `error`  
**Message:** `"10 reconnection attempts failed - restarting ESP8266"`  
**When:** All 10 reconnection attempts exhausted  
**Detail:** N/A

**Troubleshooting:**
- Indicates persistent WiFi issue
- Check router status, SSID, password
- Verify sensor within WiFi range (RSSI > -80 dBm)

---

#### 5. `queue_overflow`
**Severity:** `critical`  
**Message:** `"Reading queue full — dropping oldest reading"`  
**When:** Failed reading queue hits `MAX_QUEUE_SIZE` (20 readings)  
**Detail:** Queue size

**Example:**
```
sensor_diagnostics,device_id=sensor-1,event_type=queue_overflow,severity=critical message="Reading queue full — dropping oldest reading",detail="queue_size: 20"
```

**Troubleshooting:**
- Database unreachable for >100 minutes (20 readings × 5 min interval)
- Check InfluxDB status: `sudo systemctl status influxdb`
- Check network connectivity between ESP8266 and Raspberry Pi
- Verify InfluxDB token in `config.h` is valid
- Check InfluxDB disk space: `df -h /mnt/sensor-data`

---

#### 6. `low_heap`
**Severity:** `warning`  
**Message:** `"Low free heap memory"`  
**When:** Free heap < 10,000 bytes  
**Detail:** Current free heap in bytes

**Example:**
```
sensor_diagnostics,device_id=sensor-1,event_type=low_heap,severity=warning message="Low free heap memory",detail="free_heap: 8456"
```

**Troubleshooting:**
- Memory leak or excessive queue usage
- Normal free heap: 25,000-35,000 bytes
- If persistent <10KB, check queue size and WiFi stability
- Reboot ESP8266 if heap continues dropping

---

### Spam Prevention

Diagnostic events have **10-second minimum spacing** between duplicate event types to prevent log flooding during extended outages.

---

## Heartbeat System

**Measurement:** `sensor_heartbeat`  
**Interval:** 60 seconds  
**Sent only when WiFi connected** (not queued offline)

### Heartbeat Fields

| Field       | Type    | Unit    | Description                          |
|-------------|---------|---------|--------------------------------------|
| `uptime`    | integer | seconds | Time since last boot                 |
| `free_heap` | integer | bytes   | Free RAM (ESP8266 heap)              |
| `rssi`      | integer | dBm     | WiFi signal strength                 |

### Heartbeat Tags

| Tag        | Example          | Description            |
|------------|------------------|------------------------|
| `device_id` | `sensor-1`      | Unique sensor ID       |
| `location`  | `backyard`      | Physical location tag  |

### Example InfluxDB Line
```
sensor_heartbeat,device_id=sensor-1,location=backyard uptime=3600,free_heap=28432,rssi=-54 1747257600
```

### Heartbeat Health Thresholds

| Metric       | Good       | Warning     | Critical   |
|--------------|------------|-------------|------------|
| `rssi`       | > -60 dBm  | -60 to -80  | < -80 dBm  |
| `free_heap`  | > 20 KB    | 10-20 KB    | < 10 KB    |
| Heartbeat gap | < 5 min   | 5-10 min    | > 10 min   |

**Missing heartbeat** (no data in 10 min) indicates:
- ESP8266 offline (powered off, crashed)
- WiFi disconnected for >10 min
- InfluxDB write failure

---

## Hardware Watchdog

**Timeout:** 8 seconds  
**Fed in:** `loop()` every iteration  
**Purpose:** Auto-reboot if firmware hangs (infinite loop, blocking I/O)

### When Watchdog Triggers
- WiFi connection hangs (very rare, WiFi stack has internal timeout)
- Blocking database write >8s (prevented by non-blocking queue drain)
- Infinite loop in user code

### Preventing False Triggers
- Non-blocking queue drain limits: 10s max per loop, 5 readings max per drain
- WiFi reconnection uses non-blocking `WiFi.reconnect()` + backoff delays
- No `delay()` calls >100ms in critical code paths

### Detecting Watchdog Reboots
After reboot, check serial for:
```
⚠️ CRASH DETECTED! Last uptime: 3456s
```

If present, watchdog likely triggered. Check:
1. Free heap trend before crash (should not be declining)
2. Queue size before crash (should not be at max)
3. WiFi stability (frequent disconnects can cause blocking)

---

## Raspberry Pi System Metrics

**Measurement:** `rpi_system_metrics`  
**Interval:** 60 seconds (systemd timer)  
**Script:** `/usr/local/bin/system-metrics-collector.py`

### System Metrics Fields

| Field            | Type  | Unit    | Description                     |
|------------------|-------|---------|----------------------------------|
| `cpu_percent`    | float | %       | CPU usage (all cores average)   |
| `memory_percent` | float | %       | RAM usage                       |
| `disk_percent`   | float | %       | Disk usage (/mnt/sensor-data)   |
| `cpu_temp`       | float | °C      | CPU temperature                 |

### Example InfluxDB Line
```
rpi_system_metrics cpu_percent=15.2,memory_percent=42.1,disk_percent=38.5,cpu_temp=48.3 1747257600
```

### System Health Thresholds

| Metric           | Good      | Warning     | Critical   |
|------------------|-----------|-------------|------------|
| `cpu_percent`    | < 60%     | 60-80%      | > 80%      |
| `memory_percent` | < 80%     | 80-90%      | > 90%      |
| `disk_percent`   | < 75%     | 75-90%      | > 90%      |
| `cpu_temp`       | < 60°C    | 60-70°C     | > 70°C     |

**Critical disk usage (>90%)** triggers health monitor auto-cleanup (removes old backups).

---

## Health Monitoring & Auto-Recovery

**Service:** `sensor-health-monitor.service`  
**Interval:** Every 5 minutes  
**Script:** `/usr/local/bin/sensor-health-monitor.sh`

### Monitored Conditions

#### 1. Disk Space (>90%)
**Action:** Remove old backups (keep only last 7 days)  
**Notification:** Slack alert if configured

#### 2. Low RAM (<100MB free)
**Action:** Restart InfluxDB + Grafana services  
**Notification:** Slack alert

#### 3. High CPU Temperature (>70°C)
**Action:** Warning logged (Pi 5 has thermal throttling built-in)  
**Notification:** Slack alert

#### 4. Service Failures
**Action:**
- Attempt service restart (3 attempts with 30s delay)
- If 3 restarts fail within 10 minutes → trigger full system reboot
- 24-hour cooldown before next auto-reboot (prevents boot loops)

**State tracking:** `/var/lib/sensor-health-monitor/`
- `last_reboot` — timestamp of last auto-reboot
- `failure_count` — consecutive service failures

### Auto-Reboot Safety
- **Cooldown:** 24 hours minimum between auto-reboots
- **Failure threshold:** 3 consecutive service failures in 10 minutes
- **Manual override:** `sudo systemctl restart sensor-health-monitor` resets counters

---

## Troubleshooting Guide

### Problem: Sensor offline (no heartbeat in 10+ minutes)

**Check:**
1. Power supply connected, LED lit on ESP8266
2. Serial monitor output: `pio device monitor` (115200 baud)
3. WiFi AP visible: look for `SoilSensor-Setup` network (captive portal mode)
4. InfluxDB token valid in `config.h`

**Steps:**
```bash
# On Raspberry Pi
sudo systemctl status influxdb
curl http://localhost:8086/health

# On ESP8266 serial
# Look for:
[WiFi] ✓ Connected to <SSID>
[DB] ✓ Posted to InfluxDB (HTTP 204)
```

---

### Problem: High diagnostic event rate (>10/hour)

**Check:**
1. WiFi signal strength: `rssi` in heartbeat (should be >-70 dBm)
2. WiFi stability: router logs, interference from microwave/Bluetooth
3. InfluxDB disk space: `df -h /mnt/sensor-data`
4. Network connectivity: `ping <raspberry-pi-ip>` from nearby device

---

### Problem: Queue overflow events

**Root cause:** Database unreachable for >100 minutes (20 readings × 5 min)

**Check:**
```bash
# InfluxDB running?
sudo systemctl status influxdb

# InfluxDB reachable?
curl http://localhost:8086/health

# Disk space?
df -h /mnt/sensor-data

# Token valid? (check InfluxDB UI)
http://<pi-ip>:8086 → Data → Tokens
```

**Fix:**
- Restart InfluxDB: `sudo systemctl restart influxdb`
- Clear queue: wait for WiFi + DB recovery, queue auto-drains
- Update token in `config.h` if expired/revoked

---

### Problem: Low heap warnings

**Normal free heap:** 25,000-35,000 bytes  
**Warning threshold:** <10,000 bytes

**Check:**
1. Grafana "Sensor Details" dashboard → Free Heap Memory graph
2. Look for gradual decline (memory leak) vs. sudden drop (queue buildup)
3. Queue size: check for `queue_overflow` events

**Fix:**
- If gradual decline → potential firmware bug, contact developer
- If sudden drop → WiFi/DB issue causing queue buildup, fix connectivity
- Temporary: reboot ESP8266 via power cycle

---

### Problem: Frequent WiFi disconnects (reason 200 - beacon timeout)

**Root cause:** Weak WiFi signal, interference, or router issues

**Check:**
1. RSSI in heartbeat: should be >-70 dBm (ideal >-60 dBm)
2. Router location relative to sensor
3. 2.4 GHz interference (microwave, Bluetooth, neighbors' WiFi)

**Fix:**
- Move sensor closer to router
- Add WiFi extender/mesh node
- Change router 2.4 GHz channel (use 1, 6, or 11 — non-overlapping)
- Reduce router 2.4 GHz bandwidth to 20 MHz (improves range)

---

### Problem: Raspberry Pi high CPU temperature (>70°C)

**Check:**
```bash
vcgencmd measure_temp
# Output: temp=72.3'C

# Check throttling status
vcgencmd get_throttled
# 0x0 = OK
# 0x50000 = currently throttled
```

**Fix:**
- Add active cooling (heatsink + fan)
- Improve case ventilation
- Reduce ambient temperature
- Check for runaway processes: `htop`

---

### Problem: Grafana dashboards not loading

**Check:**
```bash
# Grafana running?
sudo systemctl status grafana-server

# Provisioning config valid?
ls -la /mnt/sensor-data/grafana/provisioning/dashboards/
cat /mnt/sensor-data/grafana/provisioning/dashboards/dashboards.yml

# Dashboard JSON files present?
ls -la /mnt/sensor-data/grafana/dashboards/

# Grafana logs
journalctl -u grafana-server -n 50
```

**Fix:**
- Restart Grafana: `sudo systemctl restart grafana-server`
- Check file permissions: dashboards must be readable by `grafana` user
- Validate JSON: `cat dashboard.json | jq .` (requires jq installed)

---

## InfluxDB Schema

### Measurements

#### 1. `sensor_reading` (soil moisture data)
**Tags:**
- `device_id` — sensor identifier
- `location` — physical location

**Fields:**
- `moisture` (float, %) — calibrated moisture percentage
- `raw` (int) — raw ADC value (0-1023)
- `rssi` (int, dBm) — WiFi signal strength

**Retention:** 365 days (1 year)

---

#### 2. `sensor_heartbeat` (device health)
**Tags:**
- `device_id`
- `location`

**Fields:**
- `uptime` (int, seconds)
- `free_heap` (int, bytes)
- `rssi` (int, dBm)

**Retention:** 90 days

---

#### 3. `sensor_diagnostics` (events & errors)
**Tags:**
- `device_id`
- `location`
- `event_type` — boot, wifi_disconnect, queue_overflow, low_heap, etc.
- `severity` — info, warning, error, critical

**Fields:**
- `message` (string) — human-readable message
- `detail` (string) — additional context (optional)

**Retention:** 365 days

---

#### 4. `rpi_system_metrics` (server health)
**Tags:** None

**Fields:**
- `cpu_percent` (float, %)
- `memory_percent` (float, %)
- `disk_percent` (float, %)
- `cpu_temp` (float, °C)

**Retention:** 365 days

---

## Query Examples

### Get all sensors with low moisture (<30%) in last 10 minutes
```flux
from(bucket: "sensor-readings")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r._value < 30.0)
  |> group(columns: ["device_id"])
  |> last()
```

### Count diagnostic events by severity (last 24h)
```flux
from(bucket: "sensor-readings")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "sensor_diagnostics")
  |> filter(fn: (r) => r._field == "severity")
  |> group(columns: ["_value"])
  |> count()
```

### Find sensors with weak WiFi (RSSI < -70 dBm)
```flux
from(bucket: "sensor-readings")
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "sensor_heartbeat")
  |> filter(fn: (r) => r._field == "rssi")
  |> filter(fn: (r) => r._value < -70)
  |> group(columns: ["device_id"])
  |> last()
```

### Raspberry Pi CPU usage trend (last 6h, 5-min averages)
```flux
from(bucket: "sensor-readings")
  |> range(start: -6h)
  |> filter(fn: (r) => r._measurement == "rpi_system_metrics")
  |> filter(fn: (r) => r._field == "cpu_percent")
  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)
```

---

## Configuration Reference

### ESP8266 (`firmware/src/config.h`)

**Critical settings:**
```cpp
#define ENABLE_DIAGNOSTICS       true   // Enable diagnostic event logging
#define ENABLE_HEARTBEAT         true   // Enable 60s heartbeat
#define ENABLE_HARDWARE_WATCHDOG true   // Enable 8s watchdog
#define QUEUE_FAILED_READINGS    true   // Queue failed readings
#define MAX_QUEUE_SIZE           20     // Max queued readings
#define MAX_DRAIN_TIME_MS        10000  // Max queue drain time per loop
#define MAX_DRAIN_PER_LOOP       5      // Max readings drained per loop
```

### Raspberry Pi

**System metrics token:**
```bash
# /etc/environment
INFLUX_TOKEN=your_influxdb_write_token_here
```

**Health monitor config:**
- `DISK_THRESHOLD=90` — trigger cleanup at 90% disk usage
- `RAM_THRESHOLD_MB=100` — restart services if RAM <100MB
- `TEMP_THRESHOLD=70` — alert if CPU temp >70°C
- `REBOOT_COOLDOWN_HOURS=24` — min time between auto-reboots

---

## Support

**Serial debugging:**
```bash
cd firmware
pio device monitor
```

**View logs:**
```bash
# ESP8266 diagnostics
# Use Grafana "System Health" dashboard → Diagnostic Events table

# Raspberry Pi services
journalctl -u influxdb -f
journalctl -u grafana-server -f
journalctl -u sensor-health-monitor -f
journalctl -u system-metrics-collector -f

# System metrics
systemctl status sensor-health-monitor
systemctl status system-metrics-collector.timer
```

**Reset everything:**
```bash
# ESP8266: power cycle or press RESET button
# Raspberry Pi services:
sudo systemctl restart influxdb grafana-server
sudo systemctl restart sensor-health-monitor
```

---

**Document Version:** v2.1.0  
**Last Updated:** 2026-05-16  
**Firmware Version:** v2.1  
**Compatible Hardware:** ESP8266, Raspberry Pi 5
