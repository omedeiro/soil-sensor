# Troubleshooting "No Data" Panels in Grafana

**Version:** 2.9.0  
**Last Updated:** June 13, 2026

This guide provides step-by-step troubleshooting for Grafana panels showing "No Data" or query errors.

---

## Quick Diagnosis

Run the automated panel health checker to identify all issues:

```bash
# On Raspberry Pi
cd ~/soil-sensor
./scripts/check-grafana-panels.py
```

**Exit codes:**
- `0` - All panels healthy
- `1` - One or more panels have "No Data"
- `2` - Query errors detected
- `3` - Datasource connection errors (critical)

---

## Catching It Before It Ships

Most "No Data" panels are not a data problem — the query could never have
matched anything. That is visible in the dashboard JSON alone, so it is checked
in CI on every push, with no Pi and no InfluxDB involved:

```bash
# Anywhere, no network needed
./scripts/check-no-data-panels.py
./scripts/check-no-data-panels.py --format json    # machine-readable
```

It compares every query in `grafana-dashboards/` against `influx-schema.json`
(the measurements, tags, and fields the firmware and Pi collectors actually
write) and `sensors-config.json`, and fails on:

| Rule | What it catches |
|------|-----------------|
| `datasource` | a datasource UID that is not the configured InfluxDB one |
| `no_query` | a panel with no query at all |
| `bucket` | reading a bucket that does not exist |
| `measurement` | filtering on a measurement nothing writes |
| `field` | filtering on a `_field` nothing writes — including a name that is really a **tag** (`event_type`, `location`, `device_id`, `hostname`) |
| `tag` | filtering on a tag/column that does not exist |
| `device_id` | a `device_id` that is not in `sensors-config.json` |
| `missing_range` | a `from()` with no `range()` (Flux rejects it) |
| `unbalanced` | unbalanced quotes or brackets |
| `variable` | a `${variable}` the dashboard never defines |

**The two rules that matter most.** `_field == "event_type"` looks right but
`event_type` is a tag on `sensor_diagnostics`, so the filter matches zero rows —
group by the tag instead and filter `_field` on a real field such as
`event_count`. And a field name that drifted from its producer (`memory_percent`
when `system-metrics-collector.sh` writes `ram_percent`) fails the same way.

If the checker is wrong — the data is written by something outside this repo —
add the measurement/field to `influx-schema.json`, or add an entry with a reason
to `tests/no-data-allowlist.json`.

The live checker below is still the one that finds panels that are *correctly*
configured but genuinely have no data (sensor offline, time range too narrow).

---

## Common Issues and Solutions

### 1. InfluxDB Connection Errors

**Symptoms:**
- Panels show "Datasource Error"
- Red 🔴 status in health check
- Error: "Connection refused" or "Unauthorized"

**Diagnosis:**
```bash
# Test InfluxDB health
curl http://192.168.99.134:8086/health

# Test with token
export INFLUX_TOKEN="your_token"
curl -H "Authorization: Token $INFLUX_TOKEN" \
  "http://192.168.99.134:8086/api/v2/buckets?org=soil-monitoring"
```

**Solutions:**

**A. InfluxDB not running:**
```bash
# Check status
ps aux | grep influx

# If not running, check logs
journalctl -u influxdb --no-pager | tail -50

# Restart (if running in Docker)
docker ps | grep influx
docker restart <container_id>
```

**B. Invalid token:**
```bash
# Generate new token in InfluxDB UI
# http://192.168.99.134:8086
# Settings → API Tokens → Generate Token

# Update systemd service
sudo nano /etc/systemd/system/grafana-panel-health.service
# Change INFLUX_TOKEN=... line

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart grafana-panel-health.timer
```

**C. Wrong bucket/org name:**
```bash
# List available buckets
influx bucket list --org soil-monitoring

# Update Grafana datasource if needed
# http://192.168.99.134:3000/datasources
```

---

### 2. "No Data" Panels

**Symptoms:**
- Panels show "No Data"
- Yellow ✗ status in health check
- Query executes successfully but returns 0 results

**Diagnosis:**
```bash
# Check if sensors are sending data
./rpi-setup/scripts/check-sensor-health.sh --verbose

# Debug specific panel query
./scripts/debug-grafana-query.sh \
  --dashboard soil-moisture-main-v2 \
  --panel 101
```

**Solutions:**

**A. Time range too narrow:**
```bash
# Symptom: Panel works with "Last 7 days" but not "Last 24 hours"
# Cause: Sensors not posting data recently

# Check sensor connectivity
for i in {1..7}; do
  ip=$(jq -r ".sensors[$((i-1))].ip" sensors-config.json)
  echo "Sensor $i: $(curl -s http://$ip/api/latest | jq -r '.moisture')%"
done

# If sensors offline, check ESP8266 logs via serial
pio device monitor
```

**Fix in Grafana:**
1. Open dashboard in edit mode
2. Select affected panel → Edit
3. Change time range to `-7d` or `-30d`
4. Save dashboard

**B. Device ID mismatch:**
```bash
# List device IDs in InfluxDB
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
    |> range(start: -7d)
    |> keep(columns: ["device_id"])
    |> distinct(column: "device_id")'

# Compare with sensors-config.json
jq -r '.sensors[].id' sensors-config.json
```

**Fix:** Update panel query to use correct device_id, or update sensors-config.json

**C. Measurement/field name typo:**
```bash
# List available measurements
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
    |> range(start: -1d)
    |> group()
    |> distinct(column: "_measurement")'

# List available fields
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
    |> range(start: -1d)
    |> group()
    |> distinct(column: "_field")'
```

**Expected values:**
- Measurement: `sensor_reading`
- Fields: `moisture`, `raw_adc`, `uptime`, `crashes`, `rssi`, `free_heap`

---

### 3. Query Syntax Errors

**Symptoms:**
- Panels show "Query Error"
- Red ⚠ status in health check
- Error message in panel (e.g., "field not found", "syntax error")

**Diagnosis:**
```bash
# Extract and test query
./scripts/debug-grafana-query.sh \
  --dashboard sensor-explorer-v1 \
  --panel 5
```

**Solutions:**

**A. Flux syntax error:**
```bash
# Common mistakes:
# - Missing |> pipe operator
# - Unmatched quotes or parentheses
# - Invalid function names

# Test query manually
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'YOUR_QUERY_HERE'
```

**B. Aggregation errors:**
```bash
# Error: "yield called on different group keys"
# Fix: Add |> group() before yield

# Error: "invalid use of function: mean"
# Fix: Use inside aggregateWindow()
```

---

## Automated Repair

Run automated repair to fix common issues:

```bash
# Dry run (shows what would be fixed)
./scripts/repair-grafana-panels.sh --auto-repair --dry-run --verbose

# Apply fixes
./scripts/repair-grafana-panels.sh --auto-repair --notify
```

**What auto-repair does:**
- Tests InfluxDB connection
- Suggests time range adjustments
- Provides query fix recommendations
- Logs all actions to `/mnt/sensor-data/logs/grafana-panel-issues.log`
- Sends Slack alert with details

---

## Manual Investigation Workflow

### Step 1: Identify Affected Panels

```bash
cd ~/soil-sensor

# Generate full health report
./scripts/check-grafana-panels.py --format json > /tmp/panel-report.json

# View summary
jq -r '.summary' /tmp/panel-report.json

# List all "No Data" panels
jq -r '.dashboards[] | .title as $dash | .panels[] | select(.status == "no_data") | "[\($dash)] \(.title)"' /tmp/panel-report.json
```

### Step 2: Test InfluxDB Connectivity

```bash
# Test health endpoint
curl http://192.168.99.134:8086/health

# Expected: {"status":"pass","version":"v2.7.12",...}
```

### Step 3: Verify Data Exists

```bash
# Check recent sensor data
export INFLUX_TOKEN="your_token"

curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
    |> range(start: -1h)
    |> filter(fn: (r) => r._measurement == "sensor_reading")
    |> filter(fn: (r) => r._field == "moisture")
    |> group(columns: ["device_id"])
    |> last()'
```

**Expected:** CSV output with 7 rows (one per sensor)

### Step 4: Debug Specific Panel Query

```bash
# Extract panel query
DASHBOARD_UID="soil-moisture-main-v2"
PANEL_ID="3"

./scripts/debug-grafana-query.sh \
  --dashboard "$DASHBOARD_UID" \
  --panel "$PANEL_ID"
```

**Output includes:**
- Full Flux query
- HTTP status code
- Query execution time
- Number of results
- Sample data (first 5 rows)
- Suggested fixes for common issues

### Step 5: Check Sensor Connectivity

```bash
# Run sensor health check
./rpi-setup/scripts/check-sensor-health.sh --check-quality --verbose

# Expected output:
# - All 7 sensors online
# - Data in last 5 minutes
# - 12 readings per sensor in last hour
# - No stuck sensors (stddev > 0.5)
```

### Step 6: Review Logs

```bash
# Panel health monitor logs
tail -50 /mnt/sensor-data/logs/grafana-panel-issues.log

# Systemd service logs
journalctl -u grafana-panel-health -n 50 --no-pager

# InfluxDB logs (if in Docker)
docker logs influxdb --tail 50
```

---

## Preventive Monitoring

### Enable Automated Monitoring

```bash
# Install (if not already installed)
cd ~/soil-sensor/rpi-setup
./install-panel-health-monitor.sh

# Check timer status
systemctl status grafana-panel-health.timer

# View next scheduled run
systemctl list-timers grafana-panel-health.timer
```

### Configure Slack Notifications

```bash
# Set webhook URL securely (umask 077 prevents any world-readable window).
# NEVER commit this URL — it lives only on the Pi.
( umask 077; printf '%s' 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  > /mnt/sensor-data/config/slack_webhook_url )
chmod 600 /mnt/sensor-data/config/slack_webhook_url

# Test notification
~/soil-sensor/scripts/send-slack-alert.sh \
  --severity info \
  --title "Test Alert" \
  --message "Grafana panel monitoring is working"
```

> **Rotating a leaked webhook:** revoke it in Slack first, then overwrite
> `/mnt/sensor-data/config/slack_webhook_url` with the new URL (same command
> above). Scripts read the file at runtime, so no service restart is required.
> Service secrets (InfluxDB token, Grafana creds) live in
> `/mnt/sensor-data/config/panel-health.env` (chmod 600) and are loaded by the
> systemd unit via `EnvironmentFile=` — they are not stored in git.

### Monitor via Systemd

```bash
# View recent runs
journalctl -u grafana-panel-health --since "1 hour ago" --no-pager

# Enable real-time monitoring
journalctl -u grafana-panel-health -f
```

---

## Diagnostic Command Reference

### Health Check Commands

| Command | Purpose | Exit Codes |
|---------|---------|------------|
| `check-grafana-panels.py` | Check all panel health | 0=healthy, 1=no_data, 2=error, 3=critical |
| `check-sensor-health.sh --notify` | Check sensor connectivity | 0=healthy, 1=offline, 2=db_error |
| `debug-grafana-query.sh --dashboard UID --panel ID` | Debug specific panel | 0=success, 1=no_data, 2=query_error |
| `repair-grafana-panels.sh --notify` | Detect and alert issues | 0=healthy, 1=issues_detected, 2=repaired |

### InfluxDB Query Commands

```bash
# List all buckets
influx bucket list --org soil-monitoring

# List measurements in bucket
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'import "influxdata/influxdb/schema"
    schema.measurements(bucket: "sensor-readings")'

# Count data points per sensor
curl -XPOST "http://192.168.99.134:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token $INFLUX_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
    |> range(start: -24h)
    |> filter(fn: (r) => r._measurement == "sensor_reading")
    |> group(columns: ["device_id"])
    |> count()'
```

### Grafana API Commands

```bash
# List all dashboards
curl -u admin:admin http://192.168.99.134:3000/api/search?type=dash-db

# Get dashboard JSON
curl -u admin:admin \
  http://192.168.99.134:3000/api/dashboards/uid/soil-moisture-main-v2

# Test datasource
curl -u admin:admin -X POST \
  http://192.168.99.134:3000/api/datasources/cflk0i2e2nwu8d/health
```

---

## Escalation Path

If issue persists after trying all solutions:

1. **Collect diagnostic bundle:**
   ```bash
   cd ~/soil-sensor
   ./scripts/check-grafana-panels.py --format json > panel-report.json
   ./rpi-setup/scripts/check-sensor-health.sh --verbose > sensor-health.txt 2>&1
   journalctl -u grafana-panel-health -n 100 > systemd-logs.txt
   
   tar -czf diagnostic-$(date +%Y%m%d-%H%M%S).tar.gz \
     panel-report.json \
     sensor-health.txt \
     systemd-logs.txt \
     /mnt/sensor-data/logs/grafana-panel-issues.log
   ```

2. **Check GitHub issues:** https://github.com/omedeiro/soil-sensor/issues

3. **Create new issue** with diagnostic bundle attached

---

## Appendix: Panel Health Monitoring System

### Architecture

```
┌─────────────────────────────────────────────┐
│  systemd Timer (every 5 minutes)            │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  repair-grafana-panels.sh                   │
│  ├─ Calls check-grafana-panels.py           │
│  ├─ Analyzes results                        │
│  ├─ Logs issues                             │
│  └─ Sends Slack notification                │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  check-grafana-panels.py                    │
│  ├─ Enumerates dashboards (Grafana API)     │
│  ├─ Extracts Flux queries from panels       │
│  ├─ Tests queries (InfluxDB API)            │
│  └─ Generates JSON report                   │
└─────────────────────────────────────────────┘
```

### File Locations

| File | Location | Purpose |
|------|----------|---------|
| `check-grafana-panels.py` | `/home/omedeiro/soil-sensor/scripts/` | Main health checker |
| `repair-grafana-panels.sh` | `/home/omedeiro/soil-sensor/scripts/` | Repair orchestrator |
| `debug-grafana-query.sh` | `/home/omedeiro/soil-sensor/scripts/` | Query debugger |
| `send-slack-alert.sh` | `/home/omedeiro/soil-sensor/scripts/` | Slack integration |
| `slack_webhook_url` | `/mnt/sensor-data/config/` | Slack webhook (secure) |
| `grafana-panel-issues.log` | `/mnt/sensor-data/logs/` | Issue history |
| `grafana-panel-health.service` | `/etc/systemd/system/` | Systemd service |
| `grafana-panel-health.timer` | `/etc/systemd/system/` | Systemd timer |

---

**Document Version:** 2.9.0  
**Last Updated:** June 13, 2026  
**Maintainer:** Owen Medeiros
