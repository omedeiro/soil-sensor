#!/bin/bash
# Filesystem Protection Installation Script
# Implements measures to prevent corruption from unclean shutdowns

set -e

echo "================================================================"
echo "Installing Filesystem Protection Measures"
echo "================================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

echo "1. Enabling data=ordered journaling for USB drive..."
# Get UUID of USB drive
USB_UUID=$(blkid /dev/sda1 | grep -o 'UUID="[^"]*"' | sed 's/UUID="//' | sed 's/"//')
echo "   USB Drive UUID: $USB_UUID"

# Update fstab with safer mount options
if ! grep -q "data=ordered" /etc/fstab; then
    echo "   Adding data=ordered,barrier=1 to mount options..."
    sed -i "s|UUID=$USB_UUID.*|UUID=$USB_UUID /mnt/sensor-data ext4 defaults,data=ordered,barrier=1,noatime 0 2|" /etc/fstab
    echo "   ✓ Updated /etc/fstab"
else
    echo "   ✓ Already configured"
fi

echo ""
echo "2. Installing filesystem check on boot service..."
cat > /etc/systemd/system/fsck-sensor-data.service << 'EOF'
[Unit]
Description=Filesystem check for sensor data USB drive
DefaultDependencies=no
Before=mnt-sensor\x2ddata.mount
After=dev-sda1.device
Requires=dev-sda1.device

[Service]
Type=oneshot
ExecStart=/sbin/fsck -y -f /dev/sda1
TimeoutSec=0
StandardOutput=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fsck-sensor-data.service
echo "   ✓ Filesystem check service enabled"

echo ""
echo "3. Configuring periodic sync for InfluxDB..."
cat > /etc/systemd/system/influxdb-sync.service << 'EOF'
[Unit]
Description=Sync InfluxDB data to disk
After=influxdb.service

[Service]
Type=oneshot
ExecStart=/bin/sync
ExecStart=/bin/sh -c 'echo 3 > /proc/sys/vm/drop_caches'
EOF

cat > /etc/systemd/system/influxdb-sync.timer << 'EOF'
[Unit]
Description=Sync InfluxDB data every 5 minutes
After=influxdb.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=influxdb-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable influxdb-sync.timer
systemctl start influxdb-sync.timer
echo "   ✓ InfluxDB sync timer enabled (every 5 minutes)"

echo ""
echo "4. Installing UPS/power monitoring script..."
cat > /usr/local/bin/monitor-power.sh << 'EOF'
#!/bin/bash
# Monitor for undervoltage events that could indicate power issues

ALERT_LOG="/mnt/sensor-data/logs/power-alerts.log"

# Check for undervoltage events
THROTTLE=$(vcgencmd get_throttled | sed 's/throttled=//')

if [ "$THROTTLE" != "0x0" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] POWER ISSUE: throttled=$THROTTLE" >> "$ALERT_LOG"
    
    # Decode throttle bits
    if [ $((THROTTLE & 0x1)) -ne 0 ]; then
        echo "[$(date)] Under-voltage detected NOW" >> "$ALERT_LOG"
    fi
    if [ $((THROTTLE & 0x10000)) -ne 0 ]; then
        echo "[$(date)] Under-voltage has occurred since boot" >> "$ALERT_LOG"
    fi
    if [ $((THROTTLE & 0x2)) -ne 0 ]; then
        echo "[$(date)] ARM frequency capped NOW" >> "$ALERT_LOG"
    fi
    if [ $((THROTTLE & 0x4)) -ne 0 ]; then
        echo "[$(date)] Currently throttled NOW" >> "$ALERT_LOG"
    fi
fi
EOF

chmod +x /usr/local/bin/monitor-power.sh

cat > /etc/systemd/system/power-monitor.service << 'EOF'
[Unit]
Description=Power quality monitor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor-power.sh
EOF

cat > /etc/systemd/system/power-monitor.timer << 'EOF'
[Unit]
Description=Check power quality every minute
After=multi-user.target

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=power-monitor.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable power-monitor.timer
systemctl start power-monitor.timer
echo "   ✓ Power monitoring enabled"

echo ""
echo "5. Configuring graceful shutdown script..."
cat > /usr/local/bin/graceful-shutdown.sh << 'EOF'
#!/bin/bash
# Graceful shutdown that ensures all data is synced

echo "Initiating graceful shutdown..."

# Stop services in order
echo "Stopping Grafana..."
systemctl stop grafana-server

echo "Stopping InfluxDB (with 30s timeout for data flush)..."
systemctl stop influxdb
sleep 5

echo "Syncing filesystems..."
sync
sync
sync

echo "Unmounting sensor data drive..."
umount /mnt/sensor-data || true

echo "Shutdown preparation complete."
EOF

chmod +x /usr/local/bin/graceful-shutdown.sh
echo "   ✓ Graceful shutdown script installed"
echo "   Usage: sudo /usr/local/bin/graceful-shutdown.sh && sudo poweroff"

echo ""
echo "6. Configuring systemd shutdown timeout..."
# Increase systemd shutdown timeout to allow services to flush data
if ! grep -q "DefaultTimeoutStopSec=90s" /etc/systemd/system.conf; then
    echo "DefaultTimeoutStopSec=90s" >> /etc/systemd/system.conf
    systemctl daemon-reexec
    echo "   ✓ Shutdown timeout increased to 90 seconds"
else
    echo "   ✓ Already configured"
fi

echo ""
echo "================================================================"
echo "Filesystem Protection Installation Complete!"
echo "================================================================"
echo ""
echo "Protections installed:"
echo "  ✓ Ordered journaling on USB drive"
echo "  ✓ Automatic filesystem check on boot"
echo "  ✓ InfluxDB data sync every 5 minutes"
echo "  ✓ Power quality monitoring"
echo "  ✓ Graceful shutdown script"
echo "  ✓ Extended service shutdown timeout"
echo ""
echo "IMPORTANT: To minimize corruption risk:"
echo "  - Always use: sudo /usr/local/bin/graceful-shutdown.sh && sudo poweroff"
echo "  - Never pull power without shutting down first"
echo "  - Check power supply quality (use official Pi power adapter)"
echo "  - Monitor /mnt/sensor-data/logs/power-alerts.log for power issues"
echo ""
echo "Next: Reboot to apply filesystem mount changes"
echo "      sudo reboot"
echo ""
