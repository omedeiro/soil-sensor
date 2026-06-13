#!/bin/bash
#
# check-sensor-health.sh
# Enhanced sensor health monitor with multi-timeframe checks and auto-detection
#
# Usage:
#   ./check-sensor-health.sh [OPTIONS]
#
# Options:
#   --alert-minutes N      Alert if no data for N minutes (default: 15)
#   --check-quality        Enable data quality validation (stuck sensors, invalid ranges)
#   --notify               Send Slack notification
#   --slack-topic TOPIC    Slack rate-limit topic (default: sensor-health)
#   --verbose              Show detailed output
#   --help                 Show this help message
#

set -euo pipefail

# Configuration
INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"
SENSORS_CONFIG="${SENSORS_CONFIG:-/home/omedeiro/soil-sensor/sensors-config.json}"
ALERT_THRESHOLD_MINUTES=15
CHECK_QUALITY=false
ENABLE_NOTIFICATIONS=false
SLACK_TOPIC="sensor-health"
VERBOSE=false

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Try to find send-slack-alert.sh
SLACK_SCRIPT="${PROJECT_ROOT}/scripts/send-slack-alert.sh"

# Colors
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
RESET='\033[0m'

# Usage help
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Enhanced sensor health monitoring with auto-detection and data quality checks.

OPTIONS:
    --alert-minutes N      Alert if no data for N minutes (default: 15)
    --check-quality        Enable data quality validation
    --notify               Send Slack notification on issues
    --slack-topic TOPIC    Slack rate-limit topic (default: sensor-health)
    --verbose              Show detailed output
    --help                 Show this help message

EXAMPLES:
    # Basic health check
    $0

    # Check with quality validation
    $0 --check-quality

    # Send Slack alerts for offline sensors
    $0 --notify

    # Custom alert threshold
    $0 --alert-minutes 30 --notify

CONFIGURATION:
    INFLUX_TOKEN must be set via environment variable:
      export INFLUX_TOKEN='your_read_token'
    
    Sensors are auto-detected from: $SENSORS_CONFIG

EXIT CODES:
    0   All sensors healthy
    1   One or more sensors offline
    2   InfluxDB connection error
    3   Configuration error
EOF
    exit 0
}

# Logging functions
log_info() { 
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[$(date +'%H:%M:%S')] ${BLUE}INFO:${RESET} $*" >&2
    fi
}
log_error() { echo -e "[$(date +'%H:%M:%S')] ${RED}ERROR:${RESET} $*" >&2; }

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --alert-minutes)
            ALERT_THRESHOLD_MINUTES="$2"
            shift 2
            ;;
        --check-quality)
            CHECK_QUALITY=true
            shift
            ;;
        --notify)
            ENABLE_NOTIFICATIONS=true
            shift
            ;;
        --slack-topic)
            SLACK_TOPIC="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
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

# Check dependencies
if [ -z "$INFLUX_TOKEN" ]; then
    log_error "INFLUX_TOKEN environment variable not set"
    log_error "Export it before running: export INFLUX_TOKEN='your_read_token'"
    exit 3
fi

if ! command -v jq &> /dev/null; then
    log_error "'jq' command not found - required for JSON parsing"
    log_error "Install with: sudo apt-get install jq"
    exit 3
fi

# Auto-detect sensors from sensors-config.json
if [[ ! -f "$SENSORS_CONFIG" ]]; then
    log_error "Sensors config not found: $SENSORS_CONFIG"
    log_error "Set SENSORS_CONFIG environment variable to correct path"
    exit 3
fi

log_info "Loading sensors from: $SENSORS_CONFIG"
EXPECTED_SENSORS=($(jq -r '.sensors[].id' "$SENSORS_CONFIG"))
SENSOR_PLANTS=($(jq -r '.sensors[].plant' "$SENSORS_CONFIG"))

if [[ ${#EXPECTED_SENSORS[@]} -eq 0 ]]; then
    log_error "No sensors found in $SENSORS_CONFIG"
    exit 3
fi

log_info "Found ${#EXPECTED_SENSORS[@]} sensors: ${EXPECTED_SENSORS[*]}"

# Function to query InfluxDB
query_influx() {
    local flux_query=$1
    local response
    
    response=$(curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
        -H "Authorization: Token ${INFLUX_TOKEN}" \
        -H "Content-Type: application/vnd.flux" \
        -d "${flux_query}" 2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "InfluxDB query failed: $response"
        return 2
    fi
    
    if echo "$response" | grep -q "unauthorized"; then
        log_error "InfluxDB unauthorized - invalid token"
        return 2
    fi
    
    echo "$response"
    return 0
}

# Check recent sensor data (last N minutes)
check_recent_data() {
    local minutes=$1
    
    log_info "Checking data from last ${minutes} minutes"
    
    local flux_query="from(bucket: \"${INFLUX_BUCKET}\")
  |> range(start: -${minutes}m)
  |> filter(fn: (r) => r._measurement == \"sensor_reading\")
  |> filter(fn: (r) => r._field == \"moisture\")
  |> group(columns: [\"device_id\"])
  |> last()
  |> keep(columns: [\"device_id\", \"_time\", \"_value\"])"
    
    local response
    if ! response=$(query_influx "$flux_query"); then
        return 2
    fi
    
    echo "$response"
}

# Check data quality (stuck sensors, invalid ranges)
check_data_quality() {
    log_info "Checking data quality (last 1 hour)"
    
    local flux_query="from(bucket: \"${INFLUX_BUCKET}\")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == \"sensor_reading\")
  |> filter(fn: (r) => r._field == \"moisture\")
  |> group(columns: [\"device_id\"])
  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)
  |> stddev()
  |> keep(columns: [\"device_id\", \"_value\"])"
    
    local response
    if ! response=$(query_influx "$flux_query"); then
        return 2
    fi
    
    echo "$response"
}

# Send Slack notification
send_slack_notification() {
    local severity=$1
    local title=$2
    local message=$3
    
    if [[ ! -x "$SLACK_SCRIPT" ]]; then
        log_error "Slack script not found or not executable: $SLACK_SCRIPT"
        return 1
    fi
    
    log_info "Sending Slack notification: $title"
    
    "$SLACK_SCRIPT" \
        --severity "$severity" \
        --title "$title" \
        --message "$message" \
        --topic "$SLACK_TOPIC" 2>&1 | grep -v "^$" || true
    
    return ${PIPESTATUS[0]}
}

# Print header
echo "════════════════════════════════════════════════════════════"
echo "Sensor Health Check - $(date +'%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════"
echo "InfluxDB:        $INFLUX_URL"
echo "Bucket:          $INFLUX_BUCKET"
echo "Alert Threshold: ${ALERT_THRESHOLD_MINUTES} minutes"
echo "Sensors:         ${#EXPECTED_SENSORS[@]} configured"
echo ""

# Test InfluxDB connection
log_info "Testing InfluxDB connection"
if ! curl -sf --max-time 5 "${INFLUX_URL}/health" > /dev/null 2>&1; then
    echo -e "${RED}✗ InfluxDB Connection: FAILED${RESET}"
    echo "  URL: $INFLUX_URL"
    echo "  Error: Connection refused or timeout"
    exit 2
fi
echo -e "${GREEN}✓ InfluxDB Connection: OK${RESET}"

# Test token validity
log_info "Testing InfluxDB token"
test_response=$(query_influx "from(bucket: \"${INFLUX_BUCKET}\") |> range(start: -1m) |> limit(n: 1)")
if [[ $? -ne 0 ]]; then
    echo -e "${RED}✗ Token Validation: FAILED${RESET}"
    echo "  Check INFLUX_TOKEN is valid and has read permission"
    exit 2
fi
echo -e "${GREEN}✓ Token Validation: OK${RESET}"
echo ""

# Check recent sensor data (primary timeframe)
echo "Checking Recent Data (last ${ALERT_THRESHOLD_MINUTES} minutes)"
echo "────────────────────────────────────────────────────────────"

response=$(check_recent_data "$ALERT_THRESHOLD_MINUTES")
if [[ $? -ne 0 ]]; then
    exit 2
fi

OFFLINE_SENSORS=()
ONLINE_SENSORS=()
SENSOR_DATA=()

for i in "${!EXPECTED_SENSORS[@]}"; do
    sensor="${EXPECTED_SENSORS[$i]}"
    plant="${SENSOR_PLANTS[$i]}"
    
    if echo "$response" | grep -q "device_id,$sensor"; then
        ONLINE_SENSORS+=("$sensor")
        
        # Extract latest value and timestamp
        moisture=$(echo "$response" | grep "device_id,$sensor" | tail -1 | awk -F',' '{print $NF}')
        timestamp=$(echo "$response" | grep "device_id,$sensor" | tail -1 | awk -F',' '{print $(NF-1)}')
        
        SENSOR_DATA+=("$sensor|$plant|$moisture|$timestamp")
        
        echo -e "  ${GREEN}✓${RESET} $sensor ($plant) - ${moisture}% @ $(date -d "$timestamp" +'%H:%M:%S' 2>/dev/null || echo "$timestamp")"
    else
        OFFLINE_SENSORS+=("$sensor|$plant")
        echo -e "  ${RED}✗${RESET} $sensor ($plant) - NO DATA for ${ALERT_THRESHOLD_MINUTES}+ minutes"
    fi
done

echo ""

# Check 1-hour history
echo "Checking 1-Hour History"
echo "────────────────────────────────────────────────────────────"

hour_response=$(check_recent_data 60)
if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}⚠ Unable to check 1-hour history${RESET}"
else
    # Count data points per sensor (should be ~12 readings for 5-minute intervals)
    for sensor in "${EXPECTED_SENSORS[@]}"; do
        count=$(echo "$hour_response" | grep -c "device_id,$sensor" || echo "0")
        expected=12
        
        if [[ $count -ge $expected ]]; then
            echo -e "  ${GREEN}✓${RESET} $sensor: $count readings (expected: ~$expected)"
        elif [[ $count -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠${RESET} $sensor: $count readings (expected: ~$expected) - sporadic connectivity"
        else
            echo -e "  ${RED}✗${RESET} $sensor: No data in last hour"
        fi
    done
fi

echo ""

# Data quality checks
if [[ "$CHECK_QUALITY" == "true" ]]; then
    echo "Data Quality Validation"
    echo "────────────────────────────────────────────────────────────"
    
    quality_response=$(check_data_quality)
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}⚠ Unable to check data quality${RESET}"
    else
        QUALITY_ISSUES=()
        
        for i in "${!EXPECTED_SENSORS[@]}"; do
            sensor="${EXPECTED_SENSORS[$i]}"
            plant="${SENSOR_PLANTS[$i]}"
            
            # Check for stuck sensors (stddev close to 0)
            stddev=$(echo "$quality_response" | grep "device_id,$sensor" | tail -1 | awk -F',' '{print $NF}')
            
            if [[ -n "$stddev" ]]; then
                # Check if stddev < 0.5 (likely stuck)
                if awk -v std="$stddev" 'BEGIN {exit !(std < 0.5)}'; then
                    echo -e "  ${YELLOW}⚠${RESET} $sensor ($plant): Potentially stuck (stddev: $stddev)"
                    QUALITY_ISSUES+=("$sensor: stuck sensor")
                else
                    echo -e "  ${GREEN}✓${RESET} $sensor ($plant): Normal variation (stddev: $stddev)"
                fi
            fi
            
            # Check value ranges (0-100%)
            for data in "${SENSOR_DATA[@]}"; do
                IFS='|' read -r s_id s_plant s_moisture s_time <<< "$data"
                
                if [[ "$s_id" == "$sensor" ]]; then
                    if awk -v m="$s_moisture" 'BEGIN {exit !(m < 0 || m > 100)}'; then
                        echo -e "  ${RED}✗${RESET} $sensor ($plant): Invalid moisture value: ${s_moisture}%"
                        QUALITY_ISSUES+=("$sensor: invalid value $s_moisture%")
                    fi
                fi
            done
        done
        
        if [[ ${#QUALITY_ISSUES[@]} -eq 0 ]]; then
            echo -e "  ${GREEN}✓ All sensors passing quality checks${RESET}"
        fi
    fi
    
    echo ""
fi

# Summary
echo "Summary"
echo "────────────────────────────────────────────────────────────"
echo -e "${GREEN}✓ Online:${RESET}  ${#ONLINE_SENSORS[@]}/${#EXPECTED_SENSORS[@]} sensors"

if [[ ${#OFFLINE_SENSORS[@]} -gt 0 ]]; then
    echo -e "${RED}✗ Offline:${RESET} ${#OFFLINE_SENSORS[@]}/${#EXPECTED_SENSORS[@]} sensors"
fi

if [[ "$CHECK_QUALITY" == "true" ]] && [[ ${#QUALITY_ISSUES[@]} -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Quality:${RESET} ${#QUALITY_ISSUES[@]} issue(s) detected"
fi

echo ""
echo "════════════════════════════════════════════════════════════"

# Send Slack notification if enabled and issues detected
if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && [[ ${#OFFLINE_SENSORS[@]} -gt 0 ]]; then
    echo ""
    echo "Sending Slack notification..."
    
    # Build message
    offline_list=""
    for sensor_info in "${OFFLINE_SENSORS[@]}"; do
        IFS='|' read -r sensor plant <<< "$sensor_info"
        offline_list+="  • $sensor ($plant)\n"
    done
    
    message="${#OFFLINE_SENSORS[@]} of ${#EXPECTED_SENSORS[@]} sensors offline:\n${offline_list}\nNo data for ${ALERT_THRESHOLD_MINUTES}+ minutes"
    
    if send_slack_notification "warning" "Sensor Offline Alert" "$message"; then
        echo -e "${GREEN}✓ Slack notification sent${RESET}"
    else
        echo -e "${YELLOW}⚠ Slack notification failed (may be rate limited)${RESET}"
    fi
fi

# Exit codes
if [[ ${#OFFLINE_SENSORS[@]} -gt 0 ]]; then
    exit 1
else
    exit 0
fi
