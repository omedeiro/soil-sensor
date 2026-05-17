# Grafana Dashboards Guide

This directory will contain Grafana dashboard configurations for the soil sensor monitoring system.

## Dashboard Export Instructions

**To export dashboards from your Grafana instance:**

1. Open Grafana web interface (default: `http://192.168.99.134:3000`)
2. Navigate to the dashboard you want to export
3. Click the **Share** icon (or dashboard settings)
4. Go to the **Export** tab
5. Click **Save to file**
6. Save the JSON file to this directory

**Recommended dashboards to create:**

### 1. 🌱 Soil Moisture Dashboard

**Purpose:** Track soil moisture levels across all sensors with easy-to-read visualizations focused on plant care.

**Recommended panels:**
- **Individual sensor gauges:** Current moisture percentage with color-coded thresholds
  - Red (0-20%): Very dry - immediate watering needed
  - Yellow (20-40%): Dry - watering recommended
  - Green (40-80%): Optimal moisture range
  - Blue (80-100%): Very wet - may indicate overwatering
  
- **Moisture statistics panel:** Current, average, min, and max moisture for selected time range

- **Individual time series plots:** Each sensor gets its own graph showing moisture trends over time
  - Use Grafana's repeat feature to automatically create a plot for each detected sensor
  - Color-coded background based on moisture thresholds

**Settings:**
- Default time range: Last 24 hours
- Auto-refresh: Every 5 minutes
- Sensor filter: Variable dropdown to select specific sensor or view all

---

### 2. ⚙️ System Diagnostics Dashboard

**Purpose:** Monitor WiFi connectivity, system health, and diagnose technical issues with ESP8266 sensors.

**Recommended panels:**

#### Top Row - Current Status
- **WiFi Signal Strength (RSSI):** Gauge showing current signal quality
  - Excellent: -30 to -50 dBm
  - Good: -50 to -60 dBm
  - Fair: -60 to -70 dBm
  - Weak: -70 to -80 dBm
  - Very Weak: -80 to -90 dBm

- **System Uptime:** Time since last restart
- **Free Heap Memory:** Available RAM on ESP8266 (healthy: >30KB)
- **Crash Counter:** Number of crashes detected (should be 0)

#### Time Series Graphs
1. **WiFi Signal Over Time:** Track connection stability
2. **Free Heap Memory Over Time:** Detect memory leaks
3. **System Uptime Over Time:** See restart patterns
4. **Raw ADC Values:** Raw sensor readings for calibration

**Settings:**
- Default time range: Last 24 hours
- Auto-refresh: Every 1 minute
- Device filter: Multi-select to view all or specific devices

---

## Installation (when JSON files exist)

### Import to Grafana

1. Open Grafana web interface (default: `http://192.168.99.134:3000`)
2. Click **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select the dashboard file from this directory
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

In your Grafana dashboard, edit panels to change when colors appear:

**Recommended thresholds:**
- Red (0-20%): Very dry
- Yellow (20-40%): Dry
- Green (40-80%): Optimal
- Blue (80-100%): Very wet

**Per-sensor thresholds:** Different plants need different moisture levels. To set custom thresholds:
1. Edit the gauge panel for a specific sensor
2. Override the threshold values in panel settings
3. Save the dashboard

### Time Range Presets

Add quick time range buttons by editing the dashboard settings:
- Last 6 hours
- Last 12 hours
- Last 24 hours (default)
- Last 7 days
- Last 30 days

### Alert Configuration

Set up alerts for low moisture levels:

1. Open a time series panel in your dashboard
2. Go to **Alert** tab
3. Create alert rule: "If moisture < 20% for 30 minutes, send notification"
4. Configure notification channel (email, Slack, Discord, etc.)

See Grafana's [Alert Rules documentation](https://grafana.com/docs/grafana/latest/alerting/) for details.

---

## Troubleshooting

### Dashboard shows "No data"

**Check:**
1. InfluxDB is running: `http://192.168.99.134:8086/health`
2. ESP8266 is posting data (check serial monitor for `[DB] ✓ Posted to InfluxDB`)
3. Data source is configured correctly in Grafana
4. Time range includes recent data (try "Last 7 days")

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

This happens when multiple devices are selected. Use a device filter variable at the top of your dashboard to filter to a single device.

---

## Best Practices

1. **Create dashboards** using the recommended panels above
2. **Set up alerts** for critical moisture levels
3. **Adjust time ranges** based on your needs:
   - 24 hours: Daily monitoring
   - 7 days: Weekly patterns
   - 30 days: Seasonal trends
4. **Export data** using Grafana's CSV export for long-term analysis
5. **Export dashboards** as JSON and commit them to this directory for version control

---

## Related Documentation

- [Technical Documentation](../docs/README.md) - WiFi stability, Grafana Cloud setup, InfluxDB notes
- [Project README](../README.md) - Complete setup and installation guide

---

**Note:** Dashboard JSON files need to be exported from Grafana and committed to this directory.

Last updated: 2026-05-10
