# Multi-Sensor Setup Guide

This guide explains how to set up multiple ESP8266 soil sensors to log data to a central database server.

## Architecture Overview

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  ESP8266 #1     │      │  ESP8266 #2     │      │  ESP8266 #3     │
│  (Garden Bed A) │      │  (Garden Bed B) │      │  (Potted Plant) │
│                 │      │                 │      │                 │
│  device_id:     │      │  device_id:     │      │  device_id:     │
│  "garden-bed-a" │      │  "garden-bed-b" │      │  "pot-basil"    │
└────────┬────────┘      └────────┬────────┘      └────────┬────────┘
         │                        │                        │
         │         WiFi Network (192.168.99.x)            │
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
                         ┌────────▼────────┐
                         │  Database Server│
                         │  (Flask + SQLite)│
                         │  192.168.99.188 │
                         │  Port: 5001     │
                         └─────────────────┘
```

## Step 1: Configure the Database Server

### Install Dependencies

```bash
cd database
python3 -m pip install -r requirements.txt
```

### Start the Server

```bash
python3 server.py
```

The server will:
- Initialize the SQLite database with multi-sensor schema
- Start listening on `0.0.0.0:5001`
- Create tables for `devices` and `readings`

### Verify Server is Running

```bash
curl http://localhost:5001/health
```

Expected response:
```json
{
  "status": "ok",
  "database": "/path/to/sensor_data.db",
  "timestamp": 1714000000
}
```

## Step 2: Configure Each ESP8266 Sensor

Each sensor needs a **unique device ID**. This ID will be used to identify readings in the database.

### Option A: Use MAC Address (Automatic)

The firmware can automatically use the device's MAC address as the ID:

```cpp
// In firmware/src/config.h
#define DEVICE_ID_AUTO      true   // Auto-generate from MAC
```

This will create IDs like: `esp8266-40915141d997`

### Option B: Use Custom ID (Recommended)

For human-readable IDs, set custom names:

```cpp
// In firmware/src/config.h
#define DEVICE_ID_AUTO      false
#define DEVICE_ID           "garden-bed-a"   // Custom unique ID
```

Examples:
- `"garden-bed-a"`
- `"greenhouse-tomatoes"`
- `"pot-basil"`
- `"lawn-north"`

### Configure Database Connection

Update `config.h` for each sensor:

```cpp
// Database server configuration
#define USE_REMOTE_DB       true
#define DB_SERVER_URL       "http://192.168.99.188:5001/api/reading"

// Device identification
#define DEVICE_ID_AUTO      false
#define DEVICE_ID           "YOUR-UNIQUE-ID-HERE"
```

### Build and Upload

```bash
cd firmware
pio run --target upload
```

## Step 3: Label Your Devices

After the first reading from each sensor, register metadata:

```bash
# Update device name and location
curl -X PUT http://192.168.99.188:5001/api/devices/garden-bed-a \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Garden Bed A",
    "location": "Backyard - North Side",
    "mac_address": "40:91:51:4f:d9:97"
  }'
```

## Step 4: Verify Multi-Sensor Operation

### List All Devices

```bash
curl http://192.168.99.188:5001/api/devices
```

Response:
```json
{
  "count": 3,
  "devices": [
    {
      "device_id": "garden-bed-a",
      "name": "Garden Bed A",
      "location": "Backyard - North Side",
      "mac_address": "40:91:51:4f:d9:97",
      "first_seen": "2026-04-25 17:30:00",
      "last_seen": "2026-04-25 18:45:00",
      "total_readings": 75
    },
    // ... more devices
  ]
}
```

### Get Latest Reading from Each Device

```bash
curl http://192.168.99.188:5001/api/devices/all/latest
```

### Get History for Specific Device

```bash
curl "http://192.168.99.188:5001/api/history?device_id=garden-bed-a&limit=100"
```

## API Reference

### Store Reading (Called by ESP8266)

```bash
POST /api/reading
Content-Type: application/json

{
  "device_id": "garden-bed-a",
  "timestamp": 1714000000,
  "raw": 520,
  "moisture": 61.9,
  "uptime": 3600,
  "crashes": 0
}
```

### Query Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/devices` | GET | List all registered devices |
| `/api/devices/<id>` | GET | Get info about specific device |
| `/api/devices/<id>` | PUT | Update device metadata |
| `/api/devices/all/latest` | GET | Latest reading from each device |
| `/api/latest?device_id=xxx` | GET | Latest reading (optional filter) |
| `/api/history?device_id=xxx&limit=N` | GET | Historical readings (optional filter) |
| `/api/stats?device_id=xxx` | GET | Statistics (optional filter) |

## Database Schema

### `devices` Table

| Column | Type | Description |
|--------|------|-------------|
| device_id | TEXT | Primary key, unique identifier |
| name | TEXT | Human-readable name |
| location | TEXT | Physical location description |
| mac_address | TEXT | WiFi MAC address |
| first_seen | TIMESTAMP | First time device reported |
| last_seen | TIMESTAMP | Most recent reading |
| total_readings | INTEGER | Total number of readings |

### `readings` Table

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Auto-increment primary key |
| device_id | TEXT | Foreign key to devices table |
| timestamp | INTEGER | Unix timestamp from sensor |
| raw | INTEGER | Raw ADC value (0-1023) |
| moisture | REAL | Calculated moisture percentage |
| uptime | INTEGER | Sensor uptime in seconds |
| crashes | INTEGER | Crash counter |
| received_at | TIMESTAMP | Server received timestamp |

## Troubleshooting

### Sensor Not Appearing in Device List

1. Check serial monitor for database POST errors
2. Verify `DB_SERVER_URL` is correct
3. Ensure server is reachable: `curl http://192.168.99.188:5001/health`

### Duplicate Device IDs

Each sensor must have a unique `DEVICE_ID`. If using `DEVICE_ID_AUTO=true`, MAC addresses ensure uniqueness.

### Database Connection Timeout

- Verify WiFi connectivity: Device must be on same network as database server
- Check firewall rules on server machine
- Test connectivity: `curl http://192.168.99.188:5001/health` from sensor network

## Next Steps

1. **Dashboard**: Create a web dashboard showing all sensors
2. **Alerts**: Set up notifications for low/high moisture
3. **Data Export**: Export readings to CSV for analysis
4. **Visualization**: Create charts comparing multiple sensors

## Example: Adding a Third Sensor

```bash
# 1. Flash new ESP8266 with unique ID
cd firmware
# Edit src/config.h:
#   DEVICE_ID = "greenhouse-tomatoes"
pio run --target upload

# 2. Wait for first reading (1 minute)

# 3. Add metadata
curl -X PUT http://192.168.99.188:5001/api/devices/greenhouse-tomatoes \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Greenhouse Tomatoes",
    "location": "Greenhouse - Row 3"
  }'

# 4. Verify
curl http://192.168.99.188:5001/api/devices/greenhouse-tomatoes
```

Done! Your multi-sensor system is now operational. 🌱
