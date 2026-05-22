#!/bin/bash
#
# Storage Health Monitor
# Monitors USB drive health, write cache, I/O errors, and mount status
# Logs to /mnt/sensor-data/logs/storage-monitor.log
#

LOG_FILE="/mnt/sensor-data/logs/storage-monitor.log"
ALERT_FILE="/mnt/sensor-data/logs/storage-alerts.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

critical() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔴 CRITICAL: $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

log "=== Storage Health Check ==="

# Check if USB drive is mounted
if ! mountpoint -q /mnt/sensor-data; then
    critical "USB drive NOT MOUNTED at /mnt/sensor-data!"
    exit 1
fi

log "✓ USB drive mounted at /mnt/sensor-data"

# Get device information
DEVICE="/dev/sda1"
DEVICE_BASE="/dev/sda"

# Check USB connection speed
USB_SPEED=$(lsusb -t | grep "Mass Storage" | grep -oP '\d+M')
log "USB connection speed: $USB_SPEED"

if [[ "$USB_SPEED" == "480M" ]]; then
    alert "USB drive connected at USB 2.0 speed (480M) - should be USB 3.0 (5000M)"
    alert "Recommendation: Move USB drive to blue USB 3.0 port for better performance"
elif [[ "$USB_SPEED" == "5000M" ]]; then
    log "✓ USB drive at USB 3.0 speed (optimal)"
fi

# Check filesystem errors in dmesg
ERROR_COUNT=$(dmesg | grep -c "EXT4-fs error")
if [ "$ERROR_COUNT" -gt 0 ]; then
    critical "Found $ERROR_COUNT EXT4 filesystem errors in kernel log!"
    log "Recent EXT4 errors:"
    dmesg | grep "EXT4-fs error" | tail -5 | while read line; do
        log "  $line"
    done
else
    log "✓ No EXT4 filesystem errors detected"
fi

# Check for I/O errors
IO_ERROR_COUNT=$(dmesg | grep -iE "(I/O error|Buffer I/O error)" | grep sda | wc -l)
if [ "$IO_ERROR_COUNT" -gt 0 ]; then
    critical "Found $IO_ERROR_COUNT I/O errors on USB drive!"
    log "Recent I/O errors:"
    dmesg | grep -iE "(I/O error|Buffer I/O error)" | grep sda | tail -5 | while read line; do
        log "  $line"
    done
else
    log "✓ No I/O errors detected"
fi

# Check USB disconnect/reconnect events
USB_RESET_COUNT=$(dmesg | grep -iE "(usb.*reset|device not accepting address)" | wc -l)
if [ "$USB_RESET_COUNT" -gt 0 ]; then
    alert "Found $USB_RESET_COUNT USB reset/disconnect events"
    log "This could indicate:"
    log "  - Loose USB connection"
    log "  - Power issues to USB port"
    log "  - Failing USB drive"
else
    log "✓ No USB disconnect events"
fi

# Check disk space
DISK_USAGE=$(df -h /mnt/sensor-data | tail -1 | awk '{print $5}' | tr -d '%')
DISK_AVAIL=$(df -h /mnt/sensor-data | tail -1 | awk '{print $4}')
log "Disk usage: ${DISK_USAGE}% (${DISK_AVAIL} available)"

if [ "$DISK_USAGE" -gt 90 ]; then
    critical "Disk usage above 90%! Risk of write failures and corruption."
elif [ "$DISK_USAGE" -gt 80 ]; then
    alert "Disk usage above 80% - consider cleanup"
fi

# Check inode usage
INODE_USAGE=$(df -i /mnt/sensor-data | tail -1 | awk '{print $5}' | tr -d '%')
log "Inode usage: ${INODE_USAGE}%"

if [ "$INODE_USAGE" -gt 80 ]; then
    alert "Inode usage above 80%! Too many small files."
fi

# Check mount options
MOUNT_OPTS=$(mount | grep sda1 | grep -oP '\(.*\)' | tr -d '()')
log "Mount options: $MOUNT_OPTS"

# Verify noatime is set (reduces writes)
if echo "$MOUNT_OPTS" | grep -q "noatime"; then
    log "✓ noatime enabled (optimal for flash drives)"
else
    alert "noatime NOT enabled - unnecessary writes to USB drive"
fi

# Check I/O scheduler
IO_SCHEDULER=$(cat /sys/block/sda/queue/scheduler | grep -oP '\[.*?\]' | tr -d '[]')
log "I/O scheduler: $IO_SCHEDULER"

if [[ "$IO_SCHEDULER" != "none" && "$IO_SCHEDULER" != "mq-deadline" ]]; then
    alert "I/O scheduler is '$IO_SCHEDULER' - 'mq-deadline' or 'none' recommended for flash drives"
fi

# Check read-ahead settings
READAHEAD=$(blockdev --getra "$DEVICE_BASE" 2>/dev/null || echo "unknown")
log "Read-ahead: $READAHEAD KB"

# Check write cache status
WRITE_CACHE=$(cat /sys/block/sda/device/scsi_disk/*/cache_type 2>/dev/null | awk '{print $1}' || echo "unknown")
log "Write cache: $WRITE_CACHE"

if [[ "$WRITE_CACHE" == "write back" ]]; then
    critical "Write cache mode is 'write back' - HIGH RISK of data loss on power failure!"
    critical "Data may still be in drive's internal cache during unclean shutdown"
    critical "Recommendation: Disable write cache or use UPS"
elif [[ "$WRITE_CACHE" == "write through" ]]; then
    log "✓ Write cache mode is 'write through' (safer for power failures)"
else
    log "Write cache mode: $WRITE_CACHE"
fi

# Check recent write activity
if [ -f "/sys/block/sda/stat" ]; then
    # Format: reads, reads_merged, sectors_read, time_reading, writes, writes_merged, sectors_written, time_writing, ...
    STATS=($(cat /sys/block/sda/stat))
    WRITES=${STATS[4]}
    SECTORS_WRITTEN=${STATS[6]}
    WRITE_TIME=${STATS[7]}
    
    # Calculate MB written (sectors are 512 bytes)
    MB_WRITTEN=$((SECTORS_WRITTEN * 512 / 1024 / 1024))
    
    log "Lifetime writes: $WRITES operations, $MB_WRITTEN MB total"
    log "Write time: ${WRITE_TIME}ms total"
    
    # Store for next run to calculate rate
    echo "$WRITES $MB_WRITTEN $WRITE_TIME $(date +%s)" > /tmp/storage-monitor-stats
fi

# Check for files being written right now
OPEN_FILES=$(lsof +D /mnt/sensor-data 2>/dev/null | grep -v "COMMAND" | wc -l)
log "Currently open files: $OPEN_FILES"

if [ "$OPEN_FILES" -gt 100 ]; then
    alert "High number of open files ($OPEN_FILES) - potential resource leak"
fi

# Check InfluxDB write activity specifically
INFLUXDB_WRITES=$(lsof +D /mnt/sensor-data/influxdb 2>/dev/null | grep influxd | wc -l)
log "InfluxDB open files: $INFLUXDB_WRITES"

# Check for pending writes in cache
DIRTY_KB=$(grep "^Dirty:" /proc/meminfo | awk '{print $2}')
WRITEBACK_KB=$(grep "^Writeback:" /proc/meminfo | awk '{print $2}')
DIRTY_MB=$((DIRTY_KB / 1024))
WRITEBACK_MB=$((WRITEBACK_KB / 1024))

log "Dirty cache (pending writes): ${DIRTY_MB} MB"
log "Writeback in progress: ${WRITEBACK_MB} MB"

if [ "$DIRTY_MB" -gt 100 ]; then
    alert "Large amount of dirty cache (${DIRTY_MB} MB) - writes delayed"
    alert "Risk of data loss if power fails before flush completes"
fi

# Check filesystem health (requires root, may fail)
FS_STATUS=$(tune2fs -l "$DEVICE" 2>/dev/null | grep "Filesystem state" | cut -d: -f2 | xargs || echo "unknown")
log "Filesystem state: $FS_STATUS"

if [[ "$FS_STATUS" == "not clean" ]]; then
    critical "Filesystem state is NOT CLEAN - previous unclean shutdown detected!"
fi

# Check last fsck
LAST_FSCK=$(tune2fs -l "$DEVICE" 2>/dev/null | grep "Last checked" | cut -d: -f2- | xargs || echo "unknown")
log "Last fsck: $LAST_FSCK"

# Summary and recommendations
log ""
log "=== Recommendations ==="

ISSUES_FOUND=0

if [[ "$USB_SPEED" == "480M" ]]; then
    log "1. Move USB drive to USB 3.0 port (blue port) for 10x faster speeds"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [[ "$WRITE_CACHE" == "write back" ]]; then
    log "2. CRITICAL: Install UPS or disable write cache to prevent data loss"
    log "   Command: hdparm -W 0 $DEVICE_BASE (disables write cache)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ "$DISK_USAGE" -gt 80 ]; then
    log "3. Free up disk space - currently at ${DISK_USAGE}%"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ "$ERROR_COUNT" -gt 0 ] || [ "$IO_ERROR_COUNT" -gt 0 ]; then
    log "4. CRITICAL: Filesystem/I/O errors detected - consider replacing USB drive"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ "$ISSUES_FOUND" -eq 0 ]; then
    log "✅ No critical storage issues detected"
else
    alert "Found $ISSUES_FOUND storage issues requiring attention"
fi

log "=== Storage check complete ==="
