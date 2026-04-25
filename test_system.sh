#!/bin/bash
# Test script to verify the complete system is working

echo "════════════════════════════════════════════════════════════"
echo "  🌱 Plant Monitor System Test"
echo "════════════════════════════════════════════════════════════"
echo ""

# Test 1: Database Server
echo "Test 1: Database Server"
echo "───────────────────────"
if curl -s --connect-timeout 3 http://192.168.99.188:5001/health > /dev/null 2>&1; then
    echo "✅ Database server is running on port 5001"
    HEALTH=$(curl -s http://192.168.99.188:5001/health)
    echo "   Status: $(echo $HEALTH | python3 -c "import sys, json; print(json.load(sys.stdin)['status'])")"
else
    echo "❌ Database server is NOT running"
    echo "   Run: cd database && python3 server.py"
    exit 1
fi
echo ""

# Test 2: Database can accept data
echo "Test 2: Database Write Test"
echo "────────────────────────────"
RESULT=$(curl -s -X POST http://192.168.99.188:5001/api/reading \
  -H "Content-Type: application/json" \
  -d "{\"timestamp\": $(date +%s), \"raw\": 500, \"moisture\": 40.0, \"uptime\": 100, \"crashes\": 0}")

if echo "$RESULT" | grep -q "\"status\":\"ok\""; then
    echo "✅ Database can store readings"
    echo "   Test reading stored successfully"
else
    echo "❌ Database POST failed"
    echo "   Response: $RESULT"
    exit 1
fi
echo ""

# Test 3: Database can retrieve data
echo "Test 3: Database Read Test"
echo "───────────────────────────"
LATEST=$(curl -s http://192.168.99.188:5001/api/latest)
if echo "$LATEST" | grep -q "moisture"; then
    echo "✅ Database can retrieve readings"
    MOISTURE=$(echo $LATEST | python3 -c "import sys, json; print(json.load(sys.stdin)['moisture'])")
    echo "   Latest moisture: ${MOISTURE}%"
else
    echo "❌ Database read failed"
    exit 1
fi
echo ""

# Test 4: ESP8266 connectivity
echo "Test 4: ESP8266 Status"
echo "──────────────────────"
if ping -c 1 -W 2 192.168.99.70 > /dev/null 2>&1; then
    echo "✅ ESP8266 is online at 192.168.99.70"
    
    # Check if web server is responding
    if curl -s --connect-timeout 3 http://192.168.99.70/api/latest > /dev/null 2>&1; then
        echo "✅ ESP8266 web server is responding"
    else
        echo "⚠️  ESP8266 is online but web server not responding"
    fi
else
    echo "❌ ESP8266 is OFFLINE"
    echo ""
    echo "   Possible reasons:"
    echo "   1. Device not powered on"
    echo "   2. Not connected to WiFi yet"
    echo "   3. Creating WiFi AP 'SoilSensor-Setup' (needs configuration)"
    echo ""
    echo "   To check:"
    echo "   - Look for 'SoilSensor-Setup' WiFi network on your phone"
    echo "   - Connect via USB and run: pio device monitor"
    echo ""
fi
echo ""

# Test 5: Check for ESP8266 data in database
echo "Test 5: ESP8266 Database Posts"
echo "───────────────────────────────"
STATS=$(curl -s http://192.168.99.188:5001/api/stats)
TOTAL=$(echo $STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['total_readings'])" 2>/dev/null || echo "0")

if [ "$TOTAL" -gt 1 ]; then
    echo "✅ Database has $TOTAL readings"
    echo "   ESP8266 is posting data!"
else
    echo "⚠️  Database only has $TOTAL reading(s)"
    echo "   ESP8266 may not have posted yet"
    echo ""
    echo "   Wait 5 minutes for first reading, or check serial monitor:"
    echo "   cd firmware && pio device monitor"
fi
echo ""

# Test 6: Dashboard accessibility
echo "Test 6: Dashboard"
echo "─────────────────"
if [ -f "/Users/owenmedeiros/soil-sensor/database/dashboard.html" ]; then
    echo "✅ Dashboard file exists"
    echo "   Open: /Users/owenmedeiros/soil-sensor/database/dashboard.html"
    echo "   Or visit: http://192.168.99.188:5001/"
else
    echo "❌ Dashboard file not found"
fi
echo ""

# Summary
echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Database Server:  ✅ Running on port 5001"
echo "Database API:     ✅ Working"
echo "ESP8266:          $(ping -c 1 -W 2 192.168.99.70 > /dev/null 2>&1 && echo '✅ Online' || echo '❌ Offline')"
echo "Total Readings:   $TOTAL"
echo ""

if ping -c 1 -W 2 192.168.99.70 > /dev/null 2>&1 && [ "$TOTAL" -gt 1 ]; then
    echo "🎉 SYSTEM IS FULLY OPERATIONAL!"
    echo ""
    echo "Next steps:"
    echo "  1. Open dashboard: /Users/owenmedeiros/soil-sensor/database/dashboard.html"
    echo "  2. Monitor logs: tail -f /tmp/db_server.log"
    echo "  3. View serial output: cd firmware && pio device monitor"
else
    echo "⚠️  SYSTEM NEEDS ATTENTION"
    echo ""
    echo "Next steps:"
    echo "  1. Connect ESP8266 via USB"
    echo "  2. Run: cd firmware && pio device monitor"
    echo "  3. Watch for '[DB] ✓ Posted to database' message"
    echo "  4. If WiFi setup needed, connect to 'SoilSensor-Setup' AP"
fi
echo ""
