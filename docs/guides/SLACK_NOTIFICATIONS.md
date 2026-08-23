# Slack Notifications

Alerting for the soil monitoring system. Three conditions are reported to a
Slack channel via an Incoming Webhook.

| # | Condition | Checked | Alert frequency |
|---|-----------|---------|-----------------|
| 1 | A plant's soil moisture drops below 50% | every 30 min | once per dry-out, reminder every 24h |
| 2 | A sensor stopped logging | every 10 min | max 1 per day |
| 3 | The whole system is down | every 10 min | max 1 per day |

## Setup

One command on the Raspberry Pi:

```bash
cd ~/soil-sensor && git pull && ./rpi-setup/install-slack-notifications.sh
```

It prompts for a Slack webhook URL and an InfluxDB read token, verifies both,
sends a test message, and enables the systemd timers.

To create the webhook: <https://api.slack.com/apps> → your app → **Incoming
Webhooks** → *Add New Webhook to Workspace* → pick the channel.

## How each alert behaves

### 1. Soil moisture below 50%

`rpi-setup/scripts/check-soil-moisture.sh`

Edge-triggered with hysteresis, so a dry plant does not generate an alert
every 30 minutes:

* Crossing below 50% alerts **once**.
* While it stays dry, it is re-alerted at most once every 24h (`--reminder-hours`).
* Once it climbs back above **55%** (threshold + `--hysteresis`) the plant is
  re-armed, so the next dry-out alerts immediately.

Readings older than 30 minutes are ignored — a silent sensor is a health
problem, reported by alert #2, not a dry plant.

Multiple dry plants are combined into a single message.

**Per-plant thresholds.** A plant that likes it wetter can override the global
value in `sensors-config.json`:

```json
{ "id": "sensor-4", "plant": "Micro Greens", "thresholds": { "alert": 60 } }
```

The global default is set by `--threshold` in
`rpi-setup/systemd/soil-moisture-check.service`.

### 2. A sensor stopped logging

`rpi-setup/scripts/check-sensor-health.sh`

A sensor is "down" after 15 minutes of silence (`--alert-minutes`). Both soil
sensors and the DHT22 climate sensors (`sensor-8`, `sensor-9`) are checked.

The rate-limit topic is derived from the **set** of offline sensors. This means
a persistent failure is reported once a day, but a *new* sensor failing raises a
fresh alert immediately instead of being masked by the earlier one:

| Run | Offline | Result |
|-----|---------|--------|
| 1 | sensor-3, sensor-8 | alert sent |
| 2 | sensor-3, sensor-8 | suppressed (same set, within 24h) |
| 3 | sensor-3, sensor-5, sensor-8 | **alert sent** (set changed) |
| 4 | none | "Sensors Recovered" notice |

### 3. The whole system is down

Also `check-sensor-health.sh`. Raised as a **critical** alert when any of:

* InfluxDB fails its health check or is not listening
* The read token is rejected (query returns non-200)
* InfluxDB is fine but **every** sensor has gone silent — typically a WiFi,
  router, or power outage

When this fires, the per-sensor list is suppressed: the shared cause is what
matters. All these causes share one topic, so you get at most one system-down
message per day.

## Important: the Pi cannot report its own death

Alerts 1–3 all run *on the Raspberry Pi*. If the Pi loses power, loses network,
or its SD card fails, nothing is left running to send a Slack message. The
alerts will simply go quiet.

Covering that requires an external watchdog. `check-sensor-health.sh` supports a
dead-man switch: it pings a URL after every successful check, and an outside
service alerts you when the pings stop.

1. Create a free check at <https://healthchecks.io> with a period of 20 minutes
   and a grace time of 10 minutes, and connect it to Slack.
2. Add its ping URL to `/mnt/sensor-data/config/soil-alerts.env`:
   ```
   HEARTBEAT_URL=https://hc-ping.com/your-uuid-here
   ```
3. `sudo systemctl restart sensor-health-check.timer`

## Operating

```bash
# Timer status
systemctl list-timers 'soil-*' 'sensor-*'

# Live logs
journalctl -u soil-moisture-check -u sensor-health-check -f

# Preview alerts without sending anything
cd ~/soil-sensor && set -a && . /mnt/sensor-data/config/soil-alerts.env && set +a
./rpi-setup/scripts/check-soil-moisture.sh --dry-run
./rpi-setup/scripts/check-sensor-health.sh --dry-run

# Force an alert through the rate limit (for testing)
./scripts/send-slack-alert.sh --severity info --message "test" --no-rate-limit
```

### Tuning

Edit the `ExecStart` line in the relevant unit, then
`sudo systemctl daemon-reload`:

| Want | Change |
|------|--------|
| Different moisture threshold | `--threshold 45` in `soil-moisture-check.service` |
| Alert sooner on a dead sensor | `--alert-minutes 30` in `sensor-health-check.service` |
| More/less frequent down alerts | `--rate-limit-seconds 43200` (12h) |
| No "recovered" messages | add `--no-recovery-notice` |
| Check moisture more often | `OnUnitActiveSec=` in `soil-moisture-check.timer` |

## Exit codes

Both check scripts use the same convention:

| Code | Meaning |
|------|---------|
| 0 | Healthy |
| 1 | Plants dry / sensors offline (alert sent) |
| 2 | InfluxDB error — system down (alert sent) |
| 3 | Configuration error (no token, missing config) |

The systemd units declare `SuccessExitStatus=0 1 2`, so a real alert does not
show up as a failed unit.

## Files

| Path | Purpose |
|------|---------|
| `scripts/send-slack-alert.sh` | Webhook sender: severity, rate limiting, retries |
| `rpi-setup/scripts/lib/influx-lib.sh` | Shared InfluxDB query + CSV parsing |
| `rpi-setup/scripts/check-soil-moisture.sh` | Alert #1 |
| `rpi-setup/scripts/check-sensor-health.sh` | Alerts #2 and #3 |
| `rpi-setup/install-slack-notifications.sh` | One-time setup |
| `rpi-setup/systemd/soil-moisture-check.{service,timer}` | 30-min moisture timer |
| `rpi-setup/systemd/sensor-health-check.{service,timer}` | 10-min health timer |

### Secrets and state (never in git)

| Path | Mode | Contents |
|------|------|----------|
| `/mnt/sensor-data/config/slack_webhook_url` | 600 | Slack webhook URL |
| `/mnt/sensor-data/config/soil-alerts.env` | 600 | `INFLUX_TOKEN`, URLs, `HEARTBEAT_URL` |
| `/mnt/sensor-data/monitor-state/` | — | Per-plant dry state, offline sensor set |
| `/mnt/sensor-data/slack-rate-limit/` | — | Rate-limit markers, one file per topic |

State lives on `/mnt/sensor-data` rather than `/tmp` deliberately: a reboot must
not reset a 24-hour suppression window, or a boot loop would produce an alert
storm.

## Troubleshooting

**No messages arriving.** Check the webhook is valid:
```bash
./scripts/send-slack-alert.sh --message "test" --no-rate-limit --verbose
```
Exit 1 = config error, 2 = rate limited, 3 = delivery failed after 3 retries.

**Alerts stopped after one message.** Expected for a persistent condition —
that is the daily rate limit. Confirm with:
```bash
ls -l /mnt/sensor-data/slack-rate-limit/
```
Delete a marker file to re-arm that topic immediately.

**"Sensor Not Logging" for a sensor that is fine.** The sensor may be posting
under a different `device_id` than the one in `sensors-config.json`. Compare:
```bash
./rpi-setup/scripts/check-sensor-health.sh --verbose
```

**Rate-limit markers never expire.** A marker is only rewritten on a successful
send, so a failed delivery does not silently consume the window. Old topic files
are harmless but can be cleared with
`find /mnt/sensor-data/slack-rate-limit -mtime +30 -delete`.
