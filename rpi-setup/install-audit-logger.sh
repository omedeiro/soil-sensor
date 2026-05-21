#!/bin/bash
# Install System Audit Logger
# Deploys comprehensive health checking and configuration validation

set -e

echo "Installing System Audit Logger..."

# Copy script to /usr/local/bin
sudo cp scripts/system-audit-logger.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/system-audit-logger.sh

# Copy systemd service and timer
sudo cp systemd/system-audit.service /etc/systemd/system/
sudo cp systemd/system-audit.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start timer
sudo systemctl enable system-audit.timer
sudo systemctl start system-audit.timer

# Run audit once immediately
echo "Running initial audit..."
sudo systemctl start system-audit.service

# Show status
echo ""
echo "System Audit Logger installed successfully!"
echo ""
echo "Status:"
sudo systemctl status system-audit.timer --no-pager | head -10
echo ""
echo "Next scheduled runs:"
systemctl list-timers system-audit.timer --no-pager
echo ""
echo "Logs:"
echo "  Audit log:  /mnt/sensor-data/logs/system-audit.log"
echo "  Alert log:  /mnt/sensor-data/logs/system-alerts.log"
echo ""
echo "To view recent audit results:"
echo "  tail -50 /mnt/sensor-data/logs/system-audit.log"
echo ""
echo "To view alerts only:"
echo "  tail -50 /mnt/sensor-data/logs/system-alerts.log"
