#!/bin/bash
# install-system-metrics.sh
# Installs Raspberry Pi system metrics collector for InfluxDB (bash version, no Python required)

set -e

echo "=== Installing System Metrics Collector (Bash Version) ==="

# Configuration
INFLUX_TOKEN="${INFLUX_TOKEN:-}"
if [[ -z "$INFLUX_TOKEN" ]]; then
    echo "ERROR: INFLUX_TOKEN environment variable not set"
    echo "Usage: INFLUX_TOKEN='your_token' ./install-system-metrics.sh"
    exit 1
fi

INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"

echo "Configuration:"
echo "  InfluxDB URL: $INFLUX_URL"
echo "  Organization: $INFLUX_ORG"
echo "  Bucket: $INFLUX_BUCKET"
echo ""

# Create scripts directory if it doesn't exist
mkdir -p ~/soil-sensor/scripts

# Copy metrics collector script
echo "Installing metrics collector script..."
cp scripts/system-metrics-collector.sh ~/soil-sensor/scripts/
chmod +x ~/soil-sensor/scripts/system-metrics-collector.sh

# Create environment file for systemd service
echo "Creating environment file..."
cat > ~/soil-sensor/system-metrics.env <<EOF
INFLUX_URL=$INFLUX_URL
INFLUX_TOKEN=$INFLUX_TOKEN
INFLUX_ORG=$INFLUX_ORG
INFLUX_BUCKET=$INFLUX_BUCKET
EOF

# Create systemd service (user service, no sudo required)
echo "Creating systemd user service..."
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/system-metrics-collector.service <<EOF
[Unit]
Description=Raspberry Pi System Metrics Collector
After=network.target

[Service]
Type=oneshot
EnvironmentFile=%h/soil-sensor/system-metrics.env
ExecStart=%h/soil-sensor/scripts/system-metrics-collector.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# Create systemd timer (runs every 60 seconds)
echo "Creating systemd timer..."
cat > ~/.config/systemd/user/system-metrics-collector.timer <<EOF
[Unit]
Description=Run System Metrics Collector every 60 seconds
Requires=system-metrics-collector.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
echo "Enabling and starting timer..."
systemctl --user daemon-reload
systemctl --user enable system-metrics-collector.timer
systemctl --user start system-metrics-collector.timer

# Enable lingering (keep user services running after logout)
echo "Enabling user service lingering..."
loginctl enable-linger $USER

# Run once immediately to test
echo ""
echo "Testing metrics collection..."
systemctl --user start system-metrics-collector.service

# Wait and check status
sleep 2
echo ""
echo "Timer status:"
systemctl --user status system-metrics-collector.timer --no-pager | head -15

echo ""
echo "Recent logs:"
journalctl --user -u system-metrics-collector.service -n 10 --no-pager

echo ""
echo "✓ System metrics collector installed successfully!"
echo ""
echo "Usage:"
echo "  systemctl --user status system-metrics-collector.timer   # Check timer status"
echo "  journalctl --user -u system-metrics-collector -f         # Follow logs"
echo "  systemctl --user stop system-metrics-collector.timer     # Stop collection"
echo "  systemctl --user start system-metrics-collector.timer    # Start collection"
echo ""
echo "Metrics will be posted to InfluxDB every 60 seconds."
