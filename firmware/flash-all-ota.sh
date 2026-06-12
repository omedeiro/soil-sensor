#!/bin/bash
# OTA flash all sensors with individual device IDs
# This script updates config.h for each sensor and flashes via OTA

set -e

# Sensor configuration (ID:Location:Plant:IP)
SENSORS=(
    "sensor-1:bed-room:Rubber Tree:192.168.99.110"
    "sensor-2:living-room:Monstera:192.168.99.149"
    "sensor-3:living-room:Avocado:192.168.99.70"
    "sensor-4:guest-room:Basil (auk):192.168.99.105"
    "sensor-5:bed-room:ZZ Plant:192.168.99.89"
    "sensor-6:living-room:Ficus Elastica Ruby:192.168.99.38"
    "sensor-7:guest-room:Basil (pot):192.168.99.141"
)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 OTA Multi-Sensor Flashing                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will flash all 7 sensors over WiFi with unique device IDs."
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
    
    echo "  DEVICE_ID: $id"
    echo "  DEVICE_LOCATION: $location"
    echo ""
    
    # Build firmware
    echo "🔨 Building firmware..."
    if ! pio run > /tmp/pio-build.log 2>&1; then
        echo "❌ Build failed! Check /tmp/pio-build.log"
        ((FAILED++))
        continue
    fi
    echo "✅ Build successful"
    echo ""
    
    # Flash via OTA
    echo "📤 Flashing via OTA to $ip..."
    if pio run --target upload --upload-port "$ip" 2>&1 | tee /tmp/pio-ota.log; then
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
