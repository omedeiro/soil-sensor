# Multi-Sensor Database System - Quick Reference

## What Changed?

Your soil sensor system now supports **multiple sensors** logging to a **central database**!

### Before (Single Sensor)
```
ESP8266 → Local RAM buffer (24h) → Web dashboard @ 192.168.99.70
```

### After (Multi-Sensor)
```
ESP8266 #1 (garden-bed-a) ──┐
ESP8266 #2 (pot-basil)     ──┼─→ Database Server → SQLite → Multi-sensor dashboard
ESP8266 #3 (greenhouse)    ──┘    @ 192.168.99.188:5001
```

## Files Added

### Database Server
- **`database/server.py`** - Flask server with multi-sensor support
- **`database/MULTI_SENSOR_SETUP.md`** - Complete setup guide
- **`database/FIRMWARE_INTEGRATION.md`** - How to modify firmware

### Firmware Support
- **`firmware/src/database_client.h`** - HTTP client header
- **`firmware/src/database_client.cpp`** - HTTP client implementation
- **`firmware/src/config.h`** - Added `USE_REMOTE_DB`, `DEVICE_ID`, `DB_SERVER_URL`

## Database Schema

### Devices Table
Tracks each sensor with metadata:
- `device_id` (primary key) - e.g., "garden-bed-a"
- `name` - e.g., "Garden Bed A"
- `location` - e.g., "Backyard - North Side"
- `mac_address` - WiFi MAC
- `first_seen`, `last_seen` - Timestamps
- `total_readings` - Count

### Readings Table
Stores sensor data with device association:
- `id` - Auto-increment
- `device_id` - Foreign key to devices
- `timestamp`, `raw`, `moisture` - Sensor data
- `uptime`, `crashes` - Diagnostics
- `received_at` - Server timestamp

## Quick Start (3 Steps)

### 1. Start Database Server
```bash
cd database
python3 -m pip install -r requirements.txt
python3 server.py
```

### 2. Configure Each Sensor
Edit `firmware/src/config.h`:
```cpp
#define USE_REMOTE_DB    true
#define DB_SERVER_URL    "http://192.168.99.188:5001/api/reading"
#define DEVICE_ID_AUTO   false
#define DEVICE_ID        "garden-bed-a"  // Unique per sensor!
```

### 3. Build & Deploy
```bash
cd firmware
pio run --target upload
```

## API Endpoints

### Device Management
```bash
# List all sensors
GET /api/devices

# Get sensor info
GET /api/devices/garden-bed-a

# Update sensor metadata
PUT /api/devices/garden-bed-a
  Body: {"name": "Garden Bed A", "location": "Backyard"}

# Latest from all sensors
GET /api/devices/all/latest
```

### Readings
```bash
# Store reading (called by ESP8266)
POST /api/reading
  Body: {"device_id": "garden-bed-a", "timestamp": 1714000000, "raw": 520, "moisture": 61.9}

# Latest reading (all sensors or filtered)
GET /api/latest?device_id=garden-bed-a

# Historical data (all sensors or filtered)
GET /api/history?device_id=garden-bed-a&limit=100

# Statistics
GET /api/stats?device_id=garden-bed-a
```

## Testing Commands

```bash
# Check server health
curl http://192.168.99.188:5001/health

# List devices
curl http://192.168.99.188:5001/api/devices | jq

# Get latest from all sensors
curl http://192.168.99.188:5001/api/devices/all/latest | jq

# Update device name
curl -X PUT http://192.168.99.188:5001/api/devices/garden-bed-a \
  -H "Content-Type: application/json" \
  -d '{"name": "Garden Bed A", "location": "North yard"}'
```

## Device ID Strategy

### Option 1: Auto-generate from MAC (Simple)
```cpp
#define DEVICE_ID_AUTO   true
#define DEVICE_ID        ""  // Ignored
```
Result: `esp8266-40915141d997`

### Option 2: Custom Names (Recommended)
```cpp
#define DEVICE_ID_AUTO   false
#define DEVICE_ID        "garden-bed-a"
```
Result: `garden-bed-a`

**Important**: Each sensor must have a **unique** ID!

## Current Status

✅ **Database server** updated with multi-sensor schema
✅ **API endpoints** support device management
✅ **Firmware config** ready for database integration
✅ **Documentation** complete (setup + integration guides)

⏳ **Not yet done**:
- Integrating database_client into main.cpp (see FIRMWARE_INTEGRATION.md)
- Building/testing with multiple sensors
- Creating multi-sensor dashboard UI

## Next Actions

**To deploy your working sensor with database:**

1. Switch back to main branch (current sensor still works):
   ```bash
   git checkout main
   ```

2. **Later**, when ready to add database:
   ```bash
   git checkout feature/database-logging
   # Follow FIRMWARE_INTEGRATION.md
   # Test with one sensor first
   # Then deploy multiple sensors
   ```

**To deploy additional sensors:**

1. Flash new ESP8266 with unique `DEVICE_ID`
2. Wait for first reading (1 min)
3. Label it: `curl -X PUT http://192.168.99.188:5001/api/devices/<id> ...`
4. Done!

## Architecture Benefits

- ✅ **Centralized data**: All sensors in one database
- ✅ **Historical analysis**: Compare multiple locations over time
- ✅ **Independent operation**: Each sensor still works standalone
- ✅ **Graceful degradation**: If database is down, local logging continues
- ✅ **Easy scaling**: Add new sensors anytime
- ✅ **RESTful API**: Integrate with other tools/dashboards

## File Organization

```
soil-sensor/
├── database/
│   ├── server.py                    # ← Updated: Multi-sensor support
│   ├── MULTI_SENSOR_SETUP.md        # ← NEW: Complete setup guide
│   ├── FIRMWARE_INTEGRATION.md      # ← NEW: How to modify firmware
│   └── QUICK_REFERENCE.md           # ← This file
│
└── firmware/
    └── src/
        ├── config.h                 # ← Updated: Added DB config
        ├── database_client.h        # ← NEW: HTTP client header
        ├── database_client.cpp      # ← NEW: HTTP client impl
        └── main.cpp                 # ← To be updated (see guide)
```

## Support

**Issues?**
1. Check `MULTI_SENSOR_SETUP.md` - Complete setup walkthrough
2. Check `FIRMWARE_INTEGRATION.md` - Code integration examples
3. Check serial monitor for error messages
4. Verify server is reachable: `curl http://192.168.99.188:5001/health`

**Working Example:**
Your currently deployed sensor (192.168.99.70) still works normally on the `main` branch!
