#!/bin/bash
# Multi-sensor flashing workflow
# Flashes all sensors with individual device IDs and locations
# Sensor data sourced from sensors-config.json at project root

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/config-helpers.sh"

declare -A SENSORS=()
load_sensors_by_number SENSORS
NUM_SENSORS=$(sensor_count)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 Multi-Sensor Flashing Workflow                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This script will flash all $NUM_SENSORS sensors with unique device IDs."
echo "You'll need to plug in each sensor via USB one at a time."
echo ""
echo "📋 Sensor List:"
echo "────────────────────────────────────────────────────────────────"
for i in $(seq 1 $NUM_SENSORS); do
    IFS=':' read -r id location plant ip mac <<< "${SENSORS[$i]}"
    printf "  %s - %s (%s)\n" "$id" "$plant" "$location"
done
echo "────────────────────────────────────────────────────────────────"
echo ""

# Ask which sensor to flash
while true; do
    echo ""
    read -p "Which sensor is connected? (1-$NUM_SENSORS, or 'q' to quit): " choice
    
    if [[ "$choice" == "q" ]]; then
        echo "✅ Flashing workflow complete!"
        exit 0
    fi
    
    if [[ ! "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt "$NUM_SENSORS" ]; then
        echo "❌ Invalid choice. Please enter 1-$NUM_SENSORS."
        continue
    fi
    
    # Parse sensor config
    IFS=':' read -r id location plant ip mac <<< "${SENSORS[$choice]}"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Flashing: $id"
    echo "║ Plant:    $plant"
    echo "║ Location: $location"
    echo "║ MAC:      $mac"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Update config.h
    echo "📝 Updating config.h..."
    sed -i.bak "s/#define DEVICE_ID .*/#define DEVICE_ID           \"$id\"          \/\/ Change for each sensor: sensor-1, sensor-2, etc./" src/config.h
    sed -i.bak "s/#define DEVICE_LOCATION .*/#define DEVICE_LOCATION     \"$location\"        \/\/ Room location for this sensor/" src/config.h
    
    echo "✅ Config updated:"
    grep "DEVICE_ID" src/config.h | grep -v "//"
    echo ""
    
    # Detect USB port
    echo "🔍 Detecting USB port..."
    USB_PORT=$(ls /dev/cu.* 2>/dev/null | grep -E "usbserial|wchusbserial" | head -1)
    
    if [ -z "$USB_PORT" ]; then
        echo "❌ No USB device found!"
        echo "   Please check USB connection and try again."
        continue
    fi
    
    echo "✅ Found: $USB_PORT"
    echo ""
    
    # Build and flash
    echo "🔨 Building firmware..."
    pio run
    
    echo ""
    echo "📤 Flashing to ESP8266..."
    pio run --target upload --upload-port "$USB_PORT"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Flash successful for $id ($plant)!"
        echo ""
        echo "📊 Verifying sensor boot (10 seconds)..."
        sleep 3
        
        # Try to read serial output
        timeout 7 cat "$USB_PORT" 2>/dev/null | grep -E "Device ID|moisture|Posted" | head -5 || true
        
        echo ""
        echo "🔌 You can now unplug this sensor and plug in the next one."
        echo ""
    else
        echo ""
        echo "❌ Flash failed! Please check connections and try again."
    fi
done
