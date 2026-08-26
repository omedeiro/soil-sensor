#!/usr/bin/env bash
# flash-when-ready.sh — wait for a hung/rebooting board to start answering
# ArduinoOTA, then flash it with flash-fleet.sh.
#
# A hung ESP8266 answers ICMP (the SDK services it in interrupt context) while
# loop() is blocked, so ping is NOT a readiness signal. The real signal is an
# ArduinoOTA reply on UDP/8266: that handler only runs from loop().
#
#   ./flash-when-ready.sh sensor-8 [sensor-5 ...]     # default: 20 min per device

set -uo pipefail
cd "$(dirname "$0")"
TIMEOUT_S="${TIMEOUT_S:-1200}"
[ $# -ge 1 ] || { echo "usage: $0 <device-id> [device-id...]"; exit 2; }

ip_of() { jq -r --arg id "$1" '(.sensors + (.climate_sensors // []))[] | select(.id==$id) | .ip' ../sensors-config.json; }

ota_alive() {
  python3 - "$1" <<'PY'
import socket,sys
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(3)
try:
    s.sendto(b"0 4200 1024 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",(sys.argv[1],8266))
    s.recvfrom(128); sys.exit(0)
except Exception:
    sys.exit(1)
finally:
    s.close()
PY
}

for id in "$@"; do
  ip="$(ip_of "$id")"
  if [ -z "$ip" ]; then echo "[$id] not in sensors-config.json"; continue; fi
  echo "[$id] $ip — waiting up to $((TIMEOUT_S/60))m for the OTA handler..."
  waited=0; ready=0
  while [ "$waited" -lt "$TIMEOUT_S" ]; do
    if ota_alive "$ip"; then ready=1; break; fi
    sleep 10; waited=$((waited+10))
    [ $((waited % 60)) -eq 0 ] && echo "  [$id] still hung after ${waited}s"
  done
  if [ "$ready" -eq 0 ]; then
    echo "[$id] never answered OTA — needs a power cycle, or USB reflash if it already had one"
    continue
  fi
  echo "[$id] OTA is alive — flashing"
  ./flash-fleet.sh --only "$id"
done
