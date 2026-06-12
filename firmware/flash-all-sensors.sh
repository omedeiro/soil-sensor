#!/bin/bash
# Multi-sensor flashing workflow
# Flashes all 7 sensors with individual device IDs and locations

set -e

# Sensor configuration (from sensors-config.json + AGENTS.md)
declare -A SENSORS=(
    ["1"]="sensor-1:bed-room:Rubber Tree:192.168.99.110:68:c6:3a:f6:b3:ae"
    ["2"]="sensor-2:living-room:Monstera:192.168.99.149:48:3f:da:19:c0:86"
    ["3"]="sensor-3:living-room:Avocado:192.168.99.70:40:91:51:4f:d9:97"
    ["4"]="sensor-4:guest-room:Basil (auk):192.168.99.105:48:3f:da:aa:fe:d7"
    ["5"]="sensor-5:bed-room:ZZ Plant:192.168.99.89:34:ab:95:16:51:d9"
    ["6"]="sensor-6:living-room:Ficus Elastica Ruby:192.168.99.38:48:3f:da:62:f9:07"
    ["7"]="sensor-7:guest-room:Basil (pot):192.168.99.141:84:cc:a8:a7:96:32"
)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ESP8266 Multi-Sensor Flashing Workflow                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This script will flash all 7 sensors with unique device IDs."
echo "You'll need to plug in each sensor via USB one at a time."
echo ""
echo "📋 Sensor List:"
echo "────────────────────────────────────────────────────────────────"
for i in {1..7}; do
    IFS=':' read -r id location plant ip mac <<< "${SENSORS[$i]}"
    printf "  %s - %s (%s)\n" "$id" "$plant" "$location"
done
echo "────────────────────────────────────────────────────────────────"
echo ""

# Ask which sensor to flash
while true; do
    echo ""
    read -p "Which sensor is connected? (1-7, or 'q' to quit): " choice
    
    if [[ "$choice" == "q" ]]; then
        echo "✅ Flashing workflow complete!"
        exit 0
    fi
    
    if [[ ! "$choice" =~ ^[1-7]$ ]]; then
        echo "❌ Invalid choice. Please enter 1-7."
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
