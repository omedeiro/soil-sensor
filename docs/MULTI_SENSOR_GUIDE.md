# Multi-Sensor Deployment Guide

Step-by-step guide for deploying multiple ESP8266 soil sensors with InfluxDB + Grafana.

## 🎯 Overview

This system supports 5-10 sensors simultaneously:
- Each sensor has unique device ID
- All sensors POST to same InfluxDB instance
- Grafana dashboards support filtering by device/location
- Central monitoring from single Raspberry Pi

## 🔧 Hardware Requirements

**Per Sensor**:
- ESP8266 (NodeMCU, Wemos D1, etc.)
- Capacitive soil moisture sensor
- USB power adapter (5V, ≥500mA)
- USB cable
- (Optional) Weatherproof enclosure

**Central Server**:
- Raspberry Pi 5 (shared across all sensors)
- 256GB USB drive (shared)
- Network router (WiFi coverage for all sensor locations)

## 📝 Deployment Steps

### Step 1: Plan Sensor Locations

Create a deployment map:

| Device ID | Location | Coverage Area | WiFi Signal |
|-----------|----------|---------------|-------------|
| sensor-1 | Backyard | Lawn area | Excellent |
| sensor-2 | Greenhouse | Tomato bed | Good |
| sensor-3 | Garden-A | Vegetable garden | Good |
| sensor-4 | Garden-B | Flower bed | Fair |
| sensor-5 | Front yard | Lawn | Excellent |

**Location selection criteria**:
- WiFi signal strength: -75 dBm or better (check with phone app)
- Power outlet within 10 feet
- Protected from direct rain (unless weatherproofed)
- Representative of soil moisture zone

### Step 2: Configure First Sensor

1. Edit `firmware/src/config.h` for sensor-1:
   ```cpp
   #define DEVICE_ID_AUTO      false
   #define DEVICE_ID           "sensor-1"
   #define DEVICE_LOCATION     "backyard"
   
   #define DB_SERVER_URL       "http://192.168.1.200:8086/api/v2/write"
   #define INFLUX_TOKEN        "your_write_token"
   #define INFLUX_ORG          "soil-monitoring"
   #define INFLUX_BUCKET       "sensor-readings"
   ```

2. Compile and flash:
   ```bash
   cd firmware
   pio run --target upload
   ```

3. Monitor serial output:
   ```bash
   pio device monitor
   ```

4. Configure WiFi via captive portal:
   - Connect to `SoilSensor-Setup` AP
   - Enter WiFi credentials
   - Wait for connection confirmation

5. Verify data flow:
   ```bash
   # Watch for successful POSTs
   [WiFi] ✓ Connected
   [DB] ✓ Posted to InfluxDB (HTTP 204)
   ```

### Step 3: Calibrate Sensor

**Option A: Via Config File**
1. Place sensor in open air, note raw ADC value from serial
2. Submerge sensor in water, note raw ADC value
3. Update `config.h`:
   ```cpp
   #define SENSOR_AIR_VALUE    780   // Your air value
   #define SENSOR_WATER_VALUE  360   // Your water value
   ```
4. Reflash firmware

**Option B: Via HTTP API** (if web server enabled)
```bash
curl -X POST "http://192.168.1.100/api/calibrate?air=780&water=360"
```

### Step 4: Clone Configuration for Additional Sensors

**For sensor-2**:
1. Copy `config.h` to `config_sensor2.h` (for reference)
2. Edit `config.h`:
   ```cpp
   #define DEVICE_ID           "sensor-2"
   #define DEVICE_LOCATION     "greenhouse"
   ```
3. Flash to second ESP8266
4. Repeat calibration process
5. Save `config.h` as `config_sensor2.h` before next sensor

**Repeat for sensors 3-5**

### Step 5: Deploy Physical Sensors

**Per sensor**:
1. Insert sensor probe into soil (2-3 inches deep)
2. Keep electronics above ground
3. Route USB cable to power adapter
4. Optional: Place electronics in weatherproof box
5. Power on and verify WiFi connection via serial

**Deployment checklist**:
- [ ] Sensor probe inserted at correct depth
- [ ] Wires not under tension
- [ ] Electronics protected from moisture
- [ ] Power cable secured
- [ ] WiFi signal verified (check RSSI in serial output)
- [ ] First reading posted to InfluxDB

### Step 6: Verify Multi-Sensor Data Flow

1. Run multi-sensor test script:
   ```bash
   export INFLUX_TOKEN="your_write_token"
   cd tests
   ./test_multi_sensor.sh
   ```

2. Check InfluxDB for all device IDs:
   ```bash
   influx query \
     --org soil-monitoring \
     --token "your_read_token" \
     'from(bucket: "sensor-readings") 
      |> range(start: -1h) 
      |> filter(fn: (r) => r._measurement == "sensor_reading")
      |> group(columns: ["device_id"])
      |> distinct(column: "device_id")'
   ```

3. Expected output:
   ```
   sensor-1
   sensor-2
   sensor-3
   sensor-4
   sensor-5
   ```

### Step 7: Configure Grafana Multi-Sensor Dashboard

1. Open Grafana: `http://192.168.1.200:3000`

2. Create multi-sensor overview panel:
   - Query:
     ```flux
     from(bucket: "sensor-readings")
       |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
       |> filter(fn: (r) => r._measurement == "sensor_reading")
       |> filter(fn: (r) => r._field == "moisture")
       |> group(columns: ["device_id", "location"])
     ```
   - Visualization: Time series
   - Legend: `{{device_id}} - {{location}}`

3. Add device selector variable:
   - Settings → Variables → New variable
   - Name: `device_id`
   - Type: Query
   - Query:
     ```flux
     import "influxdata/influxdb/schema"
     schema.tagValues(
       bucket: "sensor-readings",
       tag: "device_id"
     )
     ```
   - Multi-value: Yes
   - Include all: Yes

4. Add location filter variable:
   - Name: `location`
   - Type: Query
   - Query:
     ```flux
     import "influxdata/influxdb/schema"
     schema.tagValues(
       bucket: "sensor-readings",
       tag: "location"
     )
     ```

5. Use variables in panel queries:
   ```flux
   from(bucket: "sensor-readings")
     |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
     |> filter(fn: (r) => r._measurement == "sensor_reading")
     |> filter(fn: (r) => r.device_id =~ /^${device_id:regex}$/)
     |> filter(fn: (r) => r.location =~ /^${location:regex}$/)
   ```

## 📊 Dashboard Examples

### Current Status Panel (Stat Visualization)

Shows latest moisture reading for each sensor:

```flux
from(bucket: "sensor-readings")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> group(columns: ["device_id", "location"])
  |> last()
```

**Visualization settings**:
- Type: Stat
- Color scheme:
  - Red: 0-30% (too dry)
  - Yellow: 30-50% (optimal)
  - Green: 50-70% (good)
  - Blue: 70-100% (too wet)
- Show: Value and name

### Comparison Chart (Time Series)

Compare moisture levels across all sensors:

```flux
from(bucket: "sensor-readings")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> aggregateWindow(every: v.windowPeriod, fn: mean)
```

**Visualization settings**:
- Type: Time series
- Legend: `{{device_id}} ({{location}})`
- Y-axis: 0-100%
- Thresholds: 30%, 50%, 70%

### Alert Panel (Table)

Show sensors requiring attention:

```flux
from(bucket: "sensor-readings")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> group(columns: ["device_id", "location"])
  |> last()
  |> filter(fn: (r) => r._value < 30 or r._value > 70)
```

**Visualization settings**:
- Type: Table
- Columns: device_id, location, moisture, _time
- Color: Highlight rows in red

## 🔔 Alert Configuration

### Grafana Alerts

**Alert 1: Low Moisture**
```flux
from(bucket: "sensor-readings")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> filter(fn: (r) => r._field == "moisture")
  |> aggregateWindow(every: 10m, fn: mean)
  |> filter(fn: (r) => r._value < 30)
```

**Alert settings**:
- Condition: When average < 30%
- Duration: 10 minutes
- No data: OK (sensor may be temporarily offline)
- Notification: Send to Grafana Cloud / Email / Slack

**Alert 2: Sensor Offline**
```flux
from(bucket: "sensor-readings")
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "sensor_reading")
  |> group(columns: ["device_id"])
  |> count()
```

**Alert settings**:
- Condition: When count < 3 (expected ~6 readings in 30min)
- Duration: 30 minutes
- Notification: Send alert if sensor hasn't posted

### Grafana Cloud Push Notifications

1. Sign up for Grafana Cloud (free tier):
   - Go to: https://grafana.com/products/cloud/
   - Create free account

2. Configure OnCall integration:
   - Grafana → Alerting → Contact points → New contact point
   - Type: Grafana OnCall
   - Connect to Grafana Cloud

3. Create notification policy:
   - Match alerts by label: `severity=critical`
   - Route to: OnCall contact point
   - Group by: device_id

4. Install Grafana OnCall mobile app:
   - iOS: App Store
   - Android: Google Play
   - Login with Grafana Cloud credentials

5. Test push notification:
   - Manually trigger alert in Grafana
   - Verify push received on phone

## 🛠️ Maintenance

### Adding New Sensor

1. Flash firmware with new `DEVICE_ID`
2. Calibrate sensor
3. Deploy physically
4. Verify data appears in Grafana
5. No dashboard changes needed (auto-detects new device)

### Removing Sensor

1. Power off sensor
2. Optional: Delete historical data
   ```bash
   influx delete \
     --org soil-monitoring \
     --bucket sensor-readings \
     --start 1970-01-01T00:00:00Z \
     --stop $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
     --predicate 'device_id="sensor-3"'
   ```

### Replacing Sensor

**Same location, new hardware**:
1. Flash new ESP8266 with same `DEVICE_ID` and `DEVICE_LOCATION`
2. Calibrate
3. Swap physically
4. Old data persists in InfluxDB under same device ID

**New location**:
1. Flash with new `DEVICE_ID` (e.g., sensor-6)
2. Update `DEVICE_LOCATION`
3. Treat as new sensor (see "Adding New Sensor")

## 📈 Scaling Considerations

### 5-10 Sensors (Supported)

- InfluxDB write rate: ~1-2 writes/minute
- Network bandwidth: Negligible
- Raspberry Pi load: <5% CPU
- Storage: ~50MB/year per sensor
- No performance issues

### 10-20 Sensors (May work)

- Test with `test_multi_sensor.sh` script
- Monitor Raspberry Pi CPU/memory
- Consider increasing InfluxDB cache settings
- Monitor WiFi network congestion

### 20+ Sensors (Requires optimization)

- Consider batching writes from ESP8266
- Increase InfluxDB write buffer
- Use Ethernet for Raspberry Pi (not WiFi)
- Partition sensors across multiple InfluxDB instances
- Upgrade to Raspberry Pi with more RAM

## 🐛 Troubleshooting Multi-Sensor Issues

### Some Sensors Not Appearing in Grafana

**Check**:
1. Sensor WiFi connection (serial monitor)
2. InfluxDB write success (serial: `[DB] ✓ Posted`)
3. Query InfluxDB for missing device ID
4. Verify `DEVICE_ID` is unique (no duplicates)

### Duplicate Device IDs

**Symptoms**:
- Two sensors with same `DEVICE_ID` overwrite each other's data
- Erratic readings (jumps between physical locations)

**Solution**:
1. Identify conflicting sensors (check serial output device ID)
2. Reflash one with unique ID
3. Redeploy

### WiFi Network Congestion

**Symptoms**:
- Multiple sensors dropping WiFi simultaneously
- Increased reconnection attempts

**Solutions**:
1. Reduce number of devices on 2.4GHz band
2. Change router channel (use WiFi analyzer)
3. Upgrade to better router (WiFi 6 support)
4. Use multiple access points for coverage

### InfluxDB Write Failures

**Symptoms**:
- All sensors showing `[DB] ✗ POST failed`
- Queue filling on all sensors

**Solutions**:
1. Check InfluxDB service: `systemctl status influxdb`
2. Check Raspberry Pi disk space: `df -h`
3. Check InfluxDB logs: `journalctl -u influxdb -f`
4. Restart InfluxDB if needed

## 📚 Related Documentation

- `docs/RPI_SETUP.md` - Raspberry Pi installation
- `docs/WIFI_IMPROVEMENTS.md` - WiFi stability features
- `docs/GRAFANA_DASHBOARDS.md` - Dashboard creation (to be created)
- `tests/test_multi_sensor.sh` - Multi-sensor simulation test
- `firmware/src/config.h` - Device ID configuration

## 🎯 Best Practices

1. **Naming convention**: Use sequential IDs (sensor-1, sensor-2, etc.)
2. **Documentation**: Keep deployment map updated
3. **Labeling**: Physically label each ESP8266 with device ID
4. **Calibration**: Calibrate each sensor individually (soil varies)
5. **Testing**: Run 24h test before final deployment
6. **Monitoring**: Check Grafana daily for first week
7. **Backups**: Keep backup firmware config for each sensor
8. **Power**: Use quality USB adapters (cheap ones cause instability)
