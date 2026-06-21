# System Audit Logger

Comprehensive health checking and configuration validation that runs automatically every 5 minutes to catch issues early.

## What It Checks

### InfluxDB Health
- ✅ Startup script exists and is executable
- ✅ Data path points to correct directory (`/mnt/sensor-data/influxdb/data`)
- ✅ Database contains reasonable amount of data (>100KB)
- ✅ Service is active and no recent errors

### Backup Health
- ✅ Admin token is configured
- ✅ Backup files exist and are recent (<25 hours old)

### ESP8266 Connectivity
- ✅ Device is reachable at 192.168.99.70
- ✅ Last sensor reading is recent (<10 minutes)

### System Health
- ✅ Grafana service is running
- ✅ Disk space is healthy (<90% full)
- ✅ No filesystem corruption detected
- ✅ Log rotation is working (files <50MB)

## How It Works

The audit logger runs automatically:
- **Every 5 minutes** via systemd timer
- **1 minute after boot** to catch startup issues

Issues are logged to two files:
- `/mnt/sensor-data/logs/system-audit.log` - Full audit trail
- `/mnt/sensor-data/logs/system-alerts.log` - **Critical alerts only**

## Viewing Logs

**See recent audit results:**
```bash
tail -50 /mnt/sensor-data/logs/system-audit.log
```

**See only alerts:**
```bash
tail -50 /mnt/sensor-data/logs/system-alerts.log
```

**Follow audit log in real-time:**
```bash
tail -f /mnt/sensor-data/logs/system-audit.log
```

**Check audit timer status:**
```bash
systemctl status system-audit.timer
```

## Example Output

### Healthy System
```
[2026-05-20 20:34:11] [INFO] [AUDIT] Starting system audit
[2026-05-20 20:34:11] [PASS] [CHECK] InfluxDB startup script exists
[2026-05-20 20:34:11] [PASS] [CHECK] InfluxDB data path correct
[2026-05-20 20:34:11] [PASS] [CHECK] InfluxDB data size reasonable
[2026-05-20 20:34:11] [INFO] [AUDIT] Audit complete: 11 checks, 0 failed
```

### Issues Detected
```
[2026-05-20 20:34:11] [ALERT] [SYSTEM] InfluxDB using WRONG data path: /mnt/sensor-data/influxdb/engine (expected: /mnt/sensor-data/influxdb/data)
[2026-05-20 20:34:11] [ALERT] [SYSTEM] NO BACKUP FILES FOUND in /mnt/sensor-data/backups
[2026-05-20 20:34:11] [INFO] [AUDIT] Audit complete: 11 checks, 2 failed
```

## What Would Have Been Caught

The audit logger would have immediately detected today's issues:

### ❌ Missing InfluxDB startup script
```
[ALERT] InfluxDB startup script MISSING: /usr/lib/influxdb/scripts/influxd-systemd-start.sh
```

### ❌ Wrong data path
```
[ALERT] InfluxDB using WRONG data path: /mnt/sensor-data/influxdb/engine (expected: /mnt/sensor-data/influxdb/data)
```

### ❌ Database too small
```
[ALERT] InfluxDB data size suspiciously small: 4096 bytes (expected >100KB)
```

### ❌ Backup failures
```
[ALERT] INFLUX_ADMIN_TOKEN not set - backups will fail
[ALERT] NO BACKUP FILES FOUND in /mnt/sensor-data/backups
```

## Manual Execution

Run audit on demand:
```bash
sudo systemctl start system-audit.service
```

View results immediately:
```bash
journalctl -u system-audit.service -n 50 --no-pager
```

## Configuration

Edit check thresholds in `/usr/local/bin/system-audit-logger.sh`:
- `min_expected_size=100000` - Minimum database size (bytes)
- `max_age_hours=25` - Maximum backup age
- `max_age_minutes=10` - Maximum ESP8266 reading age
- `max_size_mb=50` - Maximum log file size

## Integration

The audit logger writes to dedicated log files:
- **Does NOT** trigger reboots (logging only)
- **Does NOT** restart services (use health monitor for that)
- **Does** alert on configuration issues
- **Does** validate data integrity

Use with the Health Monitor:
- **Audit Logger** - Detects configuration problems
- **Health Monitor** - Fixes service failures and restarts

## Installation

Already installed on your Raspberry Pi. To reinstall:
```bash
cd ~/rpi-setup
./install-audit-logger.sh
```

## Troubleshooting

**Audit not running:**
```bash
systemctl status system-audit.timer
systemctl start system-audit.timer
```

**Too many alerts:**
Adjust thresholds in `/usr/local/bin/system-audit-logger.sh`

**Missing logs:**
Ensure `/mnt/sensor-data` is mounted and writable
