#!/usr/bin/env bash
# flash-fleet.sh — safe per-sensor OTA deployment for the whole fleet.
#
# Replaces flash-ota-canary.sh, which had four defects that made it unusable or
# actively destructive:
#
#   1. It built ONE binary and flashed it to every sensor, while DEVICE_ID is a
#      per-sensor #define in config.h. Every sensor would have been stamped with
#      the same id, collapsing per-plant history. This script rebuilds per sensor
#      and passes identity via -D (config.h now #ifndef-guards those defines, so
#      the flag actually wins — without the guard the header silently overrides it).
#   2. It ran `pio run --target upload` with no -e, so it did not select the
#      espota environment. This script uses -e esp8266-ota explicitly.
#   3. It read only .sensors[] from sensors-config.json, so the two climate units
#      (sensor-8, sensor-9) were never flashed. This script reads both arrays.
#   4. It used `declare -A`, which macOS's bash 3.2 does not support, so it could
#      not run on the machine it ships to. No associative arrays here.
#
# It also verifies the real success signal: that the sensor WROTE to InfluxDB
# after rebooting, not merely that it pinged.
#
# Usage:
#   ./flash-fleet.sh                 # canary first, confirm, then the rest
#   ./flash-fleet.sh --only sensor-3 # single device
#   ./flash-fleet.sh --dry-run       # show the plan, build nothing

set -uo pipefail
cd "$(dirname "$0")"

CONFIG=../sensors-config.json
CANARY=sensor-7
PI=omedeiro@192.168.99.134
ENVNAME=esp8266-ota
SETTLE_SECONDS=90          # sensors publish every 300s; allow one cycle + slack
ONLY=""; DRYRUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

command -v jq  >/dev/null || { echo "jq is required"; exit 1; }
command -v pio >/dev/null || { echo "platformio (pio) is required"; exit 1; }
[ -f "$CONFIG" ] || { echo "not found: $CONFIG"; exit 1; }

# OTA password comes from secrets.h (gitignored), never from platformio.ini.
OTA_PASSWORD="${OTA_PASSWORD:-$(sed -n 's/.*#define[[:space:]]*OTA_PASSWORD[[:space:]]*"\(.*\)".*/\1/p' src/secrets.h 2>/dev/null | head -1)}"
[ -n "$OTA_PASSWORD" ] || { echo "OTA_PASSWORD not found in src/secrets.h and not in the environment"; exit 1; }
export OTA_PASSWORD

# During a password rotation the board is still RUNNING the old password, so the
# upload must authenticate with that while the new one is compiled in. Set
# OTA_AUTH_PASSWORD=<old> for the rotation pass; afterwards leave it unset and it
# tracks OTA_PASSWORD.
OTA_AUTH_PASSWORD="${OTA_AUTH_PASSWORD:-$OTA_PASSWORD}"
export OTA_AUTH_PASSWORD
if [ "$OTA_AUTH_PASSWORD" != "$OTA_PASSWORD" ]; then
  echo "NOTE: rotating OTA password — authenticating with the old one, compiling in the new one."
fi

# "id<TAB>location<TAB>ip" for soil probes AND climate units.
# id<TAB>location<TAB>ip<TAB>type. Type is derived from WHICH array the device is
# in: .sensors[] are soil probes, .climate_sensors[] are DHT boards. Getting this
# wrong compiles out the wrong sensor path and the board reports nothing.
DEVICES="$(jq -r '(.sensors[] | [.id,.location,.ip,"soil"]), ((.climate_sensors // [])[] | [.id,.location,.ip,"climate"]) | @tsv' "$CONFIG" | sort)"
[ -n "$DEVICES" ] || { echo "no devices in $CONFIG"; exit 1; }

echo "=== Fleet ==="
printf '%s\n' "$DEVICES" | while IFS=$'\t' read -r id loc ip typ; do printf "  %-10s %-13s %-16s %s\n" "$id" "$loc" "$ip" "$typ"; done
echo "  total: $(printf '%s\n' "$DEVICES" | wc -l | tr -d ' ')"
echo

# Read token lives on the Pi. The firmware's token is WRITE-ONLY and cannot be
# used to verify anything, so read back through the Pi instead.
read_token() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$PI" \
    'grep -m1 "^INFLUX_TOKEN=" /mnt/sensor-data/config/panel-health.env | cut -d= -f2- | tr -d "\"'"'"'"' 2>/dev/null
}

# Newest epoch-seconds this device has in InfluxDB, or 0.
last_write_epoch() {
  local id="$1" tok="$2"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$PI" "curl -s -X POST \
    'http://localhost:8086/api/v2/query?org=soil-monitoring' \
    -H 'Authorization: Token $tok' -H 'Content-Type: application/vnd.flux' \
    -H 'Accept: application/csv' \
    -d 'from(bucket:\"sensor-readings\") |> range(start:-2h) |> filter(fn:(r)=> r.device_id==\"$id\") |> keep(columns:[\"_time\"]) |> group() |> max(column:\"_time\")'" 2>/dev/null \
    | tr -d '\r' | awk -F, 'NF>3 && $0 !~ /result,table/ {print $NF}' | tail -1 \
    | python3 -c "
import sys,datetime
v=sys.stdin.read().strip()
if not v: print(0)
else:
    try: print(int(datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()))
    except Exception: print(0)
"
}

flash_one() {
  local id="$1" loc="$2" ip="$3" typ="$4"
  local dtype
  if [ "$typ" = "climate" ]; then dtype=1; else dtype=0; fi
  echo "--- $id ($loc, $typ) at $ip ---"

  if ! ping -c 1 -W 2000 "$ip" >/dev/null 2>&1; then
    echo "  SKIP: no ping response"; return 1
  fi

  if [ "$DRYRUN" -eq 1 ]; then
    echo "  DRY-RUN: would build DEVICE_ID=\"$id\" DEVICE_LOCATION=\"$loc\" DEVICE_TYPE=$dtype ($typ) -> $ip"
    return 0
  fi

  echo "  building with its own identity..."
  # config.h #ifndef-guards these, so -D wins. Verified by inspecting the ELF below.
  PLATFORMIO_BUILD_FLAGS="-DDEVICE_ID=\\\"$id\\\" -DDEVICE_LOCATION=\\\"$loc\\\" -DDEVICE_TYPE=$dtype" \
    pio run -e "$ENVNAME" >/tmp/build_$id.log 2>&1
  if [ $? -ne 0 ]; then echo "  BUILD FAILED (see /tmp/build_$id.log)"; return 1; fi

  # Prove the binary carries the right identity before it touches the hardware.
  local elf=.pio/build/$ENVNAME/firmware.elf
  # Collect first, then match. `strings | grep -q` would SIGPIPE strings once grep
  # exits early, and under `set -o pipefail` that reports failure on a SUCCESSFUL
  # match — a false abort.
  local found_ids found_locs
  found_ids=" $(strings "$elf" 2>/dev/null | grep -E '^sensor-[0-9]+$' | sort -u | tr '\n' ' ')"
  found_locs=" $(strings "$elf" 2>/dev/null | grep -E '^[a-z]+-room$' | sort -u | tr '\n' ' ')"
  case "$found_ids" in
    *" $id "*) ;;
    *) echo "  ABORT: binary carries [$found_ids] not '$id' — identity flag did not apply"; return 1;;
  esac
  case "$found_locs" in
    *" $loc "*) ;;
    *) echo "  ABORT: binary carries [$found_locs] not '$loc'"; return 1;;
  esac
  # Device-type check via LINKED SYMBOLS, not strings. String markers are
  # unreliable here: the web dashboard embeds both "moisture=" and "humidity="
  # regardless of type, and CLIMATE_MEASUREMENT is a constant present in every
  # build. The DHT library, however, is only linked when DEVICE_TYPE is climate.
  # Count into a variable first — `nm | grep -c` under `set -o pipefail` would
  # SIGPIPE and misreport.
  local dht_syms
  dht_syms="$(nm "$elf" 2>/dev/null | grep -c '_ZN3DHT' || true)"
  dht_syms="${dht_syms//[^0-9]/}"; dht_syms="${dht_syms:-0}"
  if [ "$typ" = "climate" ] && [ "$dht_syms" -eq 0 ]; then
    echo "  ABORT: climate build has no DHT symbols — DEVICE_TYPE did not apply"; return 1
  fi
  if [ "$typ" = "soil" ] && [ "$dht_syms" -gt 0 ]; then
    echo "  ABORT: soil build linked $dht_syms DHT symbols — built as CLIMATE by mistake"; return 1
  fi
  echo "  identity verified in binary: $id / $loc / $typ"

  # ArduinoOTA answers the UDP invitation from loop(). A board busy with a sensor
  # read or an InfluxDB POST can miss espota's 10s window, which surfaces as
  # "[ERROR]: No Answer" even though the board is perfectly healthy. Observed
  # hit rate on an idle-ish fleet was roughly 4 of 9 on any single attempt, so
  # retry rather than treating the first miss as a failure.
  #
  # Do NOT "check readiness" by sending an invitation first: that opens a real
  # OTA session the board then waits on, and the genuine upload gets No Answer.
  local attempt rc=1
  for attempt in 1 2 3 4 5; do
    echo "  uploading over OTA (attempt $attempt/5)..."
    PLATFORMIO_BUILD_FLAGS="-DDEVICE_ID=\\\"$id\\\" -DDEVICE_LOCATION=\\\"$loc\\\" -DDEVICE_TYPE=$dtype" \
      pio run -e "$ENVNAME" --target upload --upload-port "$ip" >/tmp/ota_$id.log 2>&1
    rc=$?
    [ $rc -eq 0 ] && break
    if grep -q "Authentication Failed" /tmp/ota_$id.log; then
      echo "  AUTH REJECTED — the board is not running the password in OTA_AUTH_PASSWORD"
      echo "  (during a rotation set OTA_AUTH_PASSWORD to the OLD password)"
      return 1
    fi
    echo "    no answer; retrying in 8s"
    sleep 8
  done
  if [ $rc -ne 0 ]; then
    echo "  UPLOAD FAILED after 5 attempts (see /tmp/ota_$id.log)"; tail -4 /tmp/ota_$id.log | sed 's/^/    /'; return 1
  fi
  echo "  uploaded"

  echo -n "  waiting for reboot"
  local i
  for i in $(seq 1 30); do
    sleep 2
    if ping -c 1 -W 2000 "$ip" >/dev/null 2>&1; then echo " — back up"; return 0; fi
    echo -n "."
  done
  echo " — did NOT come back"; return 1
}

TOK="$(read_token)"
[ -n "$TOK" ] || { echo "could not read the InfluxDB read token from the Pi"; exit 1; }

FLASHED=""; FAILED=""

do_device() {
  local id="$1" loc="$2" ip="$3" typ="$4"
  if flash_one "$id" "$loc" "$ip" "$typ"; then FLASHED="$FLASHED $id"; else FAILED="$FAILED $id"; fi
}

if [ -n "$ONLY" ]; then
  line="$(printf '%s\n' "$DEVICES" | awk -F'\t' -v id="$ONLY" '$1==id')"
  [ -n "$line" ] || { echo "no such device: $ONLY"; exit 1; }
  IFS=$'\t' read -r id loc ip typ <<< "$line"
  do_device "$id" "$loc" "$ip" "$typ"
else
  echo "=== PHASE 1: canary ($CANARY) ==="
  cline="$(printf '%s\n' "$DEVICES" | awk -F'\t' -v id="$CANARY" '$1==id')"
  [ -n "$cline" ] || { echo "canary $CANARY not in config"; exit 1; }
  IFS=$'\t' read -r cid cloc cip ctyp <<< "$cline"
  do_device "$cid" "$cloc" "$cip" "$ctyp"
  case "$FAILED" in *"$CANARY"*) echo "Canary failed — stopping."; exit 1;; esac

  if [ "$DRYRUN" -eq 0 ]; then
    echo
    echo "Waiting ${SETTLE_SECONDS}s for the canary to publish a reading..."
    sleep "$SETTLE_SECONDS"
    now=$(date +%s); last=$(last_write_epoch "$CANARY" "$TOK")
    age=$(( now - last ))
    if [ "$last" -gt 0 ] && [ "$age" -lt 900 ]; then
      echo "  ✓ canary wrote to InfluxDB ${age}s ago"
    else
      echo "  ✗ canary has NOT written to InfluxDB (last=$last). Stopping."
      exit 1
    fi
    echo
    printf "Flash the remaining devices? (y/n) "; read -r reply
    case "$reply" in [Yy]*) ;; *) echo "Stopped after canary."; exit 0;; esac
  fi

  echo
  echo "=== PHASE 2: remaining devices ==="
  while IFS=$'\t' read -r id loc ip typ; do
    [ "$id" = "$CANARY" ] && continue
    do_device "$id" "$loc" "$ip" "$typ"
    sleep 3
  done <<< "$DEVICES"
fi

echo
echo "=== Summary ==="
echo "  flashed:$FLASHED"
echo "  failed :${FAILED:- none}"
[ -n "$FAILED" ] && exit 1
exit 0
