#!/bin/bash
#
# debug-grafana-query.sh
# Extract and debug Grafana panel queries with verbose InfluxDB execution
#
# Usage:
#   ./debug-grafana-query.sh --dashboard DASHBOARD_UID --panel PANEL_ID
#   ./debug-grafana-query.sh --query 'from(bucket: "sensor-readings") |> range(start: -1h)'
#

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://192.168.99.134:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
INFLUX_URL="${INFLUX_URL:-http://192.168.99.134:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"

# Command line arguments
DASHBOARD_UID=""
PANEL_ID=""
CUSTOM_QUERY=""
SHOW_RESULTS=5  # Number of sample results to show

# Colors
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
CYAN='\033[96m'
RESET='\033[0m'

# Usage help
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Debug Grafana panel queries by extracting and testing against InfluxDB.

OPTIONS:
    --dashboard UID        Dashboard UID to inspect
    --panel ID             Panel ID to debug
    --query FLUX           Test arbitrary Flux query
    --show-results N       Number of sample results to display (default: 5)
    --help                 Show this help message

EXAMPLES:
    # Debug specific panel
    $0 --dashboard soil-moisture-main-v2 --panel 3

    # Test custom query
    $0 --query 'from(bucket: "sensor-readings") |> range(start: -1h) |> limit(n: 10)'

CONFIGURATION:
    Set via environment variables:
      GRAFANA_URL      (default: http://192.168.99.134:3000)
      GRAFANA_USER     (default: admin)
      GRAFANA_PASSWORD (default: admin)
      INFLUX_URL       (default: http://192.168.99.134:8086)
      INFLUX_TOKEN     (required)
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dashboard)
            DASHBOARD_UID="$2"
            shift 2
            ;;
        --panel)
            PANEL_ID="$2"
            shift 2
            ;;
        --query)
            CUSTOM_QUERY="$2"
            shift 2
            ;;
        --show-results)
            SHOW_RESULTS="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [[ -z "$INFLUX_TOKEN" ]]; then
    echo -e "${RED}ERROR: INFLUX_TOKEN not set${RESET}"
    echo "Export it before running: export INFLUX_TOKEN='your_read_token'"
    exit 1
fi

if [[ -z "$CUSTOM_QUERY" ]] && [[ -z "$DASHBOARD_UID" || -z "$PANEL_ID" ]]; then
    echo -e "${RED}ERROR: Must specify either --query or both --dashboard and --panel${RESET}"
    usage
fi

# Function to fetch dashboard JSON
fetch_dashboard() {
    local uid=$1
    
    curl -sf \
        -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/dashboards/uid/${uid}"
}

# Function to extract panel query
extract_panel_query() {
    local dashboard_json=$1
    local panel_id=$2
    
    echo "$dashboard_json" | jq -r \
        ".dashboard.panels[] | select(.id == ${panel_id}) | .targets[0].query // empty"
}

# Function to test Flux query
test_flux_query() {
    local query=$1
    local start_time=$(date +%s.%N)
    
    # Create temp files
    local response_file=$(mktemp)
    local headers_file=$(mktemp)
    
    # Execute query
    http_code=$(curl -s -o "$response_file" -D "$headers_file" -w "%{http_code}" \
        -X POST \
        "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
        -H "Authorization: Token ${INFLUX_TOKEN}" \
        -H "Content-Type: application/vnd.flux" \
        -H "Accept: application/csv" \
        --data "$query")
    
    local end_time=$(date +%s.%N)
    local query_time=$(echo "$end_time - $start_time" | bc)
    
    # Parse results
    local result_count=0
    if [[ "$http_code" == "200" ]]; then
        result_count=$(grep -v '^#' "$response_file" | grep -v '^$' | tail -n +2 | wc -l | tr -d ' ')
    fi
    
    echo "$http_code|$query_time|$result_count|$response_file|$headers_file"
}

# Function to suggest fixes for common issues
suggest_fixes() {
    local query=$1
    local http_code=$2
    local error_response=$3
    
    echo ""
    echo -e "${YELLOW}=== SUGGESTED FIXES ===${RESET}"
    echo ""
    
    if [[ "$http_code" == "401" ]]; then
        echo "• Invalid or expired InfluxDB token"
        echo "  → Regenerate token in InfluxDB UI (Settings → API Tokens)"
        echo ""
        
    elif [[ "$http_code" == "404" ]]; then
        echo "• Bucket or organization not found"
        echo "  → Verify bucket exists: influx bucket list --org $INFLUX_ORG"
        echo ""
        
    elif echo "$error_response" | grep -q "measurement not found"; then
        echo "• Measurement does not exist"
        echo "  → Check available measurements:"
        echo "    from(bucket: \"$INFLUX_BUCKET\") |> range(start: -1d) |> group() |> distinct(column: \"_measurement\")"
        echo ""
        
    elif echo "$error_response" | grep -q "field not found"; then
        echo "• Field does not exist in measurement"
        echo "  → Check available fields:"
        echo "    from(bucket: \"$INFLUX_BUCKET\") |> range(start: -1d) |> group() |> distinct(column: \"_field\")"
        echo ""
    fi
    
    # Generic suggestions based on query content
    if echo "$query" | grep -q "device_id"; then
        echo "• Verify device_id exists in InfluxDB:"
        echo "  → List all device IDs:"
        echo "    from(bucket: \"$INFLUX_BUCKET\") |> range(start: -1d) |> keep(columns: [\"device_id\"]) |> distinct(column: \"device_id\")"
        echo ""
    fi
    
    if echo "$query" | grep -qE "range\(start: -[0-9]+[mh]\)"; then
        echo "• Time range might be too narrow"
        echo "  → Try expanding to -24h or -7d"
        echo ""
    fi
}

# Main execution
echo "════════════════════════════════════════════════════════════"
echo "Grafana Query Debugger"
echo "════════════════════════════════════════════════════════════"
echo ""

# Get query (either from panel or custom)
QUERY=""

if [[ -n "$CUSTOM_QUERY" ]]; then
    echo -e "${BLUE}Source:${RESET} Custom query"
    QUERY="$CUSTOM_QUERY"
    
else
    echo -e "${BLUE}Dashboard UID:${RESET} $DASHBOARD_UID"
    echo -e "${BLUE}Panel ID:${RESET}      $PANEL_ID"
    echo ""
    echo "Fetching dashboard JSON..."
    
    dashboard_json=$(fetch_dashboard "$DASHBOARD_UID")
    
    if [[ -z "$dashboard_json" ]]; then
        echo -e "${RED}ERROR: Failed to fetch dashboard${RESET}"
        echo "Check GRAFANA_URL, username, password, and dashboard UID"
        exit 1
    fi
    
    dashboard_title=$(echo "$dashboard_json" | jq -r '.dashboard.title')
    echo -e "${GREEN}✓${RESET} Dashboard: $dashboard_title"
    echo ""
    
    echo "Extracting panel query..."
    QUERY=$(extract_panel_query "$dashboard_json" "$PANEL_ID")
    
    if [[ -z "$QUERY" ]]; then
        echo -e "${RED}ERROR: No query found for panel ID $PANEL_ID${RESET}"
        echo ""
        echo "Available panels:"
        echo "$dashboard_json" | jq -r '.dashboard.panels[] | "  • Panel \(.id): \(.title) (type: \(.type))"'
        exit 1
    fi
    
    panel_title=$(echo "$dashboard_json" | jq -r ".dashboard.panels[] | select(.id == ${PANEL_ID}) | .title")
    echo -e "${GREEN}✓${RESET} Panel: $panel_title"
fi

echo ""
echo -e "${CYAN}=== FLUX QUERY ===${RESET}"
echo ""
echo "$QUERY"
echo ""

# Test query
echo -e "${CYAN}=== EXECUTING QUERY ===${RESET}"
echo ""
echo "InfluxDB: $INFLUX_URL"
echo "Organization: $INFLUX_ORG"
echo "Bucket: $INFLUX_BUCKET"
echo ""

IFS='|' read -r http_code query_time result_count response_file headers_file <<< "$(test_flux_query "$QUERY")"

echo -e "${CYAN}=== RESULTS ===${RESET}"
echo ""
echo "HTTP Status:    $http_code"
echo "Query Time:     ${query_time}s"
echo "Result Count:   $result_count rows"
echo ""

if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}✓ Query executed successfully${RESET}"
    echo ""
    
    if [[ $result_count -gt 0 ]]; then
        echo -e "${CYAN}=== SAMPLE RESULTS (first $SHOW_RESULTS rows) ===${RESET}"
        echo ""
        
        # Show header
        head -1 "$response_file" | grep -v '^#'
        
        # Show data rows
        grep -v '^#' "$response_file" | tail -n +2 | head -n "$SHOW_RESULTS"
        
        if [[ $result_count -gt $SHOW_RESULTS ]]; then
            echo ""
            echo "... and $((result_count - SHOW_RESULTS)) more rows"
        fi
        
    else
        echo -e "${YELLOW}⚠ Query returned 0 results${RESET}"
        echo ""
        suggest_fixes "$QUERY" "$http_code" "$(cat "$response_file")"
    fi
    
else
    echo -e "${RED}✗ Query failed${RESET}"
    echo ""
    echo -e "${RED}=== ERROR RESPONSE ===${RESET}"
    echo ""
    cat "$response_file"
    echo ""
    
    suggest_fixes "$QUERY" "$http_code" "$(cat "$response_file")"
fi

# Cleanup
rm -f "$response_file" "$headers_file"

echo ""
echo "════════════════════════════════════════════════════════════"

# Exit codes
if [[ "$http_code" == "200" ]] && [[ $result_count -gt 0 ]]; then
    exit 0  # Success
elif [[ "$http_code" == "200" ]] && [[ $result_count -eq 0 ]]; then
    exit 1  # No data
else
    exit 2  # Query error
fi
