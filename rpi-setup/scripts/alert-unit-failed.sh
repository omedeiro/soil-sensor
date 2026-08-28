#!/bin/bash
#
# alert-unit-failed.sh
# Report a failed systemd unit to Slack. Wired up via OnFailure= on the
# monitoring units, so the alerting system reports its own breakage.
#
# Without this, an alert checker that cannot run is completely silent: a lost
# /mnt/sensor-data/config/soil-alerts.env (exit 3, "INFLUX_TOKEN not set"), an
# uninstalled jq, or a crash all leave the timer ticking, the unit failing, and
# no Slack message ever arriving. Silence looks exactly like "everything is
# fine", which is the worst possible failure mode for a monitoring system.
#
# Usage:
#   ./alert-unit-failed.sh <unit-name>
#

set -uo pipefail

UNIT="${1:-}"
[[ -n "$UNIT" ]] || { echo "Usage: $0 <unit-name>" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One alert per unit per 6h: a timer failing every 10 minutes must not produce
# 144 Slack messages a day.
RATE_LIMIT_SECONDS="${UNIT_FAILURE_RATE_LIMIT_SECONDS:-21600}"

SLACK_SCRIPT="${SLACK_SCRIPT:-}"
if [[ -z "$SLACK_SCRIPT" ]]; then
    for candidate in \
        "$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/scripts/send-slack-alert.sh" \
        "/home/omedeiro/soil-sensor/scripts/send-slack-alert.sh"; do
        [[ -x "$candidate" ]] && { SLACK_SCRIPT="$candidate"; break; }
    done
fi
[[ -n "$SLACK_SCRIPT" && -x "$SLACK_SCRIPT" ]] || {
    echo "ERROR: send-slack-alert.sh not found or not executable" >&2
    exit 1
}

# Gather what context we can. Every one of these is best-effort: this script
# runs precisely when something is already broken, so it must never itself fail.
RESULT=$(systemctl show "$UNIT" --property=Result --value 2>/dev/null || echo "unknown")
EXIT_STATUS=$(systemctl show "$UNIT" --property=ExecMainStatus --value 2>/dev/null || echo "unknown")
[[ -n "$RESULT" ]] || RESULT="unknown"
[[ -n "$EXIT_STATUS" ]] || EXIT_STATUS="unknown"

# The unprivileged service user may not be able to read the journal; if so,
# say that rather than pretending there was no output.
LOG=$(journalctl -u "$UNIT" -n 12 --no-pager -o cat 2>/dev/null | tail -12)
[[ -n "$LOG" ]] || LOG="(journal not readable by $(id -un) — run: journalctl -u ${UNIT} -n 50)"

# Exit 3 is the one failure with an unambiguous cause worth naming outright.
HINT=""
if [[ "$EXIT_STATUS" == "3" ]]; then
    HINT="\\n\\nExit 3 is a configuration error — most often a missing or unreadable /mnt/sensor-data/config/soil-alerts.env (INFLUX_TOKEN)."
fi

MESSAGE="${UNIT} failed and its checks are no longer running.\\n\\nResult: ${RESULT} (exit status ${EXIT_STATUS})${HINT}\\n\\nLast log lines:\\n${LOG}\\n\\nInvestigate with:\\n  systemctl status ${UNIT}\\n  journalctl -u ${UNIT} -n 50"

exec "$SLACK_SCRIPT" \
    --severity critical \
    --title "Monitoring Unit Failed: ${UNIT}" \
    --message "$MESSAGE" \
    --topic "unit-failed-${UNIT}" \
    --rate-limit-seconds "$RATE_LIMIT_SECONDS"
