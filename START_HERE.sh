#!/bin/bash
# Simple startup guide - Run this to see what to do next

cat << 'EOF'
════════════════════════════════════════════════════════════
  🌱 Plant Monitor - What to Do Now
════════════════════════════════════════════════════════════

GOOD NEWS: The system is ready! Here's what's working:

✅ Database server is running (port 5001)
✅ New firmware uploaded to ESP8266
✅ All stability improvements added
✅ Crash detection enabled
✅ 5-minute reading interval configured

════════════════════════════════════════════════════════════
  NEXT STEP: Connect to Serial Monitor
════════════════════════════════════════════════════════════

The ESP8266 is connected to your Mac via USB. 
You need to see what it's doing:

1. Open a terminal
2. Run these commands:

   cd /Users/owenmedeiros/soil-sensor/firmware
   pio device monitor

3. Watch for these messages:

   ✅ "Clean boot" - No crashes
   ✅ "[WiFi] ✓ Connected" - WiFi working
   ✅ "[DB] ✓ Posted to database (HTTP 201)" - Database working

════════════════════════════════════════════════════════════
  IF ESP8266 NEEDS WIFI SETUP
════════════════════════════════════════════════════════════

If you see "Starting captive portal" in serial monitor:

1. On your phone, look for WiFi: "SoilSensor-Setup"
2. Connect to it
3. Enter your home WiFi credentials
4. ESP8266 will reboot and connect

════════════════════════════════════════════════════════════
  THEN: View the Dashboard
════════════════════════════════════════════════════════════

Once ESP8266 is posting data (you'll see it in serial monitor):

Option 1: Open this file in your browser:
   /Users/owenmedeiros/soil-sensor/database/dashboard.html

Option 2: Visit this URL:
   http://192.168.99.188:5001/

You'll see:
- Current moisture level
- Sensor uptime
- Total readings
- Crash count (should be 0!)
- History graph

════════════════════════════════════════════════════════════
  TESTING COMMANDS
════════════════════════════════════════════════════════════

Run system test:
   ./test_system.sh

Watch database logs:
   tail -f /tmp/db_server.log

Check latest reading:
   curl http://192.168.99.188:5001/api/latest

════════════════════════════════════════════════════════════
  WHAT CHANGED
════════════════════════════════════════════════════════════

Stability:
- Crash detection added
- Reading interval: 1 min → 5 min
- Better watchdog handling
- Enhanced logging

Database:
- Data stored on your Mac (unlimited storage)
- Survives ESP8266 crashes/reboots
- Multiple people can view dashboard
- Historical data preserved

Port Change:
- Database now on port 5001 (macOS uses 5000)

════════════════════════════════════════════════════════════
  FILES TO REFERENCE
════════════════════════════════════════════════════════════

STATUS.md       - Current system status and configuration
TESTING.md      - Detailed testing guide
SUMMARY.md      - Complete list of improvements
test_system.sh  - Automated system test

════════════════════════════════════════════════════════════

Ready? Start by running:

   cd /Users/owenmedeiros/soil-sensor/firmware
   pio device monitor

════════════════════════════════════════════════════════════
EOF
