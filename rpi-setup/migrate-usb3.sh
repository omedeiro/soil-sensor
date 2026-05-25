#!/bin/bash
#
# USB 3.0 Migration Helper
# Safely moves USB drive from USB 2.0 to USB 3.0 port
#

set -e

echo "=========================================="
echo "USB 3.0 Migration Helper"
echo "=========================================="
echo ""

# Check current USB speed
CURRENT_SPEED=$(lsusb -t | grep "Mass Storage" | grep -oP '\d+M')

if [[ "$CURRENT_SPEED" == "5000M" ]]; then
    echo "✅ USB drive already at USB 3.0 speed!"
    echo "No migration needed."
    echo ""
    lsusb -t | grep "Mass Storage"
    exit 0
fi

echo "Current USB speed: $CURRENT_SPEED (USB 2.0)"
echo "Target speed: 5000M (USB 3.0)"
echo ""
echo "This script will:"
echo "  1. Stop all services writing to USB drive"
echo "  2. Sync all data to disk"
echo "  3. Unmount USB drive safely"
echo "  4. Prompt you to move USB drive to blue USB 3.0 port"
echo "  5. Remount and verify USB 3.0 speed"
echo "  6. Restart services"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Step 1: Stopping services..."
sudo systemctl stop influxdb
sudo systemctl stop grafana-server
sudo systemctl stop cloudflared
sudo systemctl stop power-monitor.timer
sudo systemctl stop network-monitor.timer
sudo systemctl stop storage-monitor.timer
sudo systemctl stop daily-health-report.timer
echo "✓ Services stopped"

echo ""
echo "Step 2: Syncing data to disk..."
sync
sync
sync
echo "✓ Data synced"

echo ""
echo "Step 3: Unmounting USB drive..."
sudo umount /mnt/sensor-data
echo "✓ USB drive unmounted"

echo ""
echo "=========================================="
echo "PHYSICAL ACTION REQUIRED"
echo "=========================================="
echo ""
echo "Please perform the following steps:"
echo ""
echo "1. Locate the USB drive (currently in a USB port)"
echo "2. Gently remove the USB drive"
echo "3. Identify the BLUE USB 3.0 ports on Raspberry Pi 5"
echo "   (Blue ports = USB 3.0, Black ports = USB 2.0)"
echo "4. Insert USB drive into a BLUE USB 3.0 port"
echo "5. Wait 2 seconds for detection"
echo ""
read -p "Press ENTER when USB drive is in blue USB 3.0 port..."

echo ""
echo "Step 4: Detecting USB drive..."
sleep 2

# Wait for device to appear
ATTEMPTS=0
while [ ! -b /dev/sda1 ] && [ $ATTEMPTS -lt 10 ]; do
    echo "Waiting for /dev/sda1 to appear... (attempt $((ATTEMPTS+1))/10)"
    sleep 1
    ATTEMPTS=$((ATTEMPTS+1))
done

if [ ! -b /dev/sda1 ]; then
    echo "❌ ERROR: /dev/sda1 not detected!"
    echo "Please check USB connection and try again."
    exit 1
fi

echo "✓ Device detected: /dev/sda1"

echo ""
echo "Step 5: Remounting USB drive..."
sudo mount -a
sleep 1

if ! mountpoint -q /mnt/sensor-data; then
    echo "❌ ERROR: Failed to mount /mnt/sensor-data"
    echo "Trying manual mount..."
    sudo mount /dev/sda1 /mnt/sensor-data
fi

if mountpoint -q /mnt/sensor-data; then
    echo "✓ USB drive mounted at /mnt/sensor-data"
else
    echo "❌ ERROR: Mount failed! Manual intervention required."
    exit 1
fi

echo ""
echo "Step 6: Verifying USB 3.0 speed..."
sleep 1
NEW_SPEED=$(lsusb -t | grep "Mass Storage" | grep -oP '\d+M')

echo "New USB speed: $NEW_SPEED"

if [[ "$NEW_SPEED" == "5000M" ]]; then
    echo "✅ SUCCESS! USB drive now at USB 3.0 speed!"
elif [[ "$NEW_SPEED" == "480M" ]]; then
    echo "⚠️  WARNING: Still at USB 2.0 speed (480M)"
    echo "The USB drive may still be in a USB 2.0 port."
    echo "Please double-check you used a BLUE port, not black."
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        exit 1
    fi
else
    echo "⚠️  Unknown speed: $NEW_SPEED"
fi

echo ""
echo "Step 7: Restarting services..."
sudo systemctl start influxdb
sleep 2
sudo systemctl start grafana-server
sleep 2
sudo systemctl start cloudflared
sleep 1
sudo systemctl start power-monitor.timer
sudo systemctl start network-monitor.timer
sudo systemctl start storage-monitor.timer
sudo systemctl start daily-health-report.timer
echo "✓ Services restarted"

echo ""
echo "Step 8: Verifying system health..."
sleep 3

# Check services
echo ""
echo "Service status:"
for service in influxdb grafana-server cloudflared; do
    if systemctl is-active --quiet "$service"; then
        echo "  ✓ $service: active"
    else
        echo "  ❌ $service: FAILED"
    fi
done

# Check sensors
echo ""
echo "Checking sensor connectivity..."
SENSOR_COUNT=0
for sensor_ip in 192.168.99.110 192.168.99.149 192.168.99.70 192.168.99.105; do
    if ping -c 1 -W 1 "$sensor_ip" &>/dev/null; then
        echo "  ✓ Sensor $sensor_ip: ONLINE"
        SENSOR_COUNT=$((SENSOR_COUNT+1))
    else
        echo "  ⏳ Sensor $sensor_ip: offline (may come online in 1-5 minutes)"
    fi
done

echo ""
echo "=========================================="
echo "Migration Complete!"
echo "=========================================="
echo ""
echo "Results:"
echo "  Previous speed: $CURRENT_SPEED (USB 2.0)"
echo "  Current speed:  $NEW_SPEED"
echo "  Sensors online: $SENSOR_COUNT/4"
echo ""

if [[ "$NEW_SPEED" == "5000M" ]]; then
    echo "✅ USB 3.0 migration successful!"
    echo ""
    echo "Expected improvements:"
    echo "  • 10x faster write speeds"
    echo "  • Smaller corruption window on power failures"
    echo "  • Better chance of surviving brief power blips"
    echo ""
    echo "Monitor logs for the next week:"
    echo "  tail -f /mnt/sensor-data/logs/storage-monitor.log"
    echo "  cat /mnt/sensor-data/logs/startup_history.log"
    echo ""
    echo "If no unclean shutdowns occur in 1 week → PROBLEM SOLVED"
    echo "If unclean shutdowns continue → Install UPS (see STORAGE-ROOT-CAUSE.md)"
else
    echo "⚠️  WARNING: Still at USB 2.0 speed"
    echo ""
    echo "Next steps:"
    echo "  1. Shutdown Pi: sudo shutdown -h now"
    echo "  2. Physically verify USB drive is in BLUE port"
    echo "  3. Try different blue port"
    echo "  4. Power on and check: lsusb -t | grep 5000M"
fi

echo ""
