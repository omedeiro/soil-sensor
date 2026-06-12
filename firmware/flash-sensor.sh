#!/bin/bash
# Universal sensor flashing script
# Works with auto-generated device IDs - one firmware for all sensors

set -e

echo "🔌 ESP8266 Sensor Flash Tool"
echo "============================="
echo ""
echo "This firmware uses AUTO device IDs based on MAC address."
echo "Each sensor will auto-generate a unique ID like: esp8266-68c63af6b3ae"
echo ""

# Detect USB port
echo "🔍 Detecting USB serial port..."
USB_PORT=$(ls /dev/cu.* 2>/dev/null | grep -E "usbserial|wchusbserial" | head -1)

if [ -z "$USB_PORT" ]; then
    echo "❌ No USB serial device found!"
    echo ""
    echo "Available devices:"
    ls /dev/cu.* 2>/dev/null || echo "  None"
    echo ""
    echo "📋 Troubleshooting:"
    echo "  1. Install CH340 or CP2102 USB driver"
    echo "  2. Unplug and replug the sensor"
    echo "  3. Check USB cable supports data transfer"
    echo ""
    exit 1
fi

echo "✅ Found device: $USB_PORT"
echo ""

# Flash firmware
echo "📤 Flashing firmware..."
echo "  Port: $USB_PORT"
echo "  Firmware: firmware.bin (auto device ID enabled)"
echo ""

pio run --target upload --upload-port "$USB_PORT"

FLASH_RESULT=$?

if [ $FLASH_RESULT -eq 0 ]; then
    echo ""
    echo "✅ Flash successful!"
    echo ""
    echo "📊 Monitoring serial output (Ctrl+C to exit)..."
    echo "   Watch for device ID and first reading..."
    sleep 2
    pio device monitor --port "$USB_PORT" --baud 115200
else
    echo ""
    echo "❌ Flash failed!"
    exit 1
fi
