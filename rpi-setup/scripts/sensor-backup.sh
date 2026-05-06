#!/bin/bash
# Backup Script for Soil Sensor System
# Backs up InfluxDB data and exports to CSV

BACKUP_DIR="/mnt/sensor-data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
INFLUX_ORG="soil-monitoring"
INFLUX_BUCKET="sensor-readings"

# NOTE: You must set this token after InfluxDB setup!
# Get it from InfluxDB UI: Settings → Tokens → Generate (All Access Token)
INFLUX_TOKEN="${INFLUX_ADMIN_TOKEN:-}"

if [ -z "$INFLUX_TOKEN" ]; then
    echo "[$(date)] ERROR: INFLUX_ADMIN_TOKEN not set"
    echo "Set it in /etc/environment or edit this script"
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "═══════════════════════════════════════"
log "Starting InfluxDB Backup"
log "═══════════════════════════════════════"

# Backup InfluxDB native format
log "Creating InfluxDB backup..."
if influx backup "$BACKUP_DIR/influx_$TIMESTAMP" \
    --host http://localhost:8086 \
    --org "$INFLUX_ORG" \
    --token "$INFLUX_TOKEN" 2>&1; then
    log "✓ InfluxDB backup successful: $BACKUP_DIR/influx_$TIMESTAMP"
else
    log "✗ InfluxDB backup failed"
fi

# Export to CSV for portability
log "Exporting last 30 days to CSV..."
if influx query \
    --host http://localhost:8086 \
    --org "$INFLUX_ORG" \
    --token "$INFLUX_TOKEN" \
    "from(bucket: \"$INFLUX_BUCKET\") 
     |> range(start: -30d) 
     |> pivot(rowKey:[\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")" \
    --raw > "$BACKUP_DIR/export_$TIMESTAMP.csv" 2>&1; then
    log "✓ CSV export successful: $BACKUP_DIR/export_$TIMESTAMP.csv"
else
    log "✗ CSV export failed (may be normal if no data exists yet)"
fi

# Cleanup old backups (keep 30 days)
log "Cleaning up old backups (>30 days)..."
find "$BACKUP_DIR" -type f -mtime +30 -delete
find "$BACKUP_DIR" -type d -empty -delete

# Show backup stats
BACKUP_COUNT=$(find "$BACKUP_DIR" -type d -name "influx_*" | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

log "Backup Summary:"
log "  Total backups: $BACKUP_COUNT"
log "  Total size: $TOTAL_SIZE"
log "═══════════════════════════════════════"
log "Backup Complete"
log "═══════════════════════════════════════"
