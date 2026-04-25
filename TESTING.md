# Testing Guide - Start Here!

Your plant monitor has been upgraded with stability improvements and database storage. Follow these steps to test everything.

## Step 1: Start the Database Server

Open a terminal and run:

```bash
cd /Users/owenmedeiros/soil-sensor/database
./start.sh
```

You should see:
```
═══════════════════════════════════════
  🌱 Soil Sensor Database Server
═══════════════════════════════════════

📦 Installing dependencies...
📡 Your computer's IP addresses:
   - 192.168.99.188

📝 Update your ESP8266 config.h with:
   #define DB_SERVER_URL "http://YOUR_IP:5000/api/reading"

🚀 Starting server...
```

**Leave this terminal window open!** The server needs to keep running.

## Step 2: Monitor the ESP8266

Open a NEW terminal window and run:

```bash
cd /Users/owenmedeiros/soil-sensor/firmware
pio device monitor
```

You should see output like this:

```
═══════════════════════════════════════
  🌱  Soil Moisture Monitoring System
═══════════════════════════════════════
─────────────────────────────────────
📊 Boot Information:
  Reason: External System
  Reset Info: 6
✅ Clean boot
─────────────────────────────────────
[WiFi] Connecting...
[WiFi] ✓ Connected to YourNetwork
[WiFi] IP: 192.168.99.70
[NTP] Syncing time…
[NTP] Time synced: Sat Apr 25 11:45:23 2026
[OTA] Ready for wireless updates
[HTTP] Server started on port 80
[Sensor] moisture=45.2%  raw=520
[DB] ✓ Posted to database (HTTP 201)
═══════════════════════════════════════
Setup complete. Uptime: 8 s
Reading interval: 5 min
Remote DB: enabled
═══════════════════════════════════════
```

### What to Look For:

✅ **Good Signs:**
- "✅ Clean boot" - No crashes
- "[WiFi] ✓ Connected" - WiFi working
- "[DB] ✓ Posted to database (HTTP 201)" - Database connection working
- "Remote DB: enabled"

❌ **Warning Signs:**
- "⚠️ CRASH DETECTED!" - Power issue likely
- "[DB] ✗ POST failed" - Database server not running or wrong IP
- "[WiFi] Disconnected" - WiFi problems

## Step 3: Wait for First Reading

The sensor takes a reading every 5 minutes. After 5 minutes, you should see:

```
─────────────────────────────────────
[Sensor] Reading #2
  Moisture: 45.2%
  Raw ADC: 520
  Logged: 2 readings
  Uptime: 300 s (5.0 min)
  Free heap: 36224 bytes
  WiFi RSSI: -45 dBm
[DB] ✓ Posted to database (HTTP 201)
  Read duration: 234 ms
─────────────────────────────────────
```

This means everything is working!

## Step 4: Check the Database

Go back to your database server terminal. You should see:

```
✓ Reading #1: 45.2% (raw=520, uptime=8s, crashes=0)
✓ Reading #2: 45.2% (raw=520, uptime=308s, crashes=0)
```

## Step 5: Open the Dashboard

Open this file in your web browser:
```
/Users/owenmedeiros/soil-sensor/database/dashboard.html
```

Or visit: http://192.168.99.188:5000/

You should see:
- Current moisture percentage
- Sensor uptime
- Total readings stored
- Crash count (should be 0)
- A graph of moisture over time

## Step 6: Let It Run

Leave everything running for at least 30 minutes to verify stability. Check the serial monitor periodically to make sure:

1. No crashes are occurring
2. Database POSTs are succeeding
3. Free heap memory stays above 30,000 bytes
4. WiFi RSSI is decent (above -70 dBm is good)

## Troubleshooting

### Problem: "[DB] ✗ POST failed: connection refused"

**Solution:** Make sure the database server is running.

Check if it's running:
```bash
curl http://192.168.99.188:5000/health
```

Should return: `{"status":"ok",...}`

If not working, start the database server (see Step 1).

### Problem: "⚠️ CRASH DETECTED! Count: 3"

**Solution:** Power supply issue.

Try:
1. Different USB cable
2. Different USB power adapter (need 5V, 1A minimum)
3. Plug into wall outlet, not computer USB port
4. Use a shorter USB cable

### Problem: WiFi keeps disconnecting

**Solution:** Move ESP8266 closer to router or check WiFi signal.

The serial monitor shows WiFi signal strength:
- -30 to -50 dBm: Excellent
- -50 to -70 dBm: Good
- -70 to -80 dBm: Fair (may have issues)
- Below -80 dBm: Poor (will disconnect)

### Problem: Sensor always reads 0% or 100%

**Solution:** Calibration issue (not related to stability).

See README.md for calibration instructions.

### Problem: Dashboard says "Cannot connect to database server"

**Solution:** Update the IP address in dashboard.html.

Edit `/Users/owenmedeiros/soil-sensor/database/dashboard.html` line 180:
```javascript
const DB_SERVER = 'http://192.168.99.188:5000';
```

## Understanding the Improvements

### Stability Features Added:

1. **Crash Detection** - Identifies WHY the device rebooted
2. **Watchdog Handling** - Added yield() calls to prevent freezes
3. **Reduced Frequency** - Changed from 1 minute to 5 minutes (less stress)
4. **Better Logging** - Shows uptime, memory, WiFi signal
5. **Database Storage** - Data saved externally, not in ESP8266 RAM

### Database Benefits:

1. **Unlimited Storage** - Not limited by ESP8266's 80KB RAM
2. **Data Persistence** - Survives ESP8266 crashes/reboots
3. **Remote Access** - View from any device on your network
4. **Multiple Viewers** - Many people can view simultaneously
5. **Historical Analysis** - Keep data as long as you want

## Next Steps

Once you've verified everything works:

1. **Unplug from Computer**
   - The ESP8266 can run on any USB power adapter
   - Use a wall charger for always-on operation

2. **Keep Database Server Running**
   - The Python server needs to stay running on your Mac
   - See `database/README.md` for how to run it as a background service

3. **Monitor Crashes**
   - Check the dashboard "Crash Count" periodically
   - If crashes occur, investigate power supply first

4. **Bookmark Dashboard**
   - Open `database/dashboard.html` on your phone
   - Add to home screen for easy access

## Files to Reference

- `IMPROVEMENTS.md` - Full list of changes made
- `database/README.md` - Complete database documentation
- `README.md` - Original project documentation

## Quick Commands Reference

```bash
# Start database server
cd database && ./start.sh

# Monitor ESP8266 serial output
cd firmware && pio device monitor

# Check database health
curl http://192.168.99.188:5000/health

# Get latest reading
curl http://192.168.99.188:5000/api/latest

# View all readings
open database/dashboard.html
```

## Expected Behavior

**First 5 minutes:**
- ESP8266 boots up
- Connects to WiFi
- Takes first reading immediately
- POSTs to database
- Waits 5 minutes

**Every 5 minutes after:**
- Takes new sensor reading
- POSTs to database
- Logs details to serial monitor
- Updates dashboard

**Memory usage:**
- Should stay around 35,000-40,000 free bytes
- If it drops below 20,000, something is wrong

**WiFi signal:**
- Should be stable above -70 dBm
- Reconnects automatically if drops

Ready to test! Follow Step 1 above to get started.
