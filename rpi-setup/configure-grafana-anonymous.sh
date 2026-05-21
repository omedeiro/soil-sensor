#!/bin/bash
# Configure Grafana for Anonymous Read-Only Access
# Allows anyone to view dashboards without login (view-only, no edit)

set -e

echo "========================================"
echo "Grafana Anonymous Access Configuration"
echo "========================================"
echo ""

GRAFANA_INI="/mnt/sensor-data/grafana/grafana.ini"

# Check if Grafana config exists
if [ ! -f "$GRAFANA_INI" ]; then
    echo "❌ Grafana config not found at: $GRAFANA_INI"
    echo "   Creating default config..."
    sudo mkdir -p /mnt/sensor-data/grafana
    sudo cp /etc/grafana/grafana.ini "$GRAFANA_INI"
fi

echo "Backing up current Grafana config..."
sudo cp "$GRAFANA_INI" "$GRAFANA_INI.backup.$(date +%Y%m%d_%H%M%S)"
echo "✓ Backup created"
echo ""

echo "Configuring anonymous access..."

# Enable anonymous access with Viewer role (read-only)
sudo sed -i 's/^;enabled = false/enabled = true/' "$GRAFANA_INI"
sudo sed -i 's/^enabled = false/enabled = true/' "$GRAFANA_INI"

# Set organization name and role
sudo sed -i 's/^;org_name = Main Org\./org_name = Soil Monitoring/' "$GRAFANA_INI"
sudo sed -i 's/^;org_role = Viewer/org_role = Viewer/' "$GRAFANA_INI"

# Make sure these settings are in the [auth.anonymous] section
# If section doesn't exist, add it
if ! grep -q "\[auth.anonymous\]" "$GRAFANA_INI"; then
    echo "" | sudo tee -a "$GRAFANA_INI" > /dev/null
    echo "[auth.anonymous]" | sudo tee -a "$GRAFANA_INI" > /dev/null
fi

# Use a more reliable method: create a complete config snippet
sudo tee /tmp/grafana_anonymous.conf > /dev/null <<'EOF'
[auth.anonymous]
# Enable anonymous access
enabled = true

# Organization name that should be used for anonymous users
org_name = Soil Monitoring

# Role for anonymous users (Viewer = read-only, no edit)
org_role = Viewer

# Hide the Grafana version from anonymous users
hide_version = true
EOF

# Remove existing [auth.anonymous] section and append new one
sudo sed -i '/^\[auth.anonymous\]/,/^\[/{ /^\[auth.anonymous\]/!{ /^\[/!d; } }' "$GRAFANA_INI"
sudo cat /tmp/grafana_anonymous.conf | sudo tee -a "$GRAFANA_INI" > /dev/null
rm /tmp/grafana_anonymous.conf

echo "✓ Anonymous access enabled (Viewer role = read-only)"
echo ""

# Optional: Disable user signup
echo "Disabling user signup (prevents random people from creating accounts)..."
sudo sed -i 's/^;allow_sign_up = true/allow_sign_up = false/' "$GRAFANA_INI"
sudo sed -i 's/^allow_sign_up = true/allow_sign_up = false/' "$GRAFANA_INI"
echo "✓ User signup disabled"
echo ""

# Optional: Set domain for proper redirect
echo "Setting root URL for Cloudflare Tunnel..."
sudo sed -i 's|^;root_url = .*|root_url = https://grafana.owenmedeiros.com|' "$GRAFANA_INI"
sudo sed -i 's|^root_url = .*|root_url = https://grafana.owenmedeiros.com|' "$GRAFANA_INI"
echo "✓ Root URL configured"
echo ""

# Restart Grafana to apply changes
echo "Restarting Grafana..."
sudo systemctl restart grafana-server

sleep 3

if systemctl is-active --quiet grafana-server; then
    echo "✓ Grafana restarted successfully"
else
    echo "❌ Grafana failed to restart. Check logs:"
    echo "   sudo journalctl -u grafana-server -n 50"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Grafana Configuration Complete!"
echo "========================================"
echo ""
echo "Anonymous Access: ✓ Enabled (Read-Only)"
echo "User Signup:      ✗ Disabled"
echo "Public URL:       https://grafana.owenmedeiros.com"
echo ""
echo "🔒 Security Settings:"
echo "   • Anyone can VIEW dashboards (no login required)"
echo "   • Only you (admin) can EDIT dashboards"
echo "   • Random people cannot create accounts"
echo ""
echo "To make a dashboard public:"
echo "1. Log in as admin: https://grafana.owenmedeiros.com"
echo "2. Go to Dashboard Settings → Permissions"
echo "3. Ensure 'Viewer' role has 'View' permission"
echo ""
echo "Admin login: http://192.168.99.134:3000 (local network only)"
echo ""
