#!/bin/bash
# USB flash workflow - one sensor at a time
# User plugs in each sensor, enters the sensor number, and we flash it
# Sensor data sourced from sensors-config.json at project root

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/config-helpers.sh"

NUM_SENSORS=$(sensor_count)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 USB Flashing Workflow                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
print_sensor_list

echo "Instructions:"
echo "  1. Plug in a sensor via USB"
echo "  2. Enter the sensor number (1-$NUM_SENSORS)"
echo "  3. Script will flash the correct firmware"
echo "  4. Unplug and plug in the next sensor"
echo "  5. Type 'q' to quit"
echo ""

declare -a SENSOR_DATA=("")
load_sensors_by_number SENSOR_DATA

flash_count=0

while true; do
    echo ""
    read -p "Which sensor is plugged in? (1-$NUM_SENSORS, or 'q' to quit): " choice
    
    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
        echo ""
        echo "✅ Flashed $flash_count sensor(s). Exiting."
        exit 0
    fi
    
    if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt "$NUM_SENSORS" ]; then
        echo "❌ Invalid choice. Please enter 1-$NUM_SENSORS."
        continue
    fi
    
    # Parse sensor data
    IFS=':' read -r id location plant <<< "${SENSOR_DATA[$choice]}"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Sensor $choice: $plant"
    echo "║ ID:       $id"
    echo "║ Location: $location"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Detect USB port
    echo "🔍 Detecting USB port..."
    USB_PORT=$(ls /dev/cu.* 2>/dev/null | grep -E "usbserial|wchusbserial" | head -1)
    
    if [ -z "$USB_PORT" ]; then
        echo "❌ No USB device found!"
        echo "   Make sure the sensor is plugged in and drivers are installed."
        continue
    fi
    
    echo "✅ Found: $USB_PORT"
    echo ""
    
    # Update config.h
    echo "📝 Updating config.h..."
    sed -i.bak "s/#define DEVICE_ID .*\".*\".*/#define DEVICE_ID           \"$id\"          \/\/ Change for each sensor/" src/config.h
    sed -i.bak "s/#define DEVICE_LOCATION .*\".*\".*/#define DEVICE_LOCATION     \"$location\"        \/\/ Room location/" src/config.h
    
    # Switch to USB upload mode
    sed -i.bak 's/^upload_protocol = espota/; upload_protocol = espota/' platformio.ini
    sed -i.bak 's/^upload_flags =/; upload_flags =/' platformio.ini
    sed -i.bak 's/^;     --auth=/;     --auth=/' platformio.ini
    sed -i.bak 's/^; upload_protocol = esptool/upload_protocol = esptool/' platformio.ini
    
    echo "  ID:       $id"
    echo "  Location: $location"
    echo ""
    
    # Build and flash
    echo "🔨 Building and flashing..."
    if pio run --target upload --upload-port "$USB_PORT" 2>&1 | grep -E "SUCCESS|ERROR|Writing at"; then
        echo ""
        if grep -q "SUCCESS" /tmp/flash_result.txt 2>/dev/null || [ $? -eq 0 ]; then
            echo "✅ Flash successful for $id ($plant)!"
            ((flash_count++))
            echo ""
            echo "🔌 You can now unplug this sensor and plug in the next one."
        else
            echo "❌ Flash may have failed. Check output above."
        fi
    else
        echo "❌ Flash failed!"
    fi
done
