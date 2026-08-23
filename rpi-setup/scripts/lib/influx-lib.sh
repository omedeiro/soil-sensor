#!/bin/bash
#
# influx-lib.sh
# Shared InfluxDB query helpers for soil-sensor monitoring scripts.
#
# Source this from a script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/influx-lib.sh"
#
# Expects (environment or caller-set):
#   INFLUX_URL     default http://localhost:8086
#   INFLUX_ORG     default soil-monitoring
#   INFLUX_BUCKET  default sensor-readings
#   INFLUX_TOKEN   required (read permission)
#

INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"
INFLUX_TIMEOUT="${INFLUX_TIMEOUT:-15}"

# influx_reachable
# Returns 0 if the InfluxDB /health endpoint answers "pass", 1 otherwise.
influx_reachable() {
    local body
    body=$(curl -s --max-time 5 "${INFLUX_URL}/health" 2>/dev/null) || return 1
    [[ "$body" == *'"status":"pass"'* ]] || [[ "$body" == *'"status": "pass"'* ]]
}

# influx_query <flux>
# Runs a Flux query, echoes raw annotated CSV on stdout.
# Returns 0 on success, 2 on transport/auth failure.
influx_query() {
    local flux=$1
    local response http_code

    response=$(curl -s --max-time "$INFLUX_TIMEOUT" \
        -w $'\n%{http_code}' \
        -XPOST "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
        -H "Authorization: Token ${INFLUX_TOKEN}" \
        -H "Content-Type: application/vnd.flux" \
        -H "Accept: application/csv" \
        -d "${flux}" 2>&1) || {
        echo "influx_query: curl failed: ${response}" >&2
        return 2
    }

    http_code=$(printf '%s' "$response" | tail -n1)
    response=$(printf '%s' "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        echo "influx_query: HTTP ${http_code}: ${response}" >&2
        return 2
    fi

    printf '%s\n' "$response"
    return 0
}

# influx_csv_extract <csv> <col1> [col2 ...]
# Parses InfluxDB annotated CSV and emits the requested columns, tab-separated,
# one row per data record. Column positions are resolved from each header row,
# so this does NOT depend on InfluxDB's column ordering.
# Rows missing any requested column are skipped.
influx_csv_extract() {
    local csv=$1
    shift
    local want="$*"

    printf '%s\n' "$csv" | awk -v want="$want" '
        BEGIN {
            FS = ","
            nwant = split(want, wanted, " ")
        }
        # Strip CR from CRLF line endings
        { sub(/\r$/, "") }
        # Annotation lines (#datatype, #group, #default) reset the header
        /^#/ { have_header = 0; next }
        /^[[:space:]]*$/ { next }
        {
            if (!have_header) {
                for (i = 1; i <= NF; i++) {
                    col[$i] = i
                }
                have_header = 1
                next
            }
            out = ""
            for (w = 1; w <= nwant; w++) {
                name = wanted[w]
                if (!(name in col)) next
                idx = col[name]
                if (idx > NF) next
                out = (w == 1) ? $idx : out "\t" $idx
            }
            print out
        }
    '
}
