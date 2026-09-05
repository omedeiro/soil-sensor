#!/bin/bash
# Backup Script for Soil Sensor System
# Backs up InfluxDB data and exports to CSV.
#
# Fails LOUDLY: any step that fails sends a Slack alert and exits non-zero so
# systemd records the failure. A silent backup failure went unnoticed for three
# months in Aug 2026; that is what the exit codes and the alert below prevent.
#
# Token resolution order:
#   1. $INFLUX_ADMIN_TOKEN from the environment
#   2. INFLUX_ADMIN_TOKEN= in /mnt/sensor-data/config/backup.env
#   3. INFLUX_TOKEN=       in /mnt/sensor-data/config/panel-health.env

set -uo pipefail

BACKUP_DIR="/mnt/sensor-data/backups"
CONFIG_DIR="/mnt/sensor-data/config"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
INFLUX_ORG="soil-monitoring"
INFLUX_BUCKET="sensor-readings"
INFLUX_HOST="http://localhost:8086"
RETENTION_DAYS=30
ALERT_SCRIPT="/usr/local/bin/send-slack-alert.sh"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

fail() {
    log "✗ $1"
    if [ -x "$ALERT_SCRIPT" ]; then
        "$ALERT_SCRIPT" --severity critical \
            --title "Soil sensor backup FAILED" \
            --message "$1" 2>/dev/null || log "  (Slack alert could not be sent)"
    fi
    exit 1
}

read_var() {  # read_var <file> <key>
    [ -r "$1" ] || return 1
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"''
}

log "═══════════════════════════════════════"
log "Starting InfluxDB Backup"
log "═══════════════════════════════════════"

# ---------------------------------------------------------------- preflight
command -v influx >/dev/null 2>&1 \
    || fail "influx CLI not installed on the host. Install it with rpi-setup/install-influx-cli.sh"

INFLUX_TOKEN="${INFLUX_ADMIN_TOKEN:-}"
[ -n "$INFLUX_TOKEN" ] || INFLUX_TOKEN="$(read_var "$CONFIG_DIR/backup.env" INFLUX_ADMIN_TOKEN)"
[ -n "$INFLUX_TOKEN" ] || INFLUX_TOKEN="$(read_var "$CONFIG_DIR/panel-health.env" INFLUX_TOKEN)"
[ -n "$INFLUX_TOKEN" ] \
    || fail "No InfluxDB token found (checked \$INFLUX_ADMIN_TOKEN, backup.env, panel-health.env)"

curl -fsS -m 10 "$INFLUX_HOST/health" >/dev/null 2>&1 \
    || fail "InfluxDB is not responding at $INFLUX_HOST"

mkdir -p "$BACKUP_DIR" || fail "Cannot create $BACKUP_DIR"

# ------------------------------------------------------------------ backup
TARGET="$BACKUP_DIR/influx_$TIMESTAMP"
log "Creating InfluxDB backup..."
influx backup "$TARGET" \
    --host "$INFLUX_HOST" \
    --org "$INFLUX_ORG" \
    --token "$INFLUX_TOKEN" 2>&1 \
    || fail "influx backup failed (target: $TARGET)"

# A zero-exit backup that produced nothing is still a failed backup.
if [ ! -d "$TARGET" ] || [ -z "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    fail "influx backup reported success but $TARGET is missing or empty"
fi
log "✓ InfluxDB backup successful: $TARGET ($(du -sh "$TARGET" | cut -f1))"

# ------------------------------------------------------------- CSV export
CSV="$BACKUP_DIR/export_$TIMESTAMP.csv"
log "Exporting last 30 days to CSV..."
if influx query \
    --host "$INFLUX_HOST" \
    --org "$INFLUX_ORG" \
    --token "$INFLUX_TOKEN" \
    "from(bucket: \"$INFLUX_BUCKET\")
     |> range(start: -30d)
     |> pivot(rowKey:[\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")" \
    --raw > "$CSV" 2>/dev/null && [ -s "$CSV" ]; then
    log "✓ CSV export successful: $CSV ($(du -sh "$CSV" | cut -f1))"
else
    # Non-fatal: the native backup above is the real safety net.
    log "⚠ CSV export produced no data (non-fatal)"
    rm -f "$CSV"
fi

# -------------------------------------------------------------- retention
# Scoped to this script's own artefacts so unrelated files under backups/
# (e.g. pre-restore safety copies) are never touched.
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -maxdepth 1 -type d -name 'influx_*' -mtime +$RETENTION_DAYS \
    -exec rm -rf {} + 2>/dev/null
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'export_*.csv' -mtime +$RETENTION_DAYS \
    -delete 2>/dev/null

BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "influx_*" | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
log "Backup Summary:"
log "  Total backups: $BACKUP_COUNT"
log "  Total size: $TOTAL_SIZE"
log "═══════════════════════════════════════"
log "Backup Complete"
log "═══════════════════════════════════════"
