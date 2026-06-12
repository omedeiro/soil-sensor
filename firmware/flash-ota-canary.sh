#!/bin/bash
# flash-ota-canary.sh
# Safe OTA deployment with canary testing
# Flashes one sensor first, waits for verification, then flashes remaining sensors

set -e

# Sensor configuration (from sensors-config.json)
declare -A SENSORS=(
    ["sensor-1"]="192.168.99.110"  # Rubber Tree (bed-room)
    ["sensor-2"]="192.168.99.149"  # Monstera (living-room)
    ["sensor-3"]="192.168.99.70"   # Avocado (living-room)
    ["sensor-4"]="192.168.99.105"  # Basil auk (guest-room)
    ["sensor-5"]="192.168.99.89"   # ZZ Plant (bed-room)
    ["sensor-6"]="192.168.99.38"   # Ficus Elastica Ruby (living-room)
    ["sensor-7"]="192.168.99.141"  # Basil pot (guest-room)
)

# Canary sensor (sensor-7 is designated test sensor)
CANARY_SENSOR="sensor-7"
CANARY_IP="${SENSORS[$CANARY_SENSOR]}"

# Configuration
OTA_PORT="8266"
OTA_PASSWORD="${OTA_PASSWORD:-soilmon2026}"
FIRMWARE_PATH=".pio/build/esp8266/firmware.bin"
CANARY_WAIT_SECONDS=600  # Wait 10 minutes after canary deployment
HEALTH_CHECK_INTERVAL=30  # Check canary health every 30 seconds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Canary OTA Deployment ===${NC}"
echo ""

# Validate firmware exists
if [[ ! -f "$FIRMWARE_PATH" ]]; then
    echo -e "${RED}✗ Firmware not found: $FIRMWARE_PATH${NC}"
    echo "Run 'pio run' to build firmware first"
    exit 1
fi

FIRMWARE_SIZE=$(ls -lh "$FIRMWARE_PATH" | awk '{print $5}')
echo -e "Firmware: ${GREEN}$FIRMWARE_PATH${NC} ($FIRMWARE_SIZE)"
echo ""

# Backup current firmware
echo "Creating firmware backup..."
BACKUP_PATH="$FIRMWARE_PATH.backup.$(date +%Y%m%d_%H%M%S)"
cp "$FIRMWARE_PATH" "$BACKUP_PATH"
echo -e "  ✓ Backup saved: ${BLUE}$BACKUP_PATH${NC}"
echo ""

# Function to ping sensor
ping_sensor() {
    local ip=$1
    ping -c 1 -W 2 "$ip" >/dev/null 2>&1
}

# Function to check sensor API
check_sensor_api() {
    local ip=$1
    curl -s --max-time 5 "http://$ip/api/latest" >/dev/null 2>&1
}

# Function to flash sensor via OTA
flash_sensor_ota() {
    local sensor_id=$1
    local ip=$2
    
    echo -e "${YELLOW}Flashing $sensor_id at $ip...${NC}"
    
    if ! ping_sensor "$ip"; then
        echo -e "${RED}  ✗ Sensor offline (no ping response)${NC}"
        return 1
    fi
    
    # Flash via platformio
    pio run --target upload --upload-port "$ip" 2>&1 | tee /tmp/ota_flash_$sensor_id.log | grep -E "(Success|Failed|Error|Uploading)"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo -e "${GREEN}  ✓ Flashed successfully${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Flash failed${NC}"
        return 1
    fi
}

# Function to wait for sensor to boot
wait_for_boot() {
    local sensor_id=$1
    local ip=$2
    local max_wait=60
    local elapsed=0
    
    echo -n "  Waiting for $sensor_id to boot..."
    while [[ $elapsed -lt $max_wait ]]; do
        if ping_sensor "$ip"; then
            echo -e " ${GREEN}OK${NC} (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo -e " ${RED}TIMEOUT${NC}"
    return 1
}

# Function to monitor canary health
monitor_canary() {
    local ip=$1
    local duration=$2
    local interval=$3
    
    local checks=$((duration / interval))
    local passed=0
    local failed=0
    
    echo -e "${BLUE}Monitoring canary for $duration seconds (checking every ${interval}s)...${NC}"
    
    for ((i=1; i<=checks; i++)); do
        sleep "$interval"
        
        local status=""
        if ping_sensor "$ip" && check_sensor_api "$ip"; then
            status="${GREEN}✓${NC}"
            ((passed++))
        else
            status="${RED}✗${NC}"
            ((failed++))
        fi
        
        local progress=$((i * 100 / checks))
        echo -e "  [$status] Check $i/$checks (${progress}%) - Passed: $passed, Failed: $failed"
        
        # Abort if too many failures
        if [[ $failed -gt 3 ]]; then
            echo -e "${RED}Too many health check failures! Aborting deployment.${NC}"
            return 1
        fi
    done
    
    echo ""
    local success_rate=$((passed * 100 / checks))
    if [[ $success_rate -ge 90 ]]; then
        echo -e "${GREEN}✓ Canary health check passed ($success_rate% success rate)${NC}"
        return 0
    else
        echo -e "${RED}✗ Canary health check failed ($success_rate% success rate)${NC}"
        return 1
    fi
}

# =============================================================================
# PHASE 1: CANARY DEPLOYMENT
# =============================================================================

echo -e "${BLUE}=== PHASE 1: Canary Deployment ===${NC}"
echo -e "Canary sensor: ${YELLOW}$CANARY_SENSOR${NC} at ${YELLOW}$CANARY_IP${NC}"
echo ""

read -p "Flash canary sensor now? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Flash canary
if ! flash_sensor_ota "$CANARY_SENSOR" "$CANARY_IP"; then
    echo -e "${RED}Canary deployment failed! Aborting.${NC}"
    echo "Check logs: /tmp/ota_flash_$CANARY_SENSOR.log"
    exit 1
fi

# Wait for canary to boot
if ! wait_for_boot "$CANARY_SENSOR" "$CANARY_IP"; then
    echo -e "${RED}Canary failed to boot! Aborting.${NC}"
    exit 1
fi

echo ""

# Monitor canary health
if ! monitor_canary "$CANARY_IP" "$CANARY_WAIT_SECONDS" "$HEALTH_CHECK_INTERVAL"; then
    echo -e "${RED}Canary health monitoring failed!${NC}"
    echo ""
    echo "Rollback options:"
    echo "  1. Power cycle canary sensor"
    echo "  2. USB flash with backup firmware: $BACKUP_PATH"
    echo "  3. USB flash with previous working firmware"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Canary deployment successful!${NC}"
echo ""

# =============================================================================
# PHASE 2: PRODUCTION DEPLOYMENT
# =============================================================================

echo -e "${BLUE}=== PHASE 2: Production Deployment ===${NC}"
echo "Remaining sensors to flash:"
for sensor_id in "${!SENSORS[@]}"; do
    if [[ "$sensor_id" != "$CANARY_SENSOR" ]]; then
        echo "  - $sensor_id at ${SENSORS[$sensor_id]}"
    fi
done
echo ""

read -p "Proceed with production deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Production deployment cancelled (canary is running new firmware)"
    exit 0
fi

# Flash remaining sensors
TOTAL_SENSORS=$((${#SENSORS[@]} - 1))
SUCCESS_COUNT=0
FAILED_SENSORS=()

for sensor_id in $(echo "${!SENSORS[@]}" | tr ' ' '\n' | sort); do
    if [[ "$sensor_id" == "$CANARY_SENSOR" ]]; then
        continue  # Skip canary (already flashed)
    fi
    
    sensor_ip="${SENSORS[$sensor_id]}"
    
    if flash_sensor_ota "$sensor_id" "$sensor_ip"; then
        if wait_for_boot "$sensor_id" "$sensor_ip"; then
            ((SUCCESS_COUNT++))
        else
            FAILED_SENSORS+=("$sensor_id (boot timeout)")
        fi
    else
        FAILED_SENSORS+=("$sensor_id (flash failed)")
    fi
    
    echo ""
    sleep 5  # Wait between flashes to avoid network congestion
done

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo -e "Canary sensor: ${GREEN}$CANARY_SENSOR ✓${NC}"
echo -e "Production sensors: ${GREEN}$SUCCESS_COUNT${NC}/${YELLOW}$TOTAL_SENSORS${NC} successful"

if [[ ${#FAILED_SENSORS[@]} -gt 0 ]]; then
    echo -e "${RED}Failed sensors:${NC}"
    for failed in "${FAILED_SENSORS[@]}"; do
        echo -e "  ${RED}✗${NC} $failed"
    done
    echo ""
    echo "Recovery steps:"
    echo "  1. Check sensor power supply"
    echo "  2. USB flash failed sensors with: ./flash-usb-interactive.sh"
    echo "  3. Monitor logs: journalctl --user -u system-metrics-collector -f"
    exit 1
else
    echo -e "${GREEN}All sensors flashed successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Monitor sensor data in Grafana: https://grafana.owenmedeiros.com"
    echo "  2. Check InfluxDB for new readings (should appear within 5 minutes)"
    echo "  3. Verify all 7 sensors are posting data"
fi

echo ""
echo -e "${BLUE}Firmware backup location:${NC} $BACKUP_PATH"
