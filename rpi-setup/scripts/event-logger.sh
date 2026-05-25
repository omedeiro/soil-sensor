#!/bin/bash
#
# System Event Logger - Captures all shutdown/reboot triggers
# Logs every time the system prepares to shutdown or reboot
# Helps identify what triggered unclean shutdowns
#

LOG_FILE="/mnt/sensor-data/logs/system-events.log"
SHUTDOWN_LOG="/mnt/sensor-data/logs/shutdown-events.log"
mkdir -p "$(dirname "$LOG_FILE")"

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_shutdown() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SHUTDOWN_LOG"
}

# Capture what triggered this event
TRIGGER="${1:-manual}"
PID="$$"
PPID="$(ps -o ppid= -p $$ | xargs)"
PARENT_CMD="$(ps -o cmd= -p $PPID 2>/dev/null || echo 'unknown')"

log_event "=== System Event Triggered ==="
log_event "Trigger: $TRIGGER"
log_event "PID: $PID, Parent PID: $PPID"
log_event "Parent command: $PARENT_CMD"
log_event "User: $(whoami)"
log_event "TTY: $(tty 2>/dev/null || echo 'none')"

# Log who is logged in
log_event "Active users:"
who | while read line; do
    log_event "  $line"
done

# Check for scheduled tasks
log_event "Checking for scheduled shutdowns/reboots..."
if systemctl list-timers --all | grep -E "(shutdown|reboot)"; then
    log_event "Found scheduled shutdown/reboot timers:"
    systemctl list-timers --all | grep -E "(shutdown|reboot)" | while read line; do
        log_event "  $line"
    done
else
    log_event "No scheduled shutdown/reboot timers found"
fi

# Check systemd shutdown reason
if systemctl is-system-running --quiet; then
    log_event "System state: $(systemctl is-system-running)"
else
    log_event "System state: $(systemctl is-system-running || true)"
fi

# Log current system load
log_event "System load: $(uptime)"
log_event "Memory usage: $(free -h | grep Mem | awk '{print $3 "/" $2 " used"}')"
log_event "Disk usage: $(df -h /mnt/sensor-data | tail -1 | awk '{print $3 "/" $2 " used (" $5 ")"}')"

# Check for critical service failures that might trigger reboot
log_event "Checking critical services..."
for service in influxdb grafana-server cloudflared; do
    if systemctl is-active --quiet "$service"; then
        log_event "  $service: active"
    else
        log_event "  $service: FAILED/INACTIVE"
    fi
done

# If this is a shutdown/reboot, log it specially
case "$TRIGGER" in
    shutdown|poweroff|halt)
        log_shutdown "=== SHUTDOWN INITIATED ==="
        log_shutdown "Reason: $TRIGGER"
        log_shutdown "Parent: $PARENT_CMD"
        log_shutdown "User: $(whoami)"
        ;;
    reboot|restart)
        log_shutdown "=== REBOOT INITIATED ==="
        log_shutdown "Reason: $TRIGGER"
        log_shutdown "Parent: $PARENT_CMD"
        log_shutdown "User: $(whoami)"
        ;;
esac

log_event "=== Event logging complete ==="
