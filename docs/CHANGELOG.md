# Changelog

All notable changes to the Soil Moisture Monitoring System are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.14.0] - 2026-08-23

### Added

#### Slack Notifications
- **`rpi-setup/scripts/check-soil-moisture.sh`** — New: alerts when a plant's soil moisture drops below 50%. Edge-triggered with hysteresis so a dry plant is not re-reported every 30 minutes: alerts once on crossing below the threshold, reminds at most once per 24h while still dry, and re-arms only after moisture climbs back above threshold + 5%. Readings older than 30 min are ignored (a silent sensor is a health problem, not a dry plant). Per-plant overrides via `thresholds.alert` in `sensors-config.json`
- **`rpi-setup/scripts/lib/influx-lib.sh`** — New: shared InfluxDB query + annotated-CSV parsing helpers
- **`rpi-setup/install-slack-notifications.sh`** — New: one-time setup. Prompts for the webhook and read token, stores both at mode 600, verifies InfluxDB access, sends a test message, installs and enables both timers
- **`rpi-setup/systemd/soil-moisture-check.{service,timer}`** — New: 30-minute moisture check
- **Whole-system outage detection** — `check-sensor-health.sh` now raises a single critical alert when InfluxDB is unreachable, the read token is rejected, or every sensor has gone silent; the per-sensor list is suppressed in that case since the shared cause is what matters
- **Dead-man switch support** — `--heartbeat-url` / `HEARTBEAT_URL` pings an external watchdog (e.g. healthchecks.io) after each successful check, covering the case the Pi cannot report itself: its own power or network loss
- **`docs/guides/SLACK_NOTIFICATIONS.md`** — New: setup, per-alert behaviour, tuning, and troubleshooting

### Fixed

#### Alerting Correctness
- **Offline detection was unreliable** — `check-sensor-health.sh` matched InfluxDB CSV with `grep "device_id,<id>"`, which depends on column ordering and never matches InfluxDB's standard output (where `device_id` follows `_value`). Every sensor could be reported offline. Replaced with header-driven, order-independent parsing in `influx-lib.sh`
- **Rate-limit window consumed by failed sends** — `send-slack-alert.sh` stamped its marker *before* attempting delivery, so a Slack outage silently suppressed the alert for the whole window. The marker is now written only after a confirmed 200
- **Rate-limit state lost on reboot** — markers moved from `/tmp` to `/mnt/sensor-data/slack-rate-limit`, so a boot loop cannot reset a 24h window and produce an alert storm
- **Malformed JSON payloads** — titles and messages are now JSON-escaped; a quote or backslash in a plant name previously broke the webhook payload
- **`--from-json` path was broken** — used `local` outside a function, which aborts under `set -e`
- **Climate sensors were never health-checked** — `sensor-8` and `sensor-9` (DHT22) are now included in offline detection via `climate_reading`
- **Sensor-ID prefix collisions** — substring matching meant `sensor-1` could match `sensor-10`; matching is now exact

### Changed
- **`rpi-setup/systemd/sensor-health-check.service`** — Now loads secrets from `EnvironmentFile=/mnt/sensor-data/config/soil-alerts.env` instead of a hardcoded `Environment="INFLUX_TOKEN=..."` line, runs from the git checkout rather than a copied `~/rpi-setup/scripts` directory, and declares `SuccessExitStatus=0 1 2` so a real alert is not logged as a unit failure
- **Down-alert rate limiting** — the suppression topic is derived from the *set* of offline sensors, so a persistent failure alerts once a day while an additional sensor failing alerts immediately instead of being masked
- **`scripts/send-slack-alert.sh`** — Added `--rate-limit-seconds` and `--dry-run`; replaced bash 4 associative arrays with `case` so the script runs under bash 3.2 as well

### Security
- **A live InfluxDB token was committed** in `rpi-setup/systemd/sensor-health-check.service` and `rpi-setup/systemd/system-metrics-collector.service` since commit `a136298`, in a public repository. Both units now load secrets from an `EnvironmentFile` under `/mnt/sensor-data/config/` (`soil-alerts.env` and `system-metrics.env` respectively) instead of a hardcoded `Environment="INFLUX_TOKEN=..."` line
- **`rpi-setup/install.sh`** — Stopped telling operators to add `INFLUX_TOKEN` to `/etc/environment`, which systemd units never read; it now points at `/mnt/sensor-data/config/system-metrics.env`
- **The token must be rotated in InfluxDB.** Removing it from the working tree does not remove it from git history, and the same token still appears in `rpi-setup/scripts/system-health-monitor.sh` and `docs/archive/RECOVERY_2026-05-20.md`

---

## [2.13.0] - 2026-08-02

### Fixed

#### Firmware — Power-Cycle Reliability (firmware v2.4.0, PR #20)
- **Static-IP false positive** — With `USE_STATIC_IP true`, `WiFi.localIP().isSet()` read true without a real WiFi association, so a sensor that booted before the router was ready "thought it was connected forever" and never reconnected (root cause of sensor-4/sensor-7 going permanently offline after a power reset). Fleet switched to **DHCP only**; all connectivity checks are now mode-aware via a `WIFI_IS_CONNECTED()` macro (`wifi_stability.h`)
- **Credential persistence** — `WiFi.persistent(false)` + `WiFi.disconnect(true)` could wipe SDK-stored credentials, making runtime `WiFi.reconnect()` a no-op. Now `persistent(true)`/`disconnect(false)`, and reconnects use explicit `WiFi.begin(WIFI_SSID, ...)`
- **Captive-portal dead-end** — With hardcoded credentials the blocking 180s `SoilSensor-Setup` portal is skipped entirely; failed boots hand off to the WiFi stability manager (5s→60s backoff, `ESP.restart()` after 10 failures)
- **`wifiStability.begin()`** now always runs, even when WiFi is down at boot

### Added

#### OTA Deployment (PR #20)
- **`firmware/platformio.ini`** — Split into `esp8266` (USB/esptool) and `esp8266-ota` (espota + auth) environments; OTA flashing no longer requires editing the file: `pio run -e esp8266-ota --target upload --upload-port <sensor-ip>`
- **`firmware/flash-all-ota.sh`** — Uses the `esp8266-ota` env and pins `DEVICE_TYPE_SOIL` per flash
- Entire 9-sensor fleet updated over the air (sensor-7 canary first) and verified healthy in InfluxDB

### Changed

#### Dashboards & Infrastructure
- **Grafana public hostname** renamed `grafana.owenmedeiros.com` → `soil.owenmedeiros.com` (PR #19)
- **System Status panel** — "Sensors Online" now counts only devices defined in `sensors-config.json` (device_id regex filter), uses a 10-minute heartbeat window, and shows the expected total in the display name (PR #20)
- **Sensor-details dashboard** default time range changed to 7d (PR #18)
- **Watering history dashboard** — Time Since Last Watered redesign (PR #17)

### Documentation
- **`AGENTS.md`** — Sensor table updated: adds previously undocumented **sensor-9** (guest-room DHT22 climate sensor, MAC `7c:87:ce:80:4d:36`), documents DHCP-only fleet and OTA update command
- **Skills** — `soil-sensor-firmware` (OTA workflow, v2.4.0 WiFi stability behavior) and `sensor-offline-troubleshooting` (static-IP root cause, MAC-based board identification, OTA reflash recovery) updated

---

## [2.12.3] - 2026-07-25

### Fixed

#### Watering History — Dashboard Cleanup
- **`grafana-dashboards/watering-history.json`** — Three fixes to the watering history dashboard:
  - **Moisture Trend trace labels** — Changed `byName` matchers to `byRegexp` for robustness; removed "Sensor N" prefix so legend shows just plant names ("Rubber Tree", "Monstera", etc.) instead of "Sensor 1 (Rubber Tree)"
  - **Time Since Last Watered** — Replaced 7 individual stat panels (one per sensor) with a single unified "Time Since Last Watered" panel; uses one Flux query for all sensors, `dtdurations` unit for readable output, and `"No event in 30d"` fallback. Panel count reduced from 11 to 5
  - **Watering Frequency heatmap** — Increased `cellGap` from 2 to 4, enabled `calculate: true` for proper data binning, removed `scaleDistribution: linear` that caused thin/misrendered cells

### Changed

#### Sensor Rename
- **`sensors-config.json`** — Renamed sensor-7 plant from "Basil - pot" to "Parsley"
- **`AGENTS.md`** — Updated sensor-7 reference to "Parsley"

---

## [2.12.2] - 2026-07-25

### Added

#### Watering History — Saturated & Not Working States
- **`grafana-dashboards/watering-history.json`** — Added two new states to the Watering Events Timeline (Panel 2) for sensors stuck at 100% moisture:
  - **Saturated (purple `#9C27B0`)** — Detected when sensor reports >= 99.5% moisture continuously for 30+ minutes (via Flux `stateDuration()`)
  - **Not Working (dark red `#B71C1C`)** — Detected when sensor is pinned at >= 99.5% for 24+ hours, indicating a likely hardware fault
- New state priority chain: not-working(6) > saturated(5) > offline(4) > noise(3) > watering(2) > dry(1) > normal(0)
- Value mappings and threshold steps added for states 5 and 6 in the state-timeline panel

---

## [2.12.1] - 2026-07-22

### Added

#### Per-Plant Moisture Panels
- **`scripts/generate-dashboard.py`** — New `create_single_plant_moisture_panel()` generates one single-trace moisture time series per plant, appended below the temperature/humidity block on the main dashboard. Each panel always shows exactly one plant (independent of the sensor dropdown), full width, with the plant's name used as the panel title and series display name for easy differentiation. Panels render in fixed sensor order (sensor-1 → sensor-7) and are config-driven from `sensors-config.json`.

### Changed

#### Agent Instructions
- **`AGENTS.md`** — Refactored into a lean index; detailed task-specific workflows moved into opencode skills under `.opencode/skills/` (`soil-sensor-firmware`, `grafana-dashboard-config`, `grafana-troubleshooting`, `sensor-offline-troubleshooting`, `rpi-server-ops`) that load automatically when a task matches.

### Fixed

#### Dashboard Generator Output Path
- **`scripts/generate-dashboard.py`** — Now writes to the repo-root `grafana-dashboards/soil-moisture-main.json` (the file `upload-dashboard-to-pi.sh` actually deploys) instead of `scripts/grafana-dashboards/`, fixing a mismatch where generated output was not the file being uploaded.

---

## [2.12.0] - 2026-06-28

### Added

#### Static IP Configuration
- **`config.h`** — Added `USE_STATIC_IP`, `STATIC_IP`, `STATIC_GATEWAY`, `STATIC_SUBNET`, `STATIC_DNS1`, `STATIC_DNS2` defines for boards that cannot obtain an address via DHCP (e.g., router MAC filtering, DHCP pool exhaustion)
- **`wifi_manager.cpp`** — Applies `WiFi.config()` with static IP before `WiFi.begin()` when `USE_STATIC_IP` is `true`; bypasses DHCP for reliable deployment on restricted networks

### Changed

#### WiFi Connection Reliability
- **`wifi_manager.cpp`** — Connection detection now uses `WiFi.localIP().isSet()` as fallback alongside `WiFi.status() == WL_CONNECTED` (handles ESP8266 revisions that return non-standard status codes like 7)
- **`wifi_stability.cpp`** — All 6 `WiFi.status()` checks (reconnect loop, `isHealthy()`, `getConnectedTime()`, `getDisconnectedTime()`, `printDiagnostics()` SSID/RSSI blocks) updated to use `WiFi.localIP().isSet()` fallback, preventing infinite reboot loops on affected hardware
- **`main.cpp`** — Serial WiFi status display uses `wifi.isConnected()` instead of raw `WiFi.status()` for consistency

#### Grafana Dashboard
- **Dashboard import script** — `upload-dashboard-to-pi.sh` now uses `jq` for proper JSON payload construction with Grafana folder ID targeting

### Fixed
- **WiFi status inconsistency** — `wifi_stability.cpp` used raw `WiFi.status()` while `wifi_manager.cpp` checked IP assignment; now consistent across all connection checks, eliminating a bug where the stability manager could trigger `ESP.restart()` on hardware with non-standard status codes

---

## [2.11.4] - 2026-06-28

### Changed
- **Sensor dropdown now shows plant names** — Changed Grafana variable from `query` type (raw `device_id` values) to `custom` type with static `text : value` options. Dropdown now displays "Rubber Tree", "Monstera", "Avocado" etc. instead of "sensor-1", "sensor-2". No firmware or InfluxDB changes required.

---

## [2.11.3] - 2026-06-21

### Added
- **Second climate sensor (sensor-9)** — DHT22 ambient temp/humidity installed in guest room with "Guest Room Climate" label in Grafana

### Changed
- **Sensor-8 renamed** — "Ambient Climate" → "Living Room Climate" for location-specific clarity
- **Grafana climate panels updated** — Ambient Temperature and Humidity stat/trend panels now show both climate sensors with distinct labels and colors
- **README.md** — Updated to reflect dual DHT22 climate sensors

---

## [2.11.2] - 2026-06-21

---

## [2.11.1] - 2026-06-21

### Changed

- **Repo reorganization** — Moved top-level scripts to `scripts/`, moved top-level docs to `docs/`, organized `docs/` into `archive/`, `guides/`, and `reference/` subdirectories; moved legacy standalone dashboard to `database/dashboard-24h.html`
- **Path references updated** — Updated `AGENTS.md`, `README.md`, and other docs to reference new file locations

---

## [2.11.0] - 2026-06-21

### Added

#### Watering Event Detection v2 — 5-State Timeline
- **5-state timeline** — Watering Events Timeline (Panel 2) now detects and displays 5 distinct states per sensor: Normal (green), Dry (red, <20% moisture), Watering (blue, ≥8% single-interval increase), Noise (orange, ≤-8% rapid drop), and Offline (gray, >15min reading gap).
- **Dual-threshold watering detection** — Fast watering (≥15%) and slow watering (≥8%, drip irrigation) detected separately in Moisture Trend markers (Panel 3).
- **Offline detection** — `elapsed()` function flags gaps >15 minutes between consecutive readings (3 missed 5-min intervals).
- **Plant name labels** — Timeline series labels now show plant names ("Rubber Tree", "Monstera") matching the main dashboard, using `byRegexp` field overrides.
- **State priority merging** — Uses `union()` with `aggregateWindow(fn: max)` to resolve overlapping states (Offline > Noise > Watering > Dry > Normal).

### Changed

#### Flux Query Infrastructure
- **Group key fixes** — All `group(columns: ["device_id"])` calls changed to `group(columns: ["device_id", "_field"])` to fix Grafana's "column _field needs to be in group key" error in multi-device panels.
- **interpolate.linear() compatibility** — Removed premature `group()` calls before `interpolate.linear()` which requires `_measurement` and `location` in the group key. Fixed in Panels 2, 3B, 3C, and 200.
- **Stat panel group key fix** — Removed bare `group()` (stripped all group keys) from sensor stat queries (Panels 101-107), which broke `interpolate.linear()`.
- **yield support** — Added `yield(name: "states")` to enable InfluxDB API compatibility with multiple variable assignments.

#### Grafana Dashboard Deployment
- **All dashboards in Soil Monitoring folder** — Moved all 7 dashboards from General to the `Soil Monitoring` folder via Grafana API. Provisioning directory at `/mnt/sensor-data/grafana/dashboards/` now manages all dashboards automatically.
- **Watering History dashboard** — Updated to version 8; all 11 panels verified healthy via automated checker.

### Fixed
- **Watering History dashboard** — All 10 data panels now return results (was: 0/10 healthy, all "No Data"). Root causes: `_field` missing from group key, `_measurement`/`location` missing for `interpolate.linear()`, bare `group()` stripping group keys.
- **Panel 2 query** — Redesigned from simple 2-state (watering/normal) to comprehensive 5-state timeline with offline, noise, and dry detection.
- **Panel 3 overlay markers** — Fixed interpolation queries B and C that silently failed due to incorrect group key.
- **Sensor stat panels** — Fixed `group()` stripping that prevented watering event queries from executing.

---

## [2.10.0] - 2026-06-19

### Added

#### Ambient Climate Sensor — DHT22/AM2302 (sensor-8)
- **New device type** — Compile-time `DEVICE_TYPE` switch in `config.h` selects `DEVICE_TYPE_SOIL` (capacitive probe on A0, sensors 1-7) or `DEVICE_TYPE_CLIMATE` (DHT22 on `DHT_PIN`=D2/GPIO4). Only one path compiles in, so the unused sensor adds no runtime cost.
- **DHT22 driver** — New `dht_sensor.{h,cpp}` (`DHTSensor` class) reading ambient temperature (°C and °F) and relative humidity, with NaN-retry handling for intermittent DHT reads.
- **`climate_reading` measurement** — New InfluxDB measurement with float fields `temperature_c`, `temperature_f`, `humidity` plus `uptime`/`rssi`/`free_heap` diagnostics. Tags: `device_id`, `location`. Kept separate from `sensor_reading` so the climate device never pollutes the soil-moisture dropdown or panels.
- **Climate send path** — `DatabaseClient::sendClimateReading()` / `buildClimateLineProtocol()` reuse the existing HTTP/retry logic (success on HTTP 204/200).
- **Offline queue support** — `QueuedReading` extended with climate fields; `drainQueue()` rebuilds the correct line protocol per reading type. Soil queue behavior unchanged.
- **Grafana panels** — Auto-generated **Ambient Temperature** and **Ambient Humidity** stat panels (plain number with °F / % units) plus °F and % time-series trend panels on the main dashboard.
- **Centralized config** — `sensors-config.json` gains a `climate_sensors` array and `grafana.climate_measurement`; `validate-config.py` validates climate sensors (optional, non-breaking); `generate-dashboard.py` renders the four climate panels.
- **sensor-8 deployed** — Living-room DHT22 at `192.168.99.182` (MAC `48:55:19:e6:6c:af`), verified end-to-end (serial → InfluxDB write confirmed).

### Changed
- **Firmware version** — Bumped to `2.3.0` (new DHT22 support).
- **DHT libraries** — Added `adafruit/DHT sensor library` and `adafruit/Adafruit Unified Sensor` to `platformio.ini`.
- **Documentation** — README, AGENTS.md, and dashboard guide updated for the soil/climate `DEVICE_TYPE` split and the new ambient panels.

### Technical Details
- Both firmware build paths (`DEVICE_TYPE_SOIL` and `DEVICE_TYPE_CLIMATE`) verified to compile; the default remains `DEVICE_TYPE_SOIL`, so reflashing the existing 7 soil sensors is unaffected.
- Temperature stored in both °C and °F in InfluxDB; the dashboard displays °F.
- DHT22 wiring: DATA→D2, VCC→3.3V, GND→GND (bare AM2302 needs a 10kΩ pull-up DATA↔VCC).

---

## [2.9.1] - 2026-06-14

### Added

#### Dashboard Visual Enhancements
- **Plant name display panels** — Large colored heading panels on Main Dashboard and Sensor Details showing selected plant name (e.g., "🌱 Rubber Tree" in green)
- **Dynamic color matching** — Panel background color matches sensor color from sensors-config.json configuration
- **Flux-based plant name mapping** — Uses if/else logic to map sensor IDs to plant names without requiring database queries

#### System Metrics Collection
- **Raspberry Pi metrics collector** — Installed system-metrics-collector.sh to capture CPU, RAM, disk, temperature, and uptime every 60 seconds
- **rpi_system_metrics measurement** — Posted to InfluxDB for Grafana visualization
- **systemd user timer** — Runs metrics collection as user service (system-metrics-collector.timer)

#### Documentation
- **Grafana datasource troubleshooting** — Added AGENTS.md section on datasource UID validation, health testing, and repair workflow
- **Panel health checker limitations** — Documented why check-grafana-panels.py may report false positives (queries InfluxDB directly, not through Grafana datasources)

### Changed

#### Dashboard Configuration
- **Main Dashboard template variable** — Changed default from "sensor-1" to "All" (shows all 7 sensors on load)
- **Main Dashboard includeAll** — Set to `true` with `allValue: ".*"` for regex-based filtering
- **Sensor Details template variable** — Removed "All" option, added sensors 5-7, defaults to sensor-1
- **Panel positioning** — Adjusted gridPos of all panels to accommodate plant name heading at top (y=0, h=3)

#### Datasource Migration
- **All dashboards** — Migrated from broken datasource `PB4A2C00F7BB2A2DA` (localhost:8086) to working datasource `cflk0i2e2nwu8d` (172.17.0.2:8086)
- **Grafana dashboard files** — Downloaded and saved fixed versions locally (rpi-health.json, system-health.json, alerts-overview.json, mobile-summary.json)

### Fixed

#### Critical Datasource Issues (v2.9.1)
- **Raspberry Pi Health dashboard** — All 12 panels now showing data (was: all panels "Connection Refused")
- **System Health Dashboard** — 9/11 panels healthy (was: all panels "Connection Refused")
- **Mobile Quick View** — 6/8 panels healthy (was: all panels "Connection Refused")
- **Alerts & Notifications** — 4/9 panels healthy (was: all panels "Connection Refused")

**Root Cause:**
- Dashboards used datasource `PB4A2C00F7BB2A2DA` pointing to `http://localhost:8086`
- InfluxDB runs on Docker IP `172.17.0.2:8086`, not localhost
- Grafana couldn't connect through misconfigured datasource
- Panel health checker reported false positives because it queries InfluxDB directly (not through Grafana datasources)

**Fix:**
- Changed all panels to use datasource `cflk0i2e2nwu8d` (points to correct Docker IP)
- Verified fix in browser (not just health checker)
- Downloaded fixed dashboards to local files

#### Panel Health Monitoring
- **RPI Uptime panel query** — Changed time range from -5m back to -1h (metrics written every 60s, -5m too narrow)
- **System metrics collector** — Installed missing script at ~/soil-sensor/scripts/system-metrics-collector.sh

### Technical Details

#### Affected Components
- **Datasource UID PB4A2C00F7BB2A2DA** — Broken (localhost:8086, connection refused)
- **Datasource UID cflk0i2e2nwu8d** — Working (172.17.0.2:8086, InfluxDB on Docker)
- **Dashboards fixed**: rpi-health-v1, system-health-v2, mobile-summary-v2, alerts-overview-v2
- **Dashboards already correct**: soil-moisture-main-v2, sensor-details-v2, watering-history-v1

#### Files Modified
- `generate-dashboard.py` — Added create_plant_name_panel() function, adjusted panel gridPos
- `grafana-dashboards/soil-moisture-main.json` — Regenerated with plant name panel
- `grafana-dashboards/sensor-details.json` — Added plant name panel, updated template variable
- `grafana-dashboards/rpi-health.json` — Fixed datasource UID
- `grafana-dashboards/system-health.json` — Fixed datasource UID
- `grafana-dashboards/alerts-overview.json` — Fixed datasource UID
- `grafana-dashboards/mobile-summary.json` — Fixed datasource UID
- `AGENTS.md` — Added Grafana datasource troubleshooting section
- `CHANGELOG.md` — This entry

---

## [2.9.0] - 2026-06-13

### Added

#### Grafana Panel Health Monitoring System
- **check-grafana-panels.py** — Python-based panel health checker (tests queries via Grafana API, detects "No Data" and query errors, outputs JSON/human-readable reports)
- **debug-grafana-query.sh** — Query extraction and debugging tool (extracts Flux queries from panels, tests against InfluxDB, provides fix suggestions)
- **repair-grafana-panels.sh** — Automated repair orchestrator (detects issues, logs to file, sends Slack alerts, optional auto-repair mode)
- **send-slack-alert.sh** — Generic Slack webhook integration (rate limiting, retry logic, severity levels: info/warning/error/critical)
- **grafana-panel-health.service/timer** — Systemd automation (runs every 5 minutes, starts 2 minutes after boot)
- **install-panel-health-monitor.sh** — One-command installer for Raspberry Pi (installs all components, configures systemd, sets up logging)

#### Enhanced Sensor Health Validation
- **check-sensor-health.sh enhancements** — Auto-detection from sensors-config.json (no manual sensor IDs), multi-timeframe checks (5min, 1h, 24h), data quality validation (stuck sensor detection via stddev)
- **Data quality metrics** — Standard deviation checks to detect frozen sensors, reading count validation per timeframe

#### Documentation
- **docs/TROUBLESHOOTING_NO_DATA.md** — Comprehensive 495-line troubleshooting runbook (step-by-step fixes for InfluxDB connection errors, "No Data" panels, query syntax errors, manual investigation workflow, diagnostic command reference)
- **AGENTS.md panel monitoring section** — Quick diagnosis commands, automated monitoring setup, common issue fixes, diagnostic command reference

### Changed

#### Monitoring & Alerting
- **Panel health monitoring** — Automated detection and alerting via Slack (5-minute intervals, proactive issue detection before users notice)
- **Sensor health checks** — Now auto-detects sensors from sensors-config.json instead of requiring manual IDs
- **Logging infrastructure** — New log file: `/mnt/sensor-data/logs/grafana-panel-issues.log` (persistent history of all panel issues)

#### Security
- **Slack webhook storage** — Secure file-based storage at `/mnt/sensor-data/config/slack_webhook_url` (chmod 600, not hardcoded in scripts)
- **InfluxDB token** — Embedded in systemd service environment (not exposed in logs or command-line arguments)

### Fixed

#### Monitoring Gaps
- **Silent panel failures** — Now detected automatically every 5 minutes (previously required manual dashboard checks)
- **Query errors** — Proactive detection with suggested fixes (InfluxDB connection errors, syntax errors, time range issues)
- **Sensor offline detection** — Enhanced to check multiple timeframes and data quality (not just last reading)

---

## [2.8.0] - 2026-06-11

### Added

#### System Recovery & Safety Tools
- **flash-ota-canary.sh** — Canary deployment script for safe OTA updates (tests 1 sensor first, monitors health for 10 minutes, then deploys to remaining sensors)
- **validate-config.sh** — Pre-flight firmware configuration validator (prevents DEVICE_ID conflicts, validates WiFi/InfluxDB settings, checks network connectivity)
- **system-metrics-collector.sh** — Bash-based Raspberry Pi metrics collector (CPU, RAM, disk, temperature, uptime posted to InfluxDB every 60 seconds)
- **install-system-metrics.sh** — One-command installer for system metrics collection with systemd timer
- **docker-compose.yml** — Docker Compose configuration for InfluxDB + Grafana with health checks and automatic restart
- **update-grafana-datasources.sh** — Script to migrate Grafana datasources from hardcoded IPs to container names

#### Documentation
- **RESTORATION_REPORT_2026-06-11.md** — Comprehensive system recovery report with timeline, lessons learned, and 13 robustness recommendations
- **SYSTEM_IMPROVEMENT_SUMMARY.md** — Session summary covering recovery process, new tools, workflows, and command reference
- **DOCKER_COMPOSE_MIGRATION.md** — Step-by-step guide for migrating from standalone Docker containers to Docker Compose
- **rpi-setup/FIX_GRAFANA_DATASOURCE.md** — Documentation of Docker container networking fix

#### Grafana Dashboard Enhancements
- **Raspberry Pi Uptime Panel** — Now functional with system metrics data (CPU %, temperature, RAM %, disk %, uptime in seconds)
- **System Health Monitoring** — rpi_system_metrics measurement tracks Raspberry Pi performance every 60 seconds

### Changed

#### Deployment Workflow
- **OTA deployment** — Now uses canary testing instead of simultaneous flashing of all sensors
- **Config validation** — Required before any firmware flash (validates DEVICE_ID_AUTO consistency, InfluxDB token, WiFi credentials)
- **Firmware backups** — Automatic backup creation before OTA deployment

#### Infrastructure
- **Grafana datasources** — Updated to use Docker container IP (172.17.0.2) instead of localhost for inter-container communication
- **System metrics collection** — Switched from Python to bash implementation (no dependencies required)

### Fixed

#### Critical Issues Resolved
- **Grafana "connection refused" error** — Fixed Docker container networking (datasources now use container IP instead of localhost)
- **Raspberry Pi Uptime panel** — Now displays data after installing system metrics collector
- **All 7 sensors recovered** — USB reflashed after bad OTA update on 2026-06-10 bricked all sensors
- **DEVICE_ID_AUTO conflict** — Config validator now prevents conflicting DEVICE_ID settings

#### Recovery from 2026-06-10 OTA Failure
- **Root cause** — Firmware with `DEVICE_ID_AUTO=true` but static `DEVICE_ID="sensor-7"` caused all sensors to fail boot
- **Impact** — All 7 sensors went offline simultaneously, required individual USB recovery
- **Resolution** — Each sensor USB flashed with `DEVICE_ID_AUTO=false` and unique device IDs (sensor-1 through sensor-7)
- **Prevention** — Created validate-config.sh to catch this exact scenario before deployment

### Deprecated

#### Unsafe Practices
- **Simultaneous OTA flashing** — flash-all-ota.sh now deprecated in favor of flash-ota-canary.sh
- **Manual config editing without validation** — All firmware changes should now go through validate-config.sh

### Security

#### Improvements Needed (Documented)
- **Grafana password** — Still using default admin/admin (change recommended)
- **InfluxDB token storage** — Currently in config.h plaintext (environment variable recommended)

---

## [2.7.0] - 2026-06-03

### Added

#### Centralized Sensor Configuration System
- **sensors-config.json** — Master configuration file for all sensor information (plant names, locations, IPs, MACs, colors, thresholds)
- **generate-dashboard.py** — Python script to auto-generate Grafana dashboards from config
- **validate-config.py** — Configuration validator with comprehensive error checking
- **upload-dashboard-to-pi.sh** — One-command dashboard deployment to Grafana
- **QUICK_REFERENCE.md** — Quick reference for common sensor management tasks (includes configuration guide)

#### Dashboard Improvements
- **Dynamic plant name display** — Large heading shows "🌱 [Plant Name]" when specific sensor selected
- **7-day default time window** — Changed from 24h to 7d for better trend visibility
- **Plant-only labels** — Removed room locations from labels (now shows just "Rubber Tree" instead of "Sensor 1 (Bed Room, Rubber Tree)")
- **Enhanced dropdown** — Dropdown shows plant names directly ("Rubber Tree" not "sensor-1")
- **Functional filtering** — Fixed dropdown filter to properly filter all panels when sensor selected

### Changed

#### Configuration Management
- **Dashboard generation** — Now automated via Python script instead of manual JSON editing
- **Single source of truth** — All sensor info centralized in sensors-config.json
- **Validation workflow** — Automatic validation runs before dashboard generation

#### Dashboard Layout
- **Added text panel** — New panel at top shows selected plant name
- **Adjusted panel positions** — All panels moved down to accommodate plant name header
- **Time window** — Default changed from "now-24h" to "now-7d"

### Fixed
- **Dropdown filter not working** — Added proper device_id filter to all panel queries
- **Missing plant identification** — Added dynamic plant name display for single-sensor view
- **Manual configuration pain points** — Eliminated need for manual JSON editing

---

## [2.6.0] - 2026-05-25

### Added

#### Plant Type Information
- **Plant names in dashboards** — Sensor labels now include plant type: "Sensor 1 (Bed Room, Rubber Tree)"
- **Updated sensor mapping** — All 7 sensors documented with plant types in AGENTS.md
- **Enhanced dashboard labels** — soil-moisture-main.json and sensor-details.json include plant information

#### Plant Inventory
- **sensor-1** (bed-room) — Rubber Tree
- **sensor-2** (living-room) — Monstera
- **sensor-3** (living-room) — Avocado (location corrected from guest-room)
- **sensor-4** (guest-room) — Basil - auk
- **sensor-5** (bed-room) — ZZ Plant
- **sensor-6** (living-room) — Ficus Elastica Ruby
- **sensor-7** (guest-room) — Basil - pot

#### Tooling
- **Dashboard update script** — `scripts/update_dashboard_plant_names.py` for automated plant name updates
- **Automated label generation** — Python script updates all sensor dropdowns with plant information

### Changed

#### Grafana Dashboards
- **soil-moisture-main.json** — Updated sensor dropdown with plant names for all 7 sensors
- **sensor-details.json** — Updated sensor variable with plant type labels
- **Dashboard description** — Changed from location-only to "Select sensor to view (with plant types)"

#### Documentation
- **AGENTS.md** — Updated ESP8266 Sensors section with plant types for each sensor
- **sensor-3 location** — Corrected location from guest-room to living-room
- **grafana-dashboards/README.md** — Version updated to 2.6.0 with new label format

### Fixed
- **sensor-3 location** — Corrected from guest-room to living-room in all documentation

---

## [2.5.0] - 2026-05-25

### Changed

#### Documentation
- **Communication guidelines** — Added critical instruction to AGENTS.md prohibiting validating language ("You're absolutely right!" etc.)
- **Professional objectivity** — Reinforced focus on direct, objective technical information without emotional validation

---

## [2.4.0] - 2026-05-25

### Added

#### Multi-Sensor Expansion (7 Sensors)
- **3 new sensors deployed** — sensor-5 (bed-room), sensor-6 (living-room), sensor-7 (guest-room)
- **Extended color palette** — Added purple (#B877D9), orange (#FF9830), cyan (#5DDBDB) for sensors 5-7
- **Enhanced dashboard support** — Updated soil-moisture-main.json with 7-sensor configuration
- **Sensor dropdown labels** — All 7 sensors now show proper labels: "Sensor X (Location)"
- **Radial gauge gradients** — Each new sensor has unique dark→bright color gradient (0% → 100%)
- **Trend plot colors** — All 7 sensors display with distinct, high-contrast colors
- **Clean tooltip labels** — Tooltips show "Sensor 5 (Bed Room)" instead of raw field names

#### Firmware Configuration
- **Sensor-5 configuration** — Device ID: sensor-5, Location: bed-room, IP: 192.168.99.89, MAC: 34:ab:95:16:51:d9
- **Sensor-6 configuration** — Device ID: sensor-6, Location: living-room, IP: 192.168.99.38, MAC: 48:3f:da:62:f9:07
- **Sensor-7 configuration** — Device ID: sensor-7, Location: guest-room, IP: 192.168.99.141, MAC: 84:cc:a8:a7:96:32

#### Documentation
- **Updated AGENTS.md** — Added all 7 sensors to system information with IPs, MACs, hardware details
- **Updated dashboard README** — Expanded color scheme documentation to include sensors 5-7 with gradients
- **Version updates** — Firmware v2.2.0, Dashboard v3, Documentation v2.4.0

### Changed

#### Grafana Dashboard (soil-moisture-main.json v3)
- **Sensor variable options** — Expanded from 4 to 7 sensors with location-tagged labels
- **Gauge panel overrides** — Added field overrides for sensors 5-7 with displayName and color thresholds
- **Trend plot overrides** — Added fixed colors and display names for sensors 5-7
- **Color distribution** — Improved visual distinction across 7 sensors for easier identification

#### System Scale
- **Multi-location coverage** — Now monitoring 7 sensors across 3 locations (bed-room: 2, living-room: 2, guest-room: 3)
- **Expanded capacity** — System proven to handle 7 concurrent sensors with stable WiFi and InfluxDB performance

### Fixed
- **Dashboard label consistency** — New sensors now display proper labels under radial gauges
- **Tooltip formatting** — Trend plot tooltips show human-readable labels instead of raw InfluxDB field names
- **Color matching** — Radial gauge colors now match trend plot colors (purple, orange, cyan)

---

## [2.3.0] - 2026-05-18

### Added

#### Raspberry Pi Enhanced Logging System
- **Startup logger** — Tracks boot reasons, filesystem corruption, kernel panics, USB mount status, service health
- **Boot event logging** — Logs every system boot with timestamp, uptime, boot reason, CPU temperature, service status
- **Grafana failure logging** — Dedicated log file for Grafana-specific failures with timestamps
- **Auto-reboot tracking** — Logs automatic reboot triggers to separate file
- **Log rotation** — Prevents 12GB log files (daily for health-monitor, monthly for startup logs)
- **Installation script** — One-command deployment via `install-logging.sh`
- **Comprehensive logging documentation** — `rpi-setup/LOGGING_README.md` with viewing logs, understanding boot reasons, troubleshooting

#### Grafana Dashboards
- **Raspberry Pi uptime panel** — Main dashboard now displays server uptime in top status bar (next to "Last Updated")
- **System uptime visibility** — Quick visibility into Raspberry Pi stability and reboot frequency

#### Documentation
- **Enhanced Grafana troubleshooting** — AGENTS.md updated with detailed Grafana failure recovery steps
- **System information accuracy** — Corrected username (omedeiro), IP addresses, file paths in AGENTS.md
- **Logging system reference** — Complete documentation of boot tracking, health monitoring, log rotation

### Changed

#### Raspberry Pi Monitoring
- **Health monitor improvements** — Enhanced error handling with fallback to prevent I/O errors
- **Large log rotation** — Automatically rotates existing 12GB health-monitor.log during install
- **Grafana-specific logging** — Separate log file for Grafana failures instead of mixed with general health checks

#### Dashboard Layout
- **soil-moisture-main.json v2** — Added Raspberry Pi uptime panel, improved top status bar
- **Version bump** — Dashboard schema version updated to v2

### Fixed

#### Incident Response (2026-05-18)
- **Root cause identified** — 18.5-hour Grafana outage caused by unclean shutdown at May 17 23:58:54
- **Filesystem corruption** — Dirty bit detected, fsck recovery triggered at boot
- **Silent failure** — Grafana exited cleanly (exit 0), systemd didn't auto-restart due to `Restart=on-failure`
- **Health monitor I/O errors** — 12GB log file caused write failures, preventing logging
- **No reboot tracking** — REBOOT_LOG path defined but file never created

#### System Reliability
- **Startup logger service** — Now captures all future boot events with detailed diagnostics
- **Log file management** — Log rotation prevents disk space exhaustion
- **Enhanced visibility** — Boot reasons, filesystem issues, service failures now tracked automatically

---

## [2.2.0] - 2026-05-17

### Added

#### Grafana Dashboards
- **6 dedicated dashboards** replacing single monolithic dashboard:
  - `soil-moisture-main.json` — Main overview with all sensors (tags: overview, sensors)
  - `sensor-details.json` — Individual sensor deep-dive (tags: sensors, diagnostics)
  - `system-health.json` — ESP8266 diagnostics and events (tags: diagnostics, system)
  - `alerts-overview.json` — Critical alerts and notifications (tags: alerts, monitoring)
  - `mobile-summary.json` — Mobile-optimized quick view (tags: mobile, overview)
  - `rpi-health.json` — Raspberry Pi system metrics (tags: system, server)
- **High-contrast color scheme** per sensor:
  - Sensor-1: Green (#73BF69)
  - Sensor-2: Yellow (#F2CC0C)
  - Sensor-3: Blue (#5794F2)
  - Sensor-4: Red (#FF6B6B)
- **Moisture gauge color gradients** — Dark to bright within each sensor's color family (0% dry → 100% wet)
- **Consistent sensor labels** — "Sensor 1 (Bed Room)" format with dropdown selection
- **Anonymous Grafana access** — View-only dashboards without login (Viewer role)
- **Dashboard provisioning** — Auto-reload from `/mnt/sensor-data/grafana/dashboards/` every 10 seconds
- **Automated panel testing** — `tests/check-dashboard-panels.sh` verifies all panels return data

#### Raspberry Pi Monitoring
- **System metrics collector** — Python script monitoring CPU, RAM, disk, temperature every 60 seconds
- **New InfluxDB measurement** — `rpi_system_metrics` with 12 fields (cpu_percent, cpu_temp, ram_percent, etc.)
- **systemd service** — `system-metrics-collector.service` with embedded InfluxDB token
- **Pi health dashboard** — `rpi-health.json` visualizing all Raspberry Pi metrics

#### Documentation
- **configure-grafana.sh** — Script to enable anonymous access with one command
- **Expanded README.md** — v2.2.0 features, 6 dashboards, system metrics, OTA updates
- **CHANGELOG.md** — This file

### Changed

#### Dashboard Improvements
- **Fixed "Last Updated" panel** — Now correctly converts InfluxDB nanoseconds to milliseconds (`/1000000`)
- **Fixed health score query** — Changed from `distinct() |> count()` to `group() |> count() |> group() |> count()`, now shows 100% (was 25%)
- **Fixed offline sensors stat** — Removed broken `findRecord()`, now shows correct count
- **Fixed diagnostic panels** — Corrected `event_type` tag vs field usage, removed non-existent `severity` field
- **Fixed Raspberry Pi field names** — `cpu_temp` (was `temperature`), `ram_percent` (was `memory_percent`)
- **Cleaned up dashboard tags** — Reduced from 3-4 per dashboard to exactly 2, total 8 unique tags
- **Removed time references from panel titles** — No more "(24h)" or "(12h)", titles adapt to selected time window
- **Sensor dropdown labels** — Shows "Sensor 1 (Bed Room)" instead of "sensor-1"
- **Location filtering** — All dashboards filter out 'backyard' location
- **Diagnostic event categorization** — "Critical vs Info Events" panel using map() to categorize event types

#### System Reliability
- **systemd service User config** — Changed from `pi` to `root` (pi user doesn't exist on system)
- **InfluxDB auto-restart** — Added `Restart=always` and `RestartSec=10` to systemd override
- **INFLUX_TOKEN in service file** — Embedded token in `system-metrics-collector.service` for reliability

### Fixed
- **Dashboard panel queries** — 31 panels verified working, 8 healthy "NO DATA" states, 16 skipped (Grafana variables)
- **Diagnostic logs panel** — Now uses correct fields (`event_reason`, `free_heap`, `rssi`) with pivot on event_type tag
- **Repurposed severity panel** — Changed "Diagnostic Events by Severity" to "Critical vs Info Events" with working categorization
- **Table panel pivots** — Fixed schema errors in complex join queries (2 known issues remain, non-critical)
- **Sensor uptime panel** — Shows ESP8266 uptime correctly (not Raspberry Pi uptime)
- **Last Updated relative time** — Shows "a few seconds ago" using Grafana's dateTimeFromNow unit

### Infrastructure
- **Git tag v2.2.0** — Tagged commit `54f91c6` on `feature/system-stability-improvements` branch
- **Dashboard deployment** — All 6 dashboards deployed to Pi at `/mnt/sensor-data/grafana/dashboards/`
- **Dashboard provisioning config** — Created `/mnt/sensor-data/grafana/provisioning/dashboards/dashboards.yml` with 10s updateInterval

### Incident Response
- **2026-05-17 10:38:35 EDT** — USB storage disconnect, 9-second outage
  - InfluxDB auto-restarted at 10:50:43 EDT
  - Grafana auto-restarted at 10:51:15 EDT
  - All services restored with no data loss

---

## [2.1.0] - 2026-05-15

### Added

#### Firmware
- **Hardware watchdog** — 8-second ESP8266 hardware watchdog prevents infinite loops
- **OTA updates** — Flash firmware remotely via WiFi (password: `soilmon2026`)
- **Heartbeat system** — 60-second telemetry with uptime, free heap, WiFi RSSI, queue status
- **Diagnostic events system** — Tracks crashes, WiFi events, InfluxDB errors in dedicated measurement
- **WiFi stability improvements** — Exponential backoff reconnect (5s → 60s), automatic retry, max TX power
- **New InfluxDB measurements**:
  - `sensor_heartbeat` — 60-second health telemetry
  - `sensor_diagnostics` — On-demand event tracking with event_type tag
- **Diagnostic event types**:
  - `boot_complete` — Clean boot detected
  - `crash_detected` — Crash on previous boot
  - `wifi_disconnect` — WiFi connection lost
  - `wifi_reconnect_success` — WiFi restored
  - `wifi_reconnect_failed` — Reconnect attempts exhausted
  - `queue_overflow` — Offline queue full
  - `heap_low_warning` — RAM critically low
  - `influxdb_error` — Database POST failed
  - `system_restart` — Manual or watchdog restart

#### Source Files
- `firmware/src/heartbeat.h/.cpp` — 60-second health telemetry
- `firmware/src/diagnostics.h/.cpp` — Event tracking and categorization
- `firmware/src/wifi_stability.h/.cpp` — Enhanced reconnection logic

### Changed
- **Firmware version** — Updated to v2.1.0 in `config.h`
- **WiFi reconnection strategy** — Changed from 3-attempt fixed to exponential backoff (10 attempts, 5s → 60s)
- **Boot diagnostics** — Now shows crash detection status and clean boot confirmation
- **Serial output** — Enhanced with `✅`, `⚠️`, `✓`, `✗` symbols for better readability
- **InfluxDB response validation** — Expects HTTP 204 (not 201) for successful writes

### Fixed
- **WiFi stability on power loss** — Hardware watchdog prevents hangs during reconnection
- **Queue drain blocking** — Non-blocking drain (max 10s per loop, max 5 readings)
- **Memory leaks** — Fixed heap fragmentation in WiFi reconnection logic

---

## [2.0.0] - 2026-05-10

### Added
- **Multi-sensor support** — Unlimited ESP8266 sensors with unique `DEVICE_ID`
- **InfluxDB 2.x backend** — Time-series database on Raspberry Pi 5
- **Grafana dashboard** — Live visualization with gauges, charts, filtering
- **WiFi captive portal** — WiFiManager for easy credential setup
- **Offline reading queue** — Buffer up to 20 readings during network outages
- **NTP time sync** — UTC timestamps for all readings
- **Raspberry Pi installer** — One-command setup script (`rpi-setup/install.sh`)
- **Automated backups** — Daily systemd timer at 3:00 AM
- **Health monitoring** — systemd service monitoring InfluxDB/Grafana

### Infrastructure
- **Raspberry Pi 5** — Dedicated server with 256GB USB storage
- **InfluxDB 2.7.12** — Pinned version (v2.9+ has ARM64 issues)
- **systemd services** — Auto-start, health monitoring, backups
- **UFW firewall** — Ports 22, 8086, 3000 open

### Initial Release Features
- ESP8266 firmware with PlatformIO
- Capacitive soil moisture sensor support
- WiFi stability with scan-before-connect
- In-memory ring buffer (50 readings)
- Local HTTP server (optional)
- Sensor calibration via HTTP API
- InfluxDB line protocol integration

---

## Version Numbering

- **Firmware versions** (e.g., v2.1.0) — Incremented for ESP8266 code changes
- **System versions** (e.g., v2.2.0) — Incremented for infrastructure/dashboard changes
- Firmware and system versions may diverge (current: firmware v2.1.0, system v2.2.0)

---

[2.2.0]: https://github.com/omedeiro/soil-sensor/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/omedeiro/soil-sensor/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/omedeiro/soil-sensor/releases/tag/v2.0.0
