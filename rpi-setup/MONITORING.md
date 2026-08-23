# Enhanced Monitoring System

## Overview

Comprehensive monitoring and logging system for the Raspberry Pi 5 sensor server. Tracks power issues, network connectivity, system events, and generates daily health reports to help identify root causes of unclean shutdowns and system failures.

## Installation

```bash
ssh omedeiro@192.168.99.134
cd ~/soil-sensor/rpi-setup
sudo ./install-enhanced-monitoring.sh
```

## Monitoring Components

### 1. Power Monitor (Every 2 minutes)
**Script:** `scripts/power-monitor.sh`  
**Service:** `power-monitor.timer`  
**Logs:** `/mnt/sensor-data/logs/power-monitor.log`

**Monitors:**
- Under-voltage detection (power supply issues)
- CPU throttling events
- Temperature readings
- Core voltage levels
- ARM clock speed
- System uptime and boot history

**Critical Alerts:**
- Under-voltage detected (insufficient power supply)
- Throttling active (power or thermal issues)
- Previous unclean shutdown indicators

**Example Alert:**
```
[2026-05-22 17:10:53] ⚠️  ALERT: CRITICAL: Under-voltage detected! Power supply insufficient!
[2026-05-22 17:10:53] ⚠️  ALERT: Action required: Replace power supply with 5V 3A+ adapter
```

### 2. Network Monitor (Every 5 minutes)
**Script:** `scripts/network-monitor.sh`  
**Service:** `network-monitor.timer`  
**Logs:** `/mnt/sensor-data/logs/network-monitor.log`

**Monitors:**
- Network interface status (eth0, wlan0)
- WiFi signal strength and quality
- Internet connectivity (ping test)
- DNS resolution
- InfluxDB connectivity (localhost:8086)
- Grafana connectivity (localhost:3000)
- ESP8266 sensor reachability (all 4 sensors)
- Network errors and dropped packets

**Critical Alerts:**
- Internet connectivity lost
- DNS resolution failed
- Critical service unreachable
- Sensor offline

### 3. Shutdown/Reboot Logger
**Script:** `scripts/event-logger.sh`  
**Service:** `shutdown-logger.service`  
**Logs:** `/mnt/sensor-data/logs/shutdown-events.log`

**Captures:**
- All shutdown/reboot/halt events
- What triggered the shutdown (user, script, system)
- Parent process and command
- Active logged-in users
- Scheduled shutdown timers
- System state at shutdown time
- Service status before shutdown

**Use Case:**
Helps distinguish between:
- Manual shutdowns (ssh, sudo shutdown)
- Automated shutdowns (cron jobs, timers)
- Crash/power loss (no log entry = unclean shutdown)

### 4. Daily Health Report (8 AM daily)
**Script:** `scripts/daily-health-report.sh`  
**Service:** `daily-health-report.timer`  
**Logs:** `/mnt/sensor-data/logs/daily-health-report.log`  
**Archives:** `/mnt/sensor-data/logs/reports/health-report-YYYYMMDD.log`

**Comprehensive Report Includes:**
- System information (uptime, kernel, OS)
- Power status (throttling, temperature, voltage)
- Memory and disk usage
- Service status (InfluxDB, Grafana, Cloudflare)
- Network status
- Sensor activity (last 30 minutes)
- Recent alerts (last 24 hours)
- Shutdown/reboot events (last 7 days)
- Unclean shutdown history
- InfluxDB watchdog activity
- System resource trends
- Top CPU/memory processes
- Automated recommendations

**Generate Report Manually:**
```bash
sudo systemctl start daily-health-report.service
cat /mnt/sensor-data/logs/daily-health-report.log
```

## Log Files

| Log File | Purpose | Update Frequency |
|----------|---------|------------------|
| `power-monitor.log` | Power and thermal monitoring | Every 2 minutes |
| `power-alerts.log` | Critical power issues only | As needed |
| `network-monitor.log` | Network connectivity checks | Every 5 minutes |
| `network-alerts.log` | Network failures only | As needed |
| `system-events.log` | General system events | As needed |
| `shutdown-events.log` | Shutdown/reboot triggers | On shutdown |
| `daily-health-report.log` | Comprehensive health summary | 8 AM daily |
| `reports/health-report-*.log` | Archived daily reports | 8 AM daily |

## Monitoring Status

### Check Timer Status
```bash
systemctl list-timers | grep -E "(power-monitor|network-monitor|daily-health)"
```

**Expected Output:**
```
Fri 2026-05-22 17:12:52 EDT 1min 43s  power-monitor.timer
Fri 2026-05-22 17:15:52 EDT 4min 43s  network-monitor.timer
Sat 2026-05-23 08:00:00 EDT 14h left  daily-health-report.timer
```

### View Live Logs
```bash
# Power monitoring
tail -f /mnt/sensor-data/logs/power-monitor.log

# Power alerts only
tail -f /mnt/sensor-data/logs/power-alerts.log

# Network monitoring
tail -f /mnt/sensor-data/logs/network-monitor.log

# All alerts
tail -f /mnt/sensor-data/logs/*-alerts.log

# Shutdown events
cat /mnt/sensor-data/logs/shutdown-events.log
```

### Check Service Status
```bash
systemctl status power-monitor.timer
systemctl status network-monitor.timer
systemctl status daily-health-report.timer
systemctl status shutdown-logger.service
```

## Understanding Power Issues

### Throttle Status Codes

The `vcgencmd get_throttled` command returns a hex value indicating current and historical power/thermal issues:

| Bit | Hex Value | Meaning |
|-----|-----------|---------|
| 0 | 0x1 | **CURRENT: Under-voltage detected** (power supply too weak) |
| 1 | 0x2 | CURRENT: ARM frequency capped |
| 2 | 0x4 | CURRENT: Throttling active |
| 3 | 0x8 | CURRENT: Soft temperature limit |
| 16 | 0x10000 | HISTORY: Under-voltage occurred |
| 17 | 0x20000 | HISTORY: ARM freq capping occurred |
| 18 | 0x40000 | HISTORY: Throttling occurred |
| 19 | 0x80000 | HISTORY: Soft temp limit occurred |

**Example:**
- `0x0` = All systems nominal (no issues)
- `0x50000` = Previous under-voltage and throttling (history only)
- `0x5` = CURRENT under-voltage and throttling (CRITICAL!)

### Power Supply Recommendations

**Current Setup:**
- 5V 2A power supply
- Connected to power strip

**If Under-voltage Detected:**
1. Upgrade to **5V 3A** (15W) official Raspberry Pi 5 power supply
2. Use shorter, higher-quality USB-C cable (minimize voltage drop)
3. Consider UPS (uninterruptible power supply) for protection against:
   - Power outages
   - Brownouts
   - Voltage spikes
   - Prevents unclean shutdowns

**Recommended Products:**
- Official Raspberry Pi 5 Power Supply (27W USB-C)
- CanaKit 5.1V 3A USB-C Power Supply
- UPS: CyberPower CP425SLG (500VA) or APC Back-UPS 600VA

## Investigating Unclean Shutdowns

### Pattern Analysis

**Known Unclean Shutdowns:**
- May 17, 2026 23:58
- May 20, 2026 07:11
- May 20, 2026 19:20
- May 22, 2026 06:43
- May 22, 2026 16:59

**Pattern:** No clear time pattern, but recurring events suggest external trigger (power strip, smart plug, physical access).

### Investigation Checklist

1. **Check Power Monitoring Logs** (before each incident):
   ```bash
   grep "2026-05-22 06:4" /mnt/sensor-data/logs/power-monitor.log
   grep "2026-05-22 16:5" /mnt/sensor-data/logs/power-monitor.log
   ```
   - Look for under-voltage warnings
   - Check temperature spikes
   - Verify throttling events

2. **Check Shutdown Event Logs**:
   ```bash
   cat /mnt/sensor-data/logs/shutdown-events.log
   ```
   - If empty for a crash = unclean shutdown (power loss/crash)
   - If logged = intentional shutdown (identify trigger)

3. **Check Network Logs** (correlate with failures):
   ```bash
   grep "2026-05-22 06:4" /mnt/sensor-data/logs/network-monitor.log
   grep "2026-05-22 16:5" /mnt/sensor-data/logs/network-monitor.log
   ```
   - Network issues before crash?
   - Sensor connectivity problems?

4. **Review Daily Health Reports**:
   ```bash
   ls -lh /mnt/sensor-data/logs/reports/
   cat /mnt/sensor-data/logs/reports/health-report-20260522.log
   ```
   - System load before incident
   - Memory pressure
   - Service failures

5. **External Factors to Check**:
   - Smart plug auto-reboot schedule
   - Power strip with timer
   - Building/circuit breaker issues
   - Physical access by others
   - Network router reboots

## Optional: Email/Webhook Alerts

To receive instant alerts for critical issues, edit the monitoring scripts:

### Email Alerts (using `mail` command)
```bash
# Install mail utilities
sudo apt-get install mailutils

# Edit power-monitor.sh
vim /home/omedeiro/soil-sensor/rpi-setup/scripts/power-monitor.sh

# Add to alert() function:
alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  ALERT: $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
    echo "$1" | mail -s "Raspberry Pi Alert" your-email@example.com
}
```

### Slack Alerts (soil moisture, sensor down, system down)

Already implemented — see `docs/guides/SLACK_NOTIFICATIONS.md`:

```bash
cd ~/soil-sensor && ./rpi-setup/install-slack-notifications.sh
```

Use `scripts/send-slack-alert.sh` from any other monitor script rather than
hand-rolling a curl call; it handles severity colours, rate limiting and retries:

```bash
/home/omedeiro/soil-sensor/scripts/send-slack-alert.sh \
    --severity critical --title "Power Alert" \
    --message "Undervoltage detected" --topic power
```

### Webhook Alerts (Discord, other services)
```bash
# Edit power-monitor.sh
vim /home/omedeiro/soil-sensor/rpi-setup/scripts/power-monitor.sh

# Add to alert() function:
alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  ALERT: $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
    curl -X POST "YOUR_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"🚨 Raspberry Pi Alert: $1\"}"
}
```

## Troubleshooting

### Services Not Running
```bash
# Check service status
systemctl status power-monitor.timer
systemctl status network-monitor.timer

# View service logs
journalctl -u power-monitor.timer -f
journalctl -u network-monitor.timer -f

# Restart services
sudo systemctl restart power-monitor.timer
sudo systemctl restart network-monitor.timer
```

### Logs Not Being Written
```bash
# Check log directory permissions
ls -la /mnt/sensor-data/logs/

# Fix permissions if needed
sudo chown -R omedeiro:omedeiro /mnt/sensor-data/logs
sudo chmod 755 /mnt/sensor-data/logs
```

### Script Errors
```bash
# Test scripts manually
/home/omedeiro/soil-sensor/rpi-setup/scripts/power-monitor.sh
/home/omedeiro/soil-sensor/rpi-setup/scripts/network-monitor.sh
/home/omedeiro/soil-sensor/rpi-setup/scripts/daily-health-report.sh

# Check for syntax errors
bash -n /home/omedeiro/soil-sensor/rpi-setup/scripts/power-monitor.sh
```

## Next Steps

1. **Monitor for 1 week** to establish baseline
2. **Review daily health reports** each morning
3. **Correlate alerts** with any system failures
4. **If under-voltage detected**: Upgrade power supply immediately
5. **If no power issues found**: Investigate external factors (smart plug, building power)
6. **Consider UPS installation** for critical protection

## Summary

The enhanced monitoring system provides:
- **Real-time power monitoring** (every 2 minutes)
- **Network health checks** (every 5 minutes)
- **Shutdown event logging** (captures every reboot/shutdown trigger)
- **Daily health reports** (comprehensive system overview)
- **Alert logs** (critical issues separated for quick review)

This should help identify the root cause of recurring unclean shutdowns by providing detailed logs before, during, and after each incident.
