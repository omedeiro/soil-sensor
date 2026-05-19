#!/bin/bash
# Startup Logger - Tracks system boot reasons and health
# Runs once at boot to log why the system started

STARTUP_LOG="/mnt/sensor-data/logs/startup_history.log"
UPTIME_THRESHOLD=300  # 5 minutes - if last boot was < 5 min ago, it was a crash

log_startup() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local boot_time=$(who -b | awk '{print $3, $4}')
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    
    # Get last shutdown reason from journal
    local last_shutdown=$(journalctl -b -1 --no-pager 2>/dev/null | tail -20 | grep -E "(shutdown|reboot|power|stopped|halted)" | tail -1)
    
    # Check if filesystem was dirty (improper shutdown)
    local fs_dirty=$(journalctl -b 0 --no-pager | grep -i "dirty bit" | head -1)
    
    # Check previous boot time
    local prev_boot=$(journalctl --list-boots --no-pager | awk 'NR==2 {print $5, $6}')
    
    echo "================================================================" >> "$STARTUP_LOG"
    echo "BOOT EVENT: $timestamp" >> "$STARTUP_LOG"
    echo "----------------------------------------------------------------" >> "$STARTUP_LOG"
    echo "Boot Time: $boot_time" >> "$STARTUP_LOG"
    echo "System Uptime: ${uptime_seconds}s" >> "$STARTUP_LOG"
    
    if [ -n "$prev_boot" ]; then
        echo "Previous Boot: $prev_boot" >> "$STARTUP_LOG"
    fi
    
    # Determine boot reason
    if [ -n "$fs_dirty" ]; then
        echo "Boot Reason: UNCLEAN SHUTDOWN - Filesystem corruption detected" >> "$STARTUP_LOG"
        echo "Details: $fs_dirty" >> "$STARTUP_LOG"
    elif echo "$last_shutdown" | grep -iq "reboot"; then
        echo "Boot Reason: CLEAN REBOOT" >> "$STARTUP_LOG"
        echo "Details: $last_shutdown" >> "$STARTUP_LOG"
    elif echo "$last_shutdown" | grep -iq "shutdown"; then
        echo "Boot Reason: CLEAN SHUTDOWN" >> "$STARTUP_LOG"
        echo "Details: $last_shutdown" >> "$STARTUP_LOG"
    elif echo "$last_shutdown" | grep -iq "power"; then
        echo "Boot Reason: POWER EVENT" >> "$STARTUP_LOG"
        echo "Details: $last_shutdown" >> "$STARTUP_LOG"
    else
        echo "Boot Reason: UNKNOWN - Possible crash or power loss" >> "$STARTUP_LOG"
        if [ -n "$last_shutdown" ]; then
            echo "Last Event: $last_shutdown" >> "$STARTUP_LOG"
        fi
    fi
    
    # Check for kernel panics
    local panic=$(journalctl -b -1 --no-pager 2>/dev/null | grep -i "kernel panic" | head -1)
    if [ -n "$panic" ]; then
        echo "KERNEL PANIC DETECTED: $panic" >> "$STARTUP_LOG"
    fi
    
    # Check system temperature
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp=$((temp / 1000))
        echo "CPU Temperature at boot: ${temp}°C" >> "$STARTUP_LOG"
    fi
    
    # Check USB drive mount status
    if mountpoint -q /mnt/sensor-data; then
        local mount_time=$(stat -c %Y /mnt/sensor-data 2>/dev/null)
        echo "USB Drive: MOUNTED at /mnt/sensor-data" >> "$STARTUP_LOG"
    else
        echo "USB Drive: NOT MOUNTED - CRITICAL" >> "$STARTUP_LOG"
    fi
    
    # Check services
    echo "Service Status:" >> "$STARTUP_LOG"
    systemctl is-active influxdb >/dev/null 2>&1 && echo "  ✓ InfluxDB: Active" >> "$STARTUP_LOG" || echo "  ✗ InfluxDB: Inactive" >> "$STARTUP_LOG"
    systemctl is-active grafana-server >/dev/null 2>&1 && echo "  ✓ Grafana: Active" >> "$STARTUP_LOG" || echo "  ✗ Grafana: Inactive" >> "$STARTUP_LOG"
    systemctl is-active sensor-health-monitor >/dev/null 2>&1 && echo "  ✓ Health Monitor: Active" >> "$STARTUP_LOG" || echo "  ✗ Health Monitor: Inactive" >> "$STARTUP_LOG"
    
    echo "================================================================" >> "$STARTUP_LOG"
    echo "" >> "$STARTUP_LOG"
}

# Ensure log directory exists
mkdir -p "$(dirname "$STARTUP_LOG")"

# Wait for system to stabilize
sleep 10

# Log the startup
log_startup

# Also send to syslog
logger -t startup-logger "System boot logged to $STARTUP_LOG"
