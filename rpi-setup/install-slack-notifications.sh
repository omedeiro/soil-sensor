#!/bin/bash
#
# install-slack-notifications.sh
# One-time setup for Slack alerting on the Raspberry Pi.
#
# Installs four alerts:
#   1. Soil moisture below 50%      - checked every 30 min, edge-triggered
#   2. A sensor stopped logging     - checked every 10 min, max 1 alert/day
#   3. The whole system is down     - checked every 10 min, max 1 alert/day
#   4. A check itself failed        - via OnFailure=, max 1 per unit per 6h
#
# A fifth alert lives outside the Pi entirely, in .github/workflows/watchdog.yml:
# nothing running on the Pi can report the Pi being dead.
#
# Secrets are written to /mnt/sensor-data/config/ with mode 600 and are never
# committed to git.
#

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/omedeiro/soil-sensor}"
CONFIG_DIR="${CONFIG_DIR:-/mnt/sensor-data/config}"
ENV_FILE="${CONFIG_DIR}/soil-alerts.env"
WEBHOOK_FILE="${CONFIG_DIR}/slack_webhook_url"
STATE_DIR="/mnt/sensor-data/monitor-state"
RATE_LIMIT_DIR="/mnt/sensor-data/slack-rate-limit"

GREEN='\033[92m'; YELLOW='\033[93m'; RED='\033[91m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; }
die()  { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }

echo "════════════════════════════════════════════════════════════"
echo "Slack Notifications Setup"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Prerequisites ────────────────────────────────────────────────────────────
echo "Checking prerequisites..."
for cmd in jq curl python3 systemctl; do
    command -v "$cmd" > /dev/null 2>&1 || die "'$cmd' not found (sudo apt-get install $cmd)"
done
ok "required commands present"

[[ -d "$REPO_DIR" ]] || die "Repo not found at $REPO_DIR (set REPO_DIR=...)"
ok "repo at $REPO_DIR"

for s in scripts/send-slack-alert.sh \
         rpi-setup/scripts/check-soil-moisture.sh \
         rpi-setup/scripts/check-sensor-health.sh \
         rpi-setup/scripts/alert-unit-failed.sh \
         rpi-setup/scripts/lib/influx-lib.sh; do
    [[ -f "${REPO_DIR}/${s}" ]] || die "Missing ${s} - run 'git pull' in $REPO_DIR"
done
chmod +x "${REPO_DIR}/scripts/send-slack-alert.sh" \
         "${REPO_DIR}/rpi-setup/scripts/check-soil-moisture.sh" \
         "${REPO_DIR}/rpi-setup/scripts/check-sensor-health.sh" \
         "${REPO_DIR}/rpi-setup/scripts/alert-unit-failed.sh"
ok "alert scripts present and executable"

mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$RATE_LIMIT_DIR"
ok "state directories ready"
echo ""

# ── Slack webhook ────────────────────────────────────────────────────────────
echo "── Slack webhook ───────────────────────────────────────────"
if [[ -s "$WEBHOOK_FILE" ]]; then
    ok "webhook already configured at $WEBHOOK_FILE"
    read -rp "  Replace it? (y/N) " reply
    [[ "$reply" =~ ^[Yy]$ ]] && rm -f "$WEBHOOK_FILE"
fi

if [[ ! -s "$WEBHOOK_FILE" ]]; then
    echo "  Create an Incoming Webhook at https://api.slack.com/apps"
    echo "  (Your App → Incoming Webhooks → Add New Webhook to Workspace)"
    read -rp "  Paste the webhook URL: " WEBHOOK_URL
    [[ "$WEBHOOK_URL" == https://hooks.slack.com/* ]] \
        || die "That does not look like a Slack webhook URL"
    ( umask 077; printf '%s' "$WEBHOOK_URL" > "$WEBHOOK_FILE" )
    chmod 600 "$WEBHOOK_FILE"
    ok "webhook stored at $WEBHOOK_FILE (mode 600)"
fi
echo ""

# ── InfluxDB read token ──────────────────────────────────────────────────────
echo "── InfluxDB read token ─────────────────────────────────────"
if [[ -s "$ENV_FILE" ]] && grep -q '^INFLUX_TOKEN=..' "$ENV_FILE"; then
    ok "token already configured at $ENV_FILE"
    read -rp "  Replace it? (y/N) " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then NEED_TOKEN=true; else NEED_TOKEN=false; fi
else
    NEED_TOKEN=true
fi

if [[ "$NEED_TOKEN" == "true" ]]; then
    echo "  Needs READ permission on the 'sensor-readings' bucket."
    read -rsp "  Paste the InfluxDB read token: " INFLUX_TOKEN; echo
    [[ -n "$INFLUX_TOKEN" ]] || die "Token cannot be empty"

    echo -n "  Optional dead-man switch URL (see note below, blank to skip): "
    read -r HEARTBEAT_URL

    ( umask 077; cat > "$ENV_FILE" <<EOF
# Written by install-slack-notifications.sh - DO NOT COMMIT
INFLUX_TOKEN=${INFLUX_TOKEN}
INFLUX_URL=http://localhost:8086
INFLUX_ORG=soil-monitoring
INFLUX_BUCKET=sensor-readings
SENSORS_CONFIG=${REPO_DIR}/sensors-config.json
HEARTBEAT_URL=${HEARTBEAT_URL}
EOF
    )
    chmod 600 "$ENV_FILE"
    ok "config stored at $ENV_FILE (mode 600)"
fi
echo ""

# ── Verify the token actually works ──────────────────────────────────────────
echo "── Verifying InfluxDB access ───────────────────────────────"
set +u; source "$ENV_FILE"; set -u
if curl -sf --max-time 5 "${INFLUX_URL}/health" | grep -q '"status":"pass"'; then
    ok "InfluxDB reachable at $INFLUX_URL"
else
    die "InfluxDB not reachable at $INFLUX_URL"
fi

probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
    -H "Authorization: Token ${INFLUX_TOKEN}" \
    -H "Content-Type: application/vnd.flux" \
    -d "from(bucket: \"${INFLUX_BUCKET}\") |> range(start: -1m) |> limit(n: 1)")
[[ "$probe" == "200" ]] || die "Token rejected by InfluxDB (HTTP $probe) - check permissions"
ok "read token accepted"
echo ""

# ── Send a test message ──────────────────────────────────────────────────────
echo "── Sending test message to Slack ───────────────────────────"
if "${REPO_DIR}/scripts/send-slack-alert.sh" \
        --severity success \
        --title "Slack Notifications Configured" \
        --message "Soil monitoring alerts are now active on $(hostname).\\n  • Low soil moisture (below 50%)\\n  • Sensor stopped logging (max 1/day)\\n  • Whole system down (max 1/day)" \
        --topic setup-test --no-rate-limit > /dev/null 2>&1; then
    ok "test message delivered - check your Slack channel"
else
    die "Test message failed. Verify the webhook URL in $WEBHOOK_FILE"
fi
echo ""

# ── Install systemd units ────────────────────────────────────────────────────
echo "── Installing systemd timers ───────────────────────────────"
UNIT_SRC="${REPO_DIR}/rpi-setup/systemd"
for unit in sensor-health-check.service sensor-health-check.timer \
            soil-moisture-check.service soil-moisture-check.timer \
            alert-unit-failed@.service; do
    sudo cp "${UNIT_SRC}/${unit}" /etc/systemd/system/
    ok "installed ${unit}"
done

sudo systemctl daemon-reload
sudo systemctl enable --now sensor-health-check.timer > /dev/null
sudo systemctl enable --now soil-moisture-check.timer > /dev/null
ok "timers enabled and started"
echo ""

# ── Initial run ──────────────────────────────────────────────────────────────
echo "── Running initial checks ──────────────────────────────────"
sudo systemctl start soil-moisture-check.service || true
sudo systemctl start sensor-health-check.service || true
ok "initial checks dispatched"
echo ""

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Slack notifications are active${RESET}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Alerts configured:"
echo "  • Soil moisture below 50%   - checked every 30 min"
echo "                                 alerts once, then re-arms after watering"
echo "  • Sensor stopped logging     - checked every 10 min, max 1 alert/day"
echo "  • Whole system down          - checked every 10 min, max 1 alert/day"
echo "  • A check itself failing     - reported via OnFailure=, max 1 per 6h"
echo ""
echo "Check status:"
echo "  systemctl list-timers 'soil-*' 'sensor-*'"
echo "  journalctl -u soil-moisture-check -u sensor-health-check -f"
echo ""
echo "Preview without sending:"
echo "  cd $REPO_DIR && set -a && . $ENV_FILE && set +a"
echo "  ./rpi-setup/scripts/check-soil-moisture.sh --dry-run"
echo "  ./rpi-setup/scripts/check-sensor-health.sh --dry-run"
echo ""
if [[ -z "${HEARTBEAT_URL:-}" ]]; then
    warn "No dead-man switch configured."
    echo "     If the Pi loses power or network, NOTHING on it can tell you -"
    echo "     the alerts above all run on the Pi itself. To cover that case,"
    echo "     create a free check at https://healthchecks.io (period 20 min),"
    echo "     then add its ping URL to $ENV_FILE as HEARTBEAT_URL= and run:"
    echo "       sudo systemctl restart sensor-health-check.timer"
fi
echo "════════════════════════════════════════════════════════════"
