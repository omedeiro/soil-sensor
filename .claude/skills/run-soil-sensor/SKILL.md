---
name: run-soil-sensor
description: Run, launch, drive, or smoke-test the soil-sensor system on a dev machine — mock InfluxDB + Slack webhook to exercise check-soil-moisture.sh / check-sensor-health.sh / send-slack-alert.sh, regenerate and diff the Grafana dashboard, compile the ESP8266 firmware, and probe the live Pi read-only. Use when asked to run the app, test an alerting or dashboard change for real, or verify something works outside the unit tests.
---

# Running the soil-sensor system

There is no single app to launch. The product is ESP8266 firmware → InfluxDB →
Grafana on a Raspberry Pi (`192.168.99.134`). On a dev machine the two layers
that PRs actually touch are runnable:

- **the monitoring/alerting layer** — `rpi-setup/scripts/*.sh` + `scripts/send-slack-alert.sh`
- **the dashboard generator** — `sensors-config.json` → `grafana-dashboards/soil-moisture-main.json`

Everything is driven through **`.claude/skills/run-soil-sensor/driver.py`**. It
stands up a mock InfluxDB 2.x and a mock Slack webhook on one loopback port and
runs the **real production scripts** against them, so you can see actual Slack
payloads and actual exit codes without a Pi, Docker, or a webhook.

All paths below are relative to the repo root. Python 3 stdlib only — no
install step, no venv, no network (except `live`).

## Run (agent path)

```bash
python3 .claude/skills/run-soil-sensor/driver.py smoke
```

That is the one-command check: regenerates the dashboard, diffs its panels
against the committed JSON, then runs both monitoring scripts through eight
fault scenarios and asserts each one's exit code. ~25s. Ends with a pass/fail
table.

### Drive one scenario and read the Slack payload

```bash
python3 .claude/skills/run-soil-sensor/driver.py alerts --scenario dry --clean-state
```

Prints the script's own output, then the JSON Slack actually received, decoded:

```
  ┌ SLACK :warning: Soil Moisture Low
  │ 2 plants need water:
  │   • Micro Greens (sensor-4) — 28.4% (threshold 50%)
  │   • Parsley (sensor-7) — 41.9% (threshold 50%)
  └ color=#ff9900
```

Scenarios (`--scenario`), each with the exit codes it must produce:

| scenario | what the mock reports | moisture / health exit |
|---|---|---|
| `healthy` | all sensors fresh, all wet | 0 / 0 |
| `dry` | sensor-4 at 28.4%, sensor-7 at 41.9% | 1 / 0 |
| `recovered` | those two back above threshold+hysteresis | 0 / 0 |
| `stale` | sensor-3 silent 3h, sensor-9 silent 40m | 0 / 1 |
| `all-down` | every sensor silent 5h | 0 / 2 |
| `no-data` | bucket empty | 0 / 2 |
| `auth-fail` | query returns 401 | 2 / 2 |
| `influx-down` | `/health` and query both 503 | 2 / 2 |
| `stuck` | sensor-2 stddev 0.02 → `--check-quality` flags it | 0 / 0 |

Useful flags: `--check moisture|health|both`, `--dry-run` (script prints the
payload instead of POSTing), `--no-notify`, `--clean-state` (wipe the state and
rate-limit dirs first). Anything after a `--` separator is forwarded verbatim
to the check script — the separator is required, argparse rejects the flag
otherwise:

```bash
python3 .claude/skills/run-soil-sensor/driver.py alerts --scenario dry --clean-state --check moisture -- --threshold 80
```

### Exercise the alert state machine

The alerting is edge-triggered with hysteresis, so **omit `--clean-state` to
carry state between runs** — that is the only way to see the interesting paths:

```bash
python3 .claude/skills/run-soil-sensor/driver.py alerts --scenario dry --clean-state --check moisture
python3 .claude/skills/run-soil-sensor/driver.py alerts --scenario dry --check moisture
python3 .claude/skills/run-soil-sensor/driver.py alerts --scenario recovered --check moisture
```

Run 1 alerts (`newly dry`), run 2 stays silent (`already alerted 0h ago`), run 3
sends the recovery notice and re-arms.

### Poke the mock by hand

```bash
python3 -u .claude/skills/run-soil-sensor/driver.py stack --scenario dry
```

Blocks and prints the `export` lines to paste into another shell, plus
`curl <base>/health` and `curl <base>/slack/captured | jq .`. Ctrl-C to stop.
The `-u` matters — see Gotchas.

### Dashboard changes

```bash
python3 .claude/skills/run-soil-sensor/driver.py dashboard
```

Runs `validate-config.py` then `generate-dashboard.py`, prints the full panel
inventory, and diffs it against the committed dashboard. **It restores the
committed JSON afterwards** — pass `--write` to keep the regenerated file when
you actually mean to commit it.

### Firmware compile check

```bash
python3 .claude/skills/run-soil-sensor/driver.py firmware
```

`pio run -e esp8266` in `firmware/`. ~80s warm. Ends with the RAM/Flash figures
(currently RAM 47.6%, Flash 36.0%). `--env esp8266-ota` for the OTA env. This
only compiles — flashing needs real hardware.

### Live system (read-only)

```bash
python3 .claude/skills/run-soil-sensor/driver.py live
```

Probes `soil.owenmedeiros.com`, and Grafana + InfluxDB on the Pi. Never writes
and never deploys. Deploying is a separate, deliberate act —
`scripts/upload-dashboard-to-pi.sh`.

The system's only GUI is Grafana, and it cannot be run locally (no Docker,
Grafana, or InfluxDB on this Mac). To *look* at a dashboard, open
`https://soil.owenmedeiros.com` — anonymous read-only — in a browser. The
driver's `dashboard` command is the local substitute: it tells you which panels
a config change adds, removes, or renames without rendering them.

## Run (human path)

Only relevant on the Pi itself, where the scripts read `INFLUX_TOKEN` from
`/mnt/sensor-data/config/` via systemd `EnvironmentFile=` and are fired by
`soil-moisture-check.timer` / `sensor-health-check.timer`. There is nothing to
run interactively on a laptop other than the driver above.

## Gotchas

- **`generate-dashboard.py` writes into the repo.** It has no `--output`; it
  always overwrites `grafana-dashboards/soil-moisture-main.json`. The driver
  snapshots and restores it so a read-only inspection leaves `git status`
  clean. If you invoke the script directly, expect a dirty tree.
- **It reads `scripts/sensors-config.json`, which is a symlink** to the root
  `sensors-config.json`. Copying `scripts/` elsewhere to generate in a sandbox
  breaks that link — edit the root config and let the driver restore.
- **`stack` needs `python3 -u` when its output is piped.** Only the banner is
  flushed; without `-u` a reader blocks waiting for the rest.
- **`live` uses `curl`, not `urllib`, on purpose.** The python.org Python 3.11
  on this Mac has no CA bundle, so `urllib` fails
  `https://soil.owenmedeiros.com` with `CERTIFICATE_VERIFY_FAILED` while the
  host is perfectly healthy. curl uses the system trust store.
- **`all-down` leaves the moisture check at exit 0, deliberately.** Readings
  older than `--max-age-minutes` are invisible to `check-soil-moisture.sh` — a
  silent sensor is a health problem, not a dry plant, and only
  `check-sensor-health.sh` reports it. Do not "fix" that as a bug.
- **`--dry-run` posts nothing**, so the mock Slack sink captures nothing. Use
  it to inspect the payload the script prints; drop it to see what Slack
  received and to let state files be written.
- **Rate limiting is per topic and persists on disk.** `check-sensor-health.sh`
  defaults to one alert per condition per 24h. A second run inside the window
  exits 0 from `send-slack-alert.sh`'s perspective but reports `Suppressed`.
  `--clean-state` resets it.
- **Driver state lives in `.claude/skills/run-soil-sensor/.work/`** (gitignored),
  standing in for `/mnt/sensor-data/` on the Pi.
- **The mock is a subset**, not InfluxDB: `/health`, `/api/v2/write` (204), and
  `/api/v2/query` answering the specific Flux shapes this repo emits. A new
  query shape needs a branch in `Handler._answer`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ERROR: INFLUX_TOKEN not set` when running a script by hand | You skipped the driver's env. Use `driver.py stack` and paste its `export` lines. |
| `unknown scenario '...'` | `--scenario` typo; the driver lists the valid ones in the error. |
| Alert expected but nothing captured | Either `--dry-run` is on, or the rate-limit window is still open — add `--clean-state`. |
| `pio not on PATH` | `pip install platformio` (it lives in the python.org 3.11 framework bin dir here). |
| `dashboard` reports `CHANGED` unexpectedly | The committed JSON drifted from `sensors-config.json`. Regenerate with `--write` and commit, never hand-edit the generated file. |
| `live` shows the Pi down | Check the Pi is up before assuming a code problem; `soil.owenmedeiros.com` failing while the Pi answers means the Cloudflare Tunnel, not Grafana. |
