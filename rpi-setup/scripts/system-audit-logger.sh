#!/bin/bash
# System Audit Logger - Comprehensive health and configuration verification
# Catches misconfigurations, missing files, and service issues early
# Runs every 5 minutes and logs critical issues

AUDIT_LOG="/mnt/sensor-data/logs/system-audit.log"
ALERT_LOG="/mnt/sensor-data/logs/system-alerts.log"

# Ensure log files exist
mkdir -p "$(dirname "$AUDIT_LOG")"
touch "$AUDIT_LOG" "$ALERT_LOG"

log_audit() {
    local level=$1
    local category=$2
    local message=$3
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] [$category] $message" >> "$AUDIT_LOG"
}

log_alert() {
    local message=$1
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ALERT: $message" >> "$ALERT_LOG"
    log_audit "ALERT" "SYSTEM" "$message"
}

# Check if InfluxDB data directory is correct
check_influx_data_path() {
    local running_process=$(pgrep -a influxd | grep -o 'engine-path=[^ ]*' | cut -d= -f2)
    local expected_path="/mnt/sensor-data/influxdb/data"
    
    if [ -n "$running_process" ]; then
        if [ "$running_process" != "$expected_path" ]; then
            log_alert "InfluxDB using WRONG data path: $running_process (expected: $expected_path)"
            return 1
        else
            log_audit "INFO" "INFLUX" "Data path correct: $running_process"
        fi
    else
        log_audit "WARN" "INFLUX" "InfluxDB not running - cannot verify data path"
        return 1
    fi
    return 0
}

# Check if InfluxDB startup script exists
check_influx_startup_script() {
    local script_path="/usr/lib/influxdb/scripts/influxd-systemd-start.sh"
    
    if [ ! -f "$script_path" ]; then
        log_alert "InfluxDB startup script MISSING: $script_path"
        return 1
    elif [ ! -x "$script_path" ]; then
        log_alert "InfluxDB startup script NOT EXECUTABLE: $script_path"
        return 1
    else
        log_audit "INFO" "INFLUX" "Startup script exists and is executable"
    fi
    return 0
}

# Check if InfluxDB data exists and size is reasonable
check_influx_data_size() {
    local data_dir="/mnt/sensor-data/influxdb/data"
    local min_expected_size=100000  # 100KB minimum (in bytes)
    
    if [ ! -d "$data_dir" ]; then
        log_alert "InfluxDB data directory MISSING: $data_dir"
        return 1
    fi
    
    local total_size=$(sudo find "$data_dir" -name "*.tsm" -exec du -b {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    
    if [ -z "$total_size" ] || [ "$total_size" -eq 0 ]; then
        log_alert "NO TSM DATA FILES FOUND in $data_dir - database may be empty or corrupted"
        return 1
    elif [ "$total_size" -lt "$min_expected_size" ]; then
        log_alert "InfluxDB data size suspiciously small: ${total_size} bytes (expected >100KB)"
        return 1
    else
        log_audit "INFO" "INFLUX" "Data size: ${total_size} bytes ($(echo "scale=2; $total_size/1024" | bc) KB)"
    fi
    return 0
}

# Check backup configuration
check_backup_config() {
    if [ -z "$INFLUX_ADMIN_TOKEN" ]; then
        # Try to load from environment
        if [ -f /etc/environment ]; then
            export $(grep INFLUX_ADMIN_TOKEN /etc/environment | xargs)
        fi
    fi
    
    if [ -z "$INFLUX_ADMIN_TOKEN" ]; then
        log_alert "INFLUX_ADMIN_TOKEN not set - backups will fail"
        return 1
    else
        log_audit "INFO" "BACKUP" "Admin token configured"
    fi
    return 0
}

# Check for recent successful backups
check_recent_backup() {
    local backup_dir="/mnt/sensor-data/backups"
    local max_age_hours=25  # Should have daily backup within 25 hours
    
    if [ ! -d "$backup_dir" ]; then
        log_alert "Backup directory missing: $backup_dir"
        return 1
    fi
    
    # Find most recent backup file
    local latest_backup=$(find "$backup_dir" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_backup" ]; then
        log_alert "NO BACKUP FILES FOUND in $backup_dir"
        return 1
    fi
    
    local backup_age_seconds=$(( $(date +%s) - $(stat -c %Y "$latest_backup" 2>/dev/null || echo 0) ))
    local backup_age_hours=$(( backup_age_seconds / 3600 ))
    
    if [ "$backup_age_hours" -gt "$max_age_hours" ]; then
        log_alert "Last backup is ${backup_age_hours} hours old: $latest_backup"
        return 1
    else
        log_audit "INFO" "BACKUP" "Recent backup found (${backup_age_hours}h old): $(basename "$latest_backup")"
    fi
    return 0
}

# Check ESP8266 connectivity
check_esp8266_connection() {
    local esp_ip="192.168.99.70"
    local max_age_minutes=10
    
    if ! curl -sf --max-time 3 "http://$esp_ip/api/latest" > /dev/null 2>&1; then
        log_alert "Cannot reach ESP8266 at $esp_ip"
        return 1
    fi
    
    # Check last reading timestamp
    local latest_ts=$(curl -sf --max-time 3 "http://$esp_ip/api/latest" 2>/dev/null | grep -o '"ts":[0-9]*' | cut -d: -f2)
    
    if [ -n "$latest_ts" ]; then
        local now=$(date +%s)
        local age_seconds=$(( now - latest_ts ))
        local age_minutes=$(( age_seconds / 60 ))
        
        if [ "$age_minutes" -gt "$max_age_minutes" ]; then
            log_alert "ESP8266 last reading is ${age_minutes} minutes old (expected <${max_age_minutes} min)"
            return 1
        else
            log_audit "INFO" "ESP8266" "Last reading ${age_minutes} minutes ago"
        fi
    fi
    return 0
}

# Check service health
check_service_health() {
    local service=$1
    local service_name=$2
    
    if ! systemctl is-active --quiet "$service"; then
        log_alert "Service INACTIVE: $service_name ($service)"
        return 1
    else
        # Check if service failed recently
        local failed_count=$(journalctl -u "$service" --since "5 minutes ago" --no-pager 2>/dev/null | grep -c "Failed\|failed\|error" || echo 0)
        if [ "$failed_count" -gt 5 ]; then
            log_alert "Service $service_name has $failed_count errors in last 5 minutes"
            return 1
        else
            log_audit "INFO" "SERVICE" "$service_name is active and healthy"
        fi
    fi
    return 0
}

# Check disk space for critical partitions
check_disk_space() {
    local data_usage=$(df -h /mnt/sensor-data | awk 'NR==2 {print $5}' | sed 's/%//')
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$data_usage" -ge 90 ]; then
        log_alert "Data partition critically full: ${data_usage}%"
        return 1
    elif [ "$data_usage" -ge 80 ]; then
        log_audit "WARN" "DISK" "Data partition filling up: ${data_usage}%"
    else
        log_audit "INFO" "DISK" "Data partition: ${data_usage}%, Root: ${root_usage}%"
    fi
    
    if [ "$root_usage" -ge 90 ]; then
        log_alert "Root partition critically full: ${root_usage}%"
        return 1
    fi
    return 0
}

# Check for filesystem corruption indicators
check_filesystem_health() {
    local dirty_check=$(dmesg | grep -i "filesystem.*dirty\|corruption\|read-only" | tail -1)
    
    if [ -n "$dirty_check" ]; then
        log_alert "Filesystem corruption indicators found: $dirty_check"
        return 1
    fi
    
    # Check if USB drive is mounted read-only
    if mount | grep -q "/mnt/sensor-data.*ro,"; then
        log_alert "Data partition mounted READ-ONLY - filesystem may be corrupted"
        return 1
    fi
    
    log_audit "INFO" "FILESYSTEM" "No corruption indicators detected"
    return 0
}

# Check log rotation is working
check_log_rotation() {
    local health_log="/mnt/sensor-data/logs/health-monitor.log"
    local max_size_mb=50
    
    if [ -f "$health_log" ]; then
        local size_mb=$(du -m "$health_log" 2>/dev/null | cut -f1)
        if [ "$size_mb" -gt "$max_size_mb" ]; then
            log_alert "Log file too large: $health_log (${size_mb}MB, expected <${max_size_mb}MB) - rotation may be failing"
            return 1
        fi
    fi
    
    log_audit "INFO" "LOGGING" "Log rotation appears healthy"
    return 0
}

# Main audit run
log_audit "INFO" "AUDIT" "═══════════════════════════════════════"
log_audit "INFO" "AUDIT" "Starting system audit"

TOTAL_CHECKS=0
FAILED_CHECKS=0

run_check() {
    local check_name=$1
    shift
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if ! "$@"; then
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        log_audit "FAIL" "CHECK" "$check_name"
    else
        log_audit "PASS" "CHECK" "$check_name"
    fi
}

# Run all checks
run_check "InfluxDB startup script exists" check_influx_startup_script
run_check "InfluxDB data path correct" check_influx_data_path
run_check "InfluxDB data size reasonable" check_influx_data_size
run_check "Backup configuration valid" check_backup_config
run_check "Recent backup exists" check_recent_backup
run_check "ESP8266 connectivity" check_esp8266_connection
run_check "InfluxDB service health" check_service_health "influxdb" "InfluxDB"
run_check "Grafana service health" check_service_health "grafana-server" "Grafana"
run_check "Disk space healthy" check_disk_space
run_check "Filesystem healthy" check_filesystem_health
run_check "Log rotation working" check_log_rotation

# Summary
log_audit "INFO" "AUDIT" "Audit complete: $TOTAL_CHECKS checks, $FAILED_CHECKS failed"

if [ "$FAILED_CHECKS" -gt 0 ]; then
    log_alert "System audit found $FAILED_CHECKS issues - review $AUDIT_LOG for details"
    exit 1
else
    log_audit "INFO" "AUDIT" "All checks passed ✓"
    exit 0
fi
