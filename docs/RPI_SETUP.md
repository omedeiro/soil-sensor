# Raspberry Pi Setup Guide - Soil Sensor System

Complete guide for setting up InfluxDB + Grafana on Raspberry Pi 5 for soil sensor monitoring.

## 📋 Prerequisites

- Raspberry Pi 5 with Raspberry Pi OS Bookworm 64-bit installed
- 256GB USB flash drive (will be formatted - **data will be erased**)
- Internet connection (WiFi or Ethernet)
- SSH access or direct access to Pi

## 🚀 Quick Start (One-Command Install)

1. Copy the `rpi-setup/` directory to your Raspberry Pi:
   ```bash
   scp -r rpi-setup/ pi@raspberrypi.local:~/
   ```

2. SSH into the Raspberry Pi:
   ```bash
   ssh omedeiro@raspberrypi.local
   ```

3. Run the installation script:
   ```bash
   cd rpi-setup
   sudo ./install.sh
   ```

4. Follow the prompts:
   - Confirm USB drive formatting
   - Optionally configure static IP
   - Wait for installation (5-10 minutes)
   - Reboot when prompted

## 📊 Post-Installation Setup

### Step 1: Configure InfluxDB

1. Open InfluxDB web UI:
   ```
   http://<raspberry-pi-ip>:8086
   ```

2. Complete the setup wizard:
   - **Username**: admin
   - **Password**: (create a strong password)
   - **Organization**: `soil-monitoring`
   - **Bucket**: `sensor-readings`
   - **Retention**: 365 days

3. Generate API Tokens:
   
   **ESP8266 Write Token:**
   - Go to: Settings → Tokens → Generate Token → Custom Token
   - Permissions:
     - Write access to `sensor-readings` bucket
   - Copy and save this token - you'll need it for ESP8266 configuration

   **Grafana Read Token:**
   - Generate another Custom Token
   - Permissions:
     - Read access to `sensor-readings` bucket
   - Copy and save this token for Grafana configuration

### Step 2: Configure Grafana

1. Open Grafana web UI:
   ```
   http://<raspberry-pi-ip>:3000
   ```

2. Login with default credentials:
   - **Username**: admin
   - **Password**: admin
   - **Change password when prompted!**

3. Add InfluxDB Data Source:
   - Go to: Configuration → Data Sources → Add data source
   - Select: **InfluxDB**
   - Configure:
     - **Name**: `InfluxDB-SoilSensors`
     - **Query Language**: `Flux`
     - **URL**: `http://localhost:8086`
     - **Organization**: `soil-monitoring`
     - **Token**: (paste Grafana Read Token from Step 1)
     - **Default Bucket**: `sensor-readings`
   - Click **Save & Test** (should show green checkmark)

4. Import Dashboards:
   - Go to: Dashboards → Import
   - Upload dashboard JSON files from `grafana-dashboards/` directory
   - (Dashboards will be created in next phase of implementation)

### Step 3: Configure ESP8266 Firmware

1. On your development machine, edit `firmware/src/config.h`:

   ```cpp
   // Update these values:
   #define DB_SERVER_URL       "http://192.168.99.200:8086/api/v2/write"  // Use your Pi's IP
   #define INFLUX_TOKEN        "YOUR_ESP8266_WRITE_TOKEN_HERE"  // From Step 1
   #define INFLUX_ORG          "soil-monitoring"
   #define INFLUX_BUCKET       "sensor-readings"
   
   #define DEVICE_ID_AUTO      false
   #define DEVICE_ID           "sensor-1"  // Unique ID for this sensor
   #define DEVICE_LOCATION     "test-bench"  // Location tag
   ```

2. Compile and upload firmware:
   ```bash
   cd firmware
   pio run --target upload
   pio device monitor
   ```

3. Watch serial output for:
   ```
   [WiFi] ✓ Connected
   [DB] ✓ Posted to InfluxDB (HTTP 204)
   ```

### Step 4: Verify Data Flow

1. Run the end-to-end test:
   ```bash
   export INFLUX_TOKEN="your_write_token"
   export INFLUX_ORG="soil-monitoring"
   export INFLUX_BUCKET="sensor-readings"
   
   cd tests
   ./test_e2e.sh
   ```

2. Check Grafana dashboards for live data

3. Monitor ESP8266 serial output for successful POSTs

## 🔧 System Management

### Service Status

Check if services are running:
```bash
sudo systemctl status influxdb
sudo systemctl status grafana-server
sudo systemctl status sensor-health-monitor
```

### View Logs

InfluxDB logs:
```bash
journalctl -u influxdb -f
```

Grafana logs:
```bash
journalctl -u grafana-server -f
```

Health monitor logs:
```bash
tail -f /mnt/sensor-data/logs/health-monitor.log
```

### Restart Services

```bash
sudo systemctl restart influxdb
sudo systemctl restart grafana-server
```

### Manual Backup

```bash
/usr/local/bin/sensor-backup.sh
```

Backups are stored in: `/mnt/sensor-data/backups/`

## 🌐 Network Access

### From Same Network

- **InfluxDB**: `http://<pi-ip>:8086`
- **Grafana**: `http://<pi-ip>:3000`

### Find Your Pi's IP Address

```bash
hostname -I
```

Or on the Pi:
```bash
ip addr show wlan0 | grep "inet " | awk '{print $2}'
```

## 🐛 Troubleshooting

### InfluxDB Not Starting

```bash
# Check logs
journalctl -u influxdb -n 50

# Check if USB drive is mounted
df -h /mnt/sensor-data

# Manually mount if needed
sudo mount -a
```

### USB Drive Not Mounting

```bash
# Check if drive is detected
lsblk

# Check fstab entry
cat /etc/fstab | grep sensor-data

# Manual mount
sudo mount /mnt/sensor-data
```

### Grafana Data Source Connection Failed

- Verify InfluxDB is running: `curl http://localhost:8086/health`
- Check token has read permission
- Verify organization and bucket names match

### ESP8266 Not Sending Data

1. Check serial output: `pio device monitor`
2. Verify WiFi connection
3. Check InfluxDB URL in `config.h` matches Pi's IP
4. Verify write token is correct
5. Test write manually: `./tests/test_influx_write.sh`

## 📦 Backup & Restore

### Automatic Backups

Backups run daily at 3:00 AM automatically. Check status:
```bash
systemctl status sensor-backup.timer
systemctl list-timers
```

### Manual Restore

```bash
# List available backups
ls -lh /mnt/sensor-data/backups/

# Restore from backup
influx restore /mnt/sensor-data/backups/influx_YYYYMMDD_HHMMSS \
  --host http://localhost:8086 \
  --org soil-monitoring \
  --token YOUR_ADMIN_TOKEN
```

## 🔒 Security

### Change Default Passwords

1. **Grafana**: Change on first login
2. **InfluxDB**: Set during initial setup
3. **SSH**: Change Pi's password
   ```bash
   passwd
   ```

### Firewall Status

```bash
sudo ufw status
```

### Regenerate Tokens

If tokens are compromised:
1. Go to InfluxDB UI → Settings → Tokens
2. Delete old token
3. Generate new token
4. Update ESP8266 `config.h` and Grafana data source

## 📁 Directory Structure

```
/mnt/sensor-data/
├── influxdb/          # InfluxDB data files
├── grafana/           # Grafana dashboards and config
│   ├── data/
│   └── plugins/
├── backups/           # Daily backups
│   ├── influx_YYYYMMDD_HHMMSS/
│   └── export_YYYYMMDD_HHMMSS.csv
├── logs/              # Service logs
│   ├── health-monitor.log
│   ├── backup.log
│   └── grafana/
└── docs/              # Documentation
```

## 🆘 Getting Help

1. Check logs first (see "View Logs" section)
2. Run test script: `./tests/test_e2e.sh`
3. Check `TROUBLESHOOTING.md` (to be created)
4. Review `AGENTS.md` for system architecture

## 🎯 Next Steps

- [ ] Add additional sensors (update `DEVICE_ID` for each)
- [ ] Configure alert rules in Grafana
- [ ] Set up push notifications
- [ ] Create custom dashboards
- [ ] Enable Grafana Cloud sync (optional)

---

**Installation complete!** Your Raspberry Pi is now ready to receive data from ESP8266 sensors.
