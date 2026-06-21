#!/bin/bash

# Upload the updated dashboard to Grafana on Raspberry Pi
# This script copies the dashboard file and imports it via the Grafana API

DASHBOARD_FILE="grafana-dashboards/soil-moisture-main.json"
PI_USER="omedeiro"
PI_HOST="192.168.99.134"

echo "Copying dashboard to Raspberry Pi..."
scp "$DASHBOARD_FILE" "${PI_USER}@${PI_HOST}:/tmp/soil-moisture-main.json"

echo "Importing dashboard into Grafana..."
ssh "${PI_USER}@${PI_HOST}" 'bash -s' <<'ENDSSH'
    # Create API payload (wrap dashboard in required format)
    echo "{\"dashboard\": $(cat /tmp/soil-moisture-main.json), \"overwrite\": true, \"message\": \"Updated dropdown filter and labels\"}" > /tmp/payload.json
    
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
