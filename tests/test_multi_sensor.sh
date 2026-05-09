#!/bin/bash
# Multi-Sensor Simulation Test
# Sends data from multiple simulated sensors to test Grafana multi-sensor dashboards

INFLUX_URL="${INFLUX_URL:-http://192.168.99.200:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"

if [ -z "$INFLUX_TOKEN" ]; then
    echo "Error: INFLUX_TOKEN not set"
    echo "Usage: export INFLUX_TOKEN='your_token' && ./test_multi_sensor.sh"
    exit 1
fi

echo "═══════════════════════════════════════"
echo "  Multi-Sensor Simulation Test"
echo "═══════════════════════════════════════"
echo ""
echo "Simulating 5 sensors in different locations..."
echo ""

# Sensor configurations
SENSORS=(
    "sensor-1:backyard"
    "sensor-2:greenhouse"
    "sensor-3:garden-bed-a"
    "sensor-4:garden-bed-b"
    "sensor-5:front-yard"
)

TIMESTAMP=$(date +%s)
SUCCESS_COUNT=0
FAIL_COUNT=0

for sensor_config in "${SENSORS[@]}"; do
    IFS=':' read -r device_id location <<< "$sensor_config"
    
    # Generate realistic random data
    MOISTURE=$(awk -v min=25 -v max=75 'BEGIN{srand(); print min+rand()*(max-min)}')
    RAW=$(awk -v moisture=$MOISTURE 'BEGIN{print int(780 - (moisture/100.0) * (780-360))}')
    RSSI=$((45 + RANDOM % 30))  # -45 to -75 dBm
    
    echo "[$device_id] @ $location"
    echo "  Moisture: ${MOISTURE}%"
    echo "  Raw ADC: $RAW"
    echo "  RSSI: -${RSSI} dBm"
    
    # Build line protocol
    PAYLOAD="sensor_reading,device_id=$device_id,location=$location moisture=${MOISTURE},raw_adc=${RAW}i,uptime=3600i,crashes=0i,rssi=-${RSSI}i,free_heap=35000i $TIMESTAMP"
    
    # Send to InfluxDB
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "$INFLUX_URL/api/v2/write?org=$INFLUX_ORG&bucket=$INFLUX_BUCKET&precision=s" \
        --header "Authorization: Token $INFLUX_TOKEN" \
        --header "Content-Type: text/plain" \
        --data-raw "$PAYLOAD")
    
    if [ "$HTTP_CODE" == "204" ] || [ "$HTTP_CODE" == "200" ]; then
        echo "  ✓ Sent successfully"
        ((SUCCESS_COUNT++))
    else
        echo "  ✗ Failed (HTTP $HTTP_CODE)"
        ((FAIL_COUNT++))
    fi
    
    echo ""
    sleep 1  # Small delay between sensors
done

echo "═══════════════════════════════════════"
echo "Summary:"
echo "  Successful: $SUCCESS_COUNT / ${#SENSORS[@]}"
echo "  Failed: $FAIL_COUNT"
echo ""

if [ $SUCCESS_COUNT -eq ${#SENSORS[@]} ]; then
    echo "✓ All sensors sent data successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Open Grafana: http://192.168.99.200:3000"
    echo "  2. Check multi-sensor dashboard"
    echo "  3. Verify all 5 sensors appear"
    echo "  4. Check location filtering works"
    exit 0
else
    echo "⚠ Some sensors failed to send data"
    exit 1
fi
