#!/bin/bash
#
# Daily Health Summary Report
# Generates comprehensive health report with all monitoring data
# Sends to log file and optionally to email/webhook
#

LOG_DIR="/mnt/sensor-data/logs"
REPORT_FILE="$LOG_DIR/daily-health-report.log"
REPORT_ARCHIVE="$LOG_DIR/reports/health-report-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR/reports"

generate_report() {
    cat <<EOF
================================================================================
DAILY HEALTH SUMMARY REPORT
Generated: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================

SYSTEM INFORMATION
------------------
Hostname: $(hostname)
Uptime: $(uptime -p)
Last boot: $(who -b | awk '{print $3, $4}')
Kernel: $(uname -r)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')

POWER STATUS
------------
$(vcgencmd get_throttled)
Temperature: $(vcgencmd measure_temp)
Core voltage: $(vcgencmd measure_volts core)
ARM clock: $(vcgencmd measure_clock arm | awk -F= '{printf "%.0f MHz\n", $2/1000000}')

MEMORY USAGE
------------
$(free -h)

DISK USAGE
----------
$(df -h /mnt/sensor-data)

CRITICAL SERVICES STATUS
------------------------
InfluxDB: $(systemctl is-active influxdb)
Grafana: $(systemctl is-active grafana-server)
Cloudflare Tunnel: $(systemctl is-active cloudflared)

NETWORK STATUS
--------------
Active interfaces:
$(ip -brief addr show | grep UP)

SENSOR STATUS (Last 30 minutes)
--------------------------------
EOF

    # Check InfluxDB for recent sensor data
    if systemctl is-active --quiet influxdb; then
        echo "Querying sensor readings from InfluxDB..."
        
        # This requires INFLUX_TOKEN to be set
        if [ -n "$INFLUX_TOKEN" ]; then
            for sensor in sensor-1 sensor-2 sensor-3 sensor-4; do
                local count=$(curl -s -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
                    -H "Authorization: Token $INFLUX_TOKEN" \
                    -H "Content-Type: application/vnd.flux" \
                    -d "from(bucket: \"sensor-readings\")
                        |> range(start: -30m)
                        |> filter(fn: (r) => r.device_id == \"$sensor\")
                        |> filter(fn: (r) => r._field == \"moisture\")
                        |> count()" 2>/dev/null | grep -o '"_value":[0-9]*' | cut -d: -f2 | head -1)
                
                if [ -n "$count" ] && [ "$count" -gt 0 ]; then
                    echo "  $sensor: $count readings (ACTIVE)"
                else
                    echo "  $sensor: No readings (OFFLINE)"
                fi
            done
        else
            echo "  (INFLUX_TOKEN not set - cannot query sensor data)"
        fi
    else
        echo "  InfluxDB not running - cannot check sensor status"
    fi

    cat <<EOF

RECENT ALERTS (Last 24 hours)
-----------------------------
EOF
    if [ -f "$LOG_DIR/power-alerts.log" ]; then
        echo "Power alerts:"
        tail -n 50 "$LOG_DIR/power-alerts.log" | grep "$(date +%Y-%m-%d)" || echo "  None"
    fi
    
    if [ -f "$LOG_DIR/network-alerts.log" ]; then
        echo ""
        echo "Network alerts:"
        tail -n 50 "$LOG_DIR/network-alerts.log" | grep "$(date +%Y-%m-%d)" || echo "  None"
    fi
    
    if [ -f "$LOG_DIR/system-alerts.log" ]; then
        echo ""
        echo "System alerts:"
        tail -n 50 "$LOG_DIR/system-alerts.log" | grep "$(date +%Y-%m-%d)" || echo "  None"
    fi

    cat <<EOF

SHUTDOWN/REBOOT EVENTS (Last 7 days)
-------------------------------------
EOF
    if [ -f "$LOG_DIR/shutdown-events.log" ]; then
        tail -n 100 "$LOG_DIR/shutdown-events.log" | grep "$(date -d '7 days ago' +%Y-%m-%d)" -A 999 || echo "None"
    else
        echo "No shutdown events logged"
    fi

    cat <<EOF

UNCLEAN SHUTDOWNS DETECTED
--------------------------
EOF
    if [ -f "$LOG_DIR/startup_history.log" ]; then
        grep "UNCLEAN SHUTDOWN" "$LOG_DIR/startup_history.log" | tail -n 10 || echo "None detected"
    else
        echo "No startup history available"
    fi

    cat <<EOF

INFLUXDB WATCHDOG ACTIVITY (Last 7 days)
-----------------------------------------
EOF
    if [ -f "$LOG_DIR/influxdb-watchdog.log" ]; then
        tail -n 100 "$LOG_DIR/influxdb-watchdog.log" | grep "$(date -d '7 days ago' +%Y-%m-%d)" -A 999 || echo "No watchdog activity"
    else
        echo "No watchdog logs"
    fi

    cat <<EOF

SYSTEM RESOURCE TRENDS (Last 24 hours)
---------------------------------------
EOF
    echo "System load average:"
    echo "  Current: $(uptime | awk -F'load average:' '{print $2}')"
    
    echo ""
    echo "Top 5 processes by CPU:"
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-20s %5s%%  %s\n", $11, $3, $2}'
    
    echo ""
    echo "Top 5 processes by Memory:"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "  %-20s %5s%%  %s\n", $11, $4, $2}'

    cat <<EOF

RECOMMENDATIONS
---------------
EOF

    # Check for issues and provide recommendations
    local recommendations=""
    
    # Check throttling
    if vcgencmd get_throttled | grep -qv "0x0"; then
        recommendations+="⚠️  Power throttling detected - consider upgrading to 5V 3A power supply\n"
    fi
    
    # Check disk space
    local disk_usage=$(df -h /mnt/sensor-data | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 80 ]; then
        recommendations+="⚠️  Disk usage above 80% - consider cleanup or expansion\n"
    fi
    
    # Check for recent unclean shutdowns
    if [ -f "$LOG_DIR/startup_history.log" ]; then
        local recent_unclean=$(grep "UNCLEAN SHUTDOWN" "$LOG_DIR/startup_history.log" | grep "$(date +%Y-%m-%d)" | wc -l)
        if [ "$recent_unclean" -gt 0 ]; then
            recommendations+="🔴 CRITICAL: Unclean shutdown detected today - investigate power supply and UPS\n"
        fi
    fi
    
    # Check service failures
    for service in influxdb grafana-server cloudflared; do
        if ! systemctl is-active --quiet "$service"; then
            recommendations+="⚠️  Service $service is not running\n"
        fi
    done
    
    if [ -z "$recommendations" ]; then
        echo "✅ No critical issues detected - all systems nominal"
    else
        echo -e "$recommendations"
    fi

    cat <<EOF

================================================================================
END OF REPORT
================================================================================
EOF
}

# Generate and save report
echo "Generating daily health summary..."
generate_report | tee "$REPORT_FILE" "$REPORT_ARCHIVE"

echo ""
echo "Report saved to:"
echo "  Latest: $REPORT_FILE"
echo "  Archive: $REPORT_ARCHIVE"

# Optional: Send to webhook or email if configured
# Uncomment and configure as needed
#
# if [ -n "$HEALTH_REPORT_WEBHOOK" ]; then
#     echo "Sending to webhook: $HEALTH_REPORT_WEBHOOK"
#     curl -X POST "$HEALTH_REPORT_WEBHOOK" \
#         -H "Content-Type: application/json" \
#         -d "{\"text\":\"$(cat $REPORT_FILE | sed 's/"/\\"/g')\"}"
# fi
