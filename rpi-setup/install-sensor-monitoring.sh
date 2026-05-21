#!/bin/bash
#
# install-sensor-monitoring.sh
# Install automated sensor health monitoring on Raspberry Pi
#
# This script:
#   1. Copies sensor health check script to ~/rpi-setup/scripts/
#   2. Installs systemd service and timer
#   3. Enables automatic monitoring every 10 minutes
#

set -euo pipefail

echo "════════════════════════════════════════════════════════════"
echo "Sensor Health Monitoring Installation"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if running on Raspberry Pi
if [ ! -f /proc/device-tree/model ] || ! grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
  echo "⚠️  Warning: This doesn't appear to be a Raspberry Pi"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check if InfluxDB is running
if ! systemctl is-active --quiet influxdb; then
  echo "❌ Error: InfluxDB is not running"
  echo "   Start it with: sudo systemctl start influxdb"
  exit 1
fi

# Prompt for InfluxDB read token
echo "You need an InfluxDB read token with access to the 'sensor-readings' bucket."
echo "Generate one at: http://$(hostname -I | awk '{print $1}'):8086"
echo ""
read -p "Enter InfluxDB read token: " INFLUX_TOKEN

if [ -z "$INFLUX_TOKEN" ]; then
  echo "❌ Error: Token cannot be empty"
  exit 1
fi

echo ""
echo "📦 Installing sensor health monitoring..."
echo ""

# Create scripts directory if it doesn't exist
mkdir -p ~/rpi-setup/scripts
mkdir -p ~/rpi-setup/systemd

# Copy script
echo "  ✓ Copying health check script..."
cp check-sensor-health.sh ~/rpi-setup/scripts/
chmod +x ~/rpi-setup/scripts/check-sensor-health.sh

# Update systemd service with token
echo "  ✓ Installing systemd service..."
sed "s|Environment=\"INFLUX_TOKEN=.*\"|Environment=\"INFLUX_TOKEN=$INFLUX_TOKEN\"|" \
  sensor-health-check.service > ~/rpi-setup/systemd/sensor-health-check.service

# Install systemd files
sudo cp ~/rpi-setup/systemd/sensor-health-check.service /etc/systemd/system/
sudo cp systemd/sensor-health-check.timer /etc/systemd/system/

# Reload systemd
echo "  ✓ Reloading systemd..."
sudo systemctl daemon-reload

# Enable and start timer
echo "  ✓ Enabling automatic health checks..."
sudo systemctl enable sensor-health-check.timer
sudo systemctl start sensor-health-check.timer

# Run initial check
echo ""
echo "Running initial health check..."
echo ""
export INFLUX_TOKEN="$INFLUX_TOKEN"
~/rpi-setup/scripts/check-sensor-health.sh --alert-minutes 15 || true

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Installation Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Sensor health monitoring is now active."
echo ""
echo "The system will:"
echo "  • Check sensor health every 10 minutes"
echo "  • Alert if no data received for 15+ minutes"
echo "  • Log alerts to system journal"
echo ""
echo "View status:"
echo "  systemctl status sensor-health-check.timer"
echo "  systemctl status sensor-health-check.service"
echo ""
echo "View logs:"
echo "  journalctl -u sensor-health-check -f"
echo ""
echo "Manual check:"
echo "  ~/rpi-setup/scripts/check-sensor-health.sh --alert-minutes 15"
echo ""
echo "════════════════════════════════════════════════════════════"
