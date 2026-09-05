#!/bin/bash
# Import all dashboards to Grafana on Raspberry Pi
# Uses the proven /api/dashboards/db endpoint (same as upload-dashboard-to-pi.sh)
# Dashboards are placed in the Soil Monitoring folder

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAFANA_URL="http://192.168.99.134:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
FOLDER_UID="afma8ap3k5csgb"  # Soil Monitoring folder

# Dashboard files to import
DASHBOARDS=(
  "alerts-overview.json"
  "mobile-summary.json"
  "rpi-health.json"
  "sensor-details.json"
  "sensor-explorer.json"
  "soil-moisture-main.json"
  "system-health.json"
  "watering-history.json"
)

echo "🚀 Importing Grafana dashboards..."
echo "Target: $GRAFANA_URL"
echo "Folder UID: $FOLDER_UID"
echo ""

for dashboard in "${DASHBOARDS[@]}"; do
  echo "📊 Importing $dashboard..."

  # Build payload via SSH on the Pi (avoids shell quoting issues with large JSON)
  payload=$(jq -n \
    --argjson dashboard "$(cat "$SCRIPT_DIR/$dashboard")" \
    --arg folderUid "$FOLDER_UID" \
    '{
      dashboard: $dashboard,
      overwrite: true,
      folderUid: $folderUid
    }')

  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "$payload" \
    "$GRAFANA_URL/api/dashboards/db")

  if echo "$response" | grep -q '"status":"success"'; then
    echo "✅ $dashboard imported successfully"
  elif echo "$response" | grep -q '"uid"'; then
    echo "✅ $dashboard imported successfully"
  else
    echo "❌ Failed to import $dashboard"
    echo "   Response: $response"
  fi
  echo ""
done

echo "✨ Dashboard import complete!"
echo "📈 View dashboards: $GRAFANA_URL/dashboards"
