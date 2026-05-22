#!/bin/bash
# InfluxDB Recovery Script
# Restores InfluxDB from backup after corruption

set -e

echo "================================================================"
echo "InfluxDB Recovery Script"
echo "================================================================"
echo ""
echo "This will restore InfluxDB from the most recent backup."
echo "Current corrupted data will be moved to /mnt/sensor-data/influxdb.corrupted.$(date +%Y%m%d)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Find most recent backup
BACKUP_DIR=$(ls -td /mnt/sensor-data/backups/influx_* 2>/dev/null | head -1)

if [ -z "$BACKUP_DIR" ]; then
    echo "ERROR: No backups found in /mnt/sensor-data/backups/"
    exit 1
fi

echo "Found backup: $BACKUP_DIR"
BACKUP_DATE=$(basename "$BACKUP_DIR" | sed 's/influx_//')
echo "Backup date: $BACKUP_DATE"
echo ""

read -p "Continue with restore? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Stopping InfluxDB..."
systemctl stop influxdb || true
sleep 2

echo "Step 2: Moving corrupted data..."
CORRUPT_DIR="/mnt/sensor-data/influxdb.corrupted.$(date +%Y%m%d_%H%M%S)"
mv /mnt/sensor-data/influxdb "$CORRUPT_DIR"
echo "Corrupted data saved to: $CORRUPT_DIR"

echo "Step 3: Restoring from backup..."
cp -a "$BACKUP_DIR/influxdb" /mnt/sensor-data/influxdb
chown -R influxdb:influxdb /mnt/sensor-data/influxdb
echo "Restored from: $BACKUP_DIR"

echo "Step 4: Resetting service state..."
systemctl reset-failed influxdb || true

echo "Step 5: Starting InfluxDB..."
systemctl start influxdb
sleep 5

echo ""
echo "Step 6: Checking status..."
if systemctl is-active --quiet influxdb; then
    echo "✓ InfluxDB is running!"
    echo ""
    echo "Testing connection..."
    curl -s http://localhost:8086/health || echo "Connection test failed"
    echo ""
else
    echo "✗ InfluxDB failed to start"
    echo "Checking logs:"
    journalctl -u influxdb -n 20 --no-pager
    exit 1
fi

echo ""
echo "================================================================"
echo "Recovery complete!"
echo "================================================================"
echo "Data restored from: $BACKUP_DATE"
echo "Corrupted data saved to: $CORRUPT_DIR"
echo ""
echo "Next steps:"
echo "1. Check Grafana dashboards: https://grafana.owenmedeiros.com"
echo "2. Verify sensors are posting data"
echo "3. Review /mnt/sensor-data/logs/startup_history.log for root cause"
echo ""
