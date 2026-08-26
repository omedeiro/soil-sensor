#!/bin/bash
# Comprehensive System Health Monitor
# Checks InfluxDB, Grafana, filesystem health, and auto-recovers when possible

LOG_FILE="/mnt/sensor-data/logs/system-health.log"
ALERT_LOG="/mnt/sensor-data/logs/system-alerts.log"
# InfluxDB token. Never hardcode it: this file is tracked, and a literal here
# ends up in git history permanently. Resolution order mirrors the other
# scripts in this repo.
CONFIG_DIR="${CONFIG_DIR:-/mnt/sensor-data/config}"
if [ -z "${INFLUX_TOKEN:-}" ] && [ -r "$CONFIG_DIR/panel-health.env" ]; then
    INFLUX_TOKEN="$(grep -m1 '^INFLUX_TOKEN=' "$CONFIG_DIR/panel-health.env" | cut -d= -f2- | tr -d '"'"'"'')"
fi
[ -n "${INFLUX_TOKEN:-}" ] || { echo "INFLUX_TOKEN not set and not found in $CONFIG_DIR/panel-health.env" >&2; exit 3; }

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1" | tee -a "$ALERT_LOG" "$LOG_FILE"
}

check_influxdb() {
    if ! systemctl is-active --quiet influxdb; then
        alert "InfluxDB is not running!"
        
        # Check if it's in failed state
        if systemctl is-failed --quiet influxdb; then
            alert "InfluxDB is in failed state - attempting auto-recovery"
            
            # Log failure details
            journalctl -u influxdb -n 50 --no-pager >> "$ALERT_LOG"
            
            # Attempt restart
            systemctl reset-failed influxdb
            systemctl start influxdb
            sleep 5
            
            if systemctl is-active --quiet influxdb; then
                log "✓ InfluxDB auto-recovery successful"
                return 0
            else
                alert "✗ InfluxDB auto-recovery failed - manual intervention required"
                alert "Run: sudo /home/omedeiro/soil-sensor/rpi-setup/scripts/recover-influxdb.sh"
                return 1
            fi
        else
            # Try simple start
            systemctl start influxdb
            sleep 3
            if systemctl is-active --quiet influxdb; then
                log "✓ InfluxDB started successfully"
                return 0
            fi
        fi
        return 1
    else
        # Check HTTP health
        if ! curl -sf http://localhost:8086/health > /dev/null 2>&1; then
            alert "InfluxDB is running but HTTP health check failed"
            return 1
        fi
        log "✓ InfluxDB is healthy"
        return 0
    fi
}

check_grafana() {
    if ! systemctl is-active --quiet grafana-server; then
        alert "Grafana is not running - attempting restart"
        systemctl start grafana-server
        sleep 3
        if systemctl is-active --quiet grafana-server; then
            log "✓ Grafana restarted successfully"
        else
            alert "✗ Grafana restart failed"
            return 1
        fi
    else
        # Check HTTP health
        if ! curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
            alert "Grafana is running but HTTP health check failed"
            return 1
        fi
        log "✓ Grafana is healthy"
    fi
    return 0
}

check_filesystem() {
    # Check for filesystem errors in dmesg
    FS_ERRORS=$(dmesg | grep -i "ext4-fs error" | tail -5)
    if [ -n "$FS_ERRORS" ]; then
        alert "Filesystem errors detected in kernel log"
        echo "$FS_ERRORS" >> "$ALERT_LOG"
    fi
    
    # Check USB drive mount
    if ! mountpoint -q /mnt/sensor-data; then
        alert "USB drive not mounted at /mnt/sensor-data"
        return 1
    fi
    
    # Check disk space
    DISK_USAGE=$(df -h /mnt/sensor-data | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        alert "Disk usage critical: ${DISK_USAGE}%"
    elif [ "$DISK_USAGE" -gt 80 ]; then
        log "Warning: Disk usage high: ${DISK_USAGE}%"
    fi
    
    log "✓ Filesystem healthy (${DISK_USAGE}% used)"
    return 0
}

check_sensors() {
    # Check if sensors are posting data (within last 15 minutes)
    SENSOR_COUNT=$(curl -s -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
        -H "Authorization: Token ${INFLUX_TOKEN}" \
        -H "Content-Type: application/vnd.flux" \
        -d 'from(bucket: "sensor-readings")
            |> range(start: -15m)
            |> filter(fn: (r) => r._measurement == "sensor_reading")
            |> filter(fn: (r) => r._field == "moisture")
            |> group(columns: ["device_id"])
            |> count()
            |> group()
            |> count()' 2>/dev/null | grep -c "_value" || echo "0")
    
    if [ "$SENSOR_COUNT" -lt 4 ]; then
        alert "Only $SENSOR_COUNT/4 sensors posting data in last 15 minutes"
    else
        log "✓ All sensors posting data ($SENSOR_COUNT active)"
    fi
}

check_memory() {
    FREE_MEM=$(free -m | awk 'NR==2{print $7}')
    if [ "$FREE_MEM" -lt 500 ]; then
        alert "Low memory: ${FREE_MEM}MB available"
    fi
}

check_temperature() {
    TEMP=$(vcgencmd measure_temp | sed 's/temp=//' | sed 's/°C//')
    TEMP_INT=${TEMP%.*}
    if [ "$TEMP_INT" -gt 80 ]; then
        alert "CPU temperature critical: ${TEMP}°C"
    elif [ "$TEMP_INT" -gt 70 ]; then
        log "Warning: CPU temperature high: ${TEMP}°C"
    fi
}

# Main health check
log "========================================="
log "System Health Check Starting"

check_filesystem
check_memory
check_temperature
check_influxdb
INFLUX_OK=$?
check_grafana
check_sensors

log "System Health Check Complete"
log "========================================="

exit $INFLUX_OK
