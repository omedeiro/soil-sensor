#!/bin/bash
# Create Grafana snapshots for all dashboards
# Usage: ./create-snapshots.sh

GRAFANA_URL="http://192.168.99.134:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo "================================================================"
echo "Creating Grafana Snapshots for All Dashboards"
echo "================================================================"
echo ""

# Function to create snapshot
create_snapshot() {
    local dashboard_uid=$1
    local snapshot_name=$2
    local expire_days=$3
    
    echo "Creating snapshot: $snapshot_name"
    echo "  Dashboard UID: $dashboard_uid"
    
    # Get dashboard JSON
    dashboard_json=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/dashboards/uid/$dashboard_uid")
    
    # Create snapshot
    snapshot_response=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"dashboard\": $(echo "$dashboard_json" | jq '.dashboard'),
            \"name\": \"$snapshot_name\",
            \"expires\": $expire_days
        }" \
        "$GRAFANA_URL/api/snapshots")
    
    # Extract URL
    snapshot_url=$(echo "$snapshot_response" | jq -r '.url // empty')
    snapshot_key=$(echo "$snapshot_response" | jq -r '.key // empty')
    delete_key=$(echo "$snapshot_response" | jq -r '.deleteKey // empty')
    
    if [ -n "$snapshot_url" ]; then
        echo "  ✓ Snapshot created!"
        echo "  URL: $GRAFANA_URL$snapshot_url"
        echo "  Key: $snapshot_key"
        echo "  Delete URL: $GRAFANA_URL/api/snapshots-delete/$delete_key"
        echo ""
        
        # Save to file
        echo "$snapshot_name|$GRAFANA_URL$snapshot_url|$snapshot_key|$delete_key" >> snapshots.txt
    else
        echo "  ✗ Failed to create snapshot"
        echo "  Response: $snapshot_response"
        echo ""
    fi
}

# Clear previous snapshots file
> snapshots.txt
echo "# Grafana Dashboard Snapshots - v2.3.0" >> snapshots.txt
echo "# Created: $(date)" >> snapshots.txt
echo "# Expire: Never (0 = never expire)" >> snapshots.txt
echo "# Format: Name|URL|Key|DeleteKey" >> snapshots.txt
echo "" >> snapshots.txt

# Create snapshots for all 6 dashboards
# Expire: 0 = never, 3600 = 1 hour, 86400 = 1 day, 604800 = 7 days

create_snapshot "soil-moisture-main-v2" "Soil Moisture Dashboard v2.3.0" 0
create_snapshot "sensor-details-v1" "Sensor Details v2.3.0" 0
create_snapshot "system-health-v1" "System Health v2.3.0" 0
create_snapshot "alerts-overview-v1" "Alerts Overview v2.3.0" 0
create_snapshot "mobile-summary-v1" "Mobile Summary v2.3.0" 0
create_snapshot "rpi-health-v1" "Raspberry Pi Health v2.3.0" 0

echo "================================================================"
echo "Snapshots Created!"
echo "================================================================"
echo ""
echo "All snapshot URLs saved to: snapshots.txt"
echo ""
echo "To view snapshots:"
cat snapshots.txt | grep -v "^#" | grep -v "^$" | while IFS='|' read -r name url key delete; do
    echo "  $name"
    echo "    $url"
    echo ""
done

echo "To delete a snapshot, use the delete URL from snapshots.txt"
echo ""
