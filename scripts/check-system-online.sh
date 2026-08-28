#!/bin/bash
#
# check-system-online.sh
# Probe the soil monitoring system from OUTSIDE the Raspberry Pi.
#
# Everything in rpi-setup/scripts runs ON the Pi, so none of it can report the
# Pi being dead: if the power, the SD card, or the network goes, the alerts
# simply stop arriving. This script is the other half — it runs somewhere else
# (GitHub Actions, a laptop, any host with internet) and probes the public
# Grafana endpoint served through the Cloudflare Tunnel.
#
# A single failed request is not an outage: Cloudflare hiccups, DNS blips and
# transient 5xx are common. The default is 3 attempts spaced 30s apart, and the
# system is only reported down when every attempt fails.
#
# Usage:
#   ./scripts/check-system-online.sh [OPTIONS]
#
# The final line of stdout is always "SUMMARY=<one-line description>", so a
# caller can quote it straight into an alert message.
#

set -uo pipefail

URL="${WATCHDOG_URL:-https://soil.owenmedeiros.com/api/health}"
ATTEMPTS=3
INTERVAL=30
TIMEOUT=15

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Probe the public Grafana endpoint to detect the whole Pi being offline.

OPTIONS:
    --url URL           Endpoint to probe (default: \$WATCHDOG_URL or
                        https://soil.owenmedeiros.com/api/health)
    --attempts N        Consecutive failures required to declare an outage
                        (default: 3)
    --interval SECONDS  Delay between attempts (default: 30)
    --timeout SECONDS   Per-request timeout (default: 15)
    --help              Show this help message

WHAT COUNTS AS UP:
    200          Grafana answered its health check.
    401/403      Grafana answered but wants credentials. The Pi, the tunnel
                 and Grafana are all alive, which is what this probe is for,
                 so this counts as UP (anonymous access may simply be off).

WHAT COUNTS AS DOWN:
    000          No response at all - DNS, TLS or connection failure.
    502/503/504  Cloudflare is up but cannot reach the tunnel: the Pi is
                 offline, or cloudflared is not running.
    5xx, other   Grafana is broken or something else is answering.

EXIT CODES:
    0   System is online
    1   System is down (every attempt failed)
    3   Configuration error
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --url)      URL="$2"; shift 2 ;;
        --attempts) ATTEMPTS="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --timeout)  TIMEOUT="$2"; shift 2 ;;
        --help)     usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

command -v curl > /dev/null 2>&1 || { echo "ERROR: 'curl' not found" >&2; exit 3; }
[[ "$ATTEMPTS" =~ ^[0-9]+$ && "$ATTEMPTS" -ge 1 ]] || { echo "ERROR: --attempts must be a positive integer" >&2; exit 3; }
[[ -n "$URL" ]] || { echo "ERROR: no URL to probe" >&2; exit 3; }

# Describe an HTTP status in terms of what it says about the Pi.
describe_code() {
    case "$1" in
        000) echo "no response (DNS, TLS or connection failure)" ;;
        502|503|504) echo "HTTP $1 — Cloudflare cannot reach the tunnel; the Pi is offline or cloudflared is down" ;;
        5*)  echo "HTTP $1 — Grafana is answering but unhealthy" ;;
        *)   echo "HTTP $1" ;;
    esac
}

echo "Probing $URL (${ATTEMPTS} attempts, ${INTERVAL}s apart, ${TIMEOUT}s timeout)" >&2

LAST_CODE=""
attempt=1
while [[ $attempt -le $ATTEMPTS ]]; do
    # curl already writes "000" for a request that never got a response, and
    # exits non-zero as well; normalise anything unexpected to the same value.
    LAST_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL" 2>/dev/null)
    [[ "$LAST_CODE" =~ ^[0-9]{3}$ ]] || LAST_CODE="000"

    case "$LAST_CODE" in
        200)
            echo "  attempt ${attempt}/${ATTEMPTS}: HTTP 200 — healthy" >&2
            echo "SUMMARY=Grafana answered its health check at ${URL} (HTTP 200)."
            exit 0
            ;;
        401|403)
            echo "  attempt ${attempt}/${ATTEMPTS}: HTTP ${LAST_CODE} — reachable, authentication required" >&2
            echo "SUMMARY=Grafana is reachable at ${URL} (HTTP ${LAST_CODE}: answering but requires authentication)."
            exit 0
            ;;
        *)
            echo "  attempt ${attempt}/${ATTEMPTS}: $(describe_code "$LAST_CODE")" >&2
            ;;
    esac

    if [[ $attempt -lt $ATTEMPTS ]]; then
        sleep "$INTERVAL"
    fi
    attempt=$((attempt + 1))
done

echo "SUMMARY=${URL} failed ${ATTEMPTS} consecutive probes — last result: $(describe_code "$LAST_CODE")."
exit 1
