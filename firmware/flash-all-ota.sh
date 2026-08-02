#!/bin/bash
# OTA flash all sensors with individual device IDs
# This script updates config.h for each sensor and flashes via OTA
# Sensor data sourced from sensors-config.json at project root

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/config-helpers.sh"

declare -a SENSORS=()
load_sensors_by_number SENSORS
NUM_SENSORS=$(sensor_count)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 OTA Multi-Sensor Flashing                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will flash all $NUM_SENSORS sensors over WiFi with unique device IDs."
echo "OTA password: soilmon2026"
echo ""

TOTAL=${#SENSORS[@]}
SUCCESS=0
FAILED=0

for sensor_config in "${SENSORS[@]}"; do
    IFS=':' read -r id location plant ip <<< "$sensor_config"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Flashing: $id"
    echo "║ Plant:    $plant"
    echo "║ Location: $location"
    echo "║ IP:       $ip"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check if sensor is online
    echo "🔍 Checking if sensor is online..."
    if ! ping -c 2 -W 2 "$ip" > /dev/null 2>&1; then
        echo "❌ Sensor offline - skipping"
        ((FAILED++))
        continue
    fi
    echo "✅ Sensor online at $ip"
    echo ""
    
    # Update config.h
    echo "📝 Updating config.h..."
    sed -i.bak "s/#define DEVICE_ID .*\".*\".*/#define DEVICE_ID           \"$id\"          \/\/ Change for each sensor: sensor-1, sensor-2, etc./" src/config.h
    sed -i.bak "s/#define DEVICE_LOCATION .*\".*\".*/#define DEVICE_LOCATION     \"$location\"        \/\/ Room location for this sensor/" src/config.h
    # All sensors in sensors-config.json are soil sensors. Climate boards
    # (e.g. sensor-8 DHT22) are not listed there and must be flashed manually
    # with DEVICE_TYPE_CLIMATE.
    sed -i.bak "s/#define DEVICE_TYPE .*DEVICE_TYPE_.*/#define DEVICE_TYPE          DEVICE_TYPE_SOIL   \/\/ ← set per board (default 0 for soil)/" src/config.h
    
    echo "  DEVICE_ID: $id"
    echo "  DEVICE_LOCATION: $location"
    echo "  DEVICE_TYPE: soil"
    echo ""
    
    # Build firmware
    echo "🔨 Building firmware..."
    if ! pio run -e esp8266-ota > /tmp/pio-build.log 2>&1; then
        echo "❌ Build failed! Check /tmp/pio-build.log"
        ((FAILED++))
        continue
    fi
    echo "✅ Build successful"
    echo ""
    
    # Flash via OTA
    echo "📤 Flashing via OTA to $ip..."
    if pio run -e esp8266-ota --target upload --upload-port "$ip" 2>&1 | tee /tmp/pio-ota.log; then
        echo ""
        echo "✅ OTA flash successful for $id ($plant)!"
        ((SUCCESS++))
    else
        echo ""
        echo "❌ OTA flash failed for $id"
        echo "   Check /tmp/pio-ota.log for details"
        ((FAILED++))
    fi
    
    echo ""
    echo "⏳ Waiting 5 seconds before next sensor..."
    sleep 5
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   Flashing Complete                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Results:"
echo "  ✅ Success: $SUCCESS/$TOTAL"
echo "  ❌ Failed:  $FAILED/$TOTAL"
echo ""

if [ $SUCCESS -eq $TOTAL ]; then
    echo "🎉 All sensors flashed successfully!"
    exit 0
elif [ $SUCCESS -gt 0 ]; then
    echo "⚠️  Some sensors flashed successfully, but $FAILED failed."
    exit 1
else
    echo "❌ All sensors failed to flash. Check network and OTA settings."
    exit 1
fi
