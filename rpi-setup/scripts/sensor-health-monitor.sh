#!/bin/bash
# Enhanced Health Monitor for Soil Sensor System
# Monitors InfluxDB, Grafana, and system resources
# Auto-restarts services and triggers reboot on critical failure

LOG_FILE="/mnt/sensor-data/logs/health-monitor.log"
REBOOT_LOG="/mnt/sensor-data/logs/reboot_reasons.log"
INFLUX_URL="http://localhost:8086/health"
GRAFANA_URL="http://localhost:3000/api/health"
CHECK_INTERVAL=60  # seconds

# Thresholds
DISK_WARN_THRESHOLD=90
RAM_WARN_THRESHOLD=100  # MB free
CPU_TEMP_WARN_THRESHOLD=70  # Celsius
MAX_CONSECUTIVE_FAILURES=3
REBOOT_COOLDOWN=86400  # 24 hours in seconds

# State file for tracking failures
STATE_FILE="/var/run/health-monitor-state"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize state
init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "0" > "$STATE_FILE"  # consecutive_failures
        echo "0" >> "$STATE_FILE"  # last_reboot_time
    fi
}

get_consecutive_failures() {
    head -1 "$STATE_FILE"
}

get_last_reboot_time() {
    tail -1 "$STATE_FILE"
}

set_consecutive_failures() {
    local failures=$1
    local last_reboot=$(get_last_reboot_time)
    echo "$failures" > "$STATE_FILE"
    echo "$last_reboot" >> "$STATE_FILE"
}

set_last_reboot_time() {
    local failures=$(get_consecutive_failures)
    local now=$(date +%s)
    echo "$failures" > "$STATE_FILE"
    echo "$now" >> "$STATE_FILE"
}

check_service() {
    local service_name=$1
    local health_url=$2
    local systemd_service=$3
    
    if curl -sf --max-time 5 "$health_url" > /dev/null 2>&1; then
        return 0  # Healthy
    else
        log "✗ $service_name is unhealthy - restarting $systemd_service"
        sudo systemctl restart "$systemd_service"
        sleep 10
        
        # Check again after restart
        if curl -sf --max-time 5 "$health_url" > /dev/null 2>&1; then
            log "✓ $service_name recovered after restart"
            return 0
        else
            log "✗ $service_name still unhealthy after restart"
            return 1
        fi
    fi
}

check_disk_space() {
    local usage=$(df -h /mnt/sensor-data | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -ge "$DISK_WARN_THRESHOLD" ]; then
        log "⚠️  DISK WARNING: /mnt/sensor-data is ${usage}% full (threshold: ${DISK_WARN_THRESHOLD}%)"
        return 1
    fi
    return 0
}

check_memory() {
    local free_mb=$(free -m | awk 'NR==2 {print $7}')
    
    if [ "$free_mb" -le "$RAM_WARN_THRESHOLD" ]; then
        log "⚠️  MEMORY WARNING: Only ${free_mb}MB free (threshold: ${RAM_WARN_THRESHOLD}MB)"
        return 1
    fi
    return 0
}

check_cpu_temp() {
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp=$((temp / 1000))
        
        if [ "$temp" -ge "$CPU_TEMP_WARN_THRESHOLD" ]; then
            log "⚠️  CPU TEMPERATURE WARNING: ${temp}°C (threshold: ${CPU_TEMP_WARN_THRESHOLD}°C)"
            return 1
        fi
    fi
    return 0
}

trigger_reboot() {
    local reason=$1
    local last_reboot=$(get_last_reboot_time)
    local now=$(date +%s)
    local elapsed=$((now - last_reboot))
    
    # Check cooldown period
    if [ "$elapsed" -lt "$REBOOT_COOLDOWN" ]; then
        local remaining=$((REBOOT_COOLDOWN - elapsed))
        log "⏳ Reboot requested but in cooldown period (${remaining}s remaining)"
        return 1
    fi
    
    # Log reboot reason
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] REBOOT TRIGGERED: $reason" >> "$REBOOT_LOG"
    log "🚨 TRIGGERING SYSTEM REBOOT: $reason"
    
    # Update last reboot time
    set_last_reboot_time
    
    # Trigger reboot
    sleep 5
    sudo /sbin/reboot
}

# Main loop
log "═══════════════════════════════════════"
log "Enhanced Health Monitor Started"
log "  Disk threshold: ${DISK_WARN_THRESHOLD}%"
log "  RAM threshold: ${RAM_WARN_THRESHOLD}MB free"
log "  CPU temp threshold: ${CPU_TEMP_WARN_THRESHOLD}°C"
log "  Max consecutive failures: ${MAX_CONSECUTIVE_FAILURES}"
log "═══════════════════════════════════════"

init_state

while true; do
    FAILURES=0
    
    # Check InfluxDB
    if check_service "InfluxDB" "$INFLUX_URL" "influxdb"; then
        : # Success
    else
        FAILURES=$((FAILURES + 1))
    fi
    
    sleep 5
    
    # Check Grafana
    if check_service "Grafana" "$GRAFANA_URL" "grafana-server"; then
        : # Success
    else
        FAILURES=$((FAILURES + 1))
    fi
    
    # Check system resources
    check_disk_space || FAILURES=$((FAILURES + 1))
    check_memory || FAILURES=$((FAILURES + 1))
    check_cpu_temp || FAILURES=$((FAILURES + 1))
    
    # Update consecutive failure counter
    if [ "$FAILURES" -gt 0 ]; then
        CONSECUTIVE=$(get_consecutive_failures)
        CONSECUTIVE=$((CONSECUTIVE + 1))
        set_consecutive_failures "$CONSECUTIVE"
        
        log "⚠️  Health check failed ($FAILURES issues, $CONSECUTIVE consecutive)"
        
        # Check if we need to trigger reboot
        if [ "$CONSECUTIVE" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
            trigger_reboot "Multiple consecutive health check failures ($CONSECUTIVE)"
            # If reboot is in cooldown, reset counter to avoid spam
            set_consecutive_failures 0
        fi
    else
        # Reset counter on success
        set_consecutive_failures 0
    fi
    
    sleep $((CHECK_INTERVAL - 5))
done
