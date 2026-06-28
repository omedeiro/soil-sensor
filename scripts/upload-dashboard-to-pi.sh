#!/bin/bash

# Upload the updated dashboard to Grafana on Raspberry Pi
# This script copies the dashboard file and imports it via the Grafana API

DASHBOARD_FILE="grafana-dashboards/soil-moisture-main.json"
PI_USER="omedeiro"
PI_HOST="192.168.99.134"

echo "Copying dashboard to Raspberry Pi..."
scp "$DASHBOARD_FILE" "${PI_USER}@${PI_HOST}:/tmp/soil-moisture-main.json"

echo "Importing dashboard into Grafana (folder: Soil Monitoring)..."
ssh "${PI_USER}@${PI_HOST}" 'bash -s' <<'ENDSSH'
    # Create API payload (wrap dashboard in required format, include folder)
    PAYLOAD=$(jq -n \
      --argjson dashboard "$(cat /tmp/soil-moisture-main.json)" \
      --argjson folderId 2158619959259136 \
      '{"dashboard": $dashboard, "folderId": $folderId, "overwrite": true, "message": "Auto-updated dashboard"}')
    echo "$PAYLOAD" > /tmp/payload.json
    
    # Import to Grafana (using admin credentials)
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:admin" \
        -d @/tmp/payload.json \
        http://localhost:3000/api/dashboards/db)
    
    # Check if successful
    if echo "$RESPONSE" | grep -q '"status":"success"'; then
        echo "✓ Dashboard imported successfully"
        echo "$RESPONSE" | grep -o '"url":"[^"]*"'
    else
        echo "✗ Import failed:"
        echo "$RESPONSE"
    fi
    
    # Clean up
    rm /tmp/soil-moisture-main.json /tmp/payload.json
ENDSSH

echo "✓ Dashboard upload complete!"
