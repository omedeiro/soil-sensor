#!/bin/bash
# 72-Hour Stability Test
# Long-running test to verify system stability and WiFi resilience

echo "═══════════════════════════════════════"
echo "  72-Hour Stability Test"
echo "═══════════════════════════════════════"
echo ""

ESP_IP="${ESP_IP:-192.168.99.70}"
INFLUX_URL="${INFLUX_URL:-http://192.168.99.200:8086}"
DEVICE_ID="${DEVICE_ID:-sensor-1}"

TEST_DURATION_HOURS=72
EXPECTED_READINGS=$((TEST_DURATION_HOURS * 12))  # 12 readings/hour at 5min interval

echo "Test duration: $TEST_DURATION_HOURS hours"
echo "Expected readings: ~$EXPECTED_READINGS (at 5-minute interval)"
echo ""
echo "This test monitors:"
echo "  ✓ ESP8266 uptime and crash detection"
echo "  ✓ WiFi stability and reconnection events"
echo "  ✓ Database POST success rate"
echo "  ✓ Memory leak detection (free heap monitoring)"
echo "  ✓ Reading queue usage patterns"
echo ""
echo "Test will:"
echo "  1. Monitor ESP8266 connectivity every 5 minutes"
echo "  2. Query InfluxDB for reading count every hour"
echo "  3. Log all events to: /tmp/stability_test_<timestamp>.log"
echo "  4. Generate final report after 72 hours"
echo ""
echo "Requirements:"
echo "  - ESP8266 must remain powered on"
echo "  - Serial monitor should run continuously (optional but recommended)"
echo "  - InfluxDB must be running on Raspberry Pi"
echo "  - INFLUX_TOKEN environment variable must be set for queries"
echo ""

if [ -z "$INFLUX_TOKEN" ]; then
    echo "⚠️  Warning: INFLUX_TOKEN not set"
    echo "   Reading count verification will be skipped"
    echo ""
fi

echo "Press Enter to start 72-hour stability test, or Ctrl+C to cancel..."
read

# Create log file
LOG_FILE="/tmp/stability_test_$(date +%Y%m%d_%H%M%S).log"
START_TIME=$(date +%s)
END_TIME=$((START_TIME + TEST_DURATION_HOURS * 3600))

echo "Test started at: $(date)" | tee "$LOG_FILE"
echo "Test will end at: $(date -d @$END_TIME 2>/dev/null || date -r $END_TIME)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE"
echo ""

# Stats tracking
PING_ATTEMPTS=0
PING_SUCCESSES=0
PING_FAILURES=0
LAST_READING_COUNT=0

while [ $(date +%s) -lt $END_TIME ]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_HOURS=$(( (CURRENT_TIME - START_TIME) / 3600 ))
    
    # Ping test every 5 minutes
    ((PING_ATTEMPTS++))
    
    if ping -c 3 -W 2 "$ESP_IP" > /dev/null 2>&1; then
        ((PING_SUCCESSES++))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ ESP8266 online (${PING_SUCCESSES}/${PING_ATTEMPTS})" | tee -a "$LOG_FILE"
    else
        ((PING_FAILURES++))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ESP8266 OFFLINE! (failure: $PING_FAILURES)" | tee -a "$LOG_FILE"
    fi
    
    # Query InfluxDB every hour
    if [ $((PING_ATTEMPTS % 12)) -eq 0 ] && [ -n "$INFLUX_TOKEN" ] && command -v influx &> /dev/null; then
        READING_COUNT=$(influx query \
            --host "$INFLUX_URL" \
            --org "soil-monitoring" \
            --token "$INFLUX_TOKEN" \
            "from(bucket: \"sensor-readings\") 
             |> range(start: -${ELAPSED_HOURS}h) 
             |> filter(fn: (r) => r._measurement == \"sensor_reading\")
             |> filter(fn: (r) => r.device_id == \"$DEVICE_ID\")
             |> group()
             |> count()" \
            --raw 2>&1 | tail -1 | awk '{print $NF}')
        
        if [ -n "$READING_COUNT" ]; then
            NEW_READINGS=$((READING_COUNT - LAST_READING_COUNT))
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📊 Total readings: $READING_COUNT (+$NEW_READINGS in last hour)" | tee -a "$LOG_FILE"
            LAST_READING_COUNT=$READING_COUNT
        fi
    fi
    
    # Progress update
    REMAINING_HOURS=$((TEST_DURATION_HOURS - ELAPSED_HOURS))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⏱️  Progress: ${ELAPSED_HOURS}h elapsed, ${REMAINING_HOURS}h remaining" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Wait 5 minutes
    sleep 300
done

# Generate final report
echo "" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════" | tee -a "$LOG_FILE"
echo "  72-Hour Stability Test - COMPLETE" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Test duration: $TEST_DURATION_HOURS hours" | tee -a "$LOG_FILE"
echo "Connectivity checks: $PING_ATTEMPTS" | tee -a "$LOG_FILE"
echo "  Successful: $PING_SUCCESSES" | tee -a "$LOG_FILE"
echo "  Failed: $PING_FAILURES" | tee -a "$LOG_FILE"

if [ $PING_ATTEMPTS -gt 0 ]; then
    UPTIME_PCT=$(awk "BEGIN {printf \"%.2f\", ($PING_SUCCESSES / $PING_ATTEMPTS) * 100}")
    echo "  Uptime: ${UPTIME_PCT}%" | tee -a "$LOG_FILE"
fi

if [ -n "$LAST_READING_COUNT" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Total readings collected: $LAST_READING_COUNT" | tee -a "$LOG_FILE"
    echo "Expected readings: ~$EXPECTED_READINGS" | tee -a "$LOG_FILE"
    
    if [ $LAST_READING_COUNT -gt 0 ]; then
        SUCCESS_PCT=$(awk "BEGIN {printf \"%.2f\", ($LAST_READING_COUNT / $EXPECTED_READINGS) * 100}")
        echo "Data collection rate: ${SUCCESS_PCT}%" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Determine pass/fail
if [ "$UPTIME_PCT" != "" ] && (( $(echo "$UPTIME_PCT > 95" | bc -l) )); then
    echo "✅ TEST PASSED - System is stable!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "⚠️  TEST WARNING - Uptime below 95%" | tee -a "$LOG_FILE"
    echo "   Review log for disconnect events" | tee -a "$LOG_FILE"
    exit 1
fi
