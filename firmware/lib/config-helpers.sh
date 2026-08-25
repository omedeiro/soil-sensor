# Config helpers for firmware flash scripts
# Sources sensors-config.json at the project root via jq
# Usage: source "$(dirname "$0")/lib/config-helpers.sh"

CONFIG_FILE="$(cd "$(dirname "$0")/.." && pwd)/sensors-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="$(cd "$(dirname "$0")/.." && pwd)/../sensors-config.json"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: sensors-config.json not found!" >&2
  exit 1
fi

load_sensors_by_number() {
  local _arr_name=$1
  local i=1
  while IFS= read -r _line; do
    eval "${_arr_name}[$i]=\"\$_line\""
    ((i++))
  done < <(jq -r '.sensors[] | "\(.id):\(.location):\(.plant):\(.ip):\(.mac)"' "$CONFIG_FILE")
}

load_sensors_by_id() {
  local _arr_name=$1
  while IFS= read -r _line; do
    local _id="${_line%%:*}"
    eval "${_arr_name}[\"$_id\"]=\"\$_line\""
  done < <(jq -r '.sensors[] | "\(.id):\(.location):\(.plant):\(.ip):\(.mac)"' "$CONFIG_FILE")
}

load_sensor_ips_by_id() {
  local _arr_name=$1
  while IFS=$'\t' read -r _id _ip; do
    eval "${_arr_name}[\"$_id\"]=\"\$_ip\""
  done < <(jq -r '.sensors[] | "\(.id)\t\(.ip)"' "$CONFIG_FILE")
}

sensor_count() {
  jq '.sensors | length' "$CONFIG_FILE"
}

print_sensor_list() {
  echo ""
  echo "📋 Sensor List:"
  local i=1
  while IFS= read -r _line; do
    IFS=':' read -r _id _location _plant _ip _mac <<< "$_line"
    echo "  $i - $_plant ($_location)"
    ((i++))
  done < <(jq -r '.sensors[] | "\(.id):\(.location):\(.plant):\(.ip):\(.mac)"' "$CONFIG_FILE")
  echo ""
}

# ─── Climate sensors ─────────────────────────────────────────────────────────
# sensors-config.json has TWO device arrays: .sensors[] (soil probes) and
# .climate_sensors[] (DHT temp/humidity units, sensor-8 and sensor-9). Every
# loader above reads only .sensors[], so the climate units were invisible to the
# flash scripts and would be left running stale firmware after a fleet update.

# All devices (soil + climate), "id<TAB>ip"
load_all_device_ips_by_id() {
  local _arr_name=$1
  while IFS=$'\t' read -r _id _ip; do
    [ -n "$_id" ] || continue
    eval "${_arr_name}[\"$_id\"]=\"\$_ip\""
  done < <(jq -r '(.sensors + (.climate_sensors // []))[] | "\(.id)\t\(.ip)"' "$CONFIG_FILE")
}

# All devices as "id:location:ip", for per-sensor identity builds
load_all_device_identity() {
  local _arr_name=$1
  while IFS= read -r _line; do
    local _id="${_line%%:*}"
    [ -n "$_id" ] || continue
    eval "${_arr_name}[\"$_id\"]=\"\$_line\""
  done < <(jq -r '(.sensors + (.climate_sensors // []))[] | "\(.id):\(.location):\(.ip)"' "$CONFIG_FILE")
}

all_device_count() {
  jq -r '(.sensors | length) + ((.climate_sensors // []) | length)' "$CONFIG_FILE"
}
