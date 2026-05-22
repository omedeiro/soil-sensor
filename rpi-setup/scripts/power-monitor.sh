#!/bin/bash
#
# Power Monitoring Script for Raspberry Pi 5
# Monitors voltage, throttling events, temperature, and power issues
# Logs to /mnt/sensor-data/logs/power-monitor.log
#

LOG_FILE="/mnt/sensor-data/logs/power-monitor.log"
ALERT_FILE="/mnt/sensor-data/logs/power-alerts.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  ALERT: $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

# Get throttling status
# Bits in throttled value:
# Bit 0: Under-voltage detected
# Bit 1: Arm frequency capped
# Bit 2: Currently throttled
# Bit 3: Soft temperature limit active
# Bit 16: Under-voltage has occurred
# Bit 17: Arm frequency capping has occurred
# Bit 18: Throttling has occurred
# Bit 19: Soft temperature limit has occurred
get_throttle_status() {
    local throttled=$(vcgencmd get_throttled | cut -d= -f2)
    echo "$throttled"
}

decode_throttle() {
    local value=$1
    local decimal=$((value))
    local issues=""
    
    # Current issues
    if (( decimal & 0x1 )); then
        issues+="CURRENT: Under-voltage detected! "
    fi
    if (( decimal & 0x2 )); then
        issues+="CURRENT: ARM frequency capped! "
    fi
    if (( decimal & 0x4 )); then
        issues+="CURRENT: Throttling active! "
    fi
    if (( decimal & 0x8 )); then
        issues+="CURRENT: Soft temp limit! "
    fi
    
    # Historical issues
    if (( decimal & 0x10000 )); then
        issues+="HISTORY: Under-voltage occurred. "
    fi
    if (( decimal & 0x20000 )); then
        issues+="HISTORY: ARM freq capping occurred. "
    fi
    if (( decimal & 0x40000 )); then
        issues+="HISTORY: Throttling occurred. "
    fi
    if (( decimal & 0x80000 )); then
        issues+="HISTORY: Soft temp limit occurred. "
    fi
    
    if [ -z "$issues" ]; then
        echo "OK"
    else
        echo "$issues"
    fi
}

# Get system metrics
get_temp() {
    vcgencmd measure_temp | cut -d= -f2 | cut -d\' -f1
}

get_voltage() {
    vcgencmd measure_volts core | cut -d= -f2 | cut -dV -f1
}

get_clock() {
    vcgencmd measure_clock arm | cut -d= -f2
}

get_mem() {
    vcgencmd get_mem arm | cut -d= -f2
}

# Check for critical power issues
check_power_critical() {
    local throttled=$1
    local decimal=$((throttled))
    
    # Check for current under-voltage (bit 0)
    if (( decimal & 0x1 )); then
        alert "CRITICAL: Under-voltage detected! Power supply insufficient!"
        alert "Action required: Replace power supply with 5V 3A+ adapter"
        return 1
    fi
    
    # Check for current throttling (bit 2)
    if (( decimal & 0x4 )); then
        alert "WARNING: System throttling active (insufficient power or overheating)"
        return 1
    fi
    
    return 0
}

# Main monitoring loop
log "=== Power Monitor Started ==="
log "Power supply: 5V 2A (connected to power strip)"
log "Monitoring for power issues, throttling, and temperature..."

# Get baseline
throttled=$(get_throttle_status)
temp=$(get_temp)
voltage=$(get_voltage)
clock=$(get_clock)
mem=$(get_mem)

log "Initial state:"
log "  Throttle status: $throttled"
log "  Temperature: ${temp}°C"
log "  Core voltage: ${voltage}V"
log "  ARM clock: $clock Hz"
log "  ARM memory: $mem"

throttle_decoded=$(decode_throttle "$throttled")
if [ "$throttle_decoded" != "OK" ]; then
    alert "Throttle issues detected: $throttle_decoded"
    check_power_critical "$throttled"
else
    log "  Status: ${GREEN}All systems nominal${NC}"
fi

# Log uptime and last boot
uptime_val=$(uptime -p)
last_boot=$(who -b | awk '{print $3, $4}')
log "System uptime: $uptime_val (booted: $last_boot)"

# Check for unclean shutdown indicators
if journalctl -b -1 --no-pager | grep -q "not unmounting"; then
    alert "Previous boot had unclean shutdown detected in journal"
fi

# Monitor continuously (called by systemd timer every 2 minutes)
# Just do a single check per invocation
