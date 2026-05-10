# Grafana Dashboards Guide

This directory contains Grafana dashboard configurations for the soil sensor monitoring system.

## Available Dashboards

### 1. 🌱 Soil Moisture Dashboard (`soil-sensor.json`)

**Primary dashboard for plant health monitoring**

**Purpose:** Track soil moisture levels across all sensors with easy-to-read visualizations focused on plant care.

**Key Features:**
- **Individual sensor gauges:** Each sensor displays its current moisture percentage with color-coded thresholds
  - Red (0-20%): Very dry - immediate watering needed
  - Yellow (20-40%): Dry - watering recommended
  - Green (40-80%): Optimal moisture range
  - Blue (80-100%): Very wet - may indicate overwatering
  
- **Moisture statistics panel:** Shows current, average, min, and max moisture for the selected time range

- **Individual time series plots:** Each sensor gets its own full-width graph showing moisture trends over time
  - Uses Grafana's repeat feature to automatically create a plot for each detected sensor
  - Color-coded background based on moisture thresholds
  - Displays last, mean, min, and max values in legend

**Best for:**
- Daily plant care monitoring
- Watering schedule decisions
- Identifying trends in soil moisture
- Comparing moisture levels between different plants/locations

**Settings:**
- Default time range: Last 24 hours
- Auto-refresh: Every 5 minutes
- Sensor filter: Dropdown to select specific sensor or view all

---

### 2. ⚙️ System Diagnostics Dashboard (`system-diagnostics.json`)

**Technical dashboard for network and hardware monitoring**

**Purpose:** Monitor WiFi connectivity, system health, and diagnose technical issues with ESP8266 sensors.

**Key Features:**

#### Top Row - Current Status
- **WiFi Signal Strength (RSSI):** Large gauge showing current signal quality
  - Excellent: -30 to -50 dBm
  - Good: -50 to -60 dBm
  - Fair: -60 to -70 dBm
  - Weak: -70 to -80 dBm
  - Very Weak: -80 to -90 dBm

- **System Uptime:** How long each device has been running since last restart
- **Free Heap Memory:** Available RAM on ESP8266 (healthy: >30KB)
- **Crash Counter:** Number of crashes detected (should be 0)

#### Device Status Table
- Consolidated view of all devices with key metrics
- Color-coded cells highlight problems:
  - Red WiFi signal = connection issues likely
  - Red heap memory = memory leak or instability
  - Red crashes = power supply or software issues

#### Time Series Graphs
1. **WiFi Signal Over Time:** Track connection stability and identify dead zones
2. **Free Heap Memory Over Time:** Detect memory leaks or allocation issues
3. **System Uptime Over Time:** See restart patterns and device reliability
4. **Raw ADC Values:** Raw sensor readings for calibration and troubleshooting

**Best for:**
- Diagnosing connectivity issues
- Monitoring system stability
- Identifying hardware problems
- Sensor calibration
- Network optimization

**Settings:**
- Default time range: Last 24 hours
- Auto-refresh: Every 1 minute
- Device filter: View all devices or filter to specific ones

---

## Installation

### Import to Grafana

1. Open Grafana web interface (default: `http://192.168.99.134:3000`)
2. Click **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select the dashboard file:
   - For moisture monitoring: `soil-sensor.json`
   - For diagnostics: `system-diagnostics.json`
5. Select your InfluxDB datasource (should auto-detect)
6. Click **Import**

### Update Existing Dashboard

If you've already imported a dashboard and want to update it:

1. The dashboards have `"overwrite": true` set in the JSON
2. Simply re-import the file - it will update the existing dashboard
3. Or manually copy-paste the JSON:
   - **Dashboards** → Select dashboard → **Settings** (gear icon)
   - **JSON Model** → Paste new JSON → **Save**

---

## Multi-Sensor Support

Both dashboards automatically detect all sensors in your InfluxDB database based on the `device_id` tag.

**Setting up sensors:**
```cpp
// In firmware/src/config.h
#define DEVICE_ID_AUTO      false
#define DEVICE_ID           "sensor-1"     // Unique ID for each sensor
#define DEVICE_LOCATION     "backyard"     // Optional location tag
```

**Dashboard behavior:**
- **Soil Moisture Dashboard:** Creates individual plots for each sensor using Grafana's repeat panels
- **System Diagnostics Dashboard:** Multi-select dropdown to view all or specific devices
- Sensors appear automatically when they start posting data

---

## Customization

### Adjusting Moisture Thresholds

Edit `soil-sensor.json` to change when colors appear:

```json
"thresholds": {
  "steps": [
    {"color": "red", "value": null},    // 0-20%: Very dry
    {"color": "yellow", "value": 20},   // 20-40%: Dry
    {"color": "green", "value": 40},    // 40-80%: Optimal
    {"color": "blue", "value": 80}      // 80-100%: Very wet
  ]
}
```

**Per-sensor thresholds:** Different plants need different moisture levels. To set custom thresholds:
1. Import the soil-sensor.json dashboard
2. Edit the gauge panel for a specific sensor
3. Override the threshold values
4. Save as a new dashboard (e.g., "Soil Moisture - Custom Thresholds")

### Time Range Presets

Add quick time range buttons by editing the dashboard settings:
- Last 6 hours
- Last 12 hours
- Last 24 hours (default)
- Last 7 days
- Last 30 days

### Alert Configuration

Set up alerts for low moisture levels:

1. Open **Soil Moisture Dashboard**
2. Edit a time series panel
3. Go to **Alert** tab
4. Create alert rule: "If moisture < 20% for 30 minutes, send notification"
5. Configure notification channel (email, Slack, Discord, etc.)

See Grafana's [Alert Rules documentation](https://grafana.com/docs/grafana/latest/alerting/) for details.

---

## Troubleshooting

### Dashboard shows "No data"

**Check:**
1. InfluxDB is running: `http://192.168.99.134:8086/health`
2. ESP8266 is posting data (check serial monitor for `[DB] ✓ Posted to InfluxDB`)
3. Data source UID matches your InfluxDB configuration
4. Time range includes recent data (try "Last 7 days")

**Fix datasource UID:**
1. Find your datasource UID: **Connections** → **Data sources** → **InfluxDB** → Check URL
2. Edit dashboard JSON, replace all instances of `"uid": "cflk0i2e2nwu8d"` with your UID
3. Re-import dashboard

### Sensor doesn't appear in dropdown

**Possible causes:**
- Sensor hasn't posted data yet (wait 5 minutes for first reading)
- Device ID contains special characters (use alphanumeric + hyphens only)
- InfluxDB bucket name doesn't match (default: `sensor-readings`)

**Verify data:**
```bash
# Query InfluxDB directly
curl -H "Authorization: Token YOUR_READ_TOKEN" \
  -H "Content-Type: application/json" \
  "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  --data '{"query": "from(bucket: \"sensor-readings\") |> range(start: -1h) |> filter(fn: (r) => r._measurement == \"sensor_reading\") |> distinct(column: \"device_id\")"}'
```

### Panels show "Mixed" or wrong device name

This happens when multiple devices are selected. Use the **Sensor** dropdown at the top to filter to a single device.

---

## Dashboard File Format

The JSON files follow Grafana's dashboard schema (version 38). Key sections:

- `templating.list`: Variables for filtering (e.g., device selector)
- `panels[]`: Array of visualization panels
- `targets[]`: InfluxDB Flux queries for each panel
- `fieldConfig`: Display settings, thresholds, units
- `gridPos`: Panel position and size (24-column grid)

For advanced customization, see [Grafana Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/).

---

## Best Practices

1. **Use Soil Moisture Dashboard daily** for plant care decisions
2. **Check System Diagnostics weekly** to catch issues early
3. **Set up alerts** for critical moisture levels
4. **Adjust time ranges** based on your needs:
   - 24 hours: Daily monitoring
   - 7 days: Weekly patterns
   - 30 days: Seasonal trends
5. **Export data** using Grafana's CSV export for long-term analysis
6. **Create snapshots** before making dashboard changes

---

## Related Documentation

- [Raspberry Pi Setup Guide](../docs/RPI_SETUP.md) - InfluxDB and Grafana installation
- [Multi-Sensor Deployment](../docs/MULTI_SENSOR_GUIDE.md) - Setting up 5-10 sensors
- [WiFi Improvements](../docs/WIFI_IMPROVEMENTS.md) - Network stability features

---

**Dashboard Version:**
- Soil Moisture Dashboard: v2 (soil-moisture-v2)
- System Diagnostics: v1 (system-diagnostics-v1)

Last updated: 2026-05-10
