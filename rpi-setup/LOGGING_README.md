# Enhanced Logging and Monitoring System

This directory contains scripts and configuration for comprehensive system monitoring and boot reason tracking.

## Overview

The enhanced logging system tracks:
- **System boot reasons** (clean reboot, crash, power loss, filesystem corruption)
- **Service health** (InfluxDB, Grafana)
- **System resources** (disk, RAM, CPU temperature)
- **Grafana-specific failures** (detailed failure logs)
- **Reboot events** (with reasons and cooldown protection)

## Components

### 1. Startup Logger (`startup-logger.sh`)
**Purpose:** Runs once at boot to log why the system started

**Features:**
- Detects clean vs unclean shutdowns
- Identifies filesystem corruption (dirty bit)
- Logs kernel panics
- Records temperature at boot
- Checks USB drive mount status
- Verifies service status

**Log File:** `/mnt/sensor-data/logs/startup_history.log`

**Service:** `startup-logger.service` (oneshot at boot)

### 2. Health Monitor (`sensor-health-monitor.sh`)
**Purpose:** Continuous monitoring of services and system health

**Features:**
- Monitors InfluxDB and Grafana health endpoints
- Auto-restarts failed services
- Tracks consecutive failures
- Triggers system reboot after 3 consecutive failures
- 24-hour reboot cooldown protection
- Grafana-specific failure logging

**Log Files:**
- `/mnt/sensor-data/logs/health-monitor.log` - General health checks
- `/mnt/sensor-data/logs/grafana_failures.log` - Grafana-specific issues
- `/mnt/sensor-data/logs/reboot_reasons.log` - Reboot triggers

**Service:** `sensor-health-monitor.service` (always running)

### 3. Log Rotation (`logrotate.d/soil-sensor`)
**Purpose:** Prevent logs from consuming all disk space

**Rotation Schedule:**
- `health-monitor.log` - Daily, keep 7 days, max 100MB
- `startup_history.log` - Monthly, keep 12 months, max 10MB
- `metrics-collector.log` - Daily, keep 7 days, max 50MB
- `backup.log` - Weekly, keep 4 weeks, max 10MB

## Installation

### On your local machine:

```bash
cd /Users/owenmedeiros/soil-sensor/rpi-setup

# Copy files to Raspberry Pi
scp -r scripts systemd logrotate.d install-logging.sh omedeiro@192.168.99.134:~/rpi-setup/
```

### On the Raspberry Pi:

```bash
cd ~/rpi-setup
sudo ./install-logging.sh
```

The installer will:
1. Stop health monitor
2. Install startup logger
3. Update health monitor with enhanced logging
4. Configure log rotation
5. Rotate existing large logs
6. Test startup logger
7. Restart health monitor

## Viewing Logs

### Check startup history:
```bash
ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/startup_history.log"
```

### Monitor health checks in real-time:
```bash
ssh omedeiro@192.168.99.134 "tail -f /mnt/sensor-data/logs/health-monitor.log"
```

### View Grafana failures:
```bash
ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/grafana_failures.log"
```

### Check reboot reasons:
```bash
ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/reboot_reasons.log"
```

### View last boot event:
```bash
ssh omedeiro@192.168.99.134 "tail -30 /mnt/sensor-data/logs/startup_history.log"
```

## Understanding Startup Log Entries

Example startup log entry:

```
================================================================
BOOT EVENT: 2026-05-18 19:00:00
----------------------------------------------------------------
Boot Time: May 18 19:00
System Uptime: 120s
Previous Boot: May 17 23:58
Boot Reason: UNCLEAN SHUTDOWN - Filesystem corruption detected
Details: Dirty bit is set. Fs was not properly unmounted
CPU Temperature at boot: 45°C
USB Drive: MOUNTED at /mnt/sensor-data
Service Status:
  ✓ InfluxDB: Active
  ✗ Grafana: Inactive
  ✓ Health Monitor: Active
================================================================
```

### Boot Reasons:

- **CLEAN REBOOT** - Normal `sudo reboot` command
- **CLEAN SHUTDOWN** - Normal `sudo shutdown` command
- **UNCLEAN SHUTDOWN** - Filesystem corruption detected (power loss, crash)
- **POWER EVENT** - Power-related issue
- **KERNEL PANIC** - Critical kernel error
- **UNKNOWN** - Unable to determine reason (likely crash/power loss)

## Troubleshooting

### Health monitor not running:
```bash
ssh omedeiro@192.168.99.134 "sudo systemctl status sensor-health-monitor"
ssh omedeiro@192.168.99.134 "sudo systemctl restart sensor-health-monitor"
```

### Check if startup logger ran:
```bash
ssh omedeiro@192.168.99.134 "sudo journalctl -u startup-logger -n 50"
```

### Manually run startup logger:
```bash
ssh omedeiro@192.168.99.134 "sudo /usr/local/bin/startup-logger.sh"
```

### Check log rotation status:
```bash
ssh omedeiro@192.168.99.134 "sudo logrotate -d /etc/logrotate.d/soil-sensor"
```

### Large log file emergency rotation:
```bash
ssh omedeiro@192.168.99.134 "sudo logrotate -f /etc/logrotate.d/soil-sensor"
```

## Configuration

### Health Monitor Thresholds

Edit `/usr/local/bin/sensor-health-monitor.sh`:

```bash
DISK_WARN_THRESHOLD=90         # Disk usage %
RAM_WARN_THRESHOLD=100         # Free RAM in MB
CPU_TEMP_WARN_THRESHOLD=70     # CPU temp in °C
MAX_CONSECUTIVE_FAILURES=3     # Failures before reboot
REBOOT_COOLDOWN=86400          # Seconds between reboots (24h)
CHECK_INTERVAL=60              # Seconds between checks
```

After editing, restart the service:
```bash
sudo systemctl restart sensor-health-monitor
```

## What This Solved

**Problem:** Grafana was down for 18.5 hours (May 17 11:59 PM - May 18 6:31 PM) with no way to determine why.

**Root Cause:** 
- Raspberry Pi had unclean shutdown (power loss or crash)
- Filesystem corruption detected on USB drive
- Grafana failed to start after boot
- Health monitor was restarting Grafana but it never recovered
- No logs existed to track the boot reason

**Solution:**
1. **Startup logger** now captures every boot event and reason
2. **Enhanced health monitor** logs Grafana-specific failures
3. **Log rotation** prevents disk space issues from huge logs
4. **Reboot tracking** logs when/why automatic reboots occur

## Future Improvements

Consider adding:
1. **UPS monitoring** - If you add a UPS, integrate with NUT (Network UPS Tools)
2. **Email alerts** - Send emails on critical failures
3. **Grafana dashboard** - Visualize health monitor metrics
4. **Automatic log analysis** - Parse logs for common failure patterns
5. **Backup verification** - Verify backups complete successfully
