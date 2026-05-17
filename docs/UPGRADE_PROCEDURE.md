# Upgrade Procedure - Enhanced Diagnostics & Monitoring v2.1

This guide provides step-by-step instructions to upgrade your soil sensor system with enhanced diagnostics, monitoring, and auto-recovery capabilities.

## 🎯 What's New in v2.1

### ESP8266 Sensor Improvements:
- ✅ **Diagnostic event logging** to InfluxDB (crashes, WiFi disconnects, errors)
- ✅ **Heartbeat mechanism** - detect silent sensor failures
- ✅ **Hardware watchdog** - automatic recovery from firmware hangs
- ✅ **Non-blocking queue drain** - prevents loop() blocking
- ✅ **Low heap monitoring** - early warning for memory issues

### Raspberry Pi Improvements:
- ✅ **System metrics collection** - CPU, RAM, disk, temperature tracked in InfluxDB
- ✅ **Enhanced health monitoring** - disk space, memory, temperature checks
- ✅ **Automatic service recovery** - auto-restart unhealthy services
- ✅ **Critical failure auto-reboot** - reboot after 3 consecutive failures (24h cooldown)

### Grafana Improvements:
- ✅ **Provisioned dashboards** - auto-install, no manual import
- ✅ **Mobile-optimized design** - fully responsive, touch-friendly
- ✅ **System health dashboard** - comprehensive diagnostics view
- ✅ **Slack alerting** - proactive notifications
- ✅ **Modern design system** - dark mode, accessibility, PWA support

---

## ⚠️ Pre-Upgrade Checklist

Before starting, complete these steps:

### 1. Backup Current System

```bash
# On Raspberry Pi - backup InfluxDB data
sudo systemctl stop influxdb grafana-server
sudo tar -czf ~/influxdb-backup-$(date +%Y%m%d).tar.gz /mnt/sensor-data/influxdb
sudo systemctl start influxdb grafana-server
```

### 2. Document Current State

```bash
# Record current sensor IDs and firmware versions
# Connect to each sensor via serial and note:
# - Device ID
# - MAC address
# - Last known firmware version
# - Current sensor readings (to validate after upgrade)

# On Raspberry Pi:
# - InfluxDB version: influx version
# - Grafana version: grafana-cli --version
# - Current IP address: hostname -I
```

### 3. Prepare for OTA Updates

Verify you can access sensors via OTA (no physical access needed):

```bash
# From your computer (on same network as sensors):
ping sensor-1.local  # Should respond if mDNS is working
# If not, use IP address instead
```

### 4. Set Up Slack Webhook (Optional)

1. Go to https://api.slack.com/apps
2. Create new app → "From scratch"
3. Name: "Soil Sensor Monitor", select workspace
4. Features → Incoming Webhooks → Activate
5. "Add New Webhook to Workspace" → select channel (#soil-sensor-alerts)
6. Copy webhook URL (you'll need it later)

---

## 📦 Part 1: Raspberry Pi Upgrade (Zero Downtime)

Estimated time: 20 minutes

### Step 1.1: Update Repository

```bash
# On Raspberry Pi
cd ~/soil-sensor
git pull origin main

# If you don't have git repo, download latest:
# wget https://github.com/omedeiro/soil-sensor/archive/refs/heads/main.zip
# unzip main.zip && cd soil-sensor-main
```

### Step 1.2: Install Python Dependencies

```bash
sudo apt update
sudo apt install -y python3-psutil

# Install InfluxDB Python client
pip3 install influxdb-client --break-system-packages
```

### Step 1.3: Deploy System Metrics Collector

```bash
# Copy script
sudo cp rpi-setup/scripts/system-metrics-collector.py /usr/local/bin/
sudo chmod +x /usr/local/bin/system-metrics-collector.py

# Copy systemd service and timer
sudo cp rpi-setup/systemd/system-metrics-collector.service /etc/systemd/system/
sudo cp rpi-setup/systemd/system-metrics-collector.timer /etc/systemd/system/

# Set environment variable for InfluxDB token
# Get your InfluxDB token from: http://<pi-ip>:8086 → Settings → Tokens
echo 'INFLUX_TOKEN="YOUR_INFLUX_TOKEN_HERE"' | sudo tee -a /etc/environment

# Reload systemd
sudo systemctl daemon-reload

# Enable and start metrics collector
sudo systemctl enable system-metrics-collector.timer
sudo systemctl start system-metrics-collector.timer

# Verify it's running
sudo systemctl status system-metrics-collector.timer
journalctl -u system-metrics-collector.service -f
# Should see: "✓ Sent metrics: CPU=X%, Temp=X°C..."
# Press Ctrl+C to exit
```

### Step 1.4: Update Health Monitor

```bash
# Backup existing health monitor
sudo cp /usr/local/bin/sensor-health-monitor.sh /usr/local/bin/sensor-health-monitor.sh.backup

# Deploy new version
sudo cp rpi-setup/scripts/sensor-health-monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/sensor-health-monitor.sh

# Restart health monitor
sudo systemctl restart sensor-health-monitor

# Verify
sudo systemctl status sensor-health-monitor
journalctl -u sensor-health-monitor -f
# Should see: "Enhanced Health Monitor Started"
# Press Ctrl+C to exit
```

### Step 1.5: Setup Grafana Provisioning

```bash
# Create provisioning directories
sudo mkdir -p /etc/grafana/provisioning/{dashboards,datasources,notifiers}
sudo mkdir -p /mnt/sensor-data/grafana/dashboards

# Copy provisioning configs
sudo cp rpi-setup/grafana-provisioning/dashboards/dashboards.yml \
   /etc/grafana/provisioning/dashboards/

sudo cp rpi-setup/grafana-provisioning/datasources/influxdb.yml \
   /etc/grafana/provisioning/datasources/

# Optional: Setup Slack notifications
# If you have a Slack webhook URL:
sudo cp rpi-setup/grafana-provisioning/notifiers/slack.yml.template \
   /etc/grafana/provisioning/notifiers/slack.yml

# Edit and add your webhook URL:
sudo nano /etc/grafana/provisioning/notifiers/slack.yml
# Replace ${SLACK_WEBHOOK_URL} with your actual webhook URL
# Or set environment variable: export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."

# Set InfluxDB read token in Grafana environment
echo 'INFLUX_READ_TOKEN="YOUR_READ_TOKEN_HERE"' | sudo tee -a /etc/default/grafana-server

# Copy dashboard JSON files
sudo cp grafana-dashboards/*.json /mnt/sensor-data/grafana/dashboards/
sudo chown -R grafana:grafana /mnt/sensor-data/grafana/dashboards

# Restart Grafana to load provisioning
sudo systemctl restart grafana-server

# Wait 10 seconds for restart
sleep 10

# Verify Grafana is running
sudo systemctl status grafana-server

# Check provisioning logs
sudo journalctl -u grafana-server | tail -20
# Should see: "Provisioning dashboards" messages
```

### Step 1.6: Verify Raspberry Pi Upgrade

```bash
# Check all services are running
sudo systemctl status influxdb grafana-server sensor-health-monitor system-metrics-collector.timer

# Check logs for errors
sudo journalctl -u influxdb -n 50 --no-pager
sudo journalctl -u grafana-server -n 50 --no-pager

# Verify metrics are being collected
# Wait 2 minutes, then check InfluxDB:
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-5m) 
  |> filter(fn:(r) => r._measurement == "rpi_system_metrics") 
  |> tail(n:5)'

# Should see recent CPU, RAM, disk metrics
```

✅ **Raspberry Pi upgrade complete!**

---

## 📡 Part 2: ESP8266 Firmware Upgrade (OTA or USB)

Estimated time: 10 minutes per sensor

### Step 2.1: Build New Firmware

On your development machine:

```bash
cd ~/soil-sensor/firmware

# Verify new files are present
ls src/diagnostics.* src/heartbeat.*
# Should see: diagnostics.h, diagnostics.cpp, heartbeat.h, heartbeat.cpp

# Build firmware
pio run

# Should compile successfully with new features
# Look for: "Building .pio/build/esp8266/firmware.bin"
```

### Step 2.2: Test on One Sensor First (USB Method - Recommended)

```bash
# Connect one sensor via USB

# Upload firmware
pio run --target upload --upload-port /dev/cu.usbserial-XXXX

# Monitor serial output
pio device monitor --port /dev/cu.usbserial-XXXX --baud 115200

# Expected output:
# ═══════════════════════════════════════
#   🌱  Soil Moisture Monitoring System
#      InfluxDB + WiFi Stability v2.1     ← New version!
#   Device: sensor-1  (backyard)
# ═══════════════════════════════════════
# [Watchdog] Hardware watchdog enabled (8 seconds)  ← New!
# [Diagnostics] System initialized  ← New!
# [Heartbeat] Initialized (interval: 60000 ms)  ← New!
# ...
# Setup complete. Uptime: 8 s
# Diagnostics: enabled  ← New!
# Heartbeat: enabled (60 s interval)  ← New!
# Hardware Watchdog: enabled  ← New!
```

### Step 2.3: Verify Diagnostics in InfluxDB

```bash
# On Raspberry Pi, query for new diagnostic data:

# Check for heartbeat messages
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-10m) 
  |> filter(fn:(r) => r._measurement == "sensor_heartbeat")
  |> tail(n:5)'

# Check for diagnostic events
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-1h) 
  |> filter(fn:(r) => r._measurement == "sensor_diagnostics")
  |> tail(n:10)'

# Should see boot_complete event at minimum
```

### Step 2.4: Upgrade Remaining Sensors via OTA

Once first sensor is validated:

```bash
# From your development machine:

# For each sensor, find its IP address
# Check your router or use:
nmap -sn 192.168.99.0/24 | grep -B 2 "ESP"

# Upload via OTA (no physical access needed!)
pio run --target upload --upload-port sensor-2.local
# Or use IP: pio run --target upload --upload-port 192.168.99.70

# Monitor via network (optional - requires serial proxy)
# OR check in Grafana dashboards to see sensor come back online

# Repeat for each sensor
```

**OTA Upload Notes:**
- Default OTA password: `soilmon2026` (set in main.cpp line 172)
- Sensors must be on same network as your computer
- OTA takes about 30 seconds per sensor
- Sensor will reboot automatically after upload

### Step 2.5: Verify All Sensors Upgraded

In Grafana (http://<pi-ip>:3000):

1. Open "System Health" dashboard (auto-provisioned)
2. Check "Sensor Status Table" - all sensors should show:
   - Status: Online (green)
   - Last Heartbeat: < 2 minutes ago
   - Uptime: recent (shows they rebooted)
3. Check "Diagnostic Events" panel - should see:
   - `boot_complete` events for each sensor
   - No crash events (unless intentional)

✅ **All sensors upgraded!**

---

## 📊 Part 3: Grafana Dashboard Configuration

Estimated time: 10 minutes

### Step 3.1: Access Dashboards

```bash
# Open Grafana: http://<pi-ip>:3000
# Login: admin / admin (change password if prompted)

# Navigate to: Dashboards → Browse
# You should see folder: "Soil Monitoring"
# Inside, you'll find:
#   - 🌱 Soil Moisture Dashboard (Main)
#   - 🏥 System Health
#   - (+ any other dashboards you created)
```

### Step 3.2: Configure Data Source (If Not Auto-Configured)

```bash
# Configuration → Data Sources
# Should see: "InfluxDB-SoilMonitoring" (default)

# If not present, add manually:
# 1. Add data source → InfluxDB
# 2. Name: InfluxDB-SoilMonitoring
# 3. Query Language: Flux
# 4. URL: http://localhost:8086
# 5. Organization: soil-monitoring
# 6. Token: <your-read-token>
# 7. Default Bucket: sensor-readings
# 8. Save & Test
```

### Step 3.3: Configure Alerts (If Using Slack)

```bash
# Alerting → Notification channels
# Should see: "Slack Soil Alerts" (if you configured slack.yml)

# Test notification:
# Click "Send Test" → check Slack channel

# If not working:
# - Verify webhook URL in /etc/grafana/provisioning/notifiers/slack.yml
# - Restart Grafana: sudo systemctl restart grafana-server
```

### Step 3.4: Create Alert Rules

Create alerts for critical conditions:

#### Alert 1: Sensor Heartbeat Missing

1. Open "System Health" dashboard
2. Create new alert on "Heartbeat" panel
3. Conditions:
   - WHEN: last() OF query(A)
   - IS BELOW: 1
   - FOR: 5m
4. Notifications: Send to "Slack Soil Alerts"
5. Message: `🚨 Sensor {{sensor}} offline - no heartbeat in 5 minutes`

#### Alert 2: High CPU Temperature

1. Create alert on "CPU Temperature" panel
2. Conditions:
   - WHEN: last() OF query(A)
   - IS ABOVE: 70
   - FOR: 5m
3. Notifications: Send to "Slack Soil Alerts"
4. Message: `🔥 Raspberry Pi CPU temperature critical: {{value}}°C`

#### Alert 3: Low Disk Space

1. Create alert on "Disk Usage" panel
2. Conditions:
   - WHEN: last() OF query(A)
   - IS ABOVE: 90
   - FOR: 10m
3. Notifications: Send to "Slack Soil Alerts"
4. Message: `💾 Disk space low: {{value}}% used`

✅ **Grafana configured!**

---

## 🧪 Part 4: Testing & Validation

Estimated time: 30 minutes

### Test 1: ESP8266 Heartbeat Mechanism

```bash
# In Grafana "System Health" dashboard:
# - Check "Sensor Status Table"
# - All sensors should show last heartbeat < 2 min ago
# - Wait 2 minutes, refresh
# - Heartbeat times should update

# In InfluxDB:
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-10m) 
  |> filter(fn:(r) => r._measurement == "sensor_heartbeat")
  |> group(columns: ["device_id"])
  |> count()'

# Should show multiple heartbeats per sensor
```

✅ Pass criteria: Each sensor sends heartbeat every 60 seconds

### Test 2: Hardware Watchdog Recovery

**⚠️ Warning:** This will intentionally crash a sensor!

```bash
# Connect to one test sensor via serial

# In the sensor code, temporarily add an infinite loop in loop():
# while(1) { /* hang */ }

# Upload and monitor:
pio run --target upload && pio device monitor

# Expected behavior:
# - Sensor hangs (stops printing to serial)
# - After 8 seconds, hardware watchdog triggers reset
# - Sensor reboots
# - Serial shows: "⚠️ CRASH DETECTED! Count: 1"
# - Diagnostic event sent to InfluxDB: crash_detected

# Verify in InfluxDB:
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-1h) 
  |> filter(fn:(r) => r._measurement == "sensor_diagnostics")
  |> filter(fn:(r) => r.event_type == "crash_detected")'
```

✅ Pass criteria: Sensor auto-recovers within 10 seconds, crash logged

### Test 3: Non-Blocking Queue Drain

```bash
# Simulate network outage:
# On Raspberry Pi, temporarily stop InfluxDB:
sudo systemctl stop influxdb

# Watch sensor serial output:
# Should see:
# [DB] Failed to send reading (WiFi down or server error)
# [Queue] Reading queued (1 in queue)
# [Queue] Reading queued (2 in queue)
# ... continues every 5 minutes

# Restart InfluxDB after 15 minutes (3 queued readings):
sudo systemctl start influxdb

# Sensor should immediately drain queue:
# [Main] WiFi connected - attempting to drain queue
# [Queue] Draining queue (3 readings)...
# [Queue] Limits: 10000 ms, 5 readings max   ← Time-limited!
# [Queue] ✓ Sent queued reading from <timestamp>
# [Queue] Drain complete: 3 sent, 0 failed, 0 remaining (took 2534 ms)
```

✅ Pass criteria: Queue drains without blocking loop(), within time limit

### Test 4: Raspberry Pi System Metrics

```bash
# Check metrics are being collected:
influx query --token "$INFLUX_TOKEN" 'from(bucket:"sensor-readings") 
  |> range(start:-5m) 
  |> filter(fn:(r) => r._measurement == "rpi_system_metrics")
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> tail(n:5)'

# Should show recent CPU, RAM, disk, temperature data

# In Grafana "System Health" dashboard:
# - CPU Usage graph should show recent data
# - Temperature gauge should show current temp
# - Memory and Disk gauges should be populated
```

✅ Pass criteria: Metrics collected every 60 seconds, visible in Grafana

### Test 5: Health Monitor Auto-Restart

```bash
# Intentionally crash Grafana:
sudo kill -9 $(pgrep grafana-server)

# Watch health monitor logs:
sudo journalctl -u sensor-health-monitor -f

# Should see within 60 seconds:
# [2026-05-16 12:34:56] ✗ Grafana is unhealthy - restarting grafana-server
# [2026-05-16 12:35:06] ✓ Grafana recovered after restart

# Verify Grafana is running:
sudo systemctl status grafana-server
# Should be: active (running)
```

✅ Pass criteria: Service auto-restarts within 60 seconds

### Test 6: Mobile Dashboard Responsiveness

```bash
# On your phone:
# - Open Safari/Chrome
# - Navigate to: http://<pi-ip>:3000
# - Login
# - Open "🌱 Soil Moisture Dashboard (Main)"

# Verify:
# - Panels stack vertically (not side-by-side)
# - Text is readable without zooming
# - Gauges are large and touch-friendly
# - Time range selector works with touch
# - Graphs are scrollable
# - No horizontal scrolling (except tables)

# Optional: Add to home screen (PWA)
# - Safari: Share → Add to Home Screen
# - Chrome: Menu → Add to Home Screen
```

✅ Pass criteria: Fully usable on phone without zooming

### Test 7: End-to-End Alert Flow

```bash
# Trigger test alert (simulate high CPU temp):
# On Raspberry Pi, stress CPU:
sudo apt install stress-ng
stress-ng --cpu 4 --timeout 300s &

# Monitor temperature:
watch -n 5 'cat /sys/class/thermal/thermal_zone0/temp'

# When temp > 70°C:
# - Check Slack channel for alert notification
# - Check Grafana → Alerting → Alert Rules
# - Should show "Firing" state

# Stop stress test:
sudo killall stress-ng

# When temp < 70°C:
# - Alert should auto-resolve
# - Slack should show "Resolved" notification
```

✅ Pass criteria: Alert fires within 5 min, notification received in Slack

---

## 🔄 Rollback Procedure (If Needed)

If you encounter critical issues:

### Rollback Raspberry Pi

```bash
# Stop new services
sudo systemctl stop system-metrics-collector.timer
sudo systemctl disable system-metrics-collector.timer

# Restore old health monitor
sudo cp /usr/local/bin/sensor-health-monitor.sh.backup \
   /usr/local/bin/sensor-health-monitor.sh
sudo systemctl restart sensor-health-monitor

# Remove Grafana provisioning (revert to manual dashboards)
sudo rm -rf /etc/grafana/provisioning/*
sudo systemctl restart grafana-server

# Restore InfluxDB backup (if needed - DESTRUCTIVE!)
# sudo systemctl stop influxdb
# sudo rm -rf /mnt/sensor-data/influxdb/*
# sudo tar -xzf ~/influxdb-backup-YYYYMMDD.tar.gz -C /
# sudo systemctl start influxdb
```

### Rollback ESP8266 Firmware

```bash
# If you saved previous firmware binary:
pio run --target upload --upload-port <sensor-ip> \
   --upload-file .pio/build/esp8266/firmware_old.bin

# OR reflash from USB:
pio run --target upload --upload-port /dev/cu.usbserial-XXXX
```

---

## 📋 Post-Upgrade Monitoring Checklist

Monitor these for the first 48 hours:

### Hour 1:
- [ ] All sensors showing heartbeats in Grafana
- [ ] System metrics (CPU, RAM, disk) appear in Grafana
- [ ] No crash events in diagnostics
- [ ] Health monitor running without errors

### Day 1:
- [ ] All sensors still online
- [ ] Queue successfully drains after any network blip
- [ ] No unexpected reboots (check `/mnt/sensor-data/logs/reboot_reasons.log`)
- [ ] Disk usage not increasing abnormally
- [ ] Temperature stays < 70°C

### Day 2:
- [ ] Test one manual service restart (verify auto-restart works)
- [ ] Review diagnostic events (any patterns?)
- [ ] Check heartbeat reliability (any gaps?)
- [ ] Verify mobile dashboard still works
- [ ] Test alert notifications (if configured)

---

## 🎉 Success Criteria

Your upgrade is successful if:

1. ✅ All sensors send heartbeats every 60 seconds
2. ✅ Diagnostic events logged for crashes, disconnects, errors
3. ✅ System metrics collected from Raspberry Pi every 60 seconds
4. ✅ Grafana dashboards auto-provisioned and mobile-responsive
5. ✅ Health monitor auto-restarts failed services
6. ✅ No manual interventions required for 48 hours
7. ✅ Alert notifications working (if configured)
8. ✅ Hardware watchdog prevents sensor hangs
9. ✅ Queue drain operations complete within time limits
10. ✅ Mobile dashboard fully usable on phones

---

## 📞 Troubleshooting

See [DIAGNOSTICS_REFERENCE.md](DIAGNOSTICS_REFERENCE.md) for detailed troubleshooting guide.

Common issues:

| Issue | Solution |
|-------|----------|
| Sensors not sending heartbeats | Check `ENABLE_HEARTBEAT` in config.h, verify WiFi connected |
| Diagnostics not in InfluxDB | Check `INFLUX_TOKEN` is set correctly, verify bucket name |
| Grafana dashboards not appearing | Check provisioning path, restart Grafana, check logs |
| Metrics collector failing | Verify Python dependencies installed, check token in /etc/environment |
| OTA upload fails | Verify sensor on same network, try USB upload instead |
| Slack alerts not working | Check webhook URL, test in notification channels settings |

---

## 📚 Related Documentation

- [DIAGNOSTICS_REFERENCE.md](DIAGNOSTICS_REFERENCE.md) - Complete diagnostic events reference
- [README.md](../README.md) - Project overview and setup
- [AGENTS.md](../AGENTS.md) - Agent instructions and technical reference
- [docs/README.md](../docs/README.md) - WiFi stability, Grafana Cloud, InfluxDB notes

---

**Version:** 2.1  
**Last Updated:** 2026-05-16  
**Estimated Total Time:** 70 minutes
