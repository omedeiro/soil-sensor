#!/bin/bash
# Comprehensive End-to-End Test for Soil Sensor System
# Tests: InfluxDB, Grafana, ESP8266 connectivity, data flow

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
}

# Configuration (update these for your setup)
INFLUX_URL="${INFLUX_URL:-http://192.168.99.200:8086}"
GRAFANA_URL="${GRAFANA_URL:-http://192.168.99.200:3000}"
ESP_IP="${ESP_IP:-192.168.99.70}"

log_section "🌱 Soil Sensor System - End-to-End Test"

PASS_COUNT=0
FAIL_COUNT=0

# ─── Test 1: InfluxDB Health ─────────────────────────────────────────────────

log_section "Test 1/8: InfluxDB Health Check"

if curl -sf "$INFLUX_URL/health" > /dev/null 2>&1; then
    log_info "InfluxDB is healthy"
    ((PASS_COUNT++))
else
    log_error "InfluxDB is not responding"
    ((FAIL_COUNT++))
fi

# ─── Test 2: Grafana Health ──────────────────────────────────────────────────

log_section "Test 2/8: Grafana Health Check"

if curl -sf "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
    log_info "Grafana is healthy"
    ((PASS_COUNT++))
else
    log_error "Grafana is not responding"
    ((FAIL_COUNT++))
fi

# ─── Test 3: InfluxDB Write Test ─────────────────────────────────────────────

log_section "Test 3/8: InfluxDB Write Test"

# NOTE: You need to set these environment variables:
# export INFLUX_TOKEN="your_write_token"
# export INFLUX_ORG="soil-monitoring"
# export INFLUX_BUCKET="sensor-readings"

if [ -z "$INFLUX_TOKEN" ]; then
    log_warn "INFLUX_TOKEN not set, skipping write test"
    log_warn "Set it with: export INFLUX_TOKEN='your_token'"
else
    TIMESTAMP=$(date +%s)
    TEST_PAYLOAD="sensor_reading,device_id=test-script,location=test moisture=50.0,raw_adc=500i,uptime=100i,crashes=0i,rssi=-50i,free_heap=35000i $TIMESTAMP"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "$INFLUX_URL/api/v2/write?org=${INFLUX_ORG:-soil-monitoring}&bucket=${INFLUX_BUCKET:-sensor-readings}&precision=s" \
        --header "Authorization: Token $INFLUX_TOKEN" \
        --header "Content-Type: text/plain" \
        --data-raw "$TEST_PAYLOAD")
    
    if [ "$HTTP_CODE" == "204" ] || [ "$HTTP_CODE" == "200" ]; then
        log_info "InfluxDB write successful (HTTP $HTTP_CODE)"
        ((PASS_COUNT++))
    else
        log_error "InfluxDB write failed (HTTP $HTTP_CODE)"
        ((FAIL_COUNT++))
    fi
fi

# ─── Test 4: InfluxDB Read Test ──────────────────────────────────────────────

log_section "Test 4/8: InfluxDB Read Test"

if [ -n "$INFLUX_TOKEN" ] && command -v influx &> /dev/null; then
    QUERY_RESULT=$(influx query \
        --host "$INFLUX_URL" \
        --org "${INFLUX_ORG:-soil-monitoring}" \
        --token "$INFLUX_TOKEN" \
        'from(bucket: "sensor-readings") |> range(start: -1h) |> limit(n: 1)' \
        2>&1)
    
    if echo "$QUERY_RESULT" | grep -q "moisture"; then
        log_info "InfluxDB read successful"
        ((PASS_COUNT++))
    else
        log_warn "InfluxDB read returned no data (may be normal if no data exists)"
    fi
else
    log_warn "Skipping read test (influx CLI not installed or token not set)"
fi

# ─── Test 5: Grafana Data Source ─────────────────────────────────────────────

log_section "Test 5/8: Grafana Data Source Test"

# This requires Grafana admin credentials
if [ -n "$GRAFANA_USER" ] && [ -n "$GRAFANA_PASSWORD" ]; then
    DS_HEALTH=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "$GRAFANA_URL/api/datasources/1/health" 2>&1)
    
    if echo "$DS_HEALTH" | grep -q "ok"; then
        log_info "Grafana data source is healthy"
        ((PASS_COUNT++))
    else
        log_error "Grafana data source is unhealthy"
        ((FAIL_COUNT++))
    fi
else
    log_warn "Skipping Grafana test (set GRAFANA_USER and GRAFANA_PASSWORD)"
fi

# ─── Test 6: ESP8266 Connectivity ────────────────────────────────────────────

log_section "Test 6/8: ESP8266 Connectivity"

if ping -c 3 -W 2 "$ESP_IP" > /dev/null 2>&1; then
    log_info "ESP8266 is online at $ESP_IP"
    ((PASS_COUNT++))
    
    # Try to fetch from web server
    if curl -sf --max-time 3 "http://$ESP_IP/api/latest" > /dev/null 2>&1; then
        log_info "ESP8266 web server is responding"
    else
        log_warn "ESP8266 online but web server not responding (may be disabled)"
    fi
else
    log_warn "ESP8266 is OFFLINE at $ESP_IP"
    log_warn "Check: WiFi connection, power supply, serial monitor"
fi

# ─── Test 7: System Health Services ──────────────────────────────────────────

log_section "Test 7/8: Systemd Services"

if command -v systemctl &> /dev/null; then
    SERVICES=("influxdb" "grafana-server" "sensor-health-monitor")
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "$service is running"
        else
            log_warn "$service is not running (may not be on this machine)"
        fi
    done
else
    log_warn "systemctl not available (test running on non-Pi machine?)"
fi

# ─── Test 8: Data Flow Verification ──────────────────────────────────────────

log_section "Test 8/8: Data Flow Verification"

if [ -n "$INFLUX_TOKEN" ] && command -v influx &> /dev/null; then
    echo "Checking for recent ESP8266 data in InfluxDB..."
    
    RECENT_DATA=$(influx query \
        --host "$INFLUX_URL" \
        --org "${INFLUX_ORG:-soil-monitoring}" \
        --token "$INFLUX_TOKEN" \
        'from(bucket: "sensor-readings") 
         |> range(start: -1h) 
         |> filter(fn: (r) => r._measurement == "sensor_reading")
         |> filter(fn: (r) => r.device_id != "test-script")
         |> group()
         |> count()' \
        --raw 2>&1 | tail -1)
    
    if echo "$RECENT_DATA" | grep -qE "[1-9][0-9]*"; then
        COUNT=$(echo "$RECENT_DATA" | awk '{print $NF}')
        log_info "Found $COUNT ESP8266 readings in last hour"
        log_info "Data flow is WORKING!"
        ((PASS_COUNT++))
    else
        log_warn "No ESP8266 data found in last hour"
        log_warn "Check: ESP8266 WiFi, InfluxDB config, serial monitor"
    fi
else
    log_warn "Skipping data flow test (influx CLI not available)"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

log_section "Test Summary"

echo ""
echo "Tests Passed: $PASS_COUNT"
echo "Tests Failed: $FAIL_COUNT"
echo "Tests Warned: (see output above)"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    log_info "All critical tests PASSED! 🎉"
    echo ""
    echo "Next steps:"
    echo "  1. Open Grafana: $GRAFANA_URL"
    echo "  2. Check dashboards for live data"
    echo "  3. Monitor ESP8266 serial output"
    exit 0
else
    log_error "Some tests FAILED"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check service logs: journalctl -u influxdb -f"
    echo "  - Check ESP8266 serial: cd firmware && pio device monitor"
    echo "  - Verify network connectivity"
    exit 1
fi
