#!/bin/bash
# Install enhanced logging and monitoring system
# Run this on the Raspberry Pi

set -e

echo "============================================"
echo "Installing Enhanced Logging System"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Verify we're on the Raspberry Pi
if [ ! -d "/mnt/sensor-data" ]; then
    echo "ERROR: /mnt/sensor-data not found. Is this the Raspberry Pi?"
    exit 1
fi

echo "1. Stopping health monitor..."
systemctl stop sensor-health-monitor || true

echo "2. Creating log directories..."
mkdir -p /mnt/sensor-data/logs
mkdir -p /usr/local/bin
mkdir -p /etc/logrotate.d

echo "3. Installing startup logger..."
cp scripts/startup-logger.sh /usr/local/bin/
chmod +x /usr/local/bin/startup-logger.sh

echo "4. Installing systemd service for startup logger..."
cp systemd/startup-logger.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable startup-logger.service

echo "5. Updating health monitor script..."
cp scripts/sensor-health-monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/sensor-health-monitor.sh

echo "6. Installing log rotation..."
cp logrotate.d/soil-sensor /etc/logrotate.d/

echo "7. Rotating existing logs (if too large)..."
HEALTH_LOG="/mnt/sensor-data/logs/health-monitor.log"
if [ -f "$HEALTH_LOG" ]; then
    SIZE=$(stat -f%z "$HEALTH_LOG" 2>/dev/null || stat -c%s "$HEALTH_LOG" 2>/dev/null)
    if [ "$SIZE" -gt 104857600 ]; then  # 100MB
        echo "   Health monitor log is ${SIZE} bytes, rotating..."
        mv "$HEALTH_LOG" "$HEALTH_LOG.old.$(date +%Y%m%d_%H%M%S)"
        touch "$HEALTH_LOG"
        chown root:root "$HEALTH_LOG"
    fi
fi

echo "8. Testing startup logger..."
/usr/local/bin/startup-logger.sh

echo "9. Restarting health monitor..."
systemctl restart sensor-health-monitor

echo ""
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo ""
echo "Log files:"
echo "  - Startup history: /mnt/sensor-data/logs/startup_history.log"
echo "  - Health monitor: /mnt/sensor-data/logs/health-monitor.log"
echo "  - Reboot reasons: /mnt/sensor-data/logs/reboot_reasons.log"
echo "  - Grafana failures: /mnt/sensor-data/logs/grafana_failures.log"
echo ""
echo "Services:"
echo "  - startup-logger: Runs once at boot"
echo "  - sensor-health-monitor: Continuous monitoring"
echo ""
echo "To view logs:"
echo "  tail -f /mnt/sensor-data/logs/startup_history.log"
echo "  tail -f /mnt/sensor-data/logs/health-monitor.log"
echo ""
