#!/bin/bash
#
# Enhanced Monitoring Installation Script
# Installs comprehensive logging and alerting for Raspberry Pi
#

set -e

echo "=========================================="
echo "Enhanced Monitoring Installation"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_USER="${SUDO_USER:-omedeiro}"

echo "Installation directory: $SCRIPT_DIR"
echo "Running as user: $INSTALL_USER"
echo ""

# Create log directories
echo "Creating log directories..."
mkdir -p /mnt/sensor-data/logs/reports
chown -R $INSTALL_USER:$INSTALL_USER /mnt/sensor-data/logs
echo "✓ Log directories created"

# Make scripts executable
echo ""
echo "Making scripts executable..."
chmod +x "$SCRIPT_DIR/scripts/power-monitor.sh"
chmod +x "$SCRIPT_DIR/scripts/network-monitor.sh"
chmod +x "$SCRIPT_DIR/scripts/event-logger.sh"
chmod +x "$SCRIPT_DIR/scripts/daily-health-report.sh"
echo "✓ Scripts are executable"

# Install systemd service files
echo ""
echo "Installing systemd service files..."

services=(
    "power-monitor.service"
    "power-monitor.timer"
    "network-monitor.service"
    "network-monitor.timer"
    "daily-health-report.service"
    "daily-health-report.timer"
    "shutdown-logger.service"
)

for service in "${services[@]}"; do
    echo "  Installing $service..."
    cp "$SCRIPT_DIR/systemd/$service" /etc/systemd/system/
    chown root:root "/etc/systemd/system/$service"
    chmod 644 "/etc/systemd/system/$service"
done

echo "✓ Service files installed"

# Reload systemd
echo ""
echo "Reloading systemd daemon..."
systemctl daemon-reload
echo "✓ Systemd reloaded"

# Enable and start services
echo ""
echo "Enabling and starting services..."

timers=(
    "power-monitor.timer"
    "network-monitor.timer"
    "daily-health-report.timer"
)

for timer in "${timers[@]}"; do
    echo "  Enabling $timer..."
    systemctl enable "$timer"
    systemctl start "$timer"
done

# Enable shutdown logger
echo "  Enabling shutdown-logger.service..."
systemctl enable shutdown-logger.service

echo "✓ Services enabled and started"

# Run initial checks
echo ""
echo "Running initial monitoring checks..."

echo ""
echo "1. Power Monitor:"
sudo -u $INSTALL_USER "$SCRIPT_DIR/scripts/power-monitor.sh"

echo ""
echo "2. Network Monitor:"
sudo -u $INSTALL_USER "$SCRIPT_DIR/scripts/network-monitor.sh"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Monitoring services installed:"
echo "  • Power Monitor (every 2 minutes)"
echo "  • Network Monitor (every 5 minutes)"
echo "  • Daily Health Report (8 AM daily)"
echo "  • Shutdown/Reboot Logger (on system shutdown)"
echo ""
echo "Log files location:"
echo "  /mnt/sensor-data/logs/power-monitor.log"
echo "  /mnt/sensor-data/logs/power-alerts.log"
echo "  /mnt/sensor-data/logs/network-monitor.log"
echo "  /mnt/sensor-data/logs/network-alerts.log"
echo "  /mnt/sensor-data/logs/system-events.log"
echo "  /mnt/sensor-data/logs/shutdown-events.log"
echo "  /mnt/sensor-data/logs/daily-health-report.log"
echo "  /mnt/sensor-data/logs/reports/ (daily archives)"
echo ""
echo "Check status:"
echo "  systemctl status power-monitor.timer"
echo "  systemctl status network-monitor.timer"
echo "  systemctl status daily-health-report.timer"
echo "  systemctl list-timers"
echo ""
echo "View logs:"
echo "  tail -f /mnt/sensor-data/logs/power-monitor.log"
echo "  tail -f /mnt/sensor-data/logs/power-alerts.log"
echo "  cat /mnt/sensor-data/logs/daily-health-report.log"
echo ""
echo "Generate health report now:"
echo "  sudo systemctl start daily-health-report.service"
echo ""
echo "Optional: Set INFLUX_TOKEN for sensor status in health reports"
echo "  Edit /etc/systemd/system/daily-health-report.service"
echo "  Add: Environment=\"INFLUX_TOKEN=your_read_token\""
echo "  Then: sudo systemctl daemon-reload"
echo ""
