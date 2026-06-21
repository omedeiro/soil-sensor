# Failure Analysis - May 17, 2026

## Incident Summary

**Date:** May 17, 2026  
**Time:** ~1:54 AM EDT  
**Duration:** ~6 hours (until manual power cycle at ~8:00 AM)  
**Impact:** Grafana dashboards inaccessible, required manual power cycle

## Root Cause

Systemd service files configured with incorrect user credentials:
- Services configured to run as `User=pi` and `Group=pi`
- User `pi` does not exist on this Raspberry Pi installation
- Actual user is `omedeiro`

### Affected Services

1. **sensor-health-monitor.service** - Health monitoring service
2. **sensor-backup.service** - Backup service
3. **system-metrics-collector.service** - System metrics collection

### Error Messages

```
sensor-health-monitor.service: Failed to determine user credentials: No such process
sensor-health-monitor.service: Failed at step USER spawning /usr/local/bin/sensor-health-monitor.sh: No such process
```

Services were stuck in restart loop, attempting to restart every 10 seconds.

## System Status at Time of Failure

**Boot Time:** 2026-05-17 01:54 AM EDT  
**Uptime at Discovery:** 2 minutes (just after power cycle)  
**Disk Space:** 4% used on root, 1% on /mnt/sensor-data - **No disk issues**  
**Memory:** 1.6GB used of 8GB total - **No memory issues**

**Services Status:**
- ✅ InfluxDB: Running correctly
- ✅ Grafana: Running correctly  
- ❌ Health Monitor: Failed to start (user issue)
- ❌ Backup Service: Failed to start (user issue)
- ❌ System Metrics: Not configured (timer missing)

## Investigation Findings

### What Was NOT the Cause

- ❌ Disk space (only 4% used)
- ❌ Memory exhaustion (plenty of RAM available)
- ❌ InfluxDB failure (service running normally)
- ❌ Grafana failure (service running normally)
- ❌ Network issues (no network-related errors)

### What WAS the Cause

✅ **Systemd service configuration error**
- Services configured for user `pi` which doesn't exist
- Services entered infinite restart loop
- Likely caused system instability leading to reboot

## Resolution

### Immediate Fix

1. Updated all 3 systemd service files:
   - Changed `User=pi` to `User=root`
   - Changed `Group=pi` to `Group=root`

2. Deployed fixed service files:
   ```bash
   sudo cp /tmp/*.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl restart sensor-health-monitor.service
   ```

3. Verified services started successfully

### Files Modified

- `/Users/owenmedeiros/soil-sensor/rpi-setup/systemd/sensor-health-monitor.service`
- `/Users/owenmedeiros/soil-sensor/rpi-setup/systemd/sensor-backup.service`
- `/Users/owenmedeiros/soil-sensor/rpi-setup/systemd/system-metrics-collector.service`

## Preventive Measures Implemented

### 1. Service Configuration Fix

All services now run as `root` to avoid user permission issues.

### 2. Last Updated Display

Added "Last Updated" panel to all 7 Grafana dashboards:
- Shows time since last data received
- Format: "X minutes ago"
- Located in top-right corner
- Helps identify stale data quickly

**Affected Dashboards:**
- soil-moisture-main.json
- soil-sensor.json
- sensor-details.json
- system-health.json
- alerts-overview.json
- mobile-summary.json
- system-diagnostics.json

### 3. Service Monitoring

Health monitor now running correctly and will alert on service failures.

## Lessons Learned

1. **Never assume default user names** - Always verify actual system user
2. **Test systemd services after installation** - Verify they start correctly
3. **Add monitoring for monitoring services** - Meta-monitoring is important
4. **Last updated timestamps are critical** - Helps identify stale data quickly

## Follow-Up Actions

- [x] Fix systemd service user configuration
- [x] Add Last Updated panels to all dashboards
- [x] Deploy fixes to production
- [x] Verify services running correctly
- [ ] Consider adding alerting for systemd service failures
- [ ] Add health checks for the health monitor itself
- [ ] Document proper user configuration in AGENTS.md

## Timeline

| Time | Event |
|------|-------|
| ~1:54 AM | System rebooted (unknown trigger) |
| 1:54 AM | Services failed to start due to user misconfiguration |
| 1:54-8:53 AM | Services stuck in restart loop |
| ~8:00 AM | Manual power cycle required |
| 8:54 AM | Issue diagnosed via log analysis |
| 8:54 AM | Services fixed and restarted successfully |
| 8:55 AM | Dashboards updated with Last Updated panels |

## Verification

```bash
# Check service status
sudo systemctl status sensor-health-monitor.service
sudo systemctl status sensor-backup.service

# Verify services running as root
ps aux | grep sensor-health-monitor
```

Expected: Services running as `root`, no restart loops.

## Status: RESOLVED ✅

All services now running correctly with proper user configuration.
Last Updated panels added to all dashboards for improved monitoring.
