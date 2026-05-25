#!/bin/bash
#
# Network Connectivity Monitor
# Tracks WiFi/Ethernet status, connectivity to critical services
# Logs network issues that could correlate with system failures
#

LOG_FILE="/mnt/sensor-data/logs/network-monitor.log"
ALERT_FILE="/mnt/sensor-data/logs/network-alerts.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

# Check internet connectivity
check_internet() {
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

# Check DNS resolution
check_dns() {
    if host google.com &>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

# Get network interface stats
get_interface_stats() {
    local iface=$1
    if [ -d "/sys/class/net/$iface" ]; then
        local rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        local rx_errors=$(cat /sys/class/net/$iface/statistics/rx_errors 2>/dev/null || echo 0)
        local tx_errors=$(cat /sys/class/net/$iface/statistics/tx_errors 2>/dev/null || echo 0)
        local rx_dropped=$(cat /sys/class/net/$iface/statistics/rx_dropped 2>/dev/null || echo 0)
        local tx_dropped=$(cat /sys/class/net/$iface/statistics/tx_dropped 2>/dev/null || echo 0)
        
        echo "RX: $(numfmt --to=iec $rx_bytes), TX: $(numfmt --to=iec $tx_bytes), Errors: $((rx_errors + tx_errors)), Dropped: $((rx_dropped + tx_dropped))"
    else
        echo "Interface not found"
    fi
}

# Check WiFi signal strength (if using WiFi)
check_wifi() {
    if iwconfig 2>/dev/null | grep -q "ESSID"; then
        local ssid=$(iwconfig 2>/dev/null | grep ESSID | cut -d\" -f2)
        local quality=$(iwconfig 2>/dev/null | grep "Link Quality" | awk '{print $2}' | cut -d= -f2)
        local signal=$(iwconfig 2>/dev/null | grep "Signal level" | awk '{print $4}' | cut -d= -f2)
        echo "Connected to: $ssid, Quality: $quality, Signal: $signal"
    else
        echo "Not using WiFi or not connected"
    fi
}

# Main monitoring
log "=== Network Monitor Check ==="

# Check each network interface
for iface in eth0 wlan0; do
    if [ -d "/sys/class/net/$iface" ]; then
        if ip link show "$iface" | grep -q "state UP"; then
            log "$iface: UP - $(get_interface_stats $iface)"
            
            # Get IP address
            ip=$(ip addr show "$iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            if [ -n "$ip" ]; then
                log "  IP: $ip"
            fi
        else
            log "$iface: DOWN"
        fi
    fi
done

# Check WiFi signal if applicable
wifi_info=$(check_wifi)
if [[ "$wifi_info" != "Not using WiFi"* ]]; then
    log "WiFi: $wifi_info"
fi

# Check connectivity
internet_status=$(check_internet)
dns_status=$(check_dns)

log "Internet connectivity: $internet_status"
log "DNS resolution: $dns_status"

if [ "$internet_status" = "FAILED" ]; then
    alert "Internet connectivity LOST"
fi

if [ "$dns_status" = "FAILED" ]; then
    alert "DNS resolution FAILED"
fi

# Check connectivity to critical local services
check_service_port() {
    local host=$1
    local port=$2
    local name=$3
    
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        log "$name ($host:$port): OK"
    else
        alert "$name ($host:$port): UNREACHABLE"
    fi
}

log "Checking local services..."
check_service_port "localhost" "8086" "InfluxDB"
check_service_port "localhost" "3000" "Grafana"

# Check if ESP8266 sensors are reachable
log "Checking ESP8266 sensors..."
for sensor_ip in 192.168.99.110 192.168.99.149 192.168.99.70 192.168.99.105; do
    if ping -c 1 -W 1 "$sensor_ip" &>/dev/null; then
        log "Sensor $sensor_ip: ONLINE"
    else
        log "Sensor $sensor_ip: OFFLINE"
    fi
done

log "=== Network check complete ==="
