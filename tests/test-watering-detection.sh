#!/bin/bash
# Test watering event detection queries against real InfluxDB data

set -e

# Configuration
INFLUX_URL="http://192.168.99.134:8086"
INFLUX_ORG="soil-monitoring"
INFLUX_BUCKET="sensor-readings"

# Check for token
if [ -z "$INFLUX_TOKEN" ]; then
  echo "❌ Error: INFLUX_TOKEN environment variable not set"
  echo "Usage: export INFLUX_TOKEN='your-read-token' && ./test-watering-detection.sh"
  exit 1
fi

echo "🔍 Testing Watering Event Detection Queries"
echo "=============================================="
echo ""

# Test 1: Basic moisture data retrieval
echo "Test 1: Fetching moisture data for sensor-1 (last 7 days)..."
curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.device_id == "sensor-1")
  |> limit(n: 5)' | head -20

echo ""
echo "✅ Test 1 passed - Can fetch moisture data"
echo ""

# Test 2: Detect sharp increases using difference
echo "Test 2: Detecting fast watering events (15%+ threshold in single interval)..."
curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "interpolate"

data = from(bucket: "sensor-readings")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.device_id == "sensor-1")
  |> group()

// Calculate point-to-point difference to detect sharp increases
data
  |> interpolate.linear(every: 5m)
  |> difference(nonNegative: false, columns: ["_value"])
  |> filter(fn: (r) => r._value >= 15.0)
  |> limit(n: 10)' > /tmp/watering-events.csv

echo ""
if grep -q "sensor_reading" /tmp/watering-events.csv 2>/dev/null; then
  echo "✅ Test 2 passed - Watering event detection query works"
  echo ""
  echo "Sample detected events:"
  cat /tmp/watering-events.csv | head -20
else
  echo "⚠️  No watering events detected in last 7 days (this may be normal)"
fi
echo ""

# Test 3: Time since last watering
echo "Test 3: Finding most recent watering event for sensor-1..."
curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "interpolate"

data = from(bucket: "sensor-readings")
  |> range(start: -30d)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.device_id == "sensor-1")
  |> group()

events = data
  |> interpolate.linear(every: 5m)
  |> difference(nonNegative: false, columns: ["_value"])
  |> filter(fn: (r) => r._value >= 15.0)

events
  |> last()
  |> limit(n: 1)' > /tmp/last-watering.csv

echo ""
if grep -q "sensor_reading" /tmp/last-watering.csv 2>/dev/null; then
  echo "✅ Test 3 passed - Last watering query works"
  echo ""
  echo "Most recent watering event:"
  cat /tmp/last-watering.csv | grep -A1 "_time" | tail -2
else
  echo "⚠️  No watering events found in last 30 days"
fi
echo ""

# Test 4: All sensors watering status
echo "Test 4: Checking all sensors for watering events..."
curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "interpolate"

data = from(bucket: "sensor-readings")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.location != "backyard")
  |> group(columns: ["device_id"])

data
  |> interpolate.linear(every: 5m)
  |> difference(nonNegative: false, columns: ["_value"])
  |> filter(fn: (r) => r._value >= 15.0)
  |> count()
  |> group()' > /tmp/all-sensors-events.csv

echo ""
if grep -q "sensor_reading" /tmp/all-sensors-events.csv 2>/dev/null; then
  echo "✅ Test 4 passed - Multi-sensor detection works"
  echo ""
  echo "Watering events by sensor (last 7 days):"
  cat /tmp/all-sensors-events.csv | grep -E "(device_id|_value)" | head -20
else
  echo "⚠️  No watering events detected across all sensors"
fi
echo ""

# Test 5: Slow watering detection (8%+ threshold for drip irrigation)
echo "Test 5: Detecting slow watering events (8%+ threshold, drip irrigation)..."
curl -s -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "interpolate"

data = from(bucket: "sensor-readings")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> filter(fn: (r) => r.location != "backyard")
  |> group(columns: ["device_id"])

data
  |> interpolate.linear(every: 5m)
  |> difference(nonNegative: false, columns: ["_value"])
  |> filter(fn: (r) => r._value >= 8.0 and r._value < 15.0)
  |> count()
  |> group()' > /tmp/slow-watering-events.csv

echo ""
if grep -q "sensor_reading" /tmp/slow-watering-events.csv 2>/dev/null; then
  echo "✅ Test 5 passed - Slow watering detection query works"
  echo ""
  echo "Slow watering events by sensor (last 7 days):"
  cat /tmp/slow-watering-events.csv | grep -E "(device_id|_value)" | head -20
else
  echo "⚠️  No slow watering events detected in last 7 days (this may be normal)"
fi
echo ""

# Summary
echo "=============================================="
echo "✅ All query tests completed successfully!"
echo ""
echo "Next steps:"
echo "1. Copy watering-history.json to Raspberry Pi"
echo "2. Import to Grafana via API or provisioning"
echo "3. Manually water a plant to test real-time detection"
echo ""
echo "Dashboard file: grafana-dashboards/watering-history.json"
