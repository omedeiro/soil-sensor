# Raspberry Pi Recovery Guide

**Disaster recovery procedures for the Soil Moisture Monitoring System**

This guide documents the complete rebuild process when the Raspberry Pi 5 experiences catastrophic failure (SD card corruption, filesystem damage, hardware replacement, etc.).

---

## Table of Contents

1. [When to Use This Guide](#when-to-use-this-guide)
2. [Prerequisites](#prerequisites)
3. [Recovery Process](#recovery-process)
4. [Troubleshooting](#troubleshooting)
5. [Differences from Standard Installation](#differences-from-standard-installation)
6. [Post-Recovery Checklist](#post-recovery-checklist)
7. [Backup and Restore Procedures](#backup-and-restore-procedures)

---

## When to Use This Guide

Use this recovery guide when:

- **SD card corruption** after improper shutdown or power loss
- **Filesystem corruption** preventing normal boot
- **Fresh Raspberry Pi installation** needed (new SD card, new hardware, etc.)
- **Docker-based installation required** (APT package installation fails)
- **Standard `install.sh` fails** due to distribution-specific issues

**This guide uses Docker containers instead of native APT packages** due to compatibility issues with Debian Trixie (GPG key verification failures).

---

## Prerequisites

### Hardware Required

- Raspberry Pi 5 (or compatible model)
- 256GB USB drive (labeled "sensor-data", formatted as ext4)
- MicroSD card (32GB+ recommended)
- Computer with SD card reader
- Network connection (Ethernet or WiFi)

### Software Required

- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (for SD card preparation)
- SSH client (Terminal on macOS/Linux, PuTTY on Windows)
- Git (for cloning repository)

### Information Needed

- **WiFi credentials** (if not using Ethernet)
- **Cloudflare account** (for public dashboard access)
- **Cloudflare Tunnel token** (if restoring existing tunnel)
- **InfluxDB credentials** (if restoring from backup)

---

## Recovery Process

### Step 1: Prepare Fresh SD Card

1. **Download Raspberry Pi OS:**
   - Open Raspberry Pi Imager
   - Choose: **Raspberry Pi OS (64-bit)** (Debian Bookworm or Trixie)

2. **Configure OS settings** (click gear icon):
   ```
   Hostname: raspberrypi (or custom)
   Username: omedeiro
   Password: <your-password>
   WiFi SSID: <your-network>
   WiFi Password: <your-password>
   Locale: <your-timezone>
   Enable SSH: ✓ (password authentication)
   ```

3. **Flash SD card:**
   - Select storage device
   - Click "Write"
   - Wait for completion (~5-10 minutes)

4. **Boot Raspberry Pi:**
   - Insert SD card into Pi
   - Connect power
   - Wait 2-3 minutes for first boot
   - Find IP address: `ping raspberrypi.local` or check router

### Step 2: Fix Corrupted System Files (If Needed)

**Only required if recovering from improper shutdown/filesystem corruption.**

1. **SSH into Pi:**
   ```bash
   ssh omedeiro@192.168.99.134  # Replace with your Pi's IP
   ```

2. **Check for corrupted config files:**
   ```bash
   # Check initramfs config files
   ls -la /etc/initramfs-tools/
   cat /etc/initramfs-tools/update-initramfs.conf
   cat /etc/initramfs-tools/initramfs.conf
   ```

3. **Fix corrupted files if needed:**
   ```bash
   # Restore default update-initramfs.conf
   echo "update_initramfs=yes" | sudo tee /etc/initramfs-tools/update-initramfs.conf
   
   # Restore default initramfs.conf
   sudo tee /etc/initramfs-tools/initramfs.conf > /dev/null <<EOF
   MODULES=most
   BUSYBOX=auto
   KEYMAP=n
   COMPRESS=zstd
   DEVICE=
   NFSROOT=auto
   RUNSIZE=10%
   EOF
   
   # Rebuild initramfs
   sudo update-initramfs -u
   ```

### Step 3: Mount USB Drive

1. **Identify USB drive:**
   ```bash
   lsblk
   # Look for 256GB device (usually /dev/sda1)
   ```

2. **Check filesystem (if recovering from corruption):**
   ```bash
   sudo umount /dev/sda1  # If already mounted
   sudo fsck.ext4 -y /dev/sda1  # Auto-repair filesystem
   ```

3. **Create mount point and mount:**
   ```bash
   sudo mkdir -p /mnt/sensor-data
   sudo mount /dev/sda1 /mnt/sensor-data
   
   # Verify mount
   df -h | grep sensor-data
   ```

4. **Configure auto-mount at boot:**
   ```bash
   # Get UUID
   UUID=$(sudo blkid -s UUID -o value /dev/sda1)
   
   # Add to /etc/fstab
   echo "UUID=$UUID /mnt/sensor-data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
   
   # Test fstab
   sudo mount -a
   ```

### Step 4: Install Docker

**Why Docker?** Native APT packages fail on Debian Trixie due to GPG key verification issues with InfluxData and Grafana repositories.

1. **Install Docker:**
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   
   # Logout and login for group changes
   exit
   ssh omedeiro@192.168.99.134
   
   # Verify Docker
   docker --version
   docker ps
   ```

### Step 5: Install InfluxDB (Docker)

1. **Create data directory:**
   ```bash
   sudo mkdir -p /mnt/sensor-data/influxdb/data
   sudo mkdir -p /mnt/sensor-data/influxdb/config
   sudo chown -R $USER:$USER /mnt/sensor-data/influxdb
   ```

2. **Run InfluxDB container:**
   ```bash
   docker run -d \
     --name influxdb \
     --restart always \
     -p 8086:8086 \
     -v /mnt/sensor-data/influxdb/data:/var/lib/influxdb2 \
     -v /mnt/sensor-data/influxdb/config:/etc/influxdb2 \
     -e DOCKER_INFLUXDB_INIT_MODE=setup \
     -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
     -e DOCKER_INFLUXDB_INIT_PASSWORD=soilsensor2024 \
     -e DOCKER_INFLUXDB_INIT_ORG=soil-monitoring \
     -e DOCKER_INFLUXDB_INIT_BUCKET=sensor-readings \
     -e DOCKER_INFLUXDB_INIT_RETENTION=365d \
     -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=YOUR_ADMIN_TOKEN_HERE \
     influxdb:2.7.12
   ```

3. **Verify InfluxDB:**
   ```bash
   # Check container status
   docker ps | grep influxdb
   
   # Check health
   curl http://localhost:8086/health
   
   # Expected output: {"status":"pass"}
   ```

4. **Access InfluxDB UI:**
   - Open browser: `http://192.168.99.134:8086`
   - Login: admin / soilsensor2024
   - Create tokens:
     - **Write token** for ESP8266 sensors (write access to sensor-readings bucket)
     - **Read token** for Grafana (read access to sensor-readings bucket)

### Step 6: Install Grafana (Docker)

1. **Create data directory:**
   ```bash
   sudo mkdir -p /mnt/sensor-data/grafana/data
   sudo mkdir -p /mnt/sensor-data/grafana/logs
   sudo mkdir -p /mnt/sensor-data/grafana/plugins
   
   # Grafana runs as user 472 in container
   sudo chown -R 472:472 /mnt/sensor-data/grafana
   ```

2. **Run Grafana container:**
   ```bash
   docker run -d \
     --name grafana \
     --restart always \
     -p 3000:3000 \
     -v /mnt/sensor-data/grafana/data:/var/lib/grafana \
     -v /mnt/sensor-data/grafana/logs:/var/log/grafana \
     -v /mnt/sensor-data/grafana/plugins:/var/lib/grafana/plugins \
     -e GF_AUTH_ANONYMOUS_ENABLED=true \
     -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
     -e GF_SECURITY_ALLOW_EMBEDDING=true \
     grafana/grafana:latest
   ```

3. **Verify Grafana:**
   ```bash
   # Check container status
   docker ps | grep grafana
   
   # Check logs
   docker logs grafana --tail 50
   
   # Expected: "HTTP Server Listen" message
   ```

4. **Access Grafana UI:**
   - Open browser: `http://192.168.99.134:3000`
   - Login: admin / admin (change password on first login)
   - Anonymous viewing is enabled (no login required for dashboards)

### Step 7: Configure InfluxDB Data Source in Grafana

1. **Add InfluxDB data source:**
   - Grafana UI → Configuration (⚙️) → Data sources → Add data source
   - Select: **InfluxDB**

2. **Configure connection:**
   ```
   Name: InfluxDB-SoilMonitoring
   Query Language: Flux
   URL: http://localhost:8086
   Access: Server (default)
   
   InfluxDB Details:
   Organization: soil-monitoring
   Token: <YOUR_INFLUXDB_READ_TOKEN>
   Default Bucket: sensor-readings
   ```

3. **Save and test:**
   - Click "Save & test"
   - Expected: "✓ datasource is working. 1 buckets found"
   - **Note the datasource UID** (needed for dashboard imports)

### Step 8: Install Cloudflare Tunnel

**For public HTTPS access to Grafana dashboard.**

1. **Install cloudflared:**
   ```bash
   # Download cloudflared for ARM64
   wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
   sudo dpkg -i cloudflared-linux-arm64.deb
   
   # Verify installation
   cloudflared --version
   ```

2. **Option A: Create new tunnel (first-time setup):**
   ```bash
   # Login to Cloudflare
   cloudflared tunnel login
   # Opens browser for authentication
   
   # Create tunnel
   cloudflared tunnel create soil-sensor-grafana
   # Note the tunnel ID and credentials file location
   
   # Create config
   mkdir -p ~/.cloudflared
   cat > ~/.cloudflared/config.yml <<EOF
   tunnel: soil-sensor-grafana
   credentials-file: /home/omedeiro/.cloudflared/<TUNNEL_ID>.json
   
   ingress:
     - hostname: grafana.owenmedeiros.com
       service: http://localhost:3000
     - service: http_status:404
   EOF
   
   # Route DNS
   cloudflared tunnel route dns soil-sensor-grafana grafana.owenmedeiros.com
   ```

3. **Option B: Restore existing tunnel (recovery):**
   ```bash
   # Install tunnel as service using existing token
   sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
   
   # Start service
   sudo systemctl start cloudflared
   sudo systemctl enable cloudflared
   
   # Verify status
   sudo systemctl status cloudflared
   cloudflared tunnel list
   ```

4. **Verify public access:**
   ```bash
   curl -I https://grafana.owenmedeiros.com
   # Expected: HTTP/2 200
   ```

### Step 9: Deploy Grafana Dashboards

1. **Clone repository:**
   ```bash
   cd ~
   git clone https://github.com/omedeiro/soil-sensor.git
   cd soil-sensor/grafana-dashboards
   ```

2. **Update dashboard datasource UIDs:**
   ```bash
   # Get your datasource UID from Grafana
   # (Settings → Data sources → InfluxDB-SoilMonitoring → URL contains UID)
   
   # Update sensors-config.json
   vim sensors-config.json
   # Change "influxdb_datasource_uid" to your actual UID
   ```

3. **Deploy main dashboard:**
   ```bash
   # Validate configuration
   ./validate-config.py
   
   # Generate dashboard
   ./generate-dashboard.py
   
   # Upload to Grafana
   ./upload-dashboard-to-pi.sh
   ```

4. **Import remaining dashboards:**
   ```bash
   # Use Grafana UI or API to import:
   # - alerts-overview.json
   # - mobile-summary.json
   # - rpi-health.json
   # - sensor-details.json
   # - system-health.json
   # - watering-history.json
   
   # Example API import:
   curl -X POST http://localhost:3000/api/dashboards/import \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <GRAFANA_API_KEY>" \
     -d @alerts-overview.json
   ```

### Step 10: Update ESP8266 Sensors

**All sensors need new InfluxDB write token after recovery.**

1. **Get write token from InfluxDB:**
   - InfluxDB UI → Load Data → API Tokens
   - Create new token: **Write access to sensor-readings bucket**
   - Copy token value

2. **Update firmware config:**
   ```bash
   cd ~/soil-sensor/firmware
   vim src/config.h
   
   # Update line 48:
   # INFLUX_TOKEN = "<NEW_WRITE_TOKEN>"
   ```

3. **Update sensors via OTA:**
   ```bash
   # See SENSOR_UPDATE_GUIDE.md for detailed OTA procedures
   # Or update manually via USB (7 sensors total)
   ```

---

## Troubleshooting

### InfluxDB Container Won't Start

**Problem:** `docker ps` shows InfluxDB constantly restarting.

**Solution:**
```bash
# Check logs
docker logs influxdb --tail 100

# Common issues:
# 1. Corrupted database files
sudo rm -rf /mnt/sensor-data/influxdb/data/*
docker restart influxdb

# 2. Permission issues
sudo chown -R $USER:$USER /mnt/sensor-data/influxdb
docker restart influxdb

# 3. Port already in use
sudo lsof -i :8086  # Find conflicting process
sudo kill <PID>
docker restart influxdb
```

### Grafana Shows "Bad Gateway" or Won't Load

**Problem:** Grafana dashboard returns 502 or doesn't load.

**Solution:**
```bash
# Check container status
docker ps | grep grafana
docker logs grafana --tail 50

# Common issues:
# 1. Container stopped
docker start grafana

# 2. Permission issues on data directory
sudo chown -R 472:472 /mnt/sensor-data/grafana
docker restart grafana

# 3. Corrupted database
sudo rm /mnt/sensor-data/grafana/data/grafana.db
docker restart grafana
# NOTE: This deletes dashboards - restore from backup!
```

### Cloudflare Tunnel Shows 503 Error

**Problem:** `https://grafana.owenmedeiros.com` returns 503 Service Unavailable.

**Solution:**
```bash
# Check tunnel status
sudo systemctl status cloudflared
cloudflared tunnel info soil-sensor-grafana

# Check if Grafana is running
curl http://localhost:3000
docker ps | grep grafana

# Restart tunnel
sudo systemctl restart cloudflared

# Check tunnel logs
sudo journalctl -u cloudflared -f
```

### GPG Key Verification Failures (APT Install)

**Problem:** `apt-get install influxdb2` or `grafana` fails with GPG errors on Debian Trixie.

**Root Cause:** Debian Trixie uses `sqv` for GPG verification, which doesn't support InfluxData/Grafana repository format.

**Solution:** Use Docker installation (documented above) instead of APT packages.

**Technical Details:**
```bash
# Error message:
# E: Failed to fetch https://repos.influxdata.com/debian/dists/stable/InRelease
# E: The repository 'https://repos.influxdata.com/debian stable InRelease' is not signed.

# Why it happens:
# - Debian Trixie switched from gpgv to sqv for package verification
# - InfluxData repository uses older GPG format incompatible with sqv
# - Docker bypasses APT repository entirely
```

### USB Drive Not Mounting at Boot

**Problem:** `/mnt/sensor-data` is empty after reboot.

**Solution:**
```bash
# Check if drive is detected
lsblk

# Manual mount
sudo mount /dev/sda1 /mnt/sensor-data

# Check fstab entry
cat /etc/fstab | grep sensor-data

# Recreate fstab entry if missing
UUID=$(sudo blkid -s UUID -o value /dev/sda1)
echo "UUID=$UUID /mnt/sensor-data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Test
sudo umount /mnt/sensor-data
sudo mount -a
df -h | grep sensor-data
```

### Filesystem Corruption After Power Loss

**Problem:** Pi won't boot or shows filesystem errors after improper shutdown.

**Solution:**
```bash
# Boot Pi without USB drive connected
# SSH into Pi

# Check and repair USB filesystem
sudo fsck.ext4 -y /dev/sda1

# Check system config files
cat /etc/initramfs-tools/update-initramfs.conf
cat /etc/initramfs-tools/initramfs.conf

# If corrupted, restore defaults (see Step 2 above)
```

---

## Differences from Standard Installation

### Why Docker Instead of APT Packages?

**Standard `install.sh` approach:**
```bash
# InfluxDB via APT (FAILS on Debian Trixie)
wget -qO- https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor | sudo tee /usr/share/keyrings/influxdata-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/influxdata-archive-keyring.gpg] https://repos.influxdata.com/debian stable main" | sudo tee /etc/apt/sources.list.d/influxdb.list
sudo apt-get update
sudo apt-get install influxdb2  # FAILS with GPG verification error
```

**Recovery approach (Docker):**
```bash
# InfluxDB via Docker (WORKS on all distributions)
docker run -d --name influxdb --restart always -p 8086:8086 \
  -v /mnt/sensor-data/influxdb/data:/var/lib/influxdb2 \
  influxdb:2.7.12
```

**Why This Works:**
- Docker bypasses APT repository entirely
- Uses official Docker Hub images (maintained by InfluxData/Grafana)
- No GPG key verification issues
- Portable across distributions
- Easier to update/rollback

### Configuration Differences

| Setting | Standard install.sh | Docker Recovery |
|---------|-------------------|-----------------|
| **InfluxDB data** | `/var/lib/influxdb2` | `/mnt/sensor-data/influxdb/data` |
| **Grafana data** | `/var/lib/grafana` | `/mnt/sensor-data/grafana/data` |
| **Auto-start** | systemd services | Docker `--restart always` |
| **Updates** | `apt-get upgrade` | `docker pull && docker run` |
| **Logs** | `journalctl -u influxdb` | `docker logs influxdb` |

### Manual Steps Not Automated

The following steps cannot be automated and must be done manually:

1. **InfluxDB token generation** (security requirement)
2. **Grafana datasource UID** (generated dynamically)
3. **Cloudflare Tunnel authentication** (requires browser login)
4. **ESP8266 firmware updates** (requires physical access or OTA setup)

---

## Post-Recovery Checklist

### Verify Services Running

```bash
# Check Docker containers
docker ps

# Expected output:
# CONTAINER ID   IMAGE                 STATUS
# <id>           influxdb:2.7.12      Up X minutes
# <id>           grafana/grafana      Up X minutes

# Check Cloudflare Tunnel
sudo systemctl status cloudflared
# Expected: active (running)

# Check public access
curl -I https://grafana.owenmedeiros.com
# Expected: HTTP/2 200
```

### Verify Data Collection

```bash
# Query InfluxDB for recent readings
curl -s -XPOST "http://localhost:8086/api/v2/query?org=soil-monitoring" \
  -H "Authorization: Token <YOUR_READ_TOKEN>" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket: "sensor-readings")
      |> range(start: -1h)
      |> filter(fn: (r) => r._measurement == "sensor_reading")
      |> last()' | jq

# Expected: JSON with recent sensor readings
```

### Update ESP8266 Sensors

**Critical:** All sensors need new InfluxDB write token.

```bash
# See firmware update section in Step 10
# Or consult AGENTS.md for detailed sensor update procedures
```

### Test Grafana Dashboards

1. Open: `https://grafana.owenmedeiros.com`
2. Verify:
   - [ ] Main dashboard loads without errors
   - [ ] All sensor panels show data (or "No data" if sensors not updated yet)
   - [ ] Time range selector works
   - [ ] Dropdown filters work
   - [ ] Anonymous viewing works (incognito window)

### Configure Automated Backups

```bash
# Create backup script
sudo mkdir -p /mnt/sensor-data/backups
sudo tee /usr/local/bin/backup-sensor-data.sh > /dev/null <<'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/sensor-data/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup InfluxDB
docker exec influxdb influx backup /var/lib/influxdb2/backup-$DATE
docker cp influxdb:/var/lib/influxdb2/backup-$DATE $BACKUP_DIR/influxdb-$DATE

# Backup Grafana
tar -czf $BACKUP_DIR/grafana-$DATE.tar.gz /mnt/sensor-data/grafana/data

# Delete backups older than 30 days
find $BACKUP_DIR -type d -name "influxdb-*" -mtime +30 -exec rm -rf {} \;
find $BACKUP_DIR -type f -name "grafana-*.tar.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
EOF

sudo chmod +x /usr/local/bin/backup-sensor-data.sh

# Create systemd timer
sudo tee /etc/systemd/system/backup-sensor-data.timer > /dev/null <<'EOF'
[Unit]
Description=Daily sensor data backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/backup-sensor-data.service > /dev/null <<'EOF'
[Unit]
Description=Backup sensor data

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-sensor-data.sh
EOF

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable backup-sensor-data.timer
sudo systemctl start backup-sensor-data.timer

# Verify
sudo systemctl list-timers backup-sensor-data.timer
```

---

## Backup and Restore Procedures

### InfluxDB Backup

**Create backup:**
```bash
# Manual backup
docker exec influxdb influx backup /var/lib/influxdb2/backup-$(date +%Y%m%d)

# Copy to external location
docker cp influxdb:/var/lib/influxdb2/backup-$(date +%Y%m%d) ~/influxdb-backup-$(date +%Y%m%d)
```

**Restore backup:**
```bash
# Copy backup into container
docker cp ~/influxdb-backup-20260610 influxdb:/var/lib/influxdb2/

# Restore
docker exec influxdb influx restore /var/lib/influxdb2/backup-20260610

# Restart container
docker restart influxdb
```

### Grafana Backup

**Create backup:**
```bash
# Backup dashboards, datasources, settings
tar -czf ~/grafana-backup-$(date +%Y%m%d).tar.gz /mnt/sensor-data/grafana/data
```

**Restore backup:**
```bash
# Stop Grafana
docker stop grafana

# Restore data
sudo rm -rf /mnt/sensor-data/grafana/data/*
sudo tar -xzf ~/grafana-backup-20260610.tar.gz -C /

# Fix permissions
sudo chown -R 472:472 /mnt/sensor-data/grafana

# Start Grafana
docker start grafana
```

### Full System Backup (USB Drive)

**Create backup:**
```bash
# Backup entire USB drive to external storage
sudo dd if=/dev/sda1 of=/path/to/external/sensor-data-backup-$(date +%Y%m%d).img bs=4M status=progress
```

**Restore backup:**
```bash
# WARNING: This overwrites all data on USB drive!
sudo dd if=/path/to/external/sensor-data-backup-20260610.img of=/dev/sda1 bs=4M status=progress
```

### Export Data for Migration

**Export InfluxDB data to CSV:**
```bash
# Export all sensor readings to CSV
docker exec influxdb influx query \
  --org soil-monitoring \
  --token <YOUR_READ_TOKEN> \
  'from(bucket: "sensor-readings")
   |> range(start: 0)
   |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")' \
  --raw > sensor-data-export-$(date +%Y%m%d).csv
```

**Import CSV to new InfluxDB instance:**
```bash
# Use InfluxDB UI: Load Data → File Upload → CSV
# Or use API (see InfluxDB documentation)
```

---

## Additional Resources

- **InfluxDB Docker docs:** https://hub.docker.com/_/influxdb
- **Grafana Docker docs:** https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/
- **Cloudflare Tunnel docs:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **Project repository:** https://github.com/omedeiro/soil-sensor

---

## Recovery Summary

**What we recovered:**
- ✅ Fresh Raspberry Pi OS installation
- ✅ InfluxDB 2.7.12 (Docker)
- ✅ Grafana (Docker, anonymous viewing enabled)
- ✅ Cloudflare Tunnel (public HTTPS access)
- ✅ USB drive filesystem (repaired corruption)
- ✅ Grafana dashboards deployed
- ✅ System configuration documented

**What needs manual attention after recovery:**
- ⚠️ Update ESP8266 sensors with new InfluxDB token (7 sensors)
- ⚠️ Change Grafana admin password from default
- ⚠️ Configure automated backups (optional but recommended)
- ⚠️ Import historical data if available from backup

**Estimated recovery time:**
- Fresh install: ~2 hours
- With corrupted filesystem: +30 minutes
- With data restoration: +1-2 hours (depends on data size)

---

**Document version:** 1.0.0 (June 2026)  
**Last tested:** Raspberry Pi 5, Debian Trixie, Docker 27.x
