#!/bin/bash
#
# Dashboard Panel Testing Script
# Tests all Grafana dashboard panels for "No Data" issues
#
# Usage:
#   ./check-dashboard-panels.sh
#
# Environment variables:
#   GRAFANA_URL - Grafana base URL (default: http://192.168.99.134:3000)
#   GRAFANA_USER - Grafana username (default: admin)
#   GRAFANA_PASS - Grafana password (default: admin)
#   INFLUX_TOKEN - InfluxDB read token (required)
#   INFLUX_URL - InfluxDB URL (default: http://192.168.99.134:8086)
#   INFLUX_ORG - InfluxDB org (default: soil-monitoring)

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://192.168.99.134:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"
INFLUX_URL="${INFLUX_URL:-http://192.168.99.134:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"

if [ -z "${INFLUX_TOKEN:-}" ]; then
    echo "ERROR: INFLUX_TOKEN environment variable is required"
    echo "Usage: export INFLUX_TOKEN='your_read_token'"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Dashboard Panel Testing Script"
echo "=================================================="
echo ""
echo "Grafana URL: $GRAFANA_URL"
echo "InfluxDB URL: $INFLUX_URL"
echo ""

# Statistics
TOTAL_DASHBOARDS=0
TOTAL_PANELS=0
PANELS_WITH_DATA=0
PANELS_NO_DATA=0
PANELS_ERROR=0

# Temporary files
DASHBOARDS_LIST=$(mktemp)
PANEL_QUERIES=$(mktemp)
trap "rm -f $DASHBOARDS_LIST $PANEL_QUERIES" EXIT

# Fetch all dashboards
echo "Fetching dashboard list..."
if ! curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/search?type=dash-db" > "$DASHBOARDS_LIST"; then
    echo -e "${RED}ERROR: Failed to fetch dashboard list from Grafana${NC}"
    exit 1
fi

DASHBOARD_COUNT=$(jq length "$DASHBOARDS_LIST")
echo -e "${GREEN}Found $DASHBOARD_COUNT dashboards${NC}"
echo ""

# Process each dashboard
for row in $(jq -r '.[] | @base64' "$DASHBOARDS_LIST"); do
    _jq() {
        echo "$row" | base64 --decode | jq -r "$1"
    }
    
    uid=$(_jq '.uid')
    title=$(_jq '.title')
    
    TOTAL_DASHBOARDS=$((TOTAL_DASHBOARDS + 1))
    
    echo "----------------------------------------"
    echo -e "${BLUE}Dashboard: $title${NC}"
    echo "  UID: $uid"
    
    # Fetch dashboard details
    DASHBOARD_JSON=$(mktemp)
    if ! curl -sf -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/dashboards/uid/$uid" > "$DASHBOARD_JSON"; then
        echo -e "  ${RED}ERROR: Failed to fetch dashboard details${NC}"
        rm -f "$DASHBOARD_JSON"
        continue
    fi
    
    # Extract panels with queries
    PANEL_COUNT=$(jq '.dashboard.panels | length' "$DASHBOARD_JSON" 2>/dev/null || echo "0")
    echo "  Panels: $PANEL_COUNT"
    
    if [ "$PANEL_COUNT" -eq 0 ]; then
        rm -f "$DASHBOARD_JSON"
        continue
    fi
    
    # Test each panel
    for panel_idx in $(seq 0 $((PANEL_COUNT - 1))); do
        panel_title=$(jq -r ".dashboard.panels[$panel_idx].title // \"Untitled\"" "$DASHBOARD_JSON")
        panel_type=$(jq -r ".dashboard.panels[$panel_idx].type // \"unknown\"" "$DASHBOARD_JSON")
        
        # Skip panels without targets (like row panels)
        targets_count=$(jq ".dashboard.panels[$panel_idx].targets | length" "$DASHBOARD_JSON" 2>/dev/null || echo "0")
        if [ "$targets_count" -eq 0 ]; then
            continue
        fi
        
        TOTAL_PANELS=$((TOTAL_PANELS + 1))
        
        # Extract first query (most panels have only one)
        query=$(jq -r ".dashboard.panels[$panel_idx].targets[0].query // empty" "$DASHBOARD_JSON" 2>/dev/null || echo "")
        
        if [ -z "$query" ]; then
            echo -e "    ${YELLOW}⚠ $panel_title (${panel_type}): No query found${NC}"
            PANELS_ERROR=$((PANELS_ERROR + 1))
            continue
        fi
        
        # Test query against InfluxDB
        QUERY_RESULT=$(mktemp)
        if curl -sf \
            -H "Authorization: Token $INFLUX_TOKEN" \
            -H "Content-Type: application/vnd.flux" \
            -H "Accept: application/csv" \
            -XPOST "$INFLUX_URL/api/v2/query?org=$INFLUX_ORG" \
            --data-raw "$query" > "$QUERY_RESULT" 2>/dev/null; then
            
            # Check if result has data (more than just headers)
            line_count=$(wc -l < "$QUERY_RESULT")
            
            if [ "$line_count" -gt 1 ]; then
                echo -e "    ${GREEN}✓ $panel_title (${panel_type}): Has data ($line_count lines)${NC}"
                PANELS_WITH_DATA=$((PANELS_WITH_DATA + 1))
            else
                echo -e "    ${RED}✗ $panel_title (${panel_type}): NO DATA${NC}"
                PANELS_NO_DATA=$((PANELS_NO_DATA + 1))
            fi
        else
            echo -e "    ${RED}✗ $panel_title (${panel_type}): Query failed${NC}"
            PANELS_ERROR=$((PANELS_ERROR + 1))
        fi
        
        rm -f "$QUERY_RESULT"
    done
    
    rm -f "$DASHBOARD_JSON"
    echo ""
done

# Summary
echo "=================================================="
echo "  Summary"
echo "=================================================="
echo "Total Dashboards: $TOTAL_DASHBOARDS"
echo "Total Panels: $TOTAL_PANELS"
echo ""
echo -e "${GREEN}Panels with Data: $PANELS_WITH_DATA${NC}"
echo -e "${RED}Panels with NO DATA: $PANELS_NO_DATA${NC}"
echo -e "${YELLOW}Panels with Errors: $PANELS_ERROR${NC}"
echo ""

if [ "$PANELS_NO_DATA" -gt 0 ] || [ "$PANELS_ERROR" -gt 0 ]; then
    echo -e "${RED}FAILED: Some panels have issues${NC}"
    exit 1
else
    echo -e "${GREEN}SUCCESS: All panels are working correctly${NC}"
    exit 0
fi
