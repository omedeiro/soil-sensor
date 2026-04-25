# Database Setup Guide

This setup allows your plant monitor to:
1. Store readings in a persistent database (SQLite)
2. Continue collecting data even if you close the web browser
3. View data from any device without connecting directly to the ESP8266
4. Keep historical data indefinitely (not limited by ESP8266 RAM)

## Quick Start

### Step 1: Install Python Dependencies

```bash
cd database
pip3 install -r requirements.txt
```

### Step 2: Find Your Computer's IP Address

The ESP8266 needs to know where to send data.

**On Mac:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Look for an IP like `192.168.X.X` (probably `192.168.99.100` or similar).

**On Windows:**
```
ipconfig
```

Look for "IPv4 Address" under your WiFi adapter.

### Step 3: Update ESP8266 Configuration

Edit `firmware/src/config.h`:

```cpp
#define USE_REMOTE_DB       true
#define DB_SERVER_URL       "http://YOUR_COMPUTER_IP:5000/api/reading"
```

Replace `YOUR_COMPUTER_IP` with the IP from Step 2.

Example:
```cpp
#define DB_SERVER_URL       "http://192.168.99.100:5000/api/reading"
```

### Step 4: Start the Database Server

```bash
cd database
python3 server.py
```

You should see:
```
═══════════════════════════════════════
  🌱 Soil Moisture Database Server
═══════════════════════════════════════
✓ Database initialized: /path/to/sensor_data.db

Starting Flask server...
Server will be available at:
  - http://localhost:5000
  - http://192.168.99.100:5000 (if on same network)
```

Leave this running!

### Step 5: Upload Firmware to ESP8266

```bash
cd firmware
pio run --target upload
pio device monitor
```

Watch the serial monitor. You should see:
```
[Sensor] Reading #1
  Moisture: 45.2%
  ...
[DB] ✓ Posted to database (HTTP 201)
```

### Step 6: Open the Dashboard

Open `database/dashboard.html` in your browser.

Or visit: `http://YOUR_COMPUTER_IP:5000/dashboard`

## How It Works

```
┌──────────────┐         ┌─────────────────┐         ┌──────────────┐
│   ESP8266    │  HTTP   │  Database       │  HTTP   │  Your Phone  │
│  (Sensor)    │ ──POST─►│  Server (Mac)   │◄──GET── │  / Browser   │
│              │         │  Python+SQLite  │         │              │
└──────────────┘         └─────────────────┘         └──────────────┘
     Every 5 min              Stores data              View anytime
```

**Benefits:**
- ESP8266 only needs to POST data (less memory, more stable)
- Database runs on your computer (much more storage)
- Multiple people can view the dashboard simultaneously
- Data persists even if ESP8266 reboots
- Can analyze historical trends

## Troubleshooting

### ESP8266 shows "[DB] ✗ POST failed"

**Check 1:** Is the database server running?
```bash
curl http://YOUR_COMPUTER_IP:5000/health
```

Should return: `{"status":"ok",...}`

**Check 2:** Is the IP address correct in `config.h`?

**Check 3:** Are both devices on the same WiFi network?

**Check 4:** Is your firewall blocking port 5000?

On Mac:
```bash
# Allow Python through firewall
System Preferences → Security & Privacy → Firewall → Firewall Options
```

### Dashboard shows "Cannot connect to database server"

**Check 1:** Update the `DB_SERVER` constant in `dashboard.html`:
```javascript
const DB_SERVER = 'http://YOUR_COMPUTER_IP:5000';
```

**Check 2:** Open the browser console (F12) to see detailed errors

**Check 3:** Try accessing the API directly:
```
http://YOUR_COMPUTER_IP:5000/api/latest
```

Should return JSON with the latest reading.

### Sensor reads 0% or 100% always

This is a calibration issue, not related to the database.

See the main README.md for calibration instructions.

## Running as a Service

To keep the database server running permanently:

### On Mac (using launchd)

Create `~/Library/LaunchAgents/com.soilsensor.db.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.soilsensor.db</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/Users/YOUR_USERNAME/soil-sensor/database/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Then:
```bash
launchctl load ~/Library/LaunchAgents/com.soilsensor.db.plist
```

### Using screen (simple method)

```bash
screen -S soildb
cd database
python3 server.py

# Press Ctrl+A, then D to detach
# To reattach: screen -r soildb
```

## API Reference

The database server provides these endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/reading` | Store new reading (ESP8266 uses this) |
| GET | `/api/latest` | Get most recent reading |
| GET | `/api/history?limit=288` | Get historical readings |
| GET | `/api/stats` | Get database statistics |
| POST | `/api/reset` | Clear all readings |
| GET | `/health` | Health check |

### Example: Get Latest Reading

```bash
curl http://192.168.99.100:5000/api/latest
```

Response:
```json
{
  "ts": 1775000000,
  "raw": 520,
  "moisture": 61.9,
  "uptime": 3600,
  "crashes": 0
}
```

## Data Backup

The database is stored in `database/sensor_data.db`.

To back up:
```bash
cp database/sensor_data.db database/sensor_data_backup_$(date +%Y%m%d).db
```

To export as CSV:
```bash
sqlite3 database/sensor_data.db \
  "SELECT * FROM readings;" \
  -header -csv > readings_export.csv
```

## Optional: Disable Local Web Server

Once the database is working, you can disable the ESP8266's built-in web server to save memory:

In `firmware/src/main.cpp`, comment out the web server:
```cpp
// if (wifi.isConnected()) {
//     webServer = new MonitorWebServer(logger, sensor);
//     webServer->begin();
// }
```

This makes the ESP8266 even more stable and lightweight.
