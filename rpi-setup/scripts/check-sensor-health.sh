#!/bin/bash
#
# check-sensor-health.sh
# Monitor sensor health and alert when sensors stop posting to InfluxDB
#
# Usage:
#   ./check-sensor-health.sh [--alert-minutes N] [--notify]
#
# Options:
#   --alert-minutes N   Alert if no data for N minutes (default: 15)
#   --notify            Send notification (requires notification service setup)
#

set -euo pipefail

# Configuration
INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"  # Set via environment variable
ALERT_THRESHOLD_MINUTES=15  # Alert if no data for this many minutes
ENABLE_NOTIFICATIONS=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --alert-minutes)
      ALERT_THRESHOLD_MINUTES="$2"
      shift 2
      ;;
    --notify)
      ENABLE_NOTIFICATIONS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--alert-minutes N] [--notify]"
      exit 1
      ;;
  esac
done

# Check if INFLUX_TOKEN is set
if [ -z "$INFLUX_TOKEN" ]; then
  echo "Error: INFLUX_TOKEN environment variable not set"
  echo "Export it before running: export INFLUX_TOKEN='your_read_token'"
  exit 1
fi

# Flux query to check for recent sensor data
FLUX_QUERY="from(bucket: \"${INFLUX_BUCKET}\")
  |> range(start: -${ALERT_THRESHOLD_MINUTES}m)
  |> filter(fn: (r) => r._measurement == \"sensor_reading\")
  |> filter(fn: (r) => r._field == \"moisture\")
  |> group(columns: [\"device_id\"])
  |> last()
  |> keep(columns: [\"device_id\", \"_time\", \"_value\"])"

# Query InfluxDB
response=$(curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d "${FLUX_QUERY}")

# Parse response and check for each known sensor
# Expected sensors: sensor-1, sensor-2 (add more as needed)
EXPECTED_SENSORS=("sensor-1" "sensor-2")
OFFLINE_SENSORS=()
ONLINE_SENSORS=()

for sensor in "${EXPECTED_SENSORS[@]}"; do
  if echo "$response" | grep -q "device_id,$sensor"; then
    ONLINE_SENSORS+=("$sensor")
  else
    OFFLINE_SENSORS+=("$sensor")
  fi
done

# Print status
echo "════════════════════════════════════════════════════════════"
echo "Sensor Health Check - $(date)"
echo "════════════════════════════════════════════════════════════"
echo "Alert Threshold: ${ALERT_THRESHOLD_MINUTES} minutes"
echo ""

if [ ${#ONLINE_SENSORS[@]} -gt 0 ]; then
  echo "✅ ONLINE (${#ONLINE_SENSORS[@]}):"
  for sensor in "${ONLINE_SENSORS[@]}"; do
    echo "  - $sensor"
  done
fi

if [ ${#OFFLINE_SENSORS[@]} -gt 0 ]; then
  echo ""
  echo "❌ OFFLINE (${#OFFLINE_SENSORS[@]}):"
  for sensor in "${OFFLINE_SENSORS[@]}"; do
    echo "  - $sensor (no data for ${ALERT_THRESHOLD_MINUTES}+ minutes)"
  done
  
  # Send notification if enabled
  if [ "$ENABLE_NOTIFICATIONS" = true ]; then
    echo ""
    echo "⚠️  Sending notifications..."
    
    # Example: Log to system journal
    logger -t sensor-health "ALERT: ${#OFFLINE_SENSORS[@]} sensor(s) offline: ${OFFLINE_SENSORS[*]}"
    
    # TODO: Add your notification service here
    # Examples:
    # - Send email via sendmail/msmtp
    # - Post to Slack/Discord webhook
    # - Send push notification via ntfy.sh
    # - Use Grafana's built-in alerting (recommended)
    
    echo "  ✓ Logged to system journal"
    # echo "  ✓ Sent email notification"  # Uncomment after configuring
  fi
else
  echo ""
  echo "✅ All sensors reporting normally"
fi

echo ""
echo "════════════════════════════════════════════════════════════"

# Exit with error code if sensors offline (useful for monitoring)
if [ ${#OFFLINE_SENSORS[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
