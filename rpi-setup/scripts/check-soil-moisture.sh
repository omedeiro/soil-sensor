#!/bin/bash
#
# check-soil-moisture.sh
# Alert to Slack when a plant's soil moisture drops below a threshold.
#
# Alerting is EDGE-TRIGGERED with hysteresis:
#   * A plant that crosses below the threshold alerts once.
#   * While it stays dry it is re-alerted at most once per --reminder-hours.
#   * Once it recovers above (threshold + hysteresis) it is re-armed, so the
#     next time it dries out you are told again immediately.
#
# Readings older than --max-age-minutes are ignored: a silent sensor is a
# health problem, not a dry plant, and is reported by check-sensor-health.sh.
#
# Usage:
#   ./check-soil-moisture.sh [OPTIONS]
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/influx-lib.sh
source "${SCRIPT_DIR}/lib/influx-lib.sh"

# ── Configuration ────────────────────────────────────────────────────────────
SENSORS_CONFIG="${SENSORS_CONFIG:-/home/omedeiro/soil-sensor/sensors-config.json}"
STATE_DIR="${MONITOR_STATE_DIR:-}"
SLACK_SCRIPT="${SLACK_SCRIPT:-}"

THRESHOLD=50            # alert below this moisture %
HYSTERESIS=5            # must climb this far above threshold to re-arm
MAX_AGE_MINUTES=30      # ignore readings older than this
REMINDER_HOURS=24       # re-alert cadence while a plant stays dry
NOTIFY=false
NOTIFY_RECOVERY=true
DRY_RUN=false
VERBOSE=false
SLACK_TOPIC="soil-moisture-low"

GREEN='\033[92m'; YELLOW='\033[93m'; RED='\033[91m'; BLUE='\033[94m'; RESET='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Alert when plant soil moisture drops below a threshold.

OPTIONS:
    --threshold N          Alert below N% moisture (default: 50)
    --hysteresis N         Re-arm once moisture exceeds threshold+N (default: 5)
    --max-age-minutes N    Ignore readings older than N minutes (default: 30)
    --reminder-hours N     Re-alert cadence while still dry (default: 24)
    --notify               Send Slack notification
    --no-recovery-notice   Do not send "recovered" notifications
    --dry-run              Show what would be sent without sending
    --verbose              Show detailed output
    --help                 Show this help message

PER-SENSOR THRESHOLDS:
    A sensor may override the global threshold in sensors-config.json:
      { "id": "sensor-4", "thresholds": { "alert": 60 } }

CONFIGURATION:
    INFLUX_TOKEN must be set (read permission on the sensor-readings bucket).
    Sensors are auto-detected from: \$SENSORS_CONFIG

EXIT CODES:
    0   All plants above threshold
    1   One or more plants below threshold
    2   InfluxDB connection/query error
    3   Configuration error
EOF
    exit 0
}

log_info() { [[ "$VERBOSE" == "true" ]] && echo -e "[$(date +'%H:%M:%S')] ${BLUE}INFO:${RESET} $*" >&2 || true; }
log_error() { echo -e "[$(date +'%H:%M:%S')] ${RED}ERROR:${RESET} $*" >&2; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --threshold)         THRESHOLD="$2"; shift 2 ;;
        --hysteresis)        HYSTERESIS="$2"; shift 2 ;;
        --max-age-minutes)   MAX_AGE_MINUTES="$2"; shift 2 ;;
        --reminder-hours)    REMINDER_HOURS="$2"; shift 2 ;;
        --notify)            NOTIFY=true; shift ;;
        --no-recovery-notice) NOTIFY_RECOVERY=false; shift ;;
        --dry-run)           DRY_RUN=true; NOTIFY=true; shift ;;
        --verbose)           VERBOSE=true; shift ;;
        --help)              usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# ── Locate helpers ───────────────────────────────────────────────────────────
if [[ -z "$SLACK_SCRIPT" ]]; then
    for candidate in \
        "$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/scripts/send-slack-alert.sh" \
        "/home/omedeiro/soil-sensor/scripts/send-slack-alert.sh"; do
        [[ -x "$candidate" ]] && { SLACK_SCRIPT="$candidate"; break; }
    done
fi

if [[ -z "$STATE_DIR" ]]; then
    if [[ -d /mnt/sensor-data ]]; then
        STATE_DIR="/mnt/sensor-data/monitor-state"
    else
        STATE_DIR="/tmp/soil-monitor-state"
    fi
fi
mkdir -p "$STATE_DIR" 2>/dev/null || { log_error "Cannot create state dir: $STATE_DIR"; exit 3; }

# ── Preconditions ────────────────────────────────────────────────────────────
[[ -z "$INFLUX_TOKEN" ]] && { log_error "INFLUX_TOKEN not set"; exit 3; }
command -v jq > /dev/null 2>&1 || { log_error "'jq' not found (sudo apt-get install jq)"; exit 3; }
[[ -f "$SENSORS_CONFIG" ]] || { log_error "Sensors config not found: $SENSORS_CONFIG"; exit 3; }

# ── Query latest moisture per sensor ─────────────────────────────────────────
FLUX="from(bucket: \"${INFLUX_BUCKET}\")
  |> range(start: -${MAX_AGE_MINUTES}m)
  |> filter(fn: (r) => r._measurement == \"sensor_reading\")
  |> filter(fn: (r) => r._field == \"moisture\")
  |> group(columns: [\"device_id\"])
  |> last()
  |> keep(columns: [\"device_id\", \"_time\", \"_value\"])"

echo "════════════════════════════════════════════════════════════"
echo "Soil Moisture Check - $(date +'%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════"
echo "Threshold:  below ${THRESHOLD}% (re-arm above $((THRESHOLD + HYSTERESIS))%)"
echo "Reading age: max ${MAX_AGE_MINUTES} min"
echo ""

if ! CSV=$(influx_query "$FLUX"); then
    log_error "InfluxDB query failed - cannot evaluate moisture"
    exit 2
fi

READINGS=$(influx_csv_extract "$CSV" device_id _time _value)
log_info "Parsed $(printf '%s' "$READINGS" | grep -c . || true) reading(s)"

# ── Evaluate each configured soil sensor ─────────────────────────────────────
NOW=$(date +%s)
REMINDER_SECONDS=$((REMINDER_HOURS * 3600))
ALERT_LINES=""
ALERT_COUNT=0
ALERT_IDS=""
RECOVERED_LINES=""
RECOVERED_COUNT=0
DRY_COUNT=0

while IFS=$'\t' read -r id plant override; do
    [[ -z "$id" ]] && continue

    limit="$THRESHOLD"
    [[ -n "$override" ]] && limit="$override"
    rearm=$((limit + HYSTERESIS))
    state_file="${STATE_DIR}/dry-${id}.state"

    row=$(printf '%s\n' "$READINGS" | awk -F'\t' -v d="$id" '$1 == d {print; exit}')

    if [[ -z "$row" ]]; then
        echo -e "  ${YELLOW}?${RESET} $id ($plant) - no reading in last ${MAX_AGE_MINUTES} min (see sensor health check)"
        continue
    fi

    moisture=$(printf '%s' "$row" | cut -f3)
    reading_time=$(printf '%s' "$row" | cut -f2)

    if ! awk -v m="$moisture" 'BEGIN { exit !(m == m + 0) }' 2>/dev/null; then
        echo -e "  ${YELLOW}?${RESET} $id ($plant) - non-numeric reading: '$moisture'"
        continue
    fi

    if awk -v m="$moisture" -v t="$limit" 'BEGIN { exit !(m < t) }'; then
        DRY_COUNT=$((DRY_COUNT + 1))
        should_alert=false
        reason=""

        if [[ ! -f "$state_file" ]]; then
            should_alert=true
            reason="newly dry"
        else
            last_alert=$(cat "$state_file" 2>/dev/null || echo 0)
            [[ "$last_alert" =~ ^[0-9]+$ ]] || last_alert=0
            elapsed=$((NOW - last_alert))
            if [[ $elapsed -ge $REMINDER_SECONDS ]]; then
                should_alert=true
                reason="still dry after $((elapsed / 3600))h"
            else
                reason="already alerted $((elapsed / 3600))h ago"
            fi
        fi

        if [[ "$should_alert" == "true" ]]; then
            echo -e "  ${RED}✗${RESET} $id ($plant) - ${moisture}% (below ${limit}%) → ALERT [$reason]"
            ALERT_LINES="${ALERT_LINES}  • ${plant} (${id}) — ${moisture}% (threshold ${limit}%)\\n"
            ALERT_COUNT=$((ALERT_COUNT + 1))
            ALERT_IDS="${ALERT_IDS}${id} "
        else
            echo -e "  ${YELLOW}✗${RESET} $id ($plant) - ${moisture}% (below ${limit}%) [$reason]"
        fi
    else
        if [[ -f "$state_file" ]] && awk -v m="$moisture" -v r="$rearm" 'BEGIN { exit !(m >= r) }'; then
            rm -f "$state_file"
            echo -e "  ${GREEN}✓${RESET} $id ($plant) - ${moisture}% → RECOVERED (re-armed)"
            RECOVERED_LINES="${RECOVERED_LINES}  • ${plant} (${id}) — back up to ${moisture}%\\n"
            RECOVERED_COUNT=$((RECOVERED_COUNT + 1))
        else
            echo -e "  ${GREEN}✓${RESET} $id ($plant) - ${moisture}% @ ${reading_time}"
        fi
    fi
done < <(jq -r '.sensors[] | [.id, .plant, (.thresholds.alert // "")] | @tsv' "$SENSORS_CONFIG")

echo ""
echo "────────────────────────────────────────────────────────────"
echo "Below threshold: ${DRY_COUNT} | New/reminder alerts: ${ALERT_COUNT} | Recovered: ${RECOVERED_COUNT}"
echo "════════════════════════════════════════════════════════════"

# ── Notify ───────────────────────────────────────────────────────────────────
send_alert() {
    local severity=$1 title=$2 message=$3 topic=$4
    if [[ -z "$SLACK_SCRIPT" || ! -x "$SLACK_SCRIPT" ]]; then
        log_error "send-slack-alert.sh not found or not executable"
        return 1
    fi
    local args=(--severity "$severity" --title "$title" --message "$message"
                --topic "$topic" --no-rate-limit)
    [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
    "$SLACK_SCRIPT" "${args[@]}"
}

EXIT_CODE=0
[[ $DRY_COUNT -gt 0 ]] && EXIT_CODE=1

if [[ "$NOTIFY" == "true" && $ALERT_COUNT -gt 0 ]]; then
    echo ""
    echo "Sending Slack alert for ${ALERT_COUNT} plant(s)..."
    plural="plant needs"; [[ $ALERT_COUNT -gt 1 ]] && plural="plants need"
    message="${ALERT_COUNT} ${plural} water:\\n${ALERT_LINES}"

    if send_alert "warning" "Soil Moisture Low" "$message" "$SLACK_TOPIC"; then
        # Stamp state only after a confirmed send, so a Slack outage does not
        # silently swallow the alert. Dry runs never write state.
        #
        # Only the plants NAMED in this message are stamped. A plant that was
        # suppressed ("already alerted 3h ago") keeps its original timestamp,
        # so an unrelated plant drying out cannot push its 24h reminder back.
        if [[ "$DRY_RUN" != "true" ]]; then
            for alerted_id in $ALERT_IDS; do
                echo "$NOW" > "${STATE_DIR}/dry-${alerted_id}.state"
            done
        fi
        echo -e "${GREEN}✓ Slack alert sent${RESET}"
    else
        echo -e "${YELLOW}⚠ Slack alert failed - will retry next run${RESET}"
    fi
fi

if [[ "$NOTIFY" == "true" && "$NOTIFY_RECOVERY" == "true" && $RECOVERED_COUNT -gt 0 ]]; then
    echo ""
    echo "Sending recovery notice for ${RECOVERED_COUNT} plant(s)..."
    rplural="plant is"; [[ $RECOVERED_COUNT -gt 1 ]] && rplural="plants are"
    message="${RECOVERED_COUNT} ${rplural} back above threshold:\\n${RECOVERED_LINES}"
    send_alert "success" "Soil Moisture Recovered" "$message" "${SLACK_TOPIC}-recovered" || true
fi

exit $EXIT_CODE
