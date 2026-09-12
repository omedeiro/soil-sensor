#!/bin/bash
#
# install-health-timers.sh
# Install (or audit) the two alerting timers on the Raspberry Pi.
#
#   sensor-health-check.timer   every 10 min — a sensor stopped logging,
#                               or the whole fleet went silent
#   soil-moisture-check.timer   every 30 min — a plant dropped below the
#                               moisture threshold
#
# install-slack-notifications.sh already does this as part of a full
# interactive setup. This script is the narrow, re-runnable version: it
# prompts for nothing, reuses the InfluxDB read token that panel-health.env
# already holds, and is safe to run again on a Pi that is already configured.
# Use it after an SD-card rebuild, or when --check reports drift.
#
# Usage:
#   ./install-health-timers.sh --check     # audit only, no sudo, no changes
#   ./install-health-timers.sh             # install and enable the timers
#
# Needs sudo for the /etc/systemd/system copy and systemctl enable; it will
# prompt once. Everything before that runs as the invoking user so the
# secrets file stays owned by them.
#
set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/omedeiro/soil-sensor}"
CONFIG_DIR="${CONFIG_DIR:-/mnt/sensor-data/config}"
ENV_FILE="${ENV_FILE:-${CONFIG_DIR}/soil-alerts.env}"
SOURCE_ENV="${SOURCE_ENV:-${CONFIG_DIR}/panel-health.env}"
WEBHOOK_FILE="${WEBHOOK_FILE:-${CONFIG_DIR}/slack_webhook_url}"
UNIT_SRC="${REPO_DIR}/rpi-setup/systemd"
UNIT_DEST="/etc/systemd/system"

UNITS=(
    sensor-health-check.service
    sensor-health-check.timer
    soil-moisture-check.service
    soil-moisture-check.timer
)
TIMERS=(sensor-health-check.timer soil-moisture-check.timer)

GREEN='\033[92m'; YELLOW='\033[93m'; RED='\033[91m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; }
bad()  { echo -e "  ${RED}✗${RESET} $*"; }
die()  { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }

MODE="install"
case "${1:-}" in
    --check) MODE="check" ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    "") ;;
    *) die "Unknown argument: $1 (try --check or --help)" ;;
esac

# ── Audit ────────────────────────────────────────────────────────────────────
# Read-only: no sudo, no writes. Exits 1 if anything needed is missing, so it
# can be wired into a check later.
if [[ "$MODE" == "check" ]]; then
    echo "── Alerting timers: what is actually installed ─────────────"
    drift=0

    for unit in "${UNITS[@]}"; do
        if [[ -f "${UNIT_DEST}/${unit}" ]]; then ok "${unit} installed"
        else bad "${unit} NOT installed in ${UNIT_DEST}"; drift=1; fi
    done

    for timer in "${TIMERS[@]}"; do
        # systemctl prints its verdict on stdout *and* exits non-zero for a
        # missing unit, so take the first line and default only when empty.
        # ...and `pipefail` would make that non-zero status abort the script.
        state=$(systemctl is-enabled "$timer" 2>/dev/null | head -1) || true
        active=$(systemctl is-active "$timer" 2>/dev/null | head -1) || true
        state=${state:-not-found}
        active=${active:-inactive}
        if [[ "$state" == "enabled" && "$active" == "active" ]]; then
            ok "${timer} enabled and active"
        else
            bad "${timer} is ${state}/${active} — it will never fire"; drift=1
        fi
    done

    [[ -s "$ENV_FILE" ]] && ok "${ENV_FILE} present" \
        || { bad "${ENV_FILE} missing — the units start but exit 3 (no token)"; drift=1; }
    [[ -s "$WEBHOOK_FILE" ]] && ok "${WEBHOOK_FILE} present" \
        || { bad "${WEBHOOK_FILE} missing — checks run but cannot alert"; drift=1; }

    echo ""
    if [[ "$drift" -eq 0 ]]; then
        echo -e "${GREEN}✅ Alerting is installed and armed${RESET}"
        systemctl list-timers --all 'sensor-health-check.timer' 'soil-moisture-check.timer' \
            --no-pager 2>/dev/null | head -5
        exit 0
    fi
    echo -e "${YELLOW}Alerting is NOT fully armed. Run this script with no arguments to fix.${RESET}"
    exit 1
fi

# ── Install ──────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo "Installing sensor-health + soil-moisture alert timers"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Checking prerequisites..."
for cmd in jq curl python3 systemctl; do
    command -v "$cmd" > /dev/null 2>&1 || die "'$cmd' not found (sudo apt-get install $cmd)"
done
ok "required commands present"

[[ -d "$REPO_DIR" ]] || die "Repo not found at $REPO_DIR (set REPO_DIR=...)"
for s in scripts/send-slack-alert.sh \
         rpi-setup/scripts/check-soil-moisture.sh \
         rpi-setup/scripts/check-sensor-health.sh \
         rpi-setup/scripts/lib/influx-lib.sh; do
    [[ -f "${REPO_DIR}/${s}" ]] || die "Missing ${s} — run 'git pull' in $REPO_DIR"
done
chmod +x "${REPO_DIR}/scripts/send-slack-alert.sh" \
         "${REPO_DIR}/rpi-setup/scripts/check-soil-moisture.sh" \
         "${REPO_DIR}/rpi-setup/scripts/check-sensor-health.sh"
ok "alert scripts present and executable"

for unit in "${UNITS[@]}"; do
    [[ -f "${UNIT_SRC}/${unit}" ]] || die "Missing unit ${UNIT_SRC}/${unit} — run 'git pull'"
done
ok "unit files present in the checkout"

[[ -s "$WEBHOOK_FILE" ]] \
    || die "No Slack webhook at ${WEBHOOK_FILE}. Run ./install-slack-notifications.sh instead — it prompts for one."
ok "Slack webhook configured"
echo ""

# ── Alert config ─────────────────────────────────────────────────────────────
# The units read soil-alerts.env. If it does not exist, seed it from
# panel-health.env, which already holds a working read token for the same
# bucket — no need to mint or paste another one.
echo "── Alert config (${ENV_FILE}) ──────────────────────────────"
if [[ -s "$ENV_FILE" ]] && grep -q '^INFLUX_TOKEN=..' "$ENV_FILE"; then
    ok "already present, left untouched"
else
    [[ -s "$SOURCE_ENV" ]] \
        || die "Neither ${ENV_FILE} nor ${SOURCE_ENV} exists — run ./install-slack-notifications.sh"
    mkdir -p "$CONFIG_DIR"
    (
        umask 077
        {
            echo "# Written by install-health-timers.sh — DO NOT COMMIT"
            echo "# InfluxDB read credentials copied from $(basename "$SOURCE_ENV")"
            grep -E '^(INFLUX_TOKEN|INFLUX_ORG|INFLUX_BUCKET)=' "$SOURCE_ENV"
            echo "INFLUX_URL=http://localhost:8086"
            echo "SENSORS_CONFIG=${REPO_DIR}/sensors-config.json"
            echo "HEARTBEAT_URL="
        } > "$ENV_FILE"
    )
    chmod 600 "$ENV_FILE"
    ok "created from $(basename "$SOURCE_ENV") (mode 600)"
fi

# Export while sourcing: the check scripts are children and read these from
# the environment, the same way the systemd EnvironmentFile= does.
set +u
set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a
set -u
[[ -n "${INFLUX_TOKEN:-}" ]] || die "INFLUX_TOKEN is empty in ${ENV_FILE}"
probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -XPOST "${INFLUX_URL:-http://localhost:8086}/api/v2/query?org=${INFLUX_ORG:-soil-monitoring}" \
    -H "Authorization: Token ${INFLUX_TOKEN}" \
    -H "Content-Type: application/vnd.flux" \
    -d "from(bucket: \"${INFLUX_BUCKET:-sensor-readings}\") |> range(start: -1m) |> limit(n: 1)")
[[ "$probe" == "200" ]] || die "Token rejected by InfluxDB (HTTP $probe) — check its read permission"
ok "read token accepted by InfluxDB"
echo ""

# ── Prove the checks run before arming them ──────────────────────────────────
echo "── Dry run (no Slack messages sent) ────────────────────────"
for check in check-sensor-health check-soil-moisture; do
    if "${REPO_DIR}/rpi-setup/scripts/${check}.sh" --dry-run > /dev/null 2>&1; then
        ok "${check}.sh ran clean"
    else
        # Exit 1/2 mean "found something worth alerting on", not a failure.
        rc=$?
        case "$rc" in
            1|2) ok "${check}.sh ran, would alert (exit ${rc})" ;;
            *)   die "${check}.sh failed with exit ${rc} — fix that before enabling the timer" ;;
        esac
    fi
done
echo ""

# ── systemd ──────────────────────────────────────────────────────────────────
echo "── Installing units (needs sudo) ───────────────────────────"
for unit in "${UNITS[@]}"; do
    sudo cp "${UNIT_SRC}/${unit}" "${UNIT_DEST}/"
    ok "installed ${unit}"
done
sudo systemctl daemon-reload
for timer in "${TIMERS[@]}"; do
    sudo systemctl enable --now "$timer" > /dev/null
    ok "enabled ${timer}"
done
echo ""

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Alerting is armed${RESET}"
echo "════════════════════════════════════════════════════════════"
systemctl list-timers --all 'sensor-health-check.timer' 'soil-moisture-check.timer' --no-pager | head -5
echo ""
echo "Verify any time (no sudo):  ./rpi-setup/install-health-timers.sh --check"
echo "Watch them run:             journalctl -u sensor-health-check -u soil-moisture-check -f"
echo ""
warn "These alerts all run ON the Pi. If the Pi itself loses power or network,"
echo "     nothing here can tell you. For that, add a healthchecks.io ping URL to"
echo "     ${ENV_FILE} as HEARTBEAT_URL= and restart sensor-health-check.timer."
