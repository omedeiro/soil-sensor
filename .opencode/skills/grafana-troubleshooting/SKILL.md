---
name: grafana-troubleshooting
description: Diagnose and fix Grafana problems for the soil sensor project — dashboard unreachable, "No Data" / "Connection Refused" panels, wrong datasource UID, Cloudflare Tunnel down, service restarts, and automated panel-health monitoring. Use when soil.owenmedeiros.com is down, panels show no data, cloudflared is failing, or setting up/debugging the panel-health monitor and Slack alerts. Involves scripts/check-grafana-panels.py, debug-grafana-query.sh, repair-grafana-panels.sh.
---

# Grafana Troubleshooting

Raspberry Pi: `omedeiro@192.168.99.134`. Grafana local `:3000`, public
`https://soil.owenmedeiros.com`. InfluxDB runs in Docker at `172.17.0.2:8086`
(not localhost from Grafana's perspective).

## Grafana Dashboard Unreachable

1. **Check public URL:**
   ```bash
   curl -I https://soil.owenmedeiros.com
   ```
2. **Check Cloudflare Tunnel status:**
   ```bash
   ssh omedeiro@192.168.99.134 "sudo systemctl status cloudflared"
   ssh omedeiro@192.168.99.134 "cloudflared tunnel list"
   ```
3. **Check Grafana service status:**
   ```bash
   ssh omedeiro@192.168.99.134 "systemctl status grafana-server"
   ```
4. **Check if services are running:**
   ```bash
   ssh omedeiro@192.168.99.134 "systemctl is-active grafana-server influxdb cloudflared"
   ```
5. **Restart services if down:**
   ```bash
   ssh omedeiro@192.168.99.134 "sudo systemctl restart grafana-server"
   ssh omedeiro@192.168.99.134 "sudo systemctl restart cloudflared"
   ```
6. **Check for USB mount issues:**
   ```bash
   ssh omedeiro@192.168.99.134 "df -h | grep sensor-data"
   ssh omedeiro@192.168.99.134 "journalctl -u mnt-sensor\\x2ddata.mount --no-pager"
   ```
7. **Verify data is still being collected** (ESP8266 writes to InfluxDB even if Grafana is down):
   ```bash
   curl http://192.168.99.70/api/latest          # ESP8266 status
   curl http://192.168.99.134:8086/health         # InfluxDB health
   ```
8. **Check system logs for boot/failure reasons:**
   ```bash
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/startup_history.log"
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/grafana_failures.log"
   ssh omedeiro@192.168.99.134 "cat /mnt/sensor-data/logs/reboot_reasons.log"
   ssh omedeiro@192.168.99.134 "tail -f /mnt/sensor-data/logs/health-monitor.log"
   ssh omedeiro@192.168.99.134 "sudo journalctl -u cloudflared -f"
   ```

**Common Grafana failure causes:**
- **Improper shutdown:** Filesystem corruption from power loss or hard reboot
- **USB drive unmounting:** `/mnt/sensor-data` not mounted at boot
- **Systemd restart loop:** Grafana exits cleanly (exit 0) so systemd won't auto-restart
- **Data directory corruption:** Grafana database files in `/mnt/sensor-data/grafana/data`

**Recovery steps after improper shutdown:**
1. `ssh omedeiro@192.168.99.134 "tail -50 /mnt/sensor-data/logs/startup_history.log"`
2. `ssh omedeiro@192.168.99.134 "sudo journalctl -b | grep -E '(fsck|Dirty|corrupt)'"`
3. `ssh omedeiro@192.168.99.134 "mount | grep sensor-data"`
4. `ssh omedeiro@192.168.99.134 "sudo journalctl -u grafana-server --no-pager"`
5. `sudo systemctl restart grafana-server` if needed

**Enhanced Logging System:**
- See `/rpi-setup/LOGGING_README.md` for complete logging documentation
- Startup logger tracks all boot events and reasons; health monitor auto-restarts failed services; log rotation prevents disk space issues
- Install: `cd ~/rpi-setup && sudo ./install-logging.sh`

## Grafana Datasource Configuration (CRITICAL)

If panels show "No Data" or "Connection Refused", verify the datasource.

1. **Check which datasource UID panels use:**
   ```bash
   ssh omedeiro@192.168.99.134 'curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/<dashboard-uid>" | jq "[.dashboard.panels[].datasource.uid] | unique"'
   ```
2. **Test datasource health:**
   ```bash
   ssh omedeiro@192.168.99.134 'curl -s -u admin:admin -X POST "http://localhost:3000/api/datasources/uid/<datasource-uid>/health"'
   ```
3. **Common datasource issues:**
   - **`PB4A2C00F7BB2A2DA` (InfluxDB-SoilMonitoring):** points to `http://localhost:8086` → "connection refused" because InfluxDB runs on Docker IP `172.17.0.2:8086`
   - **`cflk0i2e2nwu8d` (influxdb):** correct datasource pointing to `http://172.17.0.2:8086` (working)
4. **Fix panels using wrong datasource:**
   ```bash
   ssh omedeiro@192.168.99.134 'curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/<uid>" | jq ".dashboard" > /tmp/dashboard.json'
   ssh omedeiro@192.168.99.134 'cat /tmp/dashboard.json | jq "(.panels[] | select(.datasource.uid == \"PB4A2C00F7BB2A2DA\") | .datasource.uid) = \"cflk0i2e2nwu8d\"" > /tmp/dashboard-fixed.json'
   ssh omedeiro@192.168.99.134 'curl -s -u admin:admin -X POST -H "Content-Type: application/json" -d "{\"dashboard\": $(cat /tmp/dashboard-fixed.json), \"overwrite\": true}" http://localhost:3000/api/dashboards/db'
   ```
5. **Affected dashboards (fixed in v2.9.1):** Raspberry Pi Health, System Health, Mobile Quick View, Alerts & Notifications (all panels)

**Why the panel health checker may miss datasource issues:**
- `scripts/check-grafana-panels.py` queries InfluxDB **directly** at `192.168.99.134:8086`, NOT through Grafana's configured datasources
- Panels may show "healthy" in the checker but fail in the browser if the datasource is misconfigured
- Always verify dashboard panels in the browser after a health-check pass

## Troubleshooting "No Data" Panels (v2.9.0)

Automated panel health monitoring with Slack alerts.

**Quick Diagnosis:**
```bash
cd ~/soil-sensor
./scripts/check-grafana-panels.py
# Exit codes: 0 healthy | 1 "No Data" | 2 query errors | 3 datasource connection errors (critical)
```

**Automated Monitoring (one-time setup):**
```bash
cd ~/soil-sensor/rpi-setup
./install-panel-health-monitor.sh
# Installs: panel health checker, query debugger, repair script, systemd timer (5 min), Slack alerts
```

Configure Slack webhook (secure — never commit to git):
```bash
( umask 077; printf '%s' 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  > /mnt/sensor-data/config/slack_webhook_url )
chmod 600 /mnt/sensor-data/config/slack_webhook_url
```

Configure service secrets (InfluxDB token + Grafana creds), loaded by the systemd
unit via `EnvironmentFile=/mnt/sensor-data/config/panel-health.env`:
```bash
( umask 077; cat > /mnt/sensor-data/config/panel-health.env <<'EOF'
INFLUX_TOKEN=YOUR_INFLUX_TOKEN
INFLUX_URL=http://localhost:8086
INFLUX_ORG=soil-monitoring
INFLUX_BUCKET=sensor-readings
GRAFANA_URL=http://localhost:3000
GRAFANA_USER=admin
GRAFANA_PASSWORD=admin
EOF
)
chmod 600 /mnt/sensor-data/config/panel-health.env
```

View status:
```bash
systemctl status grafana-panel-health.timer
journalctl -u grafana-panel-health -f
```

### Secret storage rules (CRITICAL)
- Slack webhook lives ONLY in `/mnt/sensor-data/config/slack_webhook_url` (chmod 600). Never hardcode in scripts or commit to git.
- Service secrets live ONLY in `/mnt/sensor-data/config/panel-health.env` (chmod 600), loaded via `EnvironmentFile=`. The committed `grafana-panel-health.service` contains NO secrets.
- `.gitignore` blocks `*.env`, `*.token`, `*secret*`, `*webhook*`, `slack_webhook_url`, and `panel-health.env`.
- **Rotating the Slack webhook:** revoke old one in Slack, then `( umask 077; printf '%s' '<new-url>' > /mnt/sensor-data/config/slack_webhook_url ); chmod 600` — no redeploy needed (scripts read the file at runtime).

### Common Issues and Quick Fixes

1. **InfluxDB Connection Errors:**
   ```bash
   curl http://192.168.99.134:8086/health
   grep INFLUX_TOKEN /etc/systemd/system/grafana-panel-health.service
   ```
2. **"No Data" Panels:**
   ```bash
   cd ~/soil-sensor/rpi-setup/scripts
   ./check-sensor-health.sh --verbose
   cd ~/soil-sensor/scripts
   ./debug-grafana-query.sh --dashboard soil-moisture-main-v2 --panel 3
   ```
3. **Query Syntax Errors:**
   ```bash
   cd ~/soil-sensor/scripts
   ./repair-grafana-panels.sh --auto-repair --dry-run --verbose
   ./repair-grafana-panels.sh --auto-repair --notify
   ```

### Manual Investigation
```bash
./scripts/check-grafana-panels.py --format json > /tmp/panel-report.json
jq -r '.dashboards[] | .title as $dash | .panels[] | select(.status == "no_data") | "[\($dash)] \(.title)"' /tmp/panel-report.json
tail -50 /mnt/sensor-data/logs/grafana-panel-issues.log
```

### Diagnostic Commands
- `check-grafana-panels.py` — Check all panel health across all dashboards
- `check-sensor-health.sh --notify` — Check sensor connectivity and data quality
- `debug-grafana-query.sh --dashboard UID --panel ID` — Extract and test a specific panel query
- `repair-grafana-panels.sh --notify` — Detect issues and send Slack alerts
- `send-slack-alert.sh --severity info --title "..." --message "..."` — Send test notification

**Complete guide:** `docs/guides/TROUBLESHOOTING_NO_DATA.md`
