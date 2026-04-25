#!/bin/bash
# Quick WiFi monitor for ESP8266 soil sensor

echo "🔍 Monitoring for 'SoilSensor-Setup' WiFi access point..."
echo "   (Press Ctrl+C to stop)"
echo ""

while true; do
    FOUND=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport en0 scan 2>/dev/null | grep -i "SoilSensor")
    
    if [ ! -z "$FOUND" ]; then
        echo ""
        echo "✅ FOUND IT!"
        echo ""
        echo "$FOUND"
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo "📱 Next steps:"
        echo "   1. Open WiFi settings on this computer"
        echo "   2. Connect to: SoilSensor-Setup"
        echo "   3. A configuration page will open automatically"
        echo "   4. Select your WiFi network and enter password"
        echo "════════════════════════════════════════════════════════"
        break
    else
        echo -ne "⏳ Scanning... $(date '+%H:%M:%S')\r"
        sleep 2
    fi
done
