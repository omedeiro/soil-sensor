#!/bin/bash
# system-metrics-collector.sh
# Collects Raspberry Pi system metrics and sends to InfluxDB using curl
# No Python dependencies required

set -e

# Configuration from environment
INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"
INFLUX_ORG="${INFLUX_ORG:-soil-monitoring}"
INFLUX_BUCKET="${INFLUX_BUCKET:-sensor-readings}"

if [[ -z "$INFLUX_TOKEN" ]]; then
    echo "ERROR: INFLUX_TOKEN not set"
    exit 1
fi

# Get hostname
HOSTNAME=$(hostname)

# Timestamp in nanoseconds (InfluxDB format)
TIMESTAMP=$(date +%s%N)

# Collect metrics
CPU_PERCENT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}' || echo "0")

# Load averages
LOAD_1MIN=$(cat /proc/loadavg | awk '{print $1}')
LOAD_5MIN=$(cat /proc/loadavg | awk '{print $2}')
LOAD_15MIN=$(cat /proc/loadavg | awk '{print $3}')

# Memory (in MB)
MEM_INFO=$(free -m | grep Mem:)
RAM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
RAM_USED=$(echo $MEM_INFO | awk '{print $3}')
RAM_FREE=$(echo $MEM_INFO | awk '{print $7}')
RAM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")

# Disk usage for /mnt/sensor-data (in GB)
if mountpoint -q /mnt/sensor-data; then
    DISK_STAT=$(df -BG /mnt/sensor-data | tail -1)
else
    DISK_STAT=$(df -BG / | tail -1)
fi
DISK_USED=$(echo $DISK_STAT | awk '{print $3}' | sed 's/G//')
DISK_FREE=$(echo $DISK_STAT | awk '{print $4}' | sed 's/G//')
DISK_PERCENT=$(echo $DISK_STAT | awk '{print $5}' | sed 's/%//')

# Uptime in seconds
UPTIME_SECONDS=$(cat /proc/uptime | awk '{print int($1)}')

# Build InfluxDB line protocol
LINE_PROTOCOL="rpi_system_metrics,hostname=$HOSTNAME \
cpu_percent=$CPU_PERCENT,\
cpu_temp=$CPU_TEMP,\
load_1min=$LOAD_1MIN,\
load_5min=$LOAD_5MIN,\
load_15min=$LOAD_15MIN,\
ram_used_mb=$RAM_USED,\
ram_free_mb=$RAM_FREE,\
ram_percent=$RAM_PERCENT,\
disk_used_gb=$DISK_USED,\
disk_free_gb=$DISK_FREE,\
disk_percent=$DISK_PERCENT,\
uptime_seconds=$UPTIME_SECONDS $TIMESTAMP"

# Send to InfluxDB
RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null \
    -X POST "$INFLUX_URL/api/v2/write?org=$INFLUX_ORG&bucket=$INFLUX_BUCKET&precision=ns" \
    -H "Authorization: Token $INFLUX_TOKEN" \
    -H "Content-Type: text/plain" \
    --data-raw "$LINE_PROTOCOL")

# Check response
if [[ "$RESPONSE" == "204" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Sent metrics: CPU=${CPU_PERCENT}%, Temp=${CPU_TEMP}°C, RAM=${RAM_PERCENT}%, Disk=${DISK_PERCENT}%, Uptime=${UPTIME_SECONDS}s"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Failed to send metrics (HTTP $RESPONSE)"
    exit 1
fi
