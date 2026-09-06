#!/bin/bash
# Deploy Watering History dashboard to Grafana on Raspberry Pi

set -e

DASHBOARD_FILE="watering-history.json"
PI_HOST="omedeiro@192.168.99.134"

echo "🚰 Deploying Watering History Dashboard"
echo "========================================"
echo ""

# Check if dashboard file exists
if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "❌ Error: $DASHBOARD_FILE not found"
  echo "Run this script from grafana-dashboards/ directory"
  exit 1
fi

echo "Step 1: Copying dashboard to Raspberry Pi..."
scp "$DASHBOARD_FILE" "${PI_HOST}:/tmp/"
echo "✅ Copied to /tmp/$DASHBOARD_FILE"
echo ""

echo "Step 2: Moving to Grafana dashboards directory..."
ssh "$PI_HOST" "sudo cp /tmp/$DASHBOARD_FILE /mnt/sensor-data/grafana/dashboards/ && \
  sudo chown grafana:grafana /mnt/sensor-data/grafana/dashboards/$DASHBOARD_FILE"
echo "✅ Moved to /mnt/sensor-data/grafana/dashboards/"
echo ""

echo "Step 3: Importing to Grafana via API..."
ssh "$PI_HOST" "cat /mnt/sensor-data/grafana/dashboards/$DASHBOARD_FILE | python3 -c \"
import sys, json
dashboard = json.load(sys.stdin)
wrapper = {
  'dashboard': dashboard,
  'overwrite': True
}
print(json.dumps(wrapper))
\" | curl -s -X POST -u admin:admin \
  -H 'Content-Type: application/json' \
  -d @- \
  http://localhost:3000/api/dashboards/db" > /tmp/grafana-response.json

echo "✅ Imported to Grafana"
echo ""

# Check response
if grep -q '"status":"success"' /tmp/grafana-response.json; then
  echo "✅ Dashboard successfully deployed!"
  echo ""
  echo "🌐 View at: https://soil.owenmedeiros.com"
  echo "📊 Dashboard: 🚰 Watering History"
  echo ""
  echo "The dashboard will:"
  echo "  • Detect watering events (15%+ moisture increase)"
  echo "  • Show watering timeline for all sensors"
  echo "  • Display time since last watered for each plant"
  echo "  • Visualize watering patterns by day/hour"
else
  echo "⚠️  Import may have issues. Check Grafana UI."
  cat /tmp/grafana-response.json
fi

rm -f /tmp/grafana-response.json
