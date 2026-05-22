# System Reliability & Recovery Documentation

## Issue Summary (May 22, 2026)

**Problem:** Grafana dashboards showed "No Data" after waking up. System had experienced unclean shutdown causing InfluxDB corruption.

**Root Cause:** 
- Unclean shutdown (power loss or hard reboot) at ~06:43 EDT
- Filesystem corruption on SD card (EXT4 directory block checksum failures)
- InfluxDB metadata database (`influxd.bolt`) corruption
- InfluxDB crash loop - systemd gave up after 5 failed restart attempts

**Impact:**
- Grafana: Running but unable to query data (no InfluxDB connection)
- InfluxDB: Failed to start (metadata corruption)
- Data loss: Lost sensor readings from May 20-22 (restored from May 20 backup)
- Downtime: ~21 minutes until manual recovery

## Recovery Steps Performed

1. **InfluxDB Restoration:**
   ```bash
   sudo systemctl stop influxdb
   cd /mnt/sensor-data/backups/influx_20260520_203429/
   gunzip -c 20260521T003429Z.bolt.gz > /mnt/sensor-data/influxdb/influxd.bolt
   gunzip -c 20260521T003429Z.sqlite.gz > /mnt/sensor-data/influxdb/influxd.sqlite
   tar -xzf 20260521T003429Z.13.tar.gz -C /mnt/sensor-data/influxdb/engine
   chown -R influxdb:influxdb /mnt/sensor-data/influxdb
   sudo systemctl start influxdb
   ```

2. **Verification:**
   - InfluxDB health check: ✓ Pass
   - Grafana connectivity: ✓ Pass
   - All 4 sensors posting data: ✓ Pass

## Reliability Improvements Installed

### 1. InfluxDB Auto-Recovery Watchdog
- **Timer:** Runs every 5 minutes
- **Function:** Detects InfluxDB failures and automatically restores from latest backup
- **Log:** `/mnt/sensor-data/logs/influxdb-watchdog.log`
- **Service:** `influxdb-watchdog.timer` + `influxdb-watchdog.service`

### 2. System Health Monitor
- **Timer:** Runs every 10 minutes
- **Checks:**
  - InfluxDB status + HTTP health
  - Grafana status + HTTP health
  - Filesystem errors
  - Disk space usage
  - Memory availability
  - CPU temperature
  - Sensor data freshness (15min window)
- **Logs:** 
  - `/mnt/sensor-data/logs/system-health.log`
  - `/mnt/sensor-data/logs/system-alerts.log`
- **Service:** `system-health.timer` + `system-health.service`

### 3. Periodic Data Sync
- **Timer:** Runs every 10 minutes
- **Function:** Forces filesystem sync to prevent data loss during power failure
- **Log:** `/mnt/sensor-data/logs/sync.log`
- **Service:** `influxdb-sync.timer` + `influxdb-sync.service`

### 4. Grafana Auto-Restart
- **Configuration:** Grafana now auto-restarts if it crashes
- **Restart delay:** 10 seconds
- **File:** `/etc/systemd/system/grafana-server.service.d/timeout.conf`

### 5. Extended Shutdown Timeouts
- **InfluxDB:** 60 second graceful shutdown (was: 90s default)
- **Grafana:** 60 second graceful shutdown
- **Purpose:** Allows services time to flush data to disk before forced termination

### 6. Shutdown Event Logging
- **Function:** Logs all shutdown events with timestamp
- **Log:** `/mnt/sensor-data/logs/shutdown-history.log`
- **Purpose:** Track intentional vs unintentional shutdowns

## Monitoring & Maintenance

### Check System Health
```bash
# View active timers
systemctl list-timers

# Check recent health logs
tail -50 /mnt/sensor-data/logs/system-health.log

# Check for alerts
tail -50 /mnt/sensor-data/logs/system-alerts.log

# Check InfluxDB watchdog status
tail -50 /mnt/sensor-data/logs/influxdb-watchdog.log

# Check shutdown history
cat /mnt/sensor-data/logs/shutdown-history.log
```

### Manual Recovery (if needed)
```bash
# Recovery script (interactive)
sudo ~/soil-sensor/rpi-setup/scripts/recover-influxdb.sh

# Quick status check
sudo systemctl status influxdb grafana-server
curl http://localhost:8086/health
curl http://localhost:3000/api/health
```

### View Startup History
```bash
# See all boot events and reasons
cat /mnt/sensor-data/logs/startup_history.log

# Check for corruption patterns
grep "UNCLEAN" /mnt/sensor-data/logs/startup_history.log
```

## Prevention Best Practices

### DO:
✅ Let the watchdog auto-recover (wait 5-10 minutes before manual intervention)  
✅ Check logs after any unexpected downtime  
✅ Monitor `/mnt/sensor-data/logs/system-alerts.log` for warnings  
✅ Ensure quality power supply (official Raspberry Pi adapter recommended)  
✅ Use graceful shutdown when possible  

### DON'T:
❌ Pull power without shutdown (causes corruption)  
❌ Hard reboot unless absolutely necessary  
❌ Ignore repeated unclean shutdown warnings  
❌ Disable the watchdog or health monitor timers  

## Expected Behavior After Failure

1. **Unclean shutdown occurs**
2. **System boots** (~1-2 minutes)
3. **InfluxDB fails to start** (corruption detected)
4. **InfluxDB watchdog activates** (2 minutes after boot)
5. **Automatic restore from backup** (~30 seconds)
6. **InfluxDB starts successfully**
7. **Sensors resume posting data** (next 5-minute cycle)
8. **Grafana displays data** (within 5-10 minutes total)

**Total recovery time: 5-10 minutes (fully automated, no manual intervention required)**

## Files Added/Modified

### New Scripts
- `/home/omedeiro/soil-sensor/rpi-setup/install-reliability.sh` - Installation script
- `/home/omedeiro/soil-sensor/rpi-setup/scripts/recover-influxdb.sh` - Manual recovery
- `/home/omedeiro/soil-sensor/rpi-setup/scripts/system-health-monitor.sh` - Health checks
- `/usr/local/bin/influxdb-watchdog.sh` - Auto-recovery logic
- `/usr/local/bin/log-shutdown.sh` - Shutdown logging

### New Services/Timers
- `influxdb-watchdog.{service,timer}` - Auto-recovery (every 5min)
- `system-health.{service,timer}` - Health monitoring (every 10min)
- `influxdb-sync.{service,timer}` - Data sync (every 10min)
- `log-shutdown.service` - Shutdown logging

### Service Overrides
- `/etc/systemd/system/influxdb.service.d/timeout.conf` - Extended timeout
- `/etc/systemd/system/grafana-server.service.d/timeout.conf` - Extended timeout + auto-restart

### New Log Files
- `/mnt/sensor-data/logs/influxdb-watchdog.log`
- `/mnt/sensor-data/logs/system-health.log`
- `/mnt/sensor-data/logs/system-alerts.log`
- `/mnt/sensor-data/logs/shutdown-history.log`
- `/mnt/sensor-data/logs/sync.log`

## Testing

To test the auto-recovery:
```bash
# Simulate corruption (DO NOT RUN IN PRODUCTION without backup!)
sudo systemctl stop influxdb
sudo rm /mnt/sensor-data/influxdb/influxd.bolt
sudo systemctl start influxdb  # Will fail

# Wait 5 minutes - watchdog should auto-recover
# Check logs:
tail -f /mnt/sensor-data/logs/influxdb-watchdog.log
```

---
**Last Updated:** May 22, 2026  
**Next Review:** Check logs weekly for patterns
