# Agent Instructions — Soil Sensor Project

## Communication Guidelines

**CRITICAL:** The phrase "You're absolutely right!" should NEVER be used in responses. Provide direct, objective technical information without validating language.

## Specialized Skills

Detailed, task-specific workflows have been moved into opencode skills under
`.opencode/skills/`. They load automatically when a task matches. Load the
matching skill before doing the work rather than guessing.

| Skill | Use it for |
| ----- | ---------- |
| **`soil-sensor-firmware`** | Building/flashing ESP8266 (`pio run`, upload, `pio device monitor`), editing `config.h`, device type (soil/climate/DHT22), calibration, WiFi provisioning, serial monitor messages, multi-sensor setup, hardware constraints |
| **`grafana-dashboard-config`** | Editing `sensors-config.json`, validate→generate→upload dashboards, adding a sensor, changing plant names/colors/thresholds, watering-history dashboard |
| **`grafana-troubleshooting`** | Grafana unreachable, Cloudflare Tunnel, "No Data"/datasource UID fixes, panel-health monitor, Slack alerts, secret storage |
| **`sensor-offline-troubleshooting`** | ESP8266 stopped posting, power-cycle recovery, sensor health monitoring, InfluxDB last-reading queries |
| **`rpi-server-ops`** | Raspberry Pi install, InfluxDB/Grafana setup, tokens/buckets, `test_influx_write.sh`, end-to-end testing, legacy Flask/SQLite server |

## Architecture

**NEW SYSTEM (InfluxDB + Grafana on Raspberry Pi 5):**
- **ESP8266 firmware** (PlatformIO/Arduino) — reads sensor, POSTs to InfluxDB every 5 min
- **InfluxDB** (Raspberry Pi 5) — time-series database for sensor readings
- **Grafana** (Raspberry Pi 5) — dashboards, alerts, visualization
- **Raspberry Pi 5** — dedicated server, 256GB USB storage, automated backups

**OLD SYSTEM (deprecated, being replaced):**
- **Database server** (Python/Flask/SQLite on macOS) — to be phased out

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
11. **Editing auto-generated dashboard:** Never hand-edit `grafana-dashboards/soil-moisture-main.json` — regenerate from `sensors-config.json`
12. **Committing secrets:** Slack webhook / InfluxDB tokens live only on the Pi under `/mnt/sensor-data/config/` (chmod 600), never in git

## System Information

**Raspberry Pi 5 Server:**
- Username: `omedeiro`
- IP Address: `192.168.99.134`
- InfluxDB: `http://192.168.99.134:8086`
- Grafana (local): `http://192.168.99.134:3000`
- Grafana (public): `https://grafana.owenmedeiros.com`
- Data Storage: `/mnt/sensor-data` (256GB USB drive)
- Cloudflare Tunnel: `soil-sensor-grafana` (ID: ec9b412a-098a-45d2-8060-f2fa7b23b477)

**ESP8266 Sensors:**
- **sensor-1** (bed-room, Rubber Tree): `192.168.99.110` (MAC: 68:c6:3a:f6:b3:ae) - online
- **sensor-2** (living-room, Monstera): `192.168.99.149` (MAC: 48:3f:da:19:c0:86) - online
- **sensor-3** (living-room, Avocado): `192.168.99.70` (MAC: 40:91:51:4f:d9:97) - online
- **sensor-4** (guest-room, Micro Greens): `192.168.99.105` (MAC: 48:3f:da:aa:fe:d7) - online
- **sensor-5** (bed-room, ZZ Plant): `192.168.99.89` (MAC: 34:ab:95:16:51:d9) (ESP-1651D9, Wi-Fi 2.4GHz n) - online
- **sensor-6** (living-room, Ficus Elastica Ruby): `192.168.99.38` (MAC: 48:3f:da:62:f9:07) (Wi-Fi 2.4GHz n) - online
- **sensor-7** (guest-room, Basil - pot): `192.168.99.141` (MAC: 84:cc:a8:a7:96:32) (Wi-Fi 2.4GHz n) - online
- **sensor-8** (living-room, Ambient Climate — **DHT22/AM2302**, not soil): `192.168.99.182` (MAC: 48:55:19:e6:6c:af) - online
- Web Dashboard: `http://<sensor-ip>` (e.g., `http://192.168.99.110`)
- Reading Interval: 5 minutes (300000ms)

## Status Files Reference

**Documentation:**
- `docs/README.md` — Technical documentation (WiFi stability, Grafana Cloud setup, InfluxDB notes)
- `docs/guides/TROUBLESHOOTING_NO_DATA.md` — Panel health troubleshooting guide (v2.9.0)
- `grafana-dashboards/README.md` — Dashboard installation, customization, and alert setup
- `README.md` — Project overview and setup instructions
- `AGENTS.md` — This file (agent instructions index + core reference)
- `.opencode/skills/` — Task-specific skill workflows (see Specialized Skills above)
