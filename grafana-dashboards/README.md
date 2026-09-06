# Grafana Dashboards Guide

8 production-ready dashboards for the Soil Moisture Monitoring System (v2.11.2).

All dashboards feature:
- **High-contrast color scheme** per sensor (7 distinct colors for easy identification)
- **Moisture gradients** — Dark to bright within each color family (0% → 100%)
- **Dynamic labels** — "Sensor 1 (Bed Room, Rubber Tree)" format with plant types (v2.6.0)
- **Location filtering** — 'backyard' location filtered out
- **Time-adaptive titles** — Adapt to selected time window (no hardcoded "24h")
- **Auto-refresh** — 5-minute refresh, 10-second provisioning reload
- **Raspberry Pi uptime** — System uptime displayed on main dashboard (v2.3.0)
- **7-sensor support** — Supports up to 7 sensors with unique colors (v2.4.0)

---

## Dashboard Suite

### 1. 🌱 Soil Moisture Main (`soil-moisture-main.json`)
**Tags:** `overview`, `sensors`

**Purpose:** Main overview dashboard — one full-width moisture trace per plant, with no dropdown to set first.

**No template variables.** The Sensor dropdown and every panel that filtered on
it now live on [Sensor Explorer](#2--sensor-explorer-sensor-explorerjson).

**Key Panels:**
- **System status** — Percentage of configured sensors reporting
- **Raspberry Pi Uptime** — Server uptime in top status bar (v2.3.0)
- **Last updated** — Relative time since most recent reading
- **Per-plant moisture traces** (7) — One full-width single-trace time series per plant, in `sensors-config.json` order, each in that plant's color
- **Ambient Temperature & Humidity** — DHT22 climate sensor stat panels (°F / %) plus trend plots (v2.10.0)

**Use case:** Daily monitoring, quick health check, reading an individual plant's moisture curve without deselecting the others.

**Generated file** — produced by `scripts/generate-dashboard.py` from `sensors-config.json`. Never hand-edit it; CI fails on drift.

---

### 2. 🔍 Sensor Explorer (`sensor-explorer.json`)
**Tags:** `overview`, `sensors`, `explorer`

**Purpose:** The Sensor dropdown and the panels that filter on it, split out of the main dashboard.

**Key Panels:**
- **Sensor dropdown** — Custom variable listing every plant by name, plus "All" (`.*`)
- **Plant heading** — Colored banner showing the current selection
- **Current Moisture Levels** — Bar gauge, one bar per selected sensor with per-plant thresholds
- **Moisture Trends** — Overlaid moisture time series for the selection
- **Raw ADC Values** — Overlaid raw ADC time series for the selection

**Use case:** Comparing plants against each other, or isolating one plant across moisture and raw ADC at once.

**Generated file** — produced by `scripts/generate-dashboard.py` from `sensors-config.json`. Never hand-edit it; CI fails on drift.

---

### 3. 🔍 Sensor Details (`sensor-details.json`)
**Tags:** `sensors`, `diagnostics`

**Purpose:** Individual sensor deep-dive with uptime, heap, WiFi signal, and diagnostics.

**Key Panels:**
- **Sensor dropdown** — Select individual sensor for detailed view
- **Moisture gauge** — Current moisture with sensor-specific color gradient
- **WiFi RSSI gauge** — Signal strength (-30 dBm excellent → -90 dBm poor)
- **Free heap gauge** — ESP8266 available RAM (healthy: >30KB)
- **Uptime stat** — Seconds since last boot
- **Moisture history** — Time series for selected sensor
- **WiFi signal history** — RSSI over time
- **Free heap history** — Memory usage over time

**Use case:** Troubleshooting individual sensors, calibration, stability monitoring.

---

### 4. ⚙️ System Health (`system-health.json`)
**Tags:** `diagnostics`, `system`

**Purpose:** ESP8266 diagnostic events, WiFi stability, crash detection, critical events.

**Key Panels:**
- **Critical events count** — Total critical events (crashes, WiFi failures, queue overflow)
- **Critical vs Info events** — Categorized event breakdown
- **Event frequency plot** — Diagnostic events over time
- **Diagnostic logs table** — Event details with reason, heap, RSSI
- **WiFi disconnect events** — Count and timeline
- **InfluxDB error events** — Database connection issues

**Event types tracked:**
- **Critical:** `crash_detected`, `wifi_reconnect_failed`, `queue_overflow`, `heap_low_warning`, `influxdb_error`, `system_restart`
- **Info:** `boot_complete`, `wifi_disconnect`, `wifi_reconnect_success`

**Use case:** Diagnosing WiFi stability issues, crash investigation, system reliability monitoring.

---

### 5. 🚨 Alerts Overview (`alerts-overview.json`)
**Tags:** `alerts`, `monitoring`

**Purpose:** Critical alerts, watering needed notifications, sensor offline detection.

**Key Panels:**
- **Critical alerts stat** — Count of active critical alerts
- **Sensors needing water** — List of sensors below moisture threshold
- **Alert frequency plot** — Alert events over time
- **Sensor status summary table** — Per-sensor health overview

**Use case:** Quick alert dashboard, identify plants needing water, monitor alert trends.

---

### 6. 📱 Mobile Summary (`mobile-summary.json`)
**Tags:** `mobile`, `overview`

**Purpose:** Mobile-optimized quick view with essential metrics.

**Key Panels:**
- **4 moisture gauges** — Current moisture for all sensors (vertical layout)
- **System health score** — Overall health percentage
- **Last updated** — Time since most recent reading
- **Active alerts** — Count of critical alerts

**Use case:** Mobile phone viewing, quick status check on-the-go.

---

### 7. 🖥️ Raspberry Pi Health (`rpi-health.json`)
**Tags:** `system`, `server`

**Purpose:** Raspberry Pi system metrics — CPU, RAM, disk, temperature monitoring.

**Key Panels:**
- **CPU usage gauge** — Current CPU % (healthy: <80%)
- **CPU temperature gauge** — Current CPU temp °C (healthy: <70°C)
- **RAM usage gauge** — Current RAM % (healthy: <80%)
- **Disk usage gauge** — Current disk % (healthy: <90%)
- **System uptime** — Raspberry Pi OS uptime
- **CPU history plot** — CPU usage over time
- **Temperature history plot** — CPU temp over time
- **RAM history plot** — Memory usage over time
- **Disk history plot** — Disk usage over time
- **Load averages** — 1-min, 5-min, 15-min load averages

**Data source:** `rpi_system_metrics` measurement (Python collector, 60s interval)

**Use case:** Pi performance monitoring, detecting resource issues, thermal monitoring.

---

### 8. 🚰 Watering History (`watering-history.json`) — v2.7.0, enhanced v2.11.0
**Tags:** `watering`, `monitoring`

**Purpose:** Automatic detection and visualization of watering events, dry conditions, sensor noise, and offline periods.

**Key Panels:**
- **Watering Events Timeline** — 5-state timeline (Normal/Dry/Watering/Noise/Offline) per sensor, using color-coded state bands. Enhanced in v2.11.0 with offline detection, noise filtering, and dry alerts.
- **Moisture Trend with Watering Markers** — Time series plot with dual-threshold markers (fast watering ≥15% in red, slow watering ≥8% in orange).
- **Time Since Last Watered** — 7 stat panels showing hours/days since each sensor was watered (color-coded: green <2 days, yellow 2-5 days, orange 5-7 days, red >7 days)
- **Watering Frequency Heatmap** — Calendar-style view showing watering patterns by day-of-week and hour

**Detection Algorithm (v2.11.0):**
- **Fast watering:** ≥15% moisture increase in a single 5-minute interval (red markers)
- **Slow watering:** ≥8% increase (drip irrigation, orange markers)
- **Noise detection:** ≤-8% rapid drop (probe disturbance or sensor jitter, orange state)
- **Dry detection:** Moisture <20% (red state)
- **Offline detection:** Gap >15 minutes between consecutive readings (gray state)
- **State priority:** Offline(4) > Noise(3) > Watering(2) > Dry(1) > Normal(0); resolved by `aggregateWindow(fn: max)`
- **Lookback Period:** 30 days for "last watered" stats, 7 days default view for timeline

**How it works:**
1. Reads raw moisture data and checks for gaps >15 min (offline detection)
2. Applies `interpolate.linear()` for continuous data, then `difference()` for point-to-point changes
3. Classifies each reading into one of 5 states based on difference and moisture level
4. Merges all states via `union()` with 30-minute aggregation windows
5. Tracks most recent watering event per sensor for "time since" calculations

**Use case:** Track watering history, identify watering patterns, ensure plants are watered regularly, detect forgotten plants, monitor sensor connectivity and noise.

**Example insights:**
- "Basil typically gets watered Sunday mornings"
- "Monstera hasn't been watered in 5 days"
- "3 plants were watered yesterday evening"
- "Ficus Elastica was offline for 2 hours last night"

---

## Installation

### Method 1: Automated (Dashboard Provisioning) — Recommended

**On Raspberry Pi:**
```bash
# Copy dashboards to provisioning directory
sudo cp /path/to/soil-sensor/grafana-dashboards/*.json \
  /mnt/sensor-data/grafana/dashboards/

# Dashboards auto-import within 10 seconds
# No Grafana restart needed
```

**To deploy the new Watering History dashboard:**
```bash
# From your local machine
scp grafana-dashboards/watering-history.json \
  omedeiro@192.168.99.134:/tmp/

# On Raspberry Pi
ssh omedeiro@192.168.99.134
sudo cp /tmp/watering-history.json \
  /mnt/sensor-data/grafana/dashboards/
sudo chown grafana:grafana \
  /mnt/sensor-data/grafana/dashboards/watering-history.json

# Import via API
cat /mnt/sensor-data/grafana/dashboards/watering-history.json | python3 -c "
import sys, json
dashboard = json.load(sys.stdin)
wrapper = {
  'dashboard': dashboard,
  'overwrite': True
}
print(json.dumps(wrapper))
" | curl -X POST -u admin:admin \
  -H 'Content-Type: application/json' \
  -d @- \
  http://localhost:3000/api/dashboards/db

# Dashboard available at: https://soil.owenmedeiros.com
```

**Provisioning is not in use.** `rpi-setup/docker-compose.yml` deliberately does not mount
`grafana-provisioning/` — its `datasources/influxdb.yml` recreates the dead read-only
datasource and steals default status from the working one. Grafana keeps dashboards in its
own database; `/mnt/sensor-data/grafana/dashboards/` holds stale reference copies only.

---

### Method 2: Manual Import (via Grafana UI)

1. Open Grafana at `http://<pi-ip>:3000`
2. Navigate to **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select dashboard from `grafana-dashboards/` directory
5. Confirm datasource (should auto-detect `InfluxDB`)
6. Click **Import**

Repeat for all 7 dashboards.

---

### Method 3: API Import/Update

Dashboards live at the root level; there is no folder to preserve. Each is addressed by its
`uid`, so its URL (`/d/<uid>/<slug>`) is stable regardless of where it appears in the UI.

```bash
# Import a single dashboard
cat grafana-dashboards/soil-moisture-main.json | python3 -c "
import sys, json
dashboard = json.load(sys.stdin)
wrapper = {
  'dashboard': dashboard,
  'overwrite': True
}
print(json.dumps(wrapper))
" | curl -X POST -u admin:admin \
  -H 'Content-Type: application/json' \
  -d @- \
  http://<pi-ip>:3000/api/dashboards/db

# Import all dashboards
for dashboard in grafana-dashboards/*.json; do
  cat "$dashboard" | python3 -c "
import sys, json
dashboard = json.load(sys.stdin)
print(json.dumps({'dashboard': dashboard, 'overwrite': True}))
" | curl -X POST -u admin:admin \
    -H 'Content-Type: application/json' \
    -d @- \
    http://<pi-ip>:3000/api/dashboards/db
  echo "Imported: $(basename $dashboard)"
done
```

**Important:** When updating dashboards via API, Grafana stores them in its **database**, not as JSON files. This means:
1. Changes to JSON files in `grafana-dashboards/` won't auto-update in Grafana
2. You must re-import via API whenever JSON files are updated
3. Dashboard changes in Grafana UI won't update the JSON files (export needed)

---

## Deployment Workflow

### Current System Configuration

The production Grafana instance stores dashboards in its **SQLite database**, not as provisioned JSON files.

**This means:**
- Dashboard JSON files in `/mnt/sensor-data/grafana/dashboards/` are **reference copies only**
- Changes to these JSON files won't automatically appear in Grafana
- Dashboards must be updated via Grafana API or UI

### Updating Dashboards in Production

**Step 1: Update local JSON files**
```bash
# Edit dashboard JSON in grafana-dashboards/
cd /path/to/soil-sensor/grafana-dashboards
# ... make changes to *.json files ...
git commit -m "fix: update dashboard labels"
```

**Step 2: Copy to Raspberry Pi**
```bash
scp grafana-dashboards/soil-moisture-main.json \
  user@raspberrypi:/tmp/soil-moisture-main.json
```

**Step 3: Update reference copy**
```bash
ssh user@raspberrypi
sudo cp /tmp/soil-moisture-main.json \
  /mnt/sensor-data/grafana/dashboards/soil-moisture-main.json
sudo chown grafana:grafana \
  /mnt/sensor-data/grafana/dashboards/soil-moisture-main.json
```

**Step 4: Import to Grafana via API**

```bash
cat /mnt/sensor-data/grafana/dashboards/soil-moisture-main.json | python3 -c "
import sys, json
dashboard = json.load(sys.stdin)
wrapper = {
  'dashboard': dashboard,
  'overwrite': True
}
print(json.dumps(wrapper))
" | curl -X POST -u admin:admin \
  -H 'Content-Type: application/json' \
  -d @- \
  http://localhost:3000/api/dashboards/db
```

**Step 5: Verify in browser**
- Open https://soil.owenmedeiros.com
- Hard refresh (Ctrl+Shift+R / Cmd+Shift+R)
- Check that changes appear

### Setting Default Home Dashboard

```bash
# Set org-wide home dashboard
curl -X PUT -u 'admin:admin' \
  'http://localhost:3000/api/org/preferences' \
  -H 'Content-Type: application/json' \
  -d '{"homeDashboardUID": "soil-moisture-main-v2"}'
```

### Migrating to Provisioning (Future)

To enable auto-updates from JSON files:

1. **Create provisioning config:**
```bash
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo cat > /etc/grafana/provisioning/dashboards/soil-sensors.yaml <<EOF
apiVersion: 1
providers:
  - name: 'Soil Sensors'
    folder: ''
    type: file
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /mnt/sensor-data/grafana/dashboards
EOF
```

2. **Restart Grafana:**
```bash
sudo systemctl restart grafana-server
```

3. **Future updates:**
```bash
# Just copy files - Grafana auto-imports
sudo cp new-dashboard.json /mnt/sensor-data/grafana/dashboards/
# Grafana reloads within 10 seconds
```

---

## Dashboard Tags

Each dashboard has 2 functional tags for easy filtering (Sensor Explorer adds a third):

| Dashboard | Tag 1 | Tag 2 | Description |
|-----------|-------|-------|-------------|
| Soil Moisture Main | overview | sensors | One moisture trace per plant, no dropdown |
| Sensor Explorer | overview | sensors | Sensor dropdown and the panels that filter on it (also tagged `explorer`) |
| Sensor Details | sensors | diagnostics | Individual sensor deep-dive |
| System Health | diagnostics | system | ESP8266 diagnostics and events |
| Alerts Overview | alerts | monitoring | Critical alerts and notifications |
| Mobile Summary | mobile | overview | Mobile-optimized quick view |
| Raspberry Pi Health | system | server | Raspberry Pi system metrics |
| Watering History | watering | monitoring | Watering event detection and history |

**Tag categories:**
- **overview** — High-level summaries
- **sensors** — Soil moisture and sensor data
- **diagnostics** — Technical health metrics
- **alerts** — Notifications and warnings
- **monitoring** — Continuous tracking
- **system** — System-level metrics
- **server** — Raspberry Pi infrastructure
- **mobile** — Mobile-optimized views
- **watering** — Watering event tracking and history
- **explorer** — Dropdown-driven views you filter yourself

---

## Color Scheme

### Sensor Colors (High-Contrast, 7-Sensor Support)
- **Sensor-1:** Green (#73BF69)
- **Sensor-2:** Yellow (#F2CC0C)
- **Sensor-3:** Blue (#5794F2)
- **Sensor-4:** Red (#FF6B6B)
- **Sensor-5:** Purple (#B877D9) - *Added in v2.4.0*
- **Sensor-6:** Orange (#FF9830) - *Added in v2.4.0*
- **Sensor-7:** Cyan (#5DDBDB) - *Added in v2.4.0*

### Moisture Gauge Gradients
Each sensor has a dark→bright gradient (0% dry → 100% wet) within its color family:

| Sensor | 0% (Dry) | 33% | 67% | 100% (Wet) |
|--------|----------|-----|-----|------------|
| Sensor-1 (Green) | #2d5016 | #4a7a2c | #73BF69 | #73BF69 |
| Sensor-2 (Yellow) | #6b5606 | #a3890f | #F2CC0C | #F2CC0C |
| Sensor-3 (Blue) | #1f3f68 | #3669a8 | #5794F2 | #5794F2 |
| Sensor-4 (Red) | #6b2323 | #a83838 | #FF6B6B | #FF6B6B |
| Sensor-5 (Purple) | #4a2b57 | #7d4a9b | #B877D9 | #B877D9 |
| Sensor-6 (Orange) | #663c13 | #b36420 | #FF9830 | #FF9830 |
| Sensor-7 (Cyan) | #255858 | #3f9999 | #5DDBDB | #5DDBDB |

**Rationale:** Each sensor maintains its unique color for easy reference, with brightness indicating moisture level.

---

## Anonymous Access (Public Viewing)

Enable view-only access without login:

```bash
cd /path/to/soil-sensor/rpi-setup/scripts
sudo ./configure-grafana.sh
```

**What it does:**
- Enables anonymous authentication in Grafana
- Sets default role to `Viewer` (read-only)
- Reloads Grafana configuration

**Access:** `http://<pi-ip>:3000` (no login required)

**Security:** Viewer role can only view dashboards, cannot edit or create.

---

## Customization

### Adjusting Moisture Thresholds

**Current thresholds (in gauge panels):**
- **0-33%:** Dark color (dry)
- **33-67%:** Medium color (moderate)
- **67-100%:** Bright color (wet)

**To customize:**
1. Edit dashboard JSON → Find `"thresholds"` in gauge panels
2. Or edit via Grafana UI → Panel → **Thresholds** section
3. Save dashboard

### Per-Plant Thresholds

Different plants need different moisture levels:

| Plant Type | Dry Threshold | Wet Threshold |
|------------|---------------|---------------|
| Succulents | 10-30% | 40-60% |
| Vegetables | 40-60% | 70-90% |
| Tropicals | 50-70% | 80-100% |

**Recommendation:** Clone `sensor-details.json` and customize thresholds per plant type.

---

## Alert Configuration

Set up Grafana alerts for low moisture levels:

1. Open `alerts-overview.json` dashboard
2. Navigate to **Alerting** → **Alert rules** (Grafana 9+)
3. Create new alert rule:
   ```
   Query: from(bucket: "sensor-readings") 
          |> range(start: -30m) 
          |> filter(fn: (r) => r._measurement == "sensor_reading")
          |> filter(fn: (r) => r._field == "moisture")
          |> mean()
   
   Condition: moisture < 20
   Duration: 30 minutes
   ```
4. Configure notification channel:
   - **Slack:** Best for real-time notifications
   - **Email:** Good for daily summaries
   - **Discord/Telegram:** Alternative options

**Recommended alert rules:**
- **Critical low moisture:** < 20% for 30 minutes
- **Sensor offline:** No heartbeat for 10 minutes
- **WiFi instability:** > 5 disconnects in 1 hour
- **Pi high CPU:** > 80% for 10 minutes
- **Pi high temp:** > 70°C for 5 minutes

---

## Testing Dashboards

Automated panel testing script:

```bash
cd /path/to/soil-sensor/tests
export INFLUX_TOKEN="<your-read-token>"
./check-dashboard-panels.sh
```

**What it tests:**
- Queries all panels in all 6 dashboards
- Verifies data returned from InfluxDB
- Detects query errors and schema issues
- Shows actual values for verification

**Expected results:**
- **31 panels with data** — Normal operation
- **8 NO DATA panels** — Healthy empty states (no alerts/events)
- **16 skipped panels** — Grafana variables (can't test via API)
- **2 errors** — Complex joins (known, non-critical)

---

## Troubleshooting

### Dashboard shows "No data"

**Check:**
1. InfluxDB running: `http://<pi-ip>:8086/health`
2. Sensors posting data: `pio device monitor` → `[DB] ✓ Posted to InfluxDB`
3. Time range includes recent data: Set to "Last 1 hour"
4. Datasource configured: Grafana → **Connections** → **Data sources**

**Verify data in InfluxDB:**
```bash
ssh pi@<pi-ip>
curl -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token <read-token>" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings") 
      |> range(start: -1h) 
      |> filter(fn: (r) => r._measurement == "sensor_reading") 
      |> filter(fn: (r) => r._field == "moisture")'
```

---

### Panel shows "NO DATA" (healthy state)

Some panels intentionally show "NO DATA" when everything is healthy:

| Panel | Dashboard | Reason |
|-------|-----------|--------|
| Critical Events | system-health.json | No crashes/errors detected (good!) |
| Sensors Needing Water | alerts-overview.json | All sensors above threshold (good!) |
| Active Alerts | mobile-summary.json | No alerts triggered (good!) |
| WiFi Disconnect Events | system-health.json | No WiFi disconnects (good!) |

**This is normal and indicates healthy operation.**

---

### Sensor doesn't appear in dropdown

The dropdowns live on **Sensor Explorer** and **Sensor Details** — the main
dashboard has no template variables, so a missing plant there means a missing
entry in `sensors-config.json` (regenerate with `./scripts/generate-dashboard.py`).

**Possible causes:**
- Sensor hasn't posted data yet (wait 5 minutes)
- Device ID contains spaces/special chars (use `sensor-1` format)
- 'backyard' location (filtered out by default)

**Verify sensor posting:**
```bash
curl -XPOST "http://<pi-ip>:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token <read-token>" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings") 
      |> range(start: -1h) 
      |> filter(fn: (r) => r._measurement == "sensor_reading") 
      |> group(columns: ["device_id"]) 
      |> distinct(column: "device_id")'
```

---

### Dashboard provisioning not working

**Check provisioning config:**
```bash
ssh pi@<pi-ip>
cat /mnt/sensor-data/grafana/provisioning/dashboards/dashboards.yml
```

**Expected:**
```yaml
apiVersion: 1
providers:
  - name: 'Soil Sensors'
    folder: ''
    type: file
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /mnt/sensor-data/grafana/dashboards
```

**Verify Grafana sees the config:**
```bash
sudo journalctl -u grafana-server -f
# Look for: "Provisioning dashboards from configuration"
```

---

### "Last Updated" shows wrong time

**Issue:** Timezone mismatch between InfluxDB (UTC) and Grafana.

**Solution:**
- InfluxDB stores timestamps in UTC (correct)
- Grafana converts to browser timezone automatically
- "Last Updated" panel uses `dateTimeFromNow` unit (relative time)

**If still wrong:**
1. Check browser timezone settings
2. Verify Grafana timezone: **Configuration** → **Preferences** → **Timezone**
3. Verify InfluxDB timestamps are in UTC (should end with `Z`)

---

## Exporting Dashboards

To save dashboard changes back to JSON:

**Via Grafana UI:**
1. Open dashboard → **Share** → **Export** tab
2. **Save to file** → Overwrite existing JSON in `grafana-dashboards/`
3. Commit to git

**Via API:**
```bash
# Get dashboard UID from URL (/d/<uid>/dashboard-name)
UID="soil-moisture-main"

curl -H "Authorization: Bearer <api-key>" \
  http://<pi-ip>:3000/api/dashboards/uid/$UID \
  | jq '.dashboard' > grafana-dashboards/$UID.json
```

**Important:** If using provisioning with `allowUiUpdates: true`, changes are auto-saved to `/mnt/sensor-data/grafana/dashboards/`. Copy back to git repo.

---

## Best Practices

1. **Use provisioning** — Auto-reload dashboards, easier version control
2. **Enable anonymous access** — Convenient for quick checks, still secure (read-only)
3. **Set up alerts** — Critical low moisture, sensor offline, Pi high temp
4. **Export regularly** — Commit dashboard JSONs to git after changes
5. **Test after updates** — Run `check-dashboard-panels.sh` after changes
6. **Monitor Pi health** — Check `rpi-health.json` weekly for resource issues
7. **Adjust time ranges** — 24h for daily monitoring, 7d for weekly patterns

---

## Related Documentation

- [Main README](../README.md) — Complete setup and installation guide
- [Technical Documentation](../docs/README.md) — WiFi stability, Grafana Cloud setup, InfluxDB notes
- [AGENTS.md](../AGENTS.md) — Agent instructions and technical reference
- [CHANGELOG.md](../CHANGELOG.md) — Version history and release notes

---

Last updated: 2026-06-21 (v2.11.2 - sensor rename, firmware config refactor)
