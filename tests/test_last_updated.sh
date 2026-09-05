#!/bin/bash
# Test script to verify Last Updated panel query returns correct data

set -e

INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"

# Prefer the environment; fall back to the Pi's config file when it is readable.
CONFIG_FILE="${CONFIG_DIR:-/mnt/sensor-data/config}/panel-health.env"
if [ -z "${INFLUX_TOKEN:-}" ] && [ -r "$CONFIG_FILE" ]; then
    INFLUX_TOKEN="$(grep -m1 '^INFLUX_TOKEN=' "$CONFIG_FILE" | cut -d= -f2- | tr -d '"')"
fi

if [ -z "${INFLUX_TOKEN:-}" ]; then
    echo "Error: INFLUX_TOKEN environment variable not set"
    echo "Usage: export INFLUX_TOKEN='your_read_token' && ./test_last_updated.sh"
    exit 1
fi

echo "=== Testing Last Updated Panel Query ==="
echo ""

# Get the value from the query
QUERY_RESULT=$(curl -s "$INFLUX_URL/api/v2/query?org=$INFLUX_ORG" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r.location != "backyard")
  |> filter(fn: (r) => r._field == "moisture")
  |> group()
  |> max(column: "_time")
  |> map(fn: (r) => ({_time: r._time, _value: uint(v: r._time) / uint(v: 1000000)}))')

# Extract the _value (timestamp in milliseconds)
# InfluxDB returns CSV with CRLF line endings. Without stripping the trailing
# \r the value is non-numeric, $((LAST_READING_MS / 1000)) evaluates to 0, the
# elapsed-time maths returns a whole epoch ("496604 hours old"), and the date
# call below is handed an empty argument:
#     date: option requires an argument -- 'r'
LAST_READING_MS=$(echo "$QUERY_RESULT" | grep "^," | tail -1 | cut -d',' -f5 | tr -d '\r')

if ! printf '%s' "$LAST_READING_MS" | grep -qE '^[0-9]+$'; then
    echo "❌ FAILED: Query returned no usable timestamp (got: \"$LAST_READING_MS\")"
    echo ""
    echo "Full response:"
    echo "$QUERY_RESULT"
    exit 1
fi

# Get current time in seconds and milliseconds
CURRENT_SEC=$(date +%s)
LAST_READING_SEC=$((LAST_READING_MS / 1000))

# Calculate difference
DIFF_SECONDS=$((CURRENT_SEC - LAST_READING_SEC))

echo "Last reading timestamp: $LAST_READING_MS ms ($(date -d @$LAST_READING_SEC 2>/dev/null || date -r $LAST_READING_SEC))"
echo "Current timestamp:      ${CURRENT_SEC}000 ms"
echo "Difference:             $DIFF_SECONDS seconds ago"
echo ""

if [ $DIFF_SECONDS -lt 0 ]; then
    echo "⚠️  WARNING: Last reading is in the future! Check system clocks."
    exit 1
elif [ $DIFF_SECONDS -lt 600 ]; then
    echo "✅ PASS: Last reading is recent ($DIFF_SECONDS seconds ago)"
    echo ""
    echo "Expected Grafana display: 'a few seconds ago' or 'a minute ago'"
    exit 0
elif [ $DIFF_SECONDS -lt 3600 ]; then
    MINUTES=$((DIFF_SECONDS / 60))
    echo "✅ PASS: Last reading is $MINUTES minutes ago"
    echo ""
    echo "Expected Grafana display: '$MINUTES minutes ago'"
    exit 0
else
    HOURS=$((DIFF_SECONDS / 3600))
    echo "⚠️  WARNING: Last reading is $HOURS hours old"
    echo "Expected Grafana display: '$HOURS hours ago'"
    exit 0
fi
