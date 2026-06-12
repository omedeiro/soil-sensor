#!/bin/bash
# update-grafana-datasources.sh
# Updates Grafana datasources to use container name instead of hardcoded IP

set -e

echo "=== Updating Grafana Datasources for Docker Compose ==="

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

OLD_URL="http://172.17.0.2:8086"
NEW_URL="http://influxdb:8086"

echo "Grafana URL: $GRAFANA_URL"
echo "Old InfluxDB URL: $OLD_URL"
echo "New InfluxDB URL: $NEW_URL"
echo ""

# Get list of datasources
echo "Fetching datasources..."
DATASOURCES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "$GRAFANA_URL/api/datasources")

# Check if any datasources found
if [[ "$DATASOURCES" == "[]" ]]; then
    echo "No datasources found in Grafana"
    exit 1
fi

# Count datasources to update
DS_COUNT=$(echo "$DATASOURCES" | grep -o "\"type\":\"influxdb\"" | wc -l)
echo "Found $DS_COUNT InfluxDB datasource(s)"
echo ""

# Update each datasource
UPDATED=0
echo "$DATASOURCES" | jq -c '.[]' | while read -r datasource; do
    DS_ID=$(echo "$datasource" | jq -r '.id')
    DS_NAME=$(echo "$datasource" | jq -r '.name')
    DS_TYPE=$(echo "$datasource" | jq -r '.type')
    DS_URL=$(echo "$datasource" | jq -r '.url')
    
    # Only update InfluxDB datasources with old URL
    if [[ "$DS_TYPE" == "influxdb" ]] && [[ "$DS_URL" == "$OLD_URL" ]]; then
        echo "Updating datasource: $DS_NAME (ID: $DS_ID)"
        
        # Get full datasource config
        DS_CONFIG=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
            "$GRAFANA_URL/api/datasources/$DS_ID")
        
        # Update URL
        UPDATED_CONFIG=$(echo "$DS_CONFIG" | jq ".url = \"$NEW_URL\"")
        
        # Send update
        RESPONSE=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
            -X PUT \
            -H "Content-Type: application/json" \
            -d "$UPDATED_CONFIG" \
            "$GRAFANA_URL/api/datasources/$DS_ID")
        
        # Check response
        if echo "$RESPONSE" | jq -e '.message == "Datasource updated"' >/dev/null 2>&1; then
            echo "  ✓ Updated successfully"
            ((UPDATED++)) || true
        else
            echo "  ✗ Failed to update"
            echo "  Response: $RESPONSE"
        fi
    elif [[ "$DS_TYPE" == "influxdb" ]]; then
        echo "Skipping datasource: $DS_NAME (already uses $DS_URL)"
    fi
done

echo ""
echo "Updated $UPDATED datasource(s) to use $NEW_URL"
echo ""
echo "Please verify in Grafana:"
echo "  1. Navigate to Configuration → Data Sources"
echo "  2. Check that each InfluxDB datasource uses: $NEW_URL"
echo "  3. Click 'Save & Test' to verify connectivity"
