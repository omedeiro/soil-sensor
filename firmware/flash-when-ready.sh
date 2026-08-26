#!/usr/bin/env bash
# flash-when-ready.sh — wait for a hung/rebooting board to start answering
# ArduinoOTA, then flash it with flash-fleet.sh.
#
# A hung ESP8266 answers ICMP (the SDK services it in interrupt context) while
# loop() is blocked, so ping is NOT a readiness signal.
#
# Readiness here is a TCP connect to port 80. The sketch's web server only
# accepts once loop() is running, so an open port 80 proves the same thing an
# OTA reply would - but PASSIVELY.
#
# Do NOT probe readiness by sending an ArduinoOTA invitation. That is not a
# ping: "0 <port> <size> <md5>" opens a real OTA session, the device answers
# AUTH <nonce> and then waits. Abandoning that handshake leaves the handler
# tied up, and the genuine espota.py invitation that follows gets no answer:
#     [INFO]: Sending invitation to: 192.168.99.182
#     [ERROR]: No Answer
# The probe breaks the flash it is meant to enable.
#
#   ./flash-when-ready.sh sensor-8 [sensor-5 ...]     # default: 20 min per device

set -uo pipefail
cd "$(dirname "$0")"
TIMEOUT_S="${TIMEOUT_S:-1200}"
[ $# -ge 1 ] || { echo "usage: $0 <device-id> [device-id...]"; exit 2; }

ip_of() { jq -r --arg id "$1" '(.sensors + (.climate_sensors // []))[] | select(.id==$id) | .ip' ../sensors-config.json; }

sketch_alive() {
  python3 - "$1" <<'PROBE'
import socket, sys
s = socket.socket(); s.settimeout(3)
try:
    s.connect((sys.argv[1], 80))   # web server only accepts once loop() runs
    sys.exit(0)
except Exception:
    sys.exit(1)
finally:
    s.close()
PROBE
}

for id in "$@"; do
  ip="$(ip_of "$id")"
  if [ -z "$ip" ]; then echo "[$id] not in sensors-config.json"; continue; fi
  echo "[$id] $ip — waiting up to $((TIMEOUT_S/60))m for the sketch (tcp/80)..."
  waited=0; ready=0
  while [ "$waited" -lt "$TIMEOUT_S" ]; do
    if sketch_alive "$ip"; then ready=1; break; fi
    sleep 10; waited=$((waited+10))
    [ $((waited % 60)) -eq 0 ] && echo "  [$id] still hung after ${waited}s"
  done
  if [ "$ready" -eq 0 ]; then
    echo "[$id] tcp/80 never opened — sketch still hung; power cycle, or USB reflash if it already had one"
    continue
  fi
  echo "[$id] sketch is alive — settling 5s, then flashing"
  sleep 5
  ./flash-fleet.sh --only "$id"
done
