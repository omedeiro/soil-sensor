#!/bin/bash
# Monitor for device to come back online after power cycle

echo "
╔════════════════════════════════════════════════════════════╗
║     🔌 Monitoring for Device Boot...                      ║
║     Waiting for ESP8266 to come back online               ║
╚════════════════════════════════════════════════════════════╝
"

DEVICE_IP="192.168.99.70"
COUNT=0
MAX_WAIT=60  # Wait up to 60 seconds

echo "Expected IP: $DEVICE_IP"
echo "Checking every 2 seconds..."
echo ""

while [ $COUNT -lt $MAX_WAIT ]; do
    if curl -s -m 2 "http://$DEVICE_IP/api/latest" >/dev/null 2>&1; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "✅ DEVICE IS BACK ONLINE!"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        echo "Time to boot: ~$COUNT seconds"
        echo ""
        echo "Latest reading:"
        curl -s "http://$DEVICE_IP/api/latest" | python3 -m json.tool
        echo ""
        echo "Dashboard: http://$DEVICE_IP"
        echo ""
        echo "✅ Everything is working! Device survived the power cycle."
        echo ""
        exit 0
    fi
    
    printf "⏳ Waiting... %02d/%02d seconds\r" $COUNT $MAX_WAIT
    sleep 2
    COUNT=$((COUNT + 2))
done

echo ""
echo ""
echo "❌ Device did not come back online after $MAX_WAIT seconds"
echo ""
echo "Troubleshooting:"
echo "  1. Check if blue LED is blinking on ESP8266"
echo "  2. Try unplugging and replugging again"
echo "  3. Check if 'SoilSensor-Setup' WiFi appears (WiFi reset?)"
echo "  4. Verify power supply is working"
echo ""
exit 1
