---
name: grafana-dashboard-config
description: Configure and deploy Grafana dashboards for the soil sensor project from centralized config. Use when editing `sensors-config.json`, adding a sensor to a dashboard, changing plant names/colors/thresholds, running `scripts/validate-config.py`, `scripts/generate-dashboard.py`, or `scripts/upload-dashboard-to-pi.sh`, working with the auto-generated `grafana-dashboards/soil-moisture-main.json`, or setting up the watering-history dashboard.
---

# Grafana Dashboard Configuration (v2.7.0)

The main Grafana dashboard is **auto-generated** from centralized configuration.
**Never manually edit `grafana-dashboards/soil-moisture-main.json`** — it is
auto-generated and will be overwritten.

## Centralized Configuration System

- **`sensors-config.json`** — Single source of truth for all sensor information (plant names, IPs, MACs, colors, thresholds)
- **`scripts/generate-dashboard.py`** — Auto-generates `grafana-dashboards/soil-moisture-main.json` from config
- **`scripts/validate-config.py`** — Validates `sensors-config.json` before generation (checks syntax, duplicates, required fields)
- **`scripts/upload-dashboard-to-pi.sh`** — Deploys dashboard to Grafana on Raspberry Pi (uses SSH + Grafana API)

## Critical Workflow Rules

1. **NEVER manually edit `grafana-dashboards/soil-moisture-main.json`** — auto-generated, will be overwritten
2. **ALWAYS validate before generating:** run `./scripts/validate-config.py` to catch errors early
3. **ALWAYS use `scripts/upload-dashboard-to-pi.sh`** for deployment (not manual curl or API calls)
4. **Deployment order is strict:** Edit config → Validate → Generate → Upload

## Adding a New Sensor (dashboard side)

```bash
# 1. Edit sensors-config.json
vim sensors-config.json
# Add new sensor block (copy existing sensor, modify id/plant/location/ip/mac/color)

# 2. Validate configuration
./scripts/validate-config.py
# Output: ✓ Configuration is valid (8 sensors)

# 3. Generate dashboard
./scripts/generate-dashboard.py
# Output: ✓ Generated grafana-dashboards/soil-moisture-main.json

# 4. Deploy to Grafana
./scripts/upload-dashboard-to-pi.sh
# Output: ✓ Dashboard imported successfully

# 5. Configure and flash ESP8266 (see soil-sensor-firmware skill)
cd firmware
# Edit src/config.h to match sensors-config.json (DEVICE_ID, DEVICE_LOCATION)
pio run --target upload
pio device monitor
```

## Changing Plant Names / Colors

```bash
# Quick workflow (3 commands):
vim sensors-config.json              # Edit plant name or color
./scripts/validate-config.py && \
./scripts/generate-dashboard.py && \
./scripts/upload-dashboard-to-pi.sh          # Validate, generate, deploy

# Dashboard updates in ~5 seconds (hard refresh browser: Cmd+Shift+R)
```

## sensors-config.json Structure

```json
{
  "sensors": [
    {
      "id": "sensor-X",              // Must match ESP8266 DEVICE_ID in config.h
      "plant": "Plant Name",         // Displayed in Grafana dropdown and labels
      "location": "room-name",       // Must match ESP8266 DEVICE_LOCATION in config.h
      "ip": "192.168.99.XXX",       // ESP8266 IP address (informational)
      "mac": "XX:XX:XX:XX:XX:XX",   // ESP8266 MAC address (informational)
      "color": "#RRGGBB",            // Hex color for time series graphs
      "thresholds": {
        "low": 33,                   // Low moisture threshold (%)
        "medium": 67                 // Medium moisture threshold (%)
      },
      "colorSteps": [                // Color gradient for bar gauges (dry → wet)
        {"value": null, "color": "#DARK"},   // Dry color
        {"value": 33, "color": "#MEDIUM"},   // Low moisture color
        {"value": 67, "color": "#LIGHT"}     // Wet color
      ]
    }
  ],
  "grafana": {
    "influxdb_datasource_uid": "cflk0i2e2nwu8d",  // Grafana datasource UID
    "bucket": "sensor-readings",                   // InfluxDB bucket name
    "measurement": "sensor_reading"                // InfluxDB measurement name
  }
}
```

## Dashboard Features (v2.7.0)

- **7-day default time window** (not 24h) — shows last week of data by default
- **Dynamic plant name display** — Large heading shows "🌱 Rubber Tree" when specific sensor selected
- **Dropdown shows plant names** — "Rubber Tree" not "sensor-1"
- **Functional filtering** — All panels filter when sensor selected from dropdown
- **Plant-only labels** — No room locations in labels (just "Rubber Tree")
- **Auto-generated from config** — All sensor info managed in sensors-config.json

## Validation Errors

```
# - Missing comma after sensor block → JSON syntax error
# - Duplicate sensor IDs → "Duplicate sensor ID: sensor-3"
# - Invalid color format → "Invalid color format for sensor-2: #GGG"
# - Missing required fields → "Missing required field 'plant' for sensor-4"
# - threshold.low >= threshold.medium → "Invalid thresholds for sensor-1"
```

Always run `./scripts/validate-config.py` before generating.

## Deployment Troubleshooting

- **Dashboard upload fails with "Access denied":** Update credentials in `scripts/upload-dashboard-to-pi.sh` (default: admin/admin)
- **Dashboard not updating in Grafana:** Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)
- **Sensor not appearing in dropdown:** Sensor hasn't sent data yet, or `DEVICE_ID` in config.h doesn't match sensors-config.json
- **Colors not matching config:** Regenerate and upload dashboard, then hard refresh browser

## Grafana Dashboards (`/grafana-dashboards/`)

- `soil-moisture-main.json` — Main overview dashboard (auto-generated, don't edit manually)
- `watering-history.json` — Watering event detection and tracking (v2.12.3)
- `sensor-details.json` — Individual sensor deep-dive
- `system-health.json` — ESP8266 diagnostics & events
- `alerts-overview.json` — Critical alerts & notifications
- `mobile-summary.json` — Mobile-optimized view
- `rpi-health.json` — Raspberry Pi system metrics
- `deploy-watering-dashboard.sh` — Deploy watering dashboard to Grafana
- `README.md` — Dashboard installation and customization guide

## Watering History Dashboard (v2.12.2)

Automatic watering event detection and visualization.
**Location:** `grafana-dashboards/watering-history.json`

**Detection Algorithm:**
- **Threshold:** 15%+ moisture increase between consecutive readings (5-minute intervals)
- **Watered Status:** 2-hour window after detection
- **Noise Filtering:** Filters out sensor jitter, only detects sustained increases
- **Offline Detection:** Gaps > 15 minutes between readings (via `elapsed()`)
- **Saturated Detection:** Sensor at >= 99.5% for 30+ minutes (via `stateDuration()`)
- **Not Working Detection:** Sensor pinned at >= 99.5% for 24+ hours (hardware fault)
- **Lookback:** 30 days for "last watered" stats, 7 days default timeline view

**State Priority:** not-working(6) > saturated(5) > offline(4) > noise(3) > watering(2) > dry(1) > normal(0)

**Dashboard Panels:**
1. **Watering Events Timeline** — Color-coded state timeline (Normal/Dry/Watering/Noise/Offline/Saturated/Not Working)
2. **Moisture Trend with Markers** — Time series with markers at watering events; plant names as trace labels via `byRegexp`
3. **Time Since Last Watered** — Unified stat panel for all sensors (`dtdurations` unit, "No event in 30d" fallback)
4. **Watering Frequency Heatmap** — Calendar view of patterns by day/hour

**Deployment (one-time):**
```bash
cd grafana-dashboards
./deploy-watering-dashboard.sh
# Dashboard imports automatically, available at https://soil.owenmedeiros.com
```

**Testing:**
```bash
cd tests
./test-watering-detection.sh
# Simulates watering events and verifies detection logic
```

**How It Works:**
1. Flux query compares each moisture reading to previous reading (5 min apart)
2. If `current - previous >= 15%`, marks as watering event
3. Creates 2-hour "watered" status for timeline visualization
4. Calculates time since most recent watering event per sensor

**Troubleshooting:**
- **No watering events detected:** Check if moisture actually increases by 15%+ during watering
- **False positives:** Increase threshold in dashboard query (change `15.0` to `20.0`)
- **Missing data:** Ensure sensor readings are continuous (no gaps >5 minutes)
