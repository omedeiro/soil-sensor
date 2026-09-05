#!/bin/bash
# Enhanced System Reliability Installation
# Implements automated recovery and monitoring

set -e

echo "================================================================"
echo "Installing System Reliability Enhancements"
echo "================================================================"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# 1. Install automated InfluxDB recovery service
echo "1. Installing InfluxDB auto-recovery service..."
cat > /etc/systemd/system/influxdb-watchdog.service << 'EOF'
[Unit]
Description=InfluxDB Watchdog - Auto-recovery on failure
After=influxdb.service
Requires=influxdb.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/influxdb-watchdog.sh
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/influxdb-watchdog.sh << 'EOF'
#!/bin/bash
# InfluxDB Watchdog - checks health and auto-recovers

LOG="/mnt/sensor-data/logs/influxdb-watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

# Check if InfluxDB is running
if ! systemctl is-active --quiet influxdb; then
    log "ERROR: InfluxDB is not running"
    
    if systemctl is-failed --quiet influxdb; then
        log "InfluxDB is in failed state - checking for corruption"
        
        # Check if bolt file exists and is readable
        if [ ! -r /mnt/sensor-data/influxdb/influxd.bolt ]; then
            log "CRITICAL: Bolt file missing or unreadable - initiating emergency recovery"
            
            # Find most recent backup
            LATEST_BACKUP=$(ls -td /mnt/sensor-data/backups/influx_* 2>/dev/null | head -1)
            
            if [ -n "$LATEST_BACKUP" ]; then
                log "Found backup: $LATEST_BACKUP"
                log "Restoring from backup..."
                
                systemctl stop influxdb
                mkdir -p /mnt/sensor-data/influxdb
                
                cd "$LATEST_BACKUP"
                gunzip -c *.bolt.gz > /mnt/sensor-data/influxdb/influxd.bolt 2>/dev/null || true
                gunzip -c *.sqlite.gz > /mnt/sensor-data/influxdb/influxd.sqlite 2>/dev/null || true
                
                mkdir -p /mnt/sensor-data/influxdb/engine
                for tarfile in *.tar.gz; do
                    tar -xzf "$tarfile" -C /mnt/sensor-data/influxdb/engine 2>/dev/null || true
                done
                
                chown -R influxdb:influxdb /mnt/sensor-data/influxdb
                
                systemctl reset-failed influxdb
                systemctl start influxdb
                
                log "Recovery attempt complete"
            else
                log "CRITICAL: No backups found - manual intervention required"
            fi
        else
            # Just try to restart
            log "Attempting simple restart..."
            systemctl reset-failed influxdb
            systemctl start influxdb
        fi
    fi
fi

# Verify health
sleep 3
if systemctl is-active --quiet influxdb && curl -sf http://localhost:8086/health > /dev/null 2>&1; then
    log "✓ InfluxDB is healthy"
    exit 0
else
    log "✗ InfluxDB health check failed"
    exit 1
fi
EOF

chmod +x /usr/local/bin/influxdb-watchdog.sh

cat > /etc/systemd/system/influxdb-watchdog.timer << 'EOF'
[Unit]
Description=Run InfluxDB watchdog every 5 minutes
After=influxdb.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=influxdb-watchdog.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable influxdb-watchdog.timer
systemctl start influxdb-watchdog.timer
echo "   ✓ InfluxDB watchdog enabled (checks every 5 minutes)"

# 2. Install comprehensive system health monitor
echo ""
echo "2. Installing system health monitor..."
cat > /etc/systemd/system/system-health.service << 'EOF'
[Unit]
Description=System Health Monitor
After=multi-user.target influxdb.service grafana-server.service

[Service]
Type=oneshot
# INFLUX_TOKEN (read) lives on the Pi, chmod 600 — never in git.
EnvironmentFile=-/mnt/sensor-data/config/soil-alerts.env
ExecStart=/home/omedeiro/soil-sensor/rpi-setup/scripts/system-health-monitor.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/system-health.timer << 'EOF'
[Unit]
Description=Run system health check every 10 minutes
After=multi-user.target

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
Unit=system-health.service

[Install]
WantedBy=timers.target
EOF

chmod +x /home/omedeiro/soil-sensor/rpi-setup/scripts/system-health-monitor.sh
systemctl daemon-reload
systemctl enable system-health.timer
systemctl start system-health.timer
echo "   ✓ System health monitor enabled (runs every 10 minutes)"

# 3. Periodic data sync
echo ""
echo "3. Installing periodic data sync..."
cat > /etc/systemd/system/influxdb-sync.service << 'EOF'
[Unit]
Description=Sync InfluxDB data to disk
After=influxdb.service

[Service]
Type=oneshot
ExecStart=/bin/sync
ExecStart=/bin/sh -c 'echo "[$(date)] Data synced to disk" >> /mnt/sensor-data/logs/sync.log'
EOF

cat > /etc/systemd/system/influxdb-sync.timer << 'EOF'
[Unit]
Description=Sync InfluxDB data every 10 minutes
After=influxdb.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
Unit=influxdb-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable influxdb-sync.timer
systemctl start influxdb-sync.timer
echo "   ✓ Data sync enabled (every 10 minutes)"

# 4. Increase systemd service stop timeout
echo ""
echo "4. Configuring graceful shutdown..."
mkdir -p /etc/systemd/system/influxdb.service.d

cat > /etc/systemd/system/influxdb.service.d/timeout.conf << 'EOF'
[Service]
TimeoutStopSec=60s
EOF

mkdir -p /etc/systemd/system/grafana-server.service.d

cat > /etc/systemd/system/grafana-server.service.d/timeout.conf << 'EOF'
[Service]
TimeoutStopSec=60s
Restart=always
RestartSec=10
EOF

systemctl daemon-reload
echo "   ✓ Service shutdown timeouts extended"
echo "   ✓ Grafana auto-restart enabled"

# 5. Install shutdown hook to log reason
echo ""
echo "5. Installing shutdown logging..."
cat > /usr/local/bin/log-shutdown.sh << 'EOF'
#!/bin/bash
echo "[$(date)] System shutdown initiated" >> /mnt/sensor-data/logs/shutdown-history.log
sync
EOF

chmod +x /usr/local/bin/log-shutdown.sh

cat > /etc/systemd/system/log-shutdown.service << 'EOF'
[Unit]
Description=Log system shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/log-shutdown.sh
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target
EOF

systemctl daemon-reload
systemctl enable log-shutdown.service
echo "   ✓ Shutdown logging enabled"

echo ""
echo "================================================================"
echo "System Reliability Enhancements Installed!"
echo "================================================================"
echo ""
echo "Active protections:"
echo "  ✓ InfluxDB auto-recovery (checks every 5 min)"
echo "  ✓ System health monitoring (every 10 min)"
echo "  ✓ Automatic data sync (every 10 min)"
echo "  ✓ Grafana auto-restart on failure"
echo "  ✓ Extended shutdown timeouts (60s)"
echo "  ✓ Shutdown event logging"
echo ""
echo "Logs:"
echo "  - /mnt/sensor-data/logs/influxdb-watchdog.log"
echo "  - /mnt/sensor-data/logs/system-health.log"
echo "  - /mnt/sensor-data/logs/system-alerts.log"
echo "  - /mnt/sensor-data/logs/shutdown-history.log"
echo ""
echo "Status check: systemctl list-timers"
echo ""
