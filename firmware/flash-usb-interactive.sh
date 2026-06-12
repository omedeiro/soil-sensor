#!/bin/bash
# USB flash workflow - one sensor at a time
# User plugs in each sensor, enters the sensor number, and we flash it

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 USB Flashing Workflow                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Sensor List:"
echo "  1 - Rubber Tree (bed-room)"
echo "  2 - Monstera (living-room)"
echo "  3 - Avocado (living-room)"
echo "  4 - Basil - auk (guest-room)"
echo "  5 - ZZ Plant (bed-room)"
echo "  6 - Ficus Elastica Ruby (living-room)"
echo "  7 - Basil - pot (guest-room)"
echo ""
echo "Instructions:"
echo "  1. Plug in a sensor via USB"
echo "  2. Enter the sensor number (1-7)"
echo "  3. Script will flash the correct firmware"
echo "  4. Unplug and plug in the next sensor"
echo "  5. Type 'q' to quit"
echo ""

# Sensor data: ID:Location:Plant
declare -a SENSOR_DATA=(
    ""
    "sensor-1:bed-room:Rubber Tree"
    "sensor-2:living-room:Monstera"
    "sensor-3:living-room:Avocado"
    "sensor-4:guest-room:Basil - auk"
    "sensor-5:bed-room:ZZ Plant"
    "sensor-6:living-room:Ficus Elastica Ruby"
    "sensor-7:guest-room:Basil - pot"
)

flash_count=0

while true; do
    echo ""
    read -p "Which sensor is plugged in? (1-7, or 'q' to quit): " choice
    
    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
        echo ""
        echo "✅ Flashed $flash_count sensor(s). Exiting."
        exit 0
    fi
    
    if ! [[ "$choice" =~ ^[1-7]$ ]]; then
        echo "❌ Invalid choice. Please enter 1-7."
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
