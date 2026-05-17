#!/bin/bash
# Apply Grafana configuration overrides

set -e

GRAFANA_INI="/etc/grafana/grafana.ini"
OVERRIDE_FILE="/tmp/grafana.ini.override"

echo "Applying Grafana configuration overrides..."

# Backup original config if not already backed up
if [ ! -f "$GRAFANA_INI.original" ]; then
    echo "Backing up original grafana.ini..."
    cp "$GRAFANA_INI" "$GRAFANA_INI.original"
fi

# Apply overrides
echo "Enabling anonymous access..."
sed -i 's/^;enabled = false/enabled = true/' $GRAFANA_INI || \
    sed -i '/^\[auth.anonymous\]/a enabled = true' $GRAFANA_INI

sed -i 's/^;org_role = Viewer/org_role = Viewer/' $GRAFANA_INI || \
    sed -i '/^\[auth.anonymous\]/a org_role = Viewer' $GRAFANA_INI

echo "Allowing iframe embedding..."
sed -i 's/^;allow_embedding = false/allow_embedding = true/' $GRAFANA_INI || \
    sed -i '/^\[security\]/a allow_embedding = true' $GRAFANA_INI

echo "Configuration applied!"
echo "Restarting Grafana..."
systemctl restart grafana-server

echo "Waiting for Grafana to start..."
sleep 5

echo "✓ Grafana configuration complete!"
echo ""
echo "Anonymous access enabled - dashboards viewable without login"
echo "Admin credentials: admin / admin"
