#!/bin/bash

# Upload the generated dashboards to Grafana on Raspberry Pi
# This script copies each dashboard file and imports it via the Grafana API
#
# Usage:
#   ./upload-dashboard-to-pi.sh                      # both generated dashboards
#   ./upload-dashboard-to-pi.sh sensor-explorer.json # just one of them

PI_USER="omedeiro"
PI_HOST="192.168.99.134"

# The dashboards scripts/generate-dashboard.py writes
DASHBOARDS=(
  "soil-moisture-main.json"
  "sensor-explorer.json"
)

if [ "$#" -gt 0 ]; then
    DASHBOARDS=("$@")
fi

status=0

for name in "${DASHBOARDS[@]}"; do
    name=$(basename "$name")
    dashboard_file="grafana-dashboards/$name"

    if [ ! -f "$dashboard_file" ]; then
        echo "✗ $dashboard_file not found — run ./scripts/generate-dashboard.py first"
        status=1
        continue
    fi

    echo "Copying $name to Raspberry Pi..."
    if ! scp "$dashboard_file" "${PI_USER}@${PI_HOST}:/tmp/$name"; then
        echo "✗ Failed to copy $name"
        status=1
        continue
    fi

    echo "Importing $name into Grafana..."
    ssh "${PI_USER}@${PI_HOST}" 'bash -s' "$name" <<'ENDSSH' || status=1
    NAME="$1"

    # Create API payload (wrap dashboard in required format, include folder)
    PAYLOAD=$(jq -n \
      --argjson dashboard "$(cat "/tmp/$NAME")" \
      '{"dashboard": $dashboard, "overwrite": true, "message": "Auto-updated dashboard"}')
    echo "$PAYLOAD" > /tmp/payload.json

    # Import to Grafana (using admin credentials)
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:admin" \
        -d @/tmp/payload.json \
        http://localhost:3000/api/dashboards/db)

    # Clean up before reporting, so a failure still leaves /tmp tidy
    rm -f "/tmp/$NAME" /tmp/payload.json

    # Check if successful
    if echo "$RESPONSE" | grep -q '"status":"success"'; then
        echo "✓ $NAME imported successfully"
        echo "$RESPONSE" | grep -o '"url":"[^"]*"'
    else
        echo "✗ Import failed for $NAME:"
        echo "$RESPONSE"
        exit 1
    fi
ENDSSH
done

if [ "$status" -eq 0 ]; then
    echo "✓ Dashboard upload complete!"
else
    echo "✗ One or more dashboards failed to upload"
fi

exit $status
