---
name: pi-access
description: Connect to and operate the soil-sensor Raspberry Pi (omedeiro@192.168.99.134) over SSH. Covers the actual deployment topology — InfluxDB in Docker, user-level vs system systemd units, where secrets live — and the constraints that trip up automation (sudo needs a password, no influx CLI, omedeiro not in the docker group). Use when running commands on the Pi, checking service state, rotating InfluxDB tokens, or when a repo systemd unit does not match what is actually running.
---

# Raspberry Pi Access

`omedeiro@192.168.99.134` — SSH key auth is configured (`~/.ssh/id_ed25519`), host is in
`known_hosts`. Always use `BatchMode=yes` so a missing key fails fast instead of hanging on
a password prompt:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 omedeiro@192.168.99.134 'hostname'
```

## Deployment topology — verify, do not assume

The `rpi-setup/systemd/*.service` files in this repo are **templates, not a mirror of the Pi.**
As of 2026-08-23 none of them were installed in `/etc/systemd/system`. Check before assuming a
repo unit is what is running:

```bash
ssh -o BatchMode=yes omedeiro@192.168.99.134 'systemctl list-unit-files | grep -E "metrics|panel-health|sensor-health|soil"; echo ---; systemctl --user list-unit-files | grep -E "metrics|soil"'
```

| Thing | Reality on the Pi |
|---|---|
| InfluxDB | **Docker container**, not `influxdb.service` (`systemctl is-active influxdb` → `inactive`). Listening on `0.0.0.0:8086`, v2.7.12. Compose file: `~/soil-sensor/rpi-setup/docker-compose.yml` |
| `influx` CLI | **Not installed.** Use the HTTP API with `curl`, or `docker exec` into the container |
| Metrics collector | The **user-level** timer from `install-system-metrics.sh` (`systemctl --user`), reading `~/soil-sensor/system-metrics.env` — *not* the system unit in `rpi-setup/systemd/` |
| Grafana | `grafana-server` on `:3000`, public via Cloudflare Tunnel at `soil.owenmedeiros.com` |
| Repo checkout | `~/soil-sensor` |

## Constraints that block automation

- **`sudo` requires a password.** `sudo -n true` fails. Claude must not type passwords, so
  anything needing root — installing units, editing `/etc/default/grafana-server`, `docker`
  commands — has to be run by Owen interactively. Hand over a script rather than attempting it.
- **`omedeiro` is not in the `docker` group**, so every `docker` call needs sudo too.
- **Reading secrets is sandbox-blocked.** Commands that pull token values out of env files get
  denied by the permission classifier, even for hashing/comparison. Do not work around it — ask
  Owen to run the check and report the result.

## Where secrets live

All mode `600`, owned by `omedeiro` (**not** root — no sudo needed to edit these two):

- `/mnt/sensor-data/config/panel-health.env` — `INFLUX_TOKEN` + Grafana creds
- `/mnt/sensor-data/config/slack_webhook_url`
- `~/soil-sensor/system-metrics.env` — `INFLUX_TOKEN` for the live user-level collector
- `/etc/default/grafana-server` — `INFLUX_READ_TOKEN` (root-owned, needs sudo)

`soil-alerts.env` and `/mnt/sensor-data/config/system-metrics.env` are referenced by repo units
but **did not exist** as of 2026-08-23; they are created by `install-slack-notifications.sh`.

## InfluxDB token operations without the CLI

Use the HTTP API. `$TOK` should be read from a file on the Pi, never pasted:

```bash
TOK="$(grep -m1 '^INFLUX_TOKEN=' /mnt/sensor-data/config/panel-health.env | cut -d= -f2-)"
curl -s -H "Authorization: Token $TOK" http://localhost:8086/api/v2/authorizations | python3 -m json.tool
```

Create a scoped token (`POST /api/v2/authorizations`), revoke one
(`DELETE /api/v2/authorizations/{id}`). Always create and verify replacements **before**
revoking the old token — the same credential is shared by Grafana, the collector, and backups,
so revoking first takes the whole stack down at once.
