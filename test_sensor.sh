#!/bin/bash
# Test script for soil moisture sensor via WiFi/HTTP

echo "═══════════════════════════════════════════════════════"
echo "  🌱 Soil Moisture Sensor — Test Suite"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check if device is broadcasting WiFi AP
echo "📡 Step 1: Checking for WiFi access point 'SoilSensor-Setup'..."
echo ""
airport -s | grep -i "SoilSensor" || echo "⚠️  Access point not found. Device may already be connected to your WiFi."
echo ""

# Prompt for IP address
echo "If the device is already on your network, enter its IP address."
echo "You can find this by:"
echo "  1. Checking your router's DHCP client list"
echo "  2. Using: arp -a | grep -i '40:91:51'"
echo "  3. Or scanning: nmap -sn 192.168.1.0/24 (if nmap installed)"
echo ""
read -p "Enter device IP (or press Enter to scan): " DEVICE_IP

if [ -z "$DEVICE_IP" ]; then
    echo ""
    echo "🔍 Scanning local network for the device..."
    # Try common local IP ranges
    for ip in 192.168.1.{1..254}; do
        timeout 0.2 curl -s -m 1 "http://$ip/api/latest" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            DEVICE_IP=$ip
            echo "✅ Found device at: $DEVICE_IP"
            break
        fi
    done
fi

if [ -z "$DEVICE_IP" ]; then
    echo ""
    echo "❌ Could not find device. Please:"
    echo "   1. Make sure ESP8266 is powered on"
    echo "   2. Connect to 'SoilSensor-Setup' WiFi and configure it"
    echo "   3. Or manually enter the IP address"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Testing device at: $DEVICE_IP"
echo "═══════════════════════════════════════════════════════"
echo ""

# Test 1: Latest reading
echo "📊 Test 1: Fetching latest sensor reading..."
echo "   GET http://$DEVICE_IP/api/latest"
echo ""
LATEST=$(curl -s -m 5 "http://$DEVICE_IP/api/latest")
if [ $? -eq 0 ]; then
    echo "$LATEST" | python3 -m json.tool 2>/dev/null || echo "$LATEST"
    
    # Extract values
    RAW=$(echo "$LATEST" | grep -o '"raw":[0-9]*' | cut -d':' -f2)
    MOISTURE=$(echo "$LATEST" | grep -o '"moisture":[0-9.]*' | cut -d':' -f2)
    
    echo ""
    echo "   ✅ Raw ADC:   $RAW"
    echo "   ✅ Moisture:  $MOISTURE%"
else
    echo "   ❌ Failed to connect"
    exit 1
fi

echo ""
echo "───────────────────────────────────────────────────────"

# Test 2: History
echo "📈 Test 2: Checking data history..."
echo "   GET http://$DEVICE_IP/api/history"
echo ""
HISTORY=$(curl -s -m 5 "http://$DEVICE_IP/api/history")
COUNT=$(echo "$HISTORY" | grep -o '"count":[0-9]*' | cut -d':' -f2)
echo "   ✅ Readings logged: $COUNT"

echo ""
echo "───────────────────────────────────────────────────────"

# Test 3: Dashboard
echo "🌐 Test 3: Dashboard access..."
echo "   GET http://$DEVICE_IP/"
echo ""
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://$DEVICE_IP/")
if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ Dashboard is accessible"
    echo "   🌐 Open in browser: http://$DEVICE_IP"
else
    echo "   ⚠️  Dashboard returned HTTP $HTTP_CODE"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  🧪 INTERACTIVE TESTS"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Now perform these manual tests:"
echo ""
echo "1️⃣  AIR TEST (baseline dry reading)"
echo "   → Hold sensor in open air"
echo "   → Raw ADC should be HIGH (700-900)"
echo "   → Moisture should be LOW (0-10%)"
echo ""
read -p "Press Enter when ready, then I'll read the sensor..."
curl -s "http://$DEVICE_IP/api/latest" | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"   📊 Raw: {d['raw']}  |  Moisture: {d['moisture']:.1f}%\")"

echo ""
echo "2️⃣  TOUCH TEST (capacitance increase)"
echo "   → Touch the sensor plates with your finger"
echo "   → Raw ADC should DROP"
echo "   → Moisture should INCREASE"
echo ""
read -p "Press Enter when touching the sensor..."
curl -s "http://$DEVICE_IP/api/latest" | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"   📊 Raw: {d['raw']}  |  Moisture: {d['moisture']:.1f}%\")"

echo ""
echo "3️⃣  WATER TEST (maximum wet reading)"
echo "   → Dip probe into water (NOT the electronics!)"
echo "   → Raw ADC should be LOW (300-400)"
echo "   → Moisture should be HIGH (80-100%)"
echo ""
read -p "Press Enter when sensor is in water..."
curl -s "http://$DEVICE_IP/api/latest" | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"   📊 Raw: {d['raw']}  |  Moisture: {d['moisture']:.1f}%\")"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Test Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Dashboard: http://$DEVICE_IP"
echo ""
