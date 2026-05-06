#!/bin/bash
# Health Monitor for Soil Sensor System
# Monitors InfluxDB and Grafana, restarts if unhealthy

LOG_FILE="/mnt/sensor-data/logs/health-monitor.log"
INFLUX_URL="http://localhost:8086/health"
GRAFANA_URL="http://localhost:3000/api/health"
CHECK_INTERVAL=60  # seconds

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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
            log "✗ $service_name still unhealthy after restart - may need manual intervention"
            return 1
        fi
    fi
}

# Main loop
log "═══════════════════════════════════════"
log "Health Monitor Started"
log "═══════════════════════════════════════"

CONSECUTIVE_FAILURES=0

while true; do
    # Check InfluxDB
    if check_service "InfluxDB" "$INFLUX_URL" "influxdb"; then
        : # Success, no action
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    fi
    
    sleep 5
    
    # Check Grafana
    if check_service "Grafana" "$GRAFANA_URL" "grafana-server"; then
        CONSECUTIVE_FAILURES=0  # Reset on success
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    fi
    
    # If too many consecutive failures, log critical alert
    if [ $CONSECUTIVE_FAILURES -ge 5 ]; then
        log "🚨 CRITICAL: Multiple consecutive failures detected!"
        log "   Check system resources, disk space, and logs"
        CONSECUTIVE_FAILURES=0  # Reset to avoid spam
    fi
    
    sleep $((CHECK_INTERVAL - 5))
done
