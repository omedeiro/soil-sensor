#!/bin/bash
# Import all dashboards to Grafana on Raspberry Pi
# Updates datasource UID to match new Grafana instance

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAFANA_URL="http://192.168.99.134:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
NEW_DATASOURCE_UID="PB4A2C00F7BB2A2DA"

# Dashboard files to import
DASHBOARDS=(
  "alerts-overview.json"
  "mobile-summary.json"
  "rpi-health.json"
  "sensor-details.json"
  "system-health.json"
  "watering-history.json"
)

echo "🚀 Importing Grafana dashboards..."
echo "Target: $GRAFANA_URL"
echo "Datasource UID: $NEW_DATASOURCE_UID"
echo ""

for dashboard in "${DASHBOARDS[@]}"; do
  echo "📊 Importing $dashboard..."
  
  # Read dashboard JSON
  dashboard_json=$(cat "$SCRIPT_DIR/$dashboard")
  
  # Replace datasource UID (handles multiple formats)
  dashboard_json=$(echo "$dashboard_json" | \
    sed "s/\"uid\": \"cflk0i2e2nwu8d\"/\"uid\": \"$NEW_DATASOURCE_UID\"/g" | \
    sed "s/\"datasource\": \"cflk0i2e2nwu8d\"/\"datasource\": \"$NEW_DATASOURCE_UID\"/g" | \
    sed "s/\"datasource\":{\"uid\":\"cflk0i2e2nwu8d\"/\"datasource\":{\"uid\":\"$NEW_DATASOURCE_UID\"/g")
  
  # Create import payload
  payload=$(jq -n \
    --argjson dashboard "$dashboard_json" \
    '{
      dashboard: $dashboard,
      overwrite: true,
      inputs: [{
        name: "DS_INFLUXDB",
        type: "datasource",
        pluginId: "influxdb",
        value: "'$NEW_DATASOURCE_UID'"
      }]
    }')
  
  # Import to Grafana
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "$payload" \
    "$GRAFANA_URL/api/dashboards/import")
  
  # Check result
  if echo "$response" | grep -q '"status":"success"'; then
    echo "✅ $dashboard imported successfully"
  elif echo "$response" | grep -q '"uid"'; then
    echo "✅ $dashboard imported successfully"
  else
    echo "❌ Failed to import $dashboard"
    echo "   Response: $response" | head -100
  fi
  echo ""
done

echo "✨ Dashboard import complete!"
echo "📈 View dashboards: $GRAFANA_URL/dashboards"
