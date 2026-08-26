#!/bin/bash
# Test InfluxDB write from command line
# Useful for verifying connectivity and tokens

INFLUX_URL="${INFLUX_URL:-http://192.168.99.134:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"

if [ -z "$INFLUX_TOKEN" ]; then
    echo "Error: INFLUX_TOKEN environment variable not set"
    echo "Usage: export INFLUX_TOKEN='your_token' && ./test_influx_write.sh"
    exit 1
fi

echo "═══════════════════════════════════════"
echo "  InfluxDB Write Test"
echo "═══════════════════════════════════════"
echo ""
echo "URL:    $INFLUX_URL"
echo "Org:    $INFLUX_ORG"
echo "Bucket: $INFLUX_BUCKET"
echo ""

# Generate test data
TIMESTAMP=$(date +%s)
MOISTURE=$(awk -v min=30 -v max=70 'BEGIN{srand(); print min+rand()*(max-min)}')
RAW=$(awk -v min=400 -v max=700 'BEGIN{srand(); print int(min+rand()*(max-min))}')

echo "Sending test reading:"
echo "  Device: test-script"
echo "  Location: test"
echo "  Moisture: ${MOISTURE}%"
echo "  Raw ADC: $RAW"
echo "  Timestamp: $TIMESTAMP"
echo ""

# Build InfluxDB line protocol
PAYLOAD="sensor_reading,device_id=test-script,location=test moisture=${MOISTURE},raw_adc=${RAW}i,uptime=100i,crashes=0i,rssi=-50i,free_heap=35000i $TIMESTAMP"

# Send to InfluxDB
HTTP_CODE=$(curl -s -o /tmp/influx_response.txt -w "%{http_code}" -X POST \
    "$INFLUX_URL/api/v2/write?org=$INFLUX_ORG&bucket=$INFLUX_BUCKET&precision=s" \
    --header "Authorization: Token $INFLUX_TOKEN" \
    --header "Content-Type: text/plain" \
    --data-raw "$PAYLOAD")

echo "Response:"
echo "  HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" == "204" ] || [ "$HTTP_CODE" == "200" ]; then
    echo "  ✓ SUCCESS - Data written to InfluxDB"
    echo ""
    echo "Check Grafana dashboard to see the test data point!"
    echo "  URL: http://192.168.99.134:3000"
    exit 0
else
    echo "  ✗ FAILED"
    echo ""
    echo "Error details:"
    cat /tmp/influx_response.txt
    echo ""
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check InfluxDB is running: curl $INFLUX_URL/health"
    echo "  2. Verify token has write permission to bucket"
    echo "  3. Check bucket exists: influx bucket list --org $INFLUX_ORG"
    exit 1
fi
