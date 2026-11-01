# Agent Instructions — Soil Sensor Project

## Specialized Skills

Detailed, task-specific workflows live in `.claude/skills/<name>/SKILL.md`
(the canonical home); `.opencode/skills/<name>` are relative symlinks to the
same directories so opencode sees one set. They load automatically when a task
matches. Load the matching skill before doing the work rather than guessing.

| Skill | Use it for |
| ----- | ---------- |
| **`soil-sensor-firmware`** | Building/flashing ESP8266 (`pio run`, upload, `pio device monitor`), editing `config.h`, device type (soil/climate/DHT22), calibration, WiFi provisioning, serial monitor messages, multi-sensor setup, hardware constraints |
| **`grafana-dashboard-config`** | Editing `sensors-config.json`, validate→generate→upload dashboards, adding a sensor, changing plant names/colors/thresholds, watering-history dashboard |
| **`grafana-troubleshooting`** | Grafana unreachable, Cloudflare Tunnel, "No Data"/datasource UID fixes, panel-health monitor, Slack alerts, secret storage |
| **`sensor-offline-troubleshooting`** | ESP8266 stopped posting, power-cycle recovery, sensor health monitoring, InfluxDB last-reading queries |
| **`rpi-server-ops`** | Raspberry Pi install, InfluxDB/Grafana setup, tokens/buckets, `test_influx_write.sh`, end-to-end testing, legacy Flask/SQLite server |
| **`pi-access`** | SSH to the Pi (`omedeiro@192.168.99.134`), what is *actually* running there (InfluxDB in Docker, user-level timers), where secrets live, sudo/docker constraints, InfluxDB token rotation over HTTP |
| **`run-soil-sensor`** | `driver.py smoke` / `alerts` / `dashboard` / `firmware` — mock InfluxDB + Slack to exercise the real alerting scripts, diff regenerated dashboards, compile firmware; `live` is a read-only Pi probe and is deny-listed for agents |

## Standard PR Workflow

`main` is protected — never push to it directly. Full details in
`docs/guides/BRANCH_PROTECTION.md`. Summary:

1. `git checkout -b feature/<name>` (or `fix/`, `docs/`, `hotfix/`)
2. Make changes; for dashboards: edit `sensors-config.json` → `./scripts/validate-config.py` → `./scripts/generate-dashboard.py` → deploy
3. Optional version bump: `./scripts/bump-version.sh <major|minor|patch> [firmware|system|docs]`
4. `./scripts/run-ci-checks.sh` — runs exactly what CI runs, minus the firmware build
5. `git push -u origin <branch>` then `gh pr create` with summary/changes/testing checklist
6. Merge with `gh pr merge --squash` after review (Owen does this; `.claude/settings.json` denies it for agents)

## CI (`.github/workflows/ci.yml`)

Six jobs run on every push and PR; none of them need the Pi.

| Job | Checks |
| --- | ------ |
| **Dashboards** | `validate-config.py`; all tracked JSON parses; `soil-moisture-main.json` and `sensor-explorer.json` still match `generate-dashboard.py` output; `check-no-data-panels.py`; `tests/test-no-data-checker.sh` |
| **Shell & Python** | `bash -n` on every `.sh`, `shellcheck --severity=error`, `py_compile` on every `.py` |
| **Secret scan** | `scripts/check-secrets.sh` — tokens, webhooks, inline systemd secrets, private keys |
| **Firmware build** | `pio run -e esp8266` against `secrets.h.example` |
| **Agent env** | `scripts/check_agent_env.py` — `.claude/settings.json` deny rules, skill frontmatter, `.opencode/skills` symlinks, AGENTS.md size and paths |
| **Smoke** | `driver.py smoke` — regenerates the dashboard and runs both monitoring scripts through every fault scenario against a mock InfluxDB/Slack |

`scripts/check-no-data-panels.py` is the static counterpart to the Pi's live
panel-health monitor: it compares every dashboard query against
`influx-schema.json` (measurements/tags/fields as actually written by the
firmware and the Pi collectors) and `sensors-config.json`. A query filtering on
a field nothing writes — or on a *tag* via `_field ==` — fails the build.
Run everything locally with `./scripts/run-ci-checks.sh`.

## Architecture

- **ESP8266 firmware** (PlatformIO/Arduino) — reads sensor, POSTs to InfluxDB every 5 min
- **InfluxDB** (Raspberry Pi 5) — time-series database for sensor readings
- **Grafana** (Raspberry Pi 5) — dashboards, alerts, visualization
- **Raspberry Pi 5** — dedicated server, 256GB USB storage, automated backups
- Legacy Flask/SQLite server: `database/` (deprecated; see `rpi-server-ops` skill)

**Working directories:**
- Firmware: `/firmware`
- Raspberry Pi setup: `/rpi-setup`
- Database (legacy): `/database`
- Documentation: `/docs`
- Tests: `/tests`
- Dashboard scripts: `/scripts`
- Grafana dashboards: `/grafana-dashboards`

## Common Mistakes to Avoid

1. **Wrong InfluxDB port:** InfluxDB is on 8086, not 5001 (5001 was legacy SQLite server)
2. **Wrong HTTP status code:** InfluxDB returns 204 (not 201) on successful write
3. **IP mismatch:** `DB_SERVER_URL` in `config.h` must match Raspberry Pi IP (192.168.99.134)
4. **Missing/invalid token:** `INFLUX_TOKEN` must be set in `config.h` after InfluxDB setup
5. **Token permissions:** ESP8266 token needs **write** permission, Grafana token needs **read** permission
6. **Sensor voltage:** Must power sensor from 3.3V pin, not 5V (ADC max is 1.0V)
7. **Flashing without serial check:** Always run `pio device monitor` after upload to verify WiFi/DB connection
8. **Duplicate device IDs:** Each sensor must have unique `DEVICE_ID` in multi-sensor setup
9. **WiFi diagnostics disabled:** Set `ENABLE_WIFI_DIAGNOSTICS = true` in config.h for detailed logging
10. **Queue disabled:** Set `QUEUE_FAILED_READINGS = true` in config.h to survive network outages
11. **Editing auto-generated dashboards:** Never hand-edit `grafana-dashboards/soil-moisture-main.json` or `grafana-dashboards/sensor-explorer.json` — regenerate both from `sensors-config.json`
12. **Committing secrets:** Slack webhook / InfluxDB tokens live only on the Pi under `/mnt/sensor-data/config/` (chmod 600), never in git. Systemd units must read them via `EnvironmentFile=`, never `Environment="INFLUX_TOKEN=..."`
13. **Alert state in /tmp:** rate-limit and alert-state files belong on `/mnt/sensor-data` — a reboot must not reset a 24h suppression window
14. **Querying a field nothing writes:** a dashboard query filtering on an unknown `_field` (or on a *tag* such as `event_type` via `_field ==`) renders "No Data" forever. `influx-schema.json` is the contract; `./scripts/check-no-data-panels.py` enforces it in CI. When firmware starts writing a new field, add it to `influx-schema.json` in the same commit

## System Information

**Raspberry Pi 5 Server:**
- Username: `omedeiro`
- IP Address: `192.168.99.134`
- InfluxDB: `http://192.168.99.134:8086`
- Grafana (local): `http://192.168.99.134:3000`
- Grafana (public): `https://soil.owenmedeiros.com`
- Data Storage: `/mnt/sensor-data` (256GB USB drive)
- Cloudflare Tunnel: `soil-sensor-grafana` (ID: ec9b412a-098a-45d2-8060-f2fa7b23b477)

**ESP8266 sensors:** 9 boards (7 soil, 2 DHT22 climate), DHCP, OTA-updatable, 5-minute reading interval.
Current sensor IPs/MACs: `docs/SENSOR_INVENTORY.md` (DHCP leases drift; `sensors-config.json` is the source of truth for names/rooms/thresholds)

## Status Files Reference

**Documentation:**
- `docs/README.md` — Technical documentation (WiFi stability, Grafana Cloud setup, InfluxDB notes)
- `docs/guides/TROUBLESHOOTING_NO_DATA.md` — Panel health troubleshooting guide (v2.9.0)
- `influx-schema.json` — InfluxDB measurements/tags/fields as written by the firmware and Pi collectors (checked in CI)
- `.github/workflows/ci.yml` — CI: dashboards, shell/python, secret scan, firmware build, agent env, smoke
- `docs/guides/SLACK_NOTIFICATIONS.md` — Slack alerting: low moisture, sensor down, system down
- `grafana-dashboards/README.md` — Dashboard installation, customization, and alert setup
- `README.md` — Project overview and setup instructions
- `AGENTS.md` — This file (agent instructions index + core reference)
- `docs/SENSOR_INVENTORY.md` — Sensor IPs/MACs/RSSI snapshot (drifts; see System Information)
- `.claude/skills/` — Task-specific skill workflows (see Specialized Skills above); `.opencode/skills/` symlinks to them
- `.claude/settings.json` — Agent permissions: pre-approved local checks, deny list for `driver.py live`, firmware upload, `ssh … sudo`, pushes to `main`, PR merges
