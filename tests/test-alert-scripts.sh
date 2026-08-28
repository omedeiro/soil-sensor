#!/bin/bash
#
# test-alert-scripts.sh
# End-to-end tests for the Slack alerting path, with no Pi and no network.
#
# The two conditions that matter — "soil moisture is below 50%" and "the system
# is down" — are decided by shell logic that is otherwise only exercised in
# production, where a mistake is invisible (a missed alert looks exactly like a
# healthy system). These tests pin that logic down.
#
# Nothing is mocked at the script level. The real check-soil-moisture.sh,
# check-sensor-health.sh and send-slack-alert.sh run unmodified; what is
# replaced is `curl`, via a stub earlier on PATH that serves canned InfluxDB
# responses and captures the Slack payloads that would have been posted. So the
# Flux plumbing, the CSV parsing, the state machine, the rate limiting and the
# JSON escaping are all covered.
#
# Usage:
#   ./tests/test-alert-scripts.sh [--verbose]
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

PASS=0
FAIL=0
FAILED_NAMES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export STUB_DIR="$WORK/stub"
mkdir -p "$STUB_DIR" "$WORK/bin"

# ── The curl stub ────────────────────────────────────────────────────────────
# Serves three endpoints, chosen by URL:
#   .../health         InfluxDB health check
#   .../api/v2/query   Flux query — replies with the CSV in $STUB_DIR/query.csv
#   .../stub-slack     the Slack webhook — records the payload, replies 200
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
# Test double for curl. Never touches the network.
url=""
data=""
write_out=""
output_file=""
next=""
for arg in "$@"; do
    case "$next" in
        data)   data="$arg";        next=""; continue ;;
        w)      write_out="$arg";   next=""; continue ;;
        o)      output_file="$arg"; next=""; continue ;;
        skip)                       next=""; continue ;;
    esac
    case "$arg" in
        --data|-d)          next=data ;;
        -w|--write-out)     next=w ;;
        -o|--output)        next=o ;;
        --max-time|-H|-X|--retry) next=skip ;;
        -*)                 ;;
        http*)              url="$arg" ;;
    esac
done

emit_code() {
    # curl -w '%{http_code}' writes the code with no newline; influx-lib uses
    # -w $'\n%{http_code}' and takes the last line. Reproduce both faithfully.
    local code=$1
    case "$write_out" in
        '')  ;;
        *'%{http_code}'*) printf '%s' "${write_out//'%{http_code}'/$code}" ;;
    esac
}

case "$url" in
    *stub-slack*)
        # One file per payload: send-slack-alert.sh emits pretty-printed,
        # multi-line JSON, so payloads cannot share a line. The counter keeps
        # them in send order.
        mkdir -p "$STUB_DIR/slack"
        n=$(cat "$STUB_DIR/slack-count" 2>/dev/null || echo 0)
        n=$((n + 1))
        printf '%s' "$n" > "$STUB_DIR/slack-count"
        printf '%s' "$data" > "$STUB_DIR/slack/$(printf '%03d' "$n").json"
        [[ -n "$output_file" ]] && printf 'ok' > "$output_file"
        emit_code "${STUB_SLACK_HTTP:-200}"
        [[ "${STUB_SLACK_HTTP:-200}" == "200" ]] || exit 0
        exit 0
        ;;
    *"/health"*)
        # Two callers hit this path with different expectations: influx-lib's
        # influx_reachable reads the body, the watchdog probe reads
        # -w '%{http_code}'. Serve both.
        if [[ "${STUB_INFLUX_HEALTH:-pass}" == "pass" ]]; then
            body='{"name":"influxdb","message":"ready for queries and writes","status":"pass"}'
            if [[ -n "$output_file" ]]; then
                printf '%s' "$body" > "$output_file"
            else
                printf '%s' "$body"
            fi
            emit_code 200
            exit 0
        fi
        # Nothing listening: curl writes no body, reports 000, and exits 7.
        emit_code 000
        exit 7
        ;;
    *"/api/v2/query"*)
        code="${STUB_QUERY_HTTP:-200}"
        if [[ "$code" == "200" ]]; then
            cat "$STUB_DIR/query.csv" 2>/dev/null
        else
            printf '{"code":"unauthorized","message":"unauthorized access"}'
        fi
        emit_code "$code"
        exit 0
        ;;
    *)
        emit_code 404
        exit 0
        ;;
esac
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

# ── Fixture helpers ──────────────────────────────────────────────────────────

# set_readings "sensor-1=42@2" ... — value at N minutes old. A sensor left out
# is one InfluxDB returned nothing for, which is what the range() filter in
# each query does to a reading older than the window.
set_readings() {
    {
        echo '#datatype,string,long,dateTime:RFC3339,double,string'
        echo '#group,false,false,false,false,true'
        echo '#default,_result,,,,'
        echo ',result,table,_time,_value,device_id'
        local table=0
        for spec in "$@"; do
            local id="${spec%%=*}" rest="${spec#*=}"
            local value="${rest%%@*}" age="${rest##*@}"
            local ts
            ts=$(python3 -c "
import datetime, sys
t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=float(sys.argv[1]))
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))" "$age")
            echo ",,${table},${ts},${value},${id}"
            table=$((table + 1))
        done
    } > "$STUB_DIR/query.csv"
}

set_no_readings() {
    {
        echo '#datatype,string,long,dateTime:RFC3339,double,string'
        echo '#group,false,false,false,false,true'
        echo '#default,_result,,,,'
        echo ',result,table,_time,_value,device_id'
    } > "$STUB_DIR/query.csv"
}

reset_slack() {
    rm -rf "$STUB_DIR/slack" "$STUB_DIR/slack-count"
    mkdir -p "$STUB_DIR/slack"
}

slack_count() { find "$STUB_DIR/slack" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# Every payload is parsed with a strict JSON parser, so a message Slack would
# reject fails the test rather than passing a loose substring match.
slack_field() {
    python3 - "$STUB_DIR/slack" "$1" <<'FIELD'
import glob, json, os, sys
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    with open(path) as fh:
        attachment = json.load(fh)["attachments"][0]
    print(attachment["title"])
    if sys.argv[2] != "title":
        print(attachment["text"])
FIELD
}

# All attachment titles sent so far, newline separated.
slack_titles() { slack_field title; }

# The full title + text of every message sent so far.
slack_text() { slack_field all; }

# ── Environment shared by every case ─────────────────────────────────────────
# Deliberately short: check-secrets.sh flags any 32+ char token-shaped value.
export INFLUX_TOKEN="stub-token"
export INFLUX_URL="http://influx.invalid:8086"
export INFLUX_ORG="soil-monitoring"
export INFLUX_BUCKET="sensor-readings"
export SENSORS_CONFIG="${REPO_ROOT}/tests/fixtures/alerts/sensors-config.json"
export SLACK_WEBHOOK_URL="http://localhost/stub-slack"
export SLACK_SCRIPT="${REPO_ROOT}/scripts/send-slack-alert.sh"

MOISTURE="${REPO_ROOT}/rpi-setup/scripts/check-soil-moisture.sh"
HEALTH="${REPO_ROOT}/rpi-setup/scripts/check-sensor-health.sh"

# Each case gets clean state and rate-limit directories.
fresh_state() {
    rm -rf "$WORK/state" "$WORK/ratelimit"
    mkdir -p "$WORK/state" "$WORK/ratelimit"
    export MONITOR_STATE_DIR="$WORK/state"
    export RATE_LIMIT_DIR="$WORK/ratelimit"
    reset_slack
    unset STUB_INFLUX_HEALTH STUB_QUERY_HTTP STUB_SLACK_HTTP
}

LAST_OUTPUT=""
LAST_RC=0
run_check() {
    LAST_OUTPUT=$("$@" 2>&1)
    LAST_RC=$?
    if [[ "$VERBOSE" == "true" ]]; then
        printf '%s\n' "$LAST_OUTPUT" | sed 's/^/      /'
    fi
    return 0
}

# ── Assertions ───────────────────────────────────────────────────────────────
CASE=""
CASE_OK=true
CASE_MSGS=()

begin() { CASE="$1"; CASE_OK=true; CASE_MSGS=(); fresh_state; }

fail_case() { CASE_OK=false; CASE_MSGS+=("$1"); }

assert_eq() {
    local actual=$1 expected=$2 what=$3
    [[ "$actual" == "$expected" ]] || fail_case "$what: expected '$expected', got '$actual'"
}

assert_contains() {
    local haystack=$1 needle=$2 what=$3
    printf '%s' "$haystack" | grep -qF -- "$needle" \
        || fail_case "$what: expected to find '$needle'"
}

assert_not_contains() {
    local haystack=$1 needle=$2 what=$3
    printf '%s' "$haystack" | grep -qF -- "$needle" \
        && fail_case "$what: did not expect to find '$needle'"
    return 0
}

end() {
    if [[ "$CASE_OK" == "true" ]]; then
        echo -e "  ${GREEN}✓${NC} $CASE"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $CASE"
        for m in "${CASE_MSGS[@]}"; do echo -e "      ${RED}$m${NC}"; done
        if [[ "$VERBOSE" != "true" ]]; then
            echo -e "${DIM}      --- last script output ---${NC}"
            printf '%s\n' "$LAST_OUTPUT" | tail -25 | sed 's/^/      /'
        fi
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$CASE")
    fi
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Slack alerting — end-to-end tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Soil moisture below threshold${NC}"

# ─────────────────────────────────────────────────────────────────────────────
begin "every plant above 50% sends nothing"
set_readings "sensor-1=72@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_eq "$LAST_RC" 0 "exit code"
assert_eq "$(slack_count)" 0 "messages sent"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a plant below 50% alerts once and records state"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_eq "$LAST_RC" 1 "exit code"
assert_eq "$(slack_count)" 1 "messages sent"
assert_contains "$(slack_titles)" "Soil Moisture Low" "alert title"
assert_contains "$(slack_text)" "Rubber Tree" "the dry plant is named"
assert_contains "$(slack_text)" "42" "the reading is quoted"
assert_not_contains "$(slack_text)" "Monstera" "a healthy plant is not named"
[[ -f "$WORK/state/dry-sensor-1.state" ]] || fail_case "no state file written for sensor-1"
[[ -f "$WORK/state/dry-sensor-2.state" ]] && fail_case "state file written for a healthy plant"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a plant that stays dry is not re-alerted every run"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_eq "$(slack_count)" 1 "first run alerts"
reset_slack
run_check "$MOISTURE" --notify          # 30 minutes later, still dry
assert_eq "$LAST_RC" 1 "exit code stays 1 while dry"
assert_eq "$(slack_count)" 0 "second run is suppressed"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a dry plant is reminded once the reminder window elapses"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
reset_slack
# Backdate the alert by 25h; the default reminder cadence is 24h.
echo $(( $(date +%s) - 25 * 3600 )) > "$WORK/state/dry-sensor-1.state"
run_check "$MOISTURE" --notify
assert_eq "$(slack_count)" 1 "reminder sent"
assert_contains "$LAST_OUTPUT" "still dry after" "reminder reason logged"
end

# ─────────────────────────────────────────────────────────────────────────────
# Regression: stamping used to be applied to every dry plant whenever ANY alert
# went out, so one plant drying out pushed another plant's 24h reminder back.
begin "one plant drying out does not delay another plant's reminder"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify                    # sensor-1 alerts, state stamped
stamped_before=$(cat "$WORK/state/dry-sensor-1.state")
reset_slack
# 3h later sensor-2 goes dry too. sensor-1 is still dry but suppressed.
echo $(( $(date +%s) - 3 * 3600 )) > "$WORK/state/dry-sensor-1.state"
stamped_before=$(cat "$WORK/state/dry-sensor-1.state")
set_readings "sensor-1=42@2" "sensor-2=31@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_eq "$(slack_count)" 1 "one message for the newly dry plant"
assert_contains "$(slack_text)" "Monstera" "the newly dry plant is named"
assert_not_contains "$(slack_text)" "Rubber Tree" "the suppressed plant is not re-announced"
assert_eq "$(cat "$WORK/state/dry-sensor-1.state")" "$stamped_before" \
    "the suppressed plant's reminder clock"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "hysteresis: climbing just past the threshold does not re-arm"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
reset_slack
set_readings "sensor-1=52@2" "sensor-2=65@3" "sensor-3=80@1"   # above 50, below 55
run_check "$MOISTURE" --notify
assert_eq "$(slack_count)" 0 "no recovery message inside the hysteresis band"
[[ -f "$WORK/state/dry-sensor-1.state" ]] || fail_case "state cleared too early"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "watering past the hysteresis band re-arms and reports recovery"
set_readings "sensor-1=42@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
reset_slack
set_readings "sensor-1=58@2" "sensor-2=65@3" "sensor-3=80@1"   # above 55
run_check "$MOISTURE" --notify
assert_eq "$LAST_RC" 0 "exit code back to 0"
assert_eq "$(slack_count)" 1 "recovery message sent"
assert_contains "$(slack_titles)" "Soil Moisture Recovered" "recovery title"
[[ -f "$WORK/state/dry-sensor-1.state" ]] && fail_case "state file not cleared"
# Re-armed: the next dry-out alerts immediately rather than waiting 24h.
reset_slack
set_readings "sensor-1=41@2" "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_contains "$(slack_titles)" "Soil Moisture Low" "re-armed alert"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a per-plant threshold overrides the global one"
# sensor-3 has thresholds.alert = 60. 55% is fine globally, dry for this plant.
set_readings "sensor-1=72@2" "sensor-2=65@3" "sensor-3=55@1"
run_check "$MOISTURE" --notify
assert_eq "$LAST_RC" 1 "exit code"
assert_eq "$(slack_count)" 1 "messages sent"
assert_contains "$(slack_text)" "threshold 60" "the per-plant threshold is quoted"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a plant name containing quotes produces valid JSON"
set_readings "sensor-3=20@1"
run_check "$MOISTURE" --notify
assert_eq "$(slack_count)" 1 "messages sent"
# slack_text parses the payload with a strict JSON parser; if escaping were
# broken this would raise instead of returning the name.
assert_contains "$(slack_text)" 'Micro "Greens"' "the quoted plant name survives"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a silent sensor is not reported as a dry plant"
# InfluxDB returns nothing for sensor-1: its last reading is older than the
# query window. That is a health problem, not a watering problem.
set_readings "sensor-2=65@3" "sensor-3=80@1"
run_check "$MOISTURE" --notify
assert_eq "$LAST_RC" 0 "exit code"
assert_eq "$(slack_count)" 0 "messages sent"
assert_contains "$LAST_OUTPUT" "no reading in last" "the gap is logged"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "--dry-run sends nothing and writes no state"
set_readings "sensor-1=42@2"
run_check "$MOISTURE" --dry-run
assert_eq "$(slack_count)" 0 "nothing delivered"
assert_contains "$LAST_OUTPUT" "DRY RUN" "payload previewed"
[[ -f "$WORK/state/dry-sensor-1.state" ]] && fail_case "dry run wrote state"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a failed Slack delivery does not consume the alert"
set_readings "sensor-1=42@2"
STUB_SLACK_HTTP=500 run_check "$MOISTURE" --notify
[[ -f "$WORK/state/dry-sensor-1.state" ]] && fail_case "state stamped despite a failed send"
# With no state written, the next run tries again instead of going quiet.
run_check "$MOISTURE" --notify
assert_contains "$(slack_titles)" "Soil Moisture Low" "the alert is retried"
end

echo ""
echo -e "${BLUE}System down${NC}"

# ─────────────────────────────────────────────────────────────────────────────
begin "all sensors reporting sends nothing"
set_readings "sensor-1=72@2" "sensor-2=65@3" "sensor-3=80@1" "sensor-8=50@2"
run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 0 "exit code"
assert_eq "$(slack_count)" 0 "messages sent"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "InfluxDB unreachable is a system-down alert"
set_readings "sensor-1=72@2"
STUB_INFLUX_HEALTH=fail run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 2 "exit code"
assert_eq "$(slack_count)" 1 "messages sent"
assert_contains "$(slack_titles)" "System Down" "alert title"
assert_contains "$(slack_text)" "unreachable" "the cause is named"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a rejected read token is a system-down alert"
set_readings "sensor-1=72@2"
STUB_QUERY_HTTP=401 run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 2 "exit code"
assert_contains "$(slack_titles)" "System Down" "alert title"
assert_contains "$(slack_text)" "token" "an expired token is suggested"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "every sensor going silent is a system-down alert, not four sensor alerts"
set_no_readings
run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 2 "exit code"
assert_eq "$(slack_count)" 1 "one message, not one per sensor"
assert_contains "$(slack_titles)" "System Down" "alert title"
assert_contains "$(slack_text)" "stopped logging" "the cause is named"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "system down is reported once a day, not every ten minutes"
set_no_readings
run_check "$HEALTH" --notify
assert_eq "$(slack_count)" 1 "first run alerts"
run_check "$HEALTH" --notify
run_check "$HEALTH" --notify
assert_eq "$(slack_count)" 1 "later runs are rate limited"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "one silent sensor is a sensor alert, not a system-down alert"
set_readings "sensor-1=72@2" "sensor-3=80@1" "sensor-8=50@2"   # sensor-2 missing
run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 1 "exit code"
assert_eq "$(slack_count)" 1 "messages sent"
assert_contains "$(slack_titles)" "Sensor Not Logging" "alert title"
assert_not_contains "$(slack_titles)" "System Down" "not escalated to system down"
assert_contains "$(slack_text)" "sensor-2" "the silent sensor is named"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a stale reading counts as silent"
# Present in InfluxDB, but 45 minutes old against a 15-minute threshold.
set_readings "sensor-1=72@45" "sensor-2=65@3" "sensor-3=80@1" "sensor-8=50@2"
run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 1 "exit code"
assert_contains "$(slack_text)" "sensor-1" "the stale sensor is named"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a second sensor failing alerts immediately instead of being masked"
set_readings "sensor-1=72@2" "sensor-3=80@1" "sensor-8=50@2"   # sensor-2 down
run_check "$HEALTH" --notify
assert_eq "$(slack_count)" 1 "first alert"
run_check "$HEALTH" --notify
assert_eq "$(slack_count)" 1 "same set is suppressed"
set_readings "sensor-1=72@2" "sensor-8=50@2"                   # sensor-3 down too
run_check "$HEALTH" --notify
assert_eq "$(slack_count)" 2 "a changed offline set alerts again"
assert_contains "$(slack_text)" "sensor-3" "the newly failed sensor is named"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "recovery is reported after a system-down"
set_no_readings
run_check "$HEALTH" --notify
assert_contains "$(slack_titles)" "System Down" "outage alerted"
reset_slack
set_readings "sensor-1=72@2" "sensor-2=65@3" "sensor-3=80@1" "sensor-8=50@2"
run_check "$HEALTH" --notify
assert_eq "$LAST_RC" 0 "exit code"
assert_eq "$(slack_count)" 1 "recovery message sent"
assert_contains "$(slack_titles)" "Recovered" "recovery title"
end

# ─────────────────────────────────────────────────────────────────────────────
begin "a missing token is a configuration error, not a false all-clear"
set_readings "sensor-1=72@2"
LAST_OUTPUT=$(env -u INFLUX_TOKEN "$HEALTH" --notify 2>&1); LAST_RC=$?
assert_eq "$LAST_RC" 3 "exit code"
assert_eq "$(slack_count)" 0 "no message (systemd OnFailure reports this)"
end

echo ""
echo -e "${BLUE}Off-Pi watchdog probe${NC}"

PROBE="${REPO_ROOT}/scripts/check-system-online.sh"

begin "a healthy endpoint is up"
run_check "$PROBE" --url "http://localhost/health" --attempts 1 --interval 0 --timeout 1
assert_eq "$LAST_RC" 0 "exit code"
end

begin "a tunnel that cannot reach the Pi is down"
STUB_QUERY_HTTP=200 run_check env STUB_INFLUX_HEALTH=fail "$PROBE" \
    --url "http://localhost/health" --attempts 2 --interval 0 --timeout 1
assert_eq "$LAST_RC" 1 "exit code"
assert_contains "$LAST_OUTPUT" "SUMMARY=" "a summary line is emitted"
end

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}All ${PASS} checks passed${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    exit 0
fi
echo -e "  ${GREEN}Passed: ${PASS}${NC}   ${RED}Failed: ${FAIL}${NC}"
for name in "${FAILED_NAMES[@]}"; do echo -e "  ${RED}✗${NC} $name"; done
echo "═══════════════════════════════════════════════════════════════"
exit 1
