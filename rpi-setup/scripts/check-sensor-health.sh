#!/bin/bash
#
# check-sensor-health.sh
# Detects sensors that have stopped logging, and whole-system outages, and
# reports them to Slack at most once per day.
#
# Three distinct conditions are recognised:
#
#   1. SYSTEM DOWN   - InfluxDB is unreachable/unauthorised, or every single
#                      sensor has gone silent. Sent as a critical alert on its
#                      own topic; the per-sensor list is suppressed because the
#                      shared cause is what matters.
#   2. SENSOR DOWN   - One or more (but not all) sensors stopped logging.
#                      The rate-limit topic is derived from the *set* of
#                      offline sensors, so an additional sensor failing raises
#                      a fresh alert immediately rather than being masked by an
#                      earlier one.
#   3. RECOVERY      - Something that was previously down is reporting again.
#
# Both soil sensors (sensor_reading/moisture) and climate sensors
# (climate_reading/humidity) are checked.
#
# Usage:
#   ./check-sensor-health.sh [OPTIONS]
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/influx-lib.sh
source "${SCRIPT_DIR}/lib/influx-lib.sh"

# ── Configuration ────────────────────────────────────────────────────────────
SENSORS_CONFIG="${SENSORS_CONFIG:-/home/omedeiro/soil-sensor/sensors-config.json}"
STATE_DIR="${MONITOR_STATE_DIR:-}"
SLACK_SCRIPT="${SLACK_SCRIPT:-}"

ALERT_THRESHOLD_MINUTES=15
LOOKBACK_HOURS=24
RATE_LIMIT_SECONDS=86400      # max one alert per day, per the same condition
CHECK_QUALITY=false
ENABLE_NOTIFICATIONS=false
NOTIFY_RECOVERY=true
DRY_RUN=false
VERBOSE=false
SLACK_TOPIC="sensor-health"
HEARTBEAT_URL="${HEARTBEAT_URL:-}"

GREEN='\033[92m'; YELLOW='\033[93m'; RED='\033[91m'; BLUE='\033[94m'; RESET='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Detect sensors that stopped logging and whole-system outages, and alert Slack
at most once per day per condition.

OPTIONS:
    --alert-minutes N      Consider a sensor down after N minutes of silence
                           (default: 15)
    --lookback-hours N     How far back to look for a last reading (default: 24)
    --rate-limit-seconds N Suppression window per condition (default: 86400 = 1/day)
    --check-quality        Enable data quality validation (stuck sensors)
    --notify               Send Slack notifications
    --no-recovery-notice   Do not send "recovered" notifications
    --slack-topic TOPIC    Base rate-limit topic (default: sensor-health)
    --heartbeat-url URL    Ping this URL on every successful check (dead-man
                           switch, e.g. healthchecks.io) so an external service
                           can detect the Pi itself going offline
    --dry-run              Show what would be sent without sending
    --verbose              Show detailed output
    --help                 Show this help message

CONFIGURATION:
    INFLUX_TOKEN must be set (read permission on the sensor-readings bucket).
    Sensors are auto-detected from: \$SENSORS_CONFIG

EXIT CODES:
    0   All sensors healthy
    1   One or more sensors offline
    2   InfluxDB connection error (system down)
    3   Configuration error
EOF
    exit 0
}

log_info() { [[ "$VERBOSE" == "true" ]] && echo -e "[$(date +'%H:%M:%S')] ${BLUE}INFO:${RESET} $*" >&2 || true; }
log_error() { echo -e "[$(date +'%H:%M:%S')] ${RED}ERROR:${RESET} $*" >&2; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --alert-minutes)      ALERT_THRESHOLD_MINUTES="$2"; shift 2 ;;
        --lookback-hours)     LOOKBACK_HOURS="$2"; shift 2 ;;
        --rate-limit-seconds) RATE_LIMIT_SECONDS="$2"; shift 2 ;;
        --check-quality)      CHECK_QUALITY=true; shift ;;
        --notify)             ENABLE_NOTIFICATIONS=true; shift ;;
        --no-recovery-notice) NOTIFY_RECOVERY=false; shift ;;
        --slack-topic)        SLACK_TOPIC="$2"; shift 2 ;;
        --heartbeat-url)      HEARTBEAT_URL="$2"; shift 2 ;;
        --dry-run)            DRY_RUN=true; ENABLE_NOTIFICATIONS=true; shift ;;
        --verbose)            VERBOSE=true; shift ;;
        --help)               usage ;;
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

DOWN_STATE="${STATE_DIR}/sensors-down.state"

# ── Notification helper ──────────────────────────────────────────────────────
send_alert() {
    local severity=$1 title=$2 message=$3 topic=$4

    if [[ "$ENABLE_NOTIFICATIONS" != "true" ]]; then
        return 0
    fi
    if [[ -z "$SLACK_SCRIPT" || ! -x "$SLACK_SCRIPT" ]]; then
        log_error "send-slack-alert.sh not found or not executable"
        return 1
    fi

    local args=(--severity "$severity" --title "$title" --message "$message"
                --topic "$topic" --rate-limit-seconds "$RATE_LIMIT_SECONDS")
    [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)

    "$SLACK_SCRIPT" "${args[@]}"
    local rc=$?
    case $rc in
        0) echo -e "${GREEN}✓ Slack notification sent${RESET}" ;;
        2) echo -e "${BLUE}· Suppressed (already alerted within the rate-limit window)${RESET}" ;;
        *) echo -e "${YELLOW}⚠ Slack delivery failed (rc=$rc) - will retry next run${RESET}" ;;
    esac
    return $rc
}

# Report a total outage, record it, and exit.
system_down() {
    local reason=$1 detail=$2

    echo ""
    echo -e "${RED}✗ SYSTEM DOWN: ${reason}${RESET}"
    echo "  $detail"

    send_alert "critical" "Soil Monitoring System Down" \
        "${reason}\\n\\n${detail}\\n\\nSensor data is not being collected." \
        "${SLACK_TOPIC}-system-down" || true

    echo "system-down" > "$DOWN_STATE"
    exit 2
}

# ── Preconditions ────────────────────────────────────────────────────────────
[[ -z "$INFLUX_TOKEN" ]] && { log_error "INFLUX_TOKEN not set"; exit 3; }
command -v jq > /dev/null 2>&1 || { log_error "'jq' not found (sudo apt-get install jq)"; exit 3; }
[[ -f "$SENSORS_CONFIG" ]] || { log_error "Sensors config not found: $SENSORS_CONFIG"; exit 3; }

# Portable RFC3339 -> epoch seconds (GNU date on the Pi, BSD date on macOS).
rfc3339_to_epoch() {
    local ts=${1%%.*}
    ts=${ts%Z}
    date -u -d "${ts}Z" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null \
        || echo 0
}

human_age() {
    local secs=$1
    if   [[ $secs -lt 3600 ]]; then echo "$((secs / 60))m"
    elif [[ $secs -lt 86400 ]]; then echo "$((secs / 3600))h $(((secs % 3600) / 60))m"
    else echo "$((secs / 86400))d $(((secs % 86400) / 3600))h"
    fi
}

echo "════════════════════════════════════════════════════════════"
echo "Sensor Health Check - $(date +'%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════"
echo "InfluxDB:        $INFLUX_URL"
echo "Bucket:          $INFLUX_BUCKET"
echo "Alert Threshold: ${ALERT_THRESHOLD_MINUTES} minutes of silence"
echo "Rate limit:      one alert per condition per $((RATE_LIMIT_SECONDS / 3600))h"
echo ""

# ── 1. Is the monitoring system itself alive? ────────────────────────────────
if ! influx_reachable; then
    system_down "InfluxDB is unreachable at ${INFLUX_URL}" \
        "The database did not answer its health check. Grafana dashboards will show No Data."
fi
echo -e "${GREEN}✓ InfluxDB Connection: OK${RESET}"

# ── 2. Fetch the last reading for every sensor ───────────────────────────────
FLUX="union(tables: [
  from(bucket: \"${INFLUX_BUCKET}\")
    |> range(start: -${LOOKBACK_HOURS}h)
    |> filter(fn: (r) => r._measurement == \"sensor_reading\" and r._field == \"moisture\"),
  from(bucket: \"${INFLUX_BUCKET}\")
    |> range(start: -${LOOKBACK_HOURS}h)
    |> filter(fn: (r) => r._measurement == \"climate_reading\" and r._field == \"humidity\")
])
  |> group(columns: [\"device_id\"])
  |> last()
  |> keep(columns: [\"device_id\", \"_time\", \"_value\"])"

if ! CSV=$(influx_query "$FLUX"); then
    system_down "InfluxDB query failed" \
        "The health check could not read from the '${INFLUX_BUCKET}' bucket. This usually means an invalid or expired read token."
fi
echo -e "${GREEN}✓ Token Validation: OK${RESET}"
echo ""

LAST_SEEN=$(influx_csv_extract "$CSV" device_id _time _value)

# ── 3. Evaluate each configured sensor ───────────────────────────────────────
NOW=$(date -u +%s)
THRESHOLD_SECONDS=$((ALERT_THRESHOLD_MINUTES * 60))

OFFLINE_IDS=""
OFFLINE_LINES=""
OFFLINE_COUNT=0
ONLINE_COUNT=0
TOTAL_COUNT=0

echo "Sensor Status (silent for more than ${ALERT_THRESHOLD_MINUTES} min = down)"
echo "────────────────────────────────────────────────────────────"

while IFS=$'\t' read -r id label kind; do
    [[ -z "$id" ]] && continue
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    row=$(printf '%s\n' "$LAST_SEEN" | awk -F'\t' -v d="$id" '$1 == d {print; exit}')

    if [[ -z "$row" ]]; then
        OFFLINE_COUNT=$((OFFLINE_COUNT + 1))
        OFFLINE_IDS="${OFFLINE_IDS}${id} "
        OFFLINE_LINES="${OFFLINE_LINES}  • ${id} (${label}) — no data in ${LOOKBACK_HOURS}h\\n"
        echo -e "  ${RED}✗${RESET} $id ($label) [$kind] - NO DATA in last ${LOOKBACK_HOURS}h"
        continue
    fi

    ts=$(printf '%s' "$row" | cut -f2)
    epoch=$(rfc3339_to_epoch "$ts")
    age=$((NOW - epoch))
    [[ $age -lt 0 ]] && age=0

    if [[ $epoch -eq 0 ]]; then
        echo -e "  ${YELLOW}?${RESET} $id ($label) - unparseable timestamp: $ts"
        ONLINE_COUNT=$((ONLINE_COUNT + 1))
        continue
    fi

    if [[ $age -gt $THRESHOLD_SECONDS ]]; then
        OFFLINE_COUNT=$((OFFLINE_COUNT + 1))
        OFFLINE_IDS="${OFFLINE_IDS}${id} "
        OFFLINE_LINES="${OFFLINE_LINES}  • ${id} (${label}) — last reading $(human_age $age) ago\\n"
        echo -e "  ${RED}✗${RESET} $id ($label) [$kind] - silent for $(human_age $age)"
    else
        ONLINE_COUNT=$((ONLINE_COUNT + 1))
        echo -e "  ${GREEN}✓${RESET} $id ($label) [$kind] - last reading $(human_age $age) ago"
    fi
done < <(jq -r '
    ((.sensors // [])[]         | [.id, .plant, "soil"]    | @tsv),
    ((.climate_sensors // [])[] | [.id, .label, "climate"] | @tsv)
' "$SENSORS_CONFIG")

if [[ $TOTAL_COUNT -eq 0 ]]; then
    log_error "No sensors found in $SENSORS_CONFIG"
    exit 3
fi

echo ""
echo "Summary"
echo "────────────────────────────────────────────────────────────"
echo -e "${GREEN}✓ Online:${RESET}  ${ONLINE_COUNT}/${TOTAL_COUNT} sensors"
[[ $OFFLINE_COUNT -gt 0 ]] && echo -e "${RED}✗ Offline:${RESET} ${OFFLINE_COUNT}/${TOTAL_COUNT} sensors"
echo "════════════════════════════════════════════════════════════"

# ── 4. Whole-system outage: every sensor has gone silent ─────────────────────
if [[ $OFFLINE_COUNT -eq $TOTAL_COUNT ]]; then
    system_down "All ${TOTAL_COUNT} sensors have stopped logging" \
        "InfluxDB is reachable but no sensor has reported in over ${ALERT_THRESHOLD_MINUTES} minutes. Likely causes: WiFi/router outage, power loss to the sensors, or an InfluxDB write-token problem."
fi

# ── 5. Data quality (optional) ───────────────────────────────────────────────
if [[ "$CHECK_QUALITY" == "true" ]]; then
    echo ""
    echo "Data Quality Validation (stuck sensors, last 1h)"
    echo "────────────────────────────────────────────────────────────"

    Q_FLUX="from(bucket: \"${INFLUX_BUCKET}\")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == \"sensor_reading\" and r._field == \"moisture\")
  |> group(columns: [\"device_id\"])
  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)
  |> stddev()
  |> keep(columns: [\"device_id\", \"_value\"])"

    if Q_CSV=$(influx_query "$Q_FLUX"); then
        while IFS=$'\t' read -r qid qstd; do
            [[ -z "$qid" ]] && continue
            if awk -v s="$qstd" 'BEGIN { exit !(s == s + 0 && s < 0.5) }' 2>/dev/null; then
                echo -e "  ${YELLOW}⚠${RESET} $qid: potentially stuck (stddev $qstd)"
            else
                echo -e "  ${GREEN}✓${RESET} $qid: normal variation (stddev $qstd)"
            fi
        done < <(influx_csv_extract "$Q_CSV" device_id _value)
    else
        echo -e "  ${YELLOW}⚠ Unable to check data quality${RESET}"
    fi
fi

# ── 6. Notify ────────────────────────────────────────────────────────────────
PREV_DOWN=""
[[ -f "$DOWN_STATE" ]] && PREV_DOWN=$(cat "$DOWN_STATE" 2>/dev/null || echo "")

# Normalise the offline set so the rate-limit topic is stable regardless of
# the order sensors were evaluated in. OFFLINE_SET is the human-readable,
# space-separated list; OFFLINE_KEY is the filesystem-safe topic suffix.
OFFLINE_SET=$(printf '%s' "$OFFLINE_IDS" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ' | sed 's/ $//')
OFFLINE_KEY=$(printf '%s' "$OFFLINE_SET" | tr ' ' '_')

if [[ $OFFLINE_COUNT -gt 0 ]]; then
    echo ""
    verb="has"; [[ $OFFLINE_COUNT -gt 1 ]] && verb="have"
    message="${OFFLINE_COUNT} of ${TOTAL_COUNT} sensors ${verb} stopped logging:\\n${OFFLINE_LINES}\\nNo data received for more than ${ALERT_THRESHOLD_MINUTES} minutes."

    # Topic includes the offline set: a NEW sensor failing alerts right away
    # instead of being masked by an earlier alert's daily window.
    send_alert "warning" "Sensor Not Logging" "$message" \
        "${SLACK_TOPIC}-down-${OFFLINE_KEY}" || true

    [[ "$DRY_RUN" != "true" ]] && printf '%s' "$OFFLINE_SET" > "$DOWN_STATE"

elif [[ -n "$PREV_DOWN" ]]; then
    echo ""
    if [[ "$NOTIFY_RECOVERY" == "true" ]]; then
        if [[ "$PREV_DOWN" == "system-down" ]]; then
            send_alert "success" "Soil Monitoring System Recovered" \
                "All ${TOTAL_COUNT} sensors are logging again." \
                "${SLACK_TOPIC}-recovered" || true
        else
            send_alert "success" "Sensors Recovered" \
                "All ${TOTAL_COUNT} sensors are logging again (previously down: ${PREV_DOWN// /, })." \
                "${SLACK_TOPIC}-recovered" || true
        fi
    fi
    [[ "$DRY_RUN" != "true" ]] && rm -f "$DOWN_STATE"
fi

# ── 7. Dead-man heartbeat ────────────────────────────────────────────────────
# Pinged only on a completed check. If the Pi loses power or network, the ping
# stops and the external watchdog raises the alert that this host cannot.
if [[ -n "$HEARTBEAT_URL" && "$DRY_RUN" != "true" ]]; then
    if curl -fsS --max-time 10 --retry 2 "$HEARTBEAT_URL" > /dev/null 2>&1; then
        log_info "Heartbeat ping sent"
    else
        log_error "Heartbeat ping failed: $HEARTBEAT_URL"
    fi
fi

[[ $OFFLINE_COUNT -gt 0 ]] && exit 1
exit 0
