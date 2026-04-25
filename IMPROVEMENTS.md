# Stability & Database Improvements Summary

## What Changed

### 1. Improved Firmware Stability
- Added crash detection that reports WHY the device rebooted
- Added watchdog yield() calls throughout code to prevent freezes
- Increased reading interval from 1 minute to 5 minutes (reduces stress)
- Added comprehensive logging of uptime, memory, WiFi signal
- Better error handling for network operations

### 2. Database Storage System
- ESP8266 now POSTs data to a database server (Python Flask + SQLite)
- Database runs on your Mac (or any computer on your network)
- Unlimited storage (not limited by ESP8266's 80KB RAM)
- Data persists even if ESP8266 crashes or restarts
- New web dashboard reads from database instead of ESP8266

### 3. Enhanced Monitoring
- Serial monitor shows detailed boot information
- Tracks total crash count
- Reports free memory, WiFi signal strength, uptime
- Logs every reading with timestamps

## Quick Setup

### 1. Start Database Server
```bash
cd database
./start.sh
```

Note the IP address shown (e.g., 192.168.99.100)

### 2. Update ESP8266 Config

The firmware is already configured, but verify in `firmware/src/config.h`:

```cpp
#define READ_INTERVAL_MS    300000  // 5 minutes
#define USE_REMOTE_DB       true
#define DB_SERVER_URL       "http://192.168.99.100:5000/api/reading"
```

Update the IP if needed.

### 3. Upload Firmware

With the ESP8266 connected to your Mac via USB:

```bash
cd firmware
pio run --target upload
pio device monitor
```

### 4. Watch Serial Output

You should see something like:

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
[NTP] Time synced: Sat Apr 25 11:23:45 2026
[OTA] Ready for wireless updates
[HTTP] Server started on port 80
[Sensor] moisture=45.2%  raw=520
[DB] ✓ Posted to database (HTTP 201)
═══════════════════════════════════════
Setup complete. Uptime: 12 s
Reading interval: 5 min
Remote DB: enabled
═══════════════════════════════════════
```

**Key things to check:**
- ✅ Clean boot (no crashes)
- ✓ Connected to WiFi
- ✓ Posted to database (HTTP 201)

If you see crashes or database POST failures, see troubleshooting below.

### 5. View Dashboard

Open in your browser:
- File: `database/dashboard.html` (open directly)
- Or: `http://YOUR_MAC_IP:5000/` for server status

## What to Look For

### Healthy System
```
[Sensor] Reading #15
  Moisture: 45.2%
  Raw ADC: 520
  Logged: 15 readings
  Uptime: 4500 s (75.0 min)
  Free heap: 36224 bytes
  WiFi RSSI: -45 dBm
[DB] ✓ Posted to database (HTTP 201)
  Read duration: 234 ms
```

### Problem Indicators

**Crash on boot:**
```
⚠️  CRASH DETECTED! Count: 3
  Reset Info: 1  <- Hardware watchdog (bad!)
```
→ Likely power supply issue. Try a different USB cable/adapter.

**WiFi disconnections:**
```
WiFi RSSI: -82 dBm  <- Very weak signal!
```
→ Move ESP8266 closer to router or use WiFi extender.

**Database POST failures:**
```
[DB] ✗ POST failed: connection refused
```
→ Database server not running or wrong IP address in config.h

**Low memory:**
```
Free heap: 8432 bytes  <- Too low!
```
→ Memory leak. The database mode should prevent this.

## Interpreting Crash Reasons

When you see "Boot Information" in serial output:

| Reset Info | Meaning | Action |
|------------|---------|--------|
| 0 | Normal startup | Good! |
| 1 | Hardware watchdog | Code froze - power issue likely |
| 2 | Exception/crash | Software bug |
| 3 | Software watchdog | Code blocking too long |
| 4 | Software restart | Intentional reboot (OK) |
| 6 | External reset | Power loss or manual reset |

**Most Common Issue:** Reset Info 1 or 6 = **Power supply problem**

Try:
1. Different USB cable (many are charge-only, can't deliver stable power)
2. Different USB adapter (need 5V, 1A minimum)
3. Shorter USB cable (longer = more voltage drop)
4. Wall outlet instead of computer USB port

## Testing the Database

```bash
# Check if database server is running
curl http://192.168.99.100:5000/health

# Get latest reading
curl http://192.168.99.100:5000/api/latest

# Get statistics
curl http://192.168.99.100:5000/api/stats

# View all data
open database/dashboard.html
```

## Disable Local Web Server (Optional)

Once the database is working, you can disable the ESP8266's web server to save memory:

Edit `firmware/src/main.cpp` around line 106:

```cpp
// Comment out these lines:
// if (wifi.isConnected()) {
//     webServer = new MonitorWebServer(logger, sensor);
//     webServer->begin();
// }
```

This makes the ESP8266 more stable and uses less RAM.

## File Changes Summary

### Modified Files:
- `firmware/src/config.h` - Changed interval to 5 min, added DB config
- `firmware/src/main.cpp` - Added crash detection, logging, DB posting

### New Files:
- `database/server.py` - Flask database server
- `database/dashboard.html` - Web dashboard that reads from DB
- `database/requirements.txt` - Python dependencies
- `database/start.sh` - Easy startup script
- `database/README.md` - Full database documentation

## Next Steps

1. Let it run for a few hours and check for crashes in serial output
2. If you see repeated crashes, check power supply first
3. If stable, you can disconnect from USB and power via wall adapter
4. Keep database server running on your Mac for continuous logging
5. Access dashboard from your phone: http://YOUR_MAC_IP:5000/dashboard.html

## Reverting Changes

If you want to go back to the old 1-minute local-only mode:

Edit `firmware/src/config.h`:
```cpp
#define READ_INTERVAL_MS    60000  // 1 minute
#define USE_REMOTE_DB       false  // Disable database
```

Then re-upload firmware.
