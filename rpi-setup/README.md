# Raspberry Pi Setup Scripts

Scripts for installing and configuring the Soil Moisture Monitoring System on Raspberry Pi 5.

---

## Quick Start

### Initial Setup (One-time installation)

```bash
git clone https://github.com/omedeiro/soil-sensor.git
cd soil-sensor/rpi-setup
sudo ./install.sh
```

This installs:
- InfluxDB 2.7.12 (pinned version for ARM64 compatibility)
- Grafana (latest stable)
- System metrics collector (CPU, RAM, disk monitoring)
- Health monitoring service
- Automated backups
- UFW firewall configuration

### Public Access Setup (Optional)

**Enable public HTTPS access via Cloudflare Tunnel:**

```bash
./install-cloudflare-tunnel.sh      # Set up Cloudflare Tunnel
./configure-grafana-anonymous.sh    # Enable anonymous viewing
```

After setup, your Grafana dashboards will be publicly accessible at `https://grafana.owenmedeiros.com` (or your configured domain).

### Enhanced Logging (Optional)

**Install enhanced logging system:**

```bash
sudo ./install-logging.sh
```

This adds:
- Boot event tracking
- Filesystem corruption detection
- Grafana failure logging
- Automatic log rotation

See [LOGGING_README.md](LOGGING_README.md) for details.

### Sensor Health Monitoring (Recommended)

**Install automated sensor offline detection:**

```bash
./install-sensor-monitoring.sh
```

This installs:
- Automated health checks every 10 minutes
- Alerts when sensors stop posting (15+ minutes offline)
- System journal logging for troubleshooting
- Integration with Grafana alerts dashboard

After installation:
```bash
# View monitoring status
systemctl status sensor-health-check.timer

# View logs in real-time
journalctl -u sensor-health-check -f

# Manual health check
~/rpi-setup/scripts/check-sensor-health.sh --alert-minutes 15
```

---

## Installation Scripts

### `install.sh`
**Main installation script** — Sets up complete monitoring system.

**What it does:**
- Mounts 256GB USB drive to `/mnt/sensor-data`
- Installs InfluxDB 2.7.12 (ARM64)
- Installs Grafana (latest stable)
- Configures systemd services for auto-start
- Sets up UFW firewall (ports 22, 8086, 3000)
- Installs system metrics collector
- Configures health monitoring
- Sets up daily automated backups

**Post-install steps:**
1. Configure InfluxDB at `http://<pi-ip>:8086`
   - Create org: `soil-monitoring`
   - Create bucket: `sensor-readings` (365-day retention)
   - Generate write token for ESP8266
   - Generate read token for Grafana

2. Configure Grafana at `http://<pi-ip>:3000`
   - Login: `admin` / `admin` (change on first login)
   - Add InfluxDB datasource (Flux mode)
   - Import dashboards from `grafana-dashboards/`

---

### `install-cloudflare-tunnel.sh`
**Cloudflare Tunnel installer** — Enables public HTTPS access to Grafana.

**What it does:**
- Downloads and installs `cloudflared` (ARM64 binary)
- Authenticates with Cloudflare account
- Creates tunnel named `soil-sensor-grafana`
- Configures DNS routing (`grafana.owenmedeiros.com`)
- Installs as systemd service (auto-starts on boot)

**Prerequisites:**
- Cloudflare account (free)
- Domain name added to Cloudflare (or use free `trycloudflare.com` subdomain)

**Usage:**
```bash
./install-cloudflare-tunnel.sh
```

**Interactive steps:**
1. Script will open browser for Cloudflare authentication
2. Download `cert.pem` from browser
3. Script will detect and use the certificate
4. DNS record created automatically

**Verify installation:**
```bash
sudo systemctl status cloudflared
cloudflared tunnel list
```

---

### `configure-grafana-anonymous.sh`
**Grafana anonymous access configurator** — Enables read-only public viewing.

**What it does:**
- Enables anonymous access in Grafana config
- Sets all anonymous users to Viewer role (read-only)
- Disables user signup (prevents random account creation)
- Sets root URL to public domain
- Restarts Grafana to apply changes

**Usage:**
```bash
./configure-grafana-anonymous.sh
```

**Security settings:**
- ✅ Anyone can **VIEW** dashboards (no login required)
- ✅ Only admins can **EDIT** dashboards
- ✅ User signup **DISABLED** (no random accounts)

**Admin access:**
- Local: `http://192.168.99.134:3000` → Sign in
- Public: `https://grafana.owenmedeiros.com` → Sign in

---

### `install-logging.sh`
**Enhanced logging system installer** — Adds boot tracking and failure monitoring.

**What it does:**
- Installs startup logger (tracks boot events, filesystem corruption)
- Adds Grafana failure logging to health monitor
- Configures log rotation (prevents disk space issues)
- Creates systemd service for startup logger

**Logs created:**
- `/mnt/sensor-data/logs/startup_history.log` — Boot events and reasons
- `/mnt/sensor-data/logs/grafana_failures.log` — Grafana restart triggers
- `/mnt/sensor-data/logs/reboot_reasons.log` — Automatic reboot triggers
- `/mnt/sensor-data/logs/health-monitor.log` — Service monitoring

**Usage:**
```bash
sudo ./install-logging.sh
```

See [LOGGING_README.md](LOGGING_README.md) for complete documentation.

---

### `install-audit-logger.sh`
**Audit logger installer** — Tracks system events and changes (advanced).

**Usage:**
```bash
sudo ./install-audit-logger.sh
```

---

## System Services

After installation, these systemd services are available:

| Service | Description | Auto-start |
|---------|-------------|-----------|
| `influxdb` | Time-series database | ✅ Yes |
| `grafana-server` | Dashboard server | ✅ Yes |
| `cloudflared` | Cloudflare Tunnel (if installed) | ✅ Yes |
| `system-metrics-collector` | Pi CPU/RAM/disk monitoring | ✅ Yes |
| `sensor-health-monitor` | Service monitoring and auto-restart | ✅ Yes |
| `sensor-backup.timer` | Daily backup at 3:00 AM | ✅ Yes |
| `startup-logger` | Boot event logging (if installed) | ✅ Yes |

**Common commands:**
```bash
# Check service status
sudo systemctl status influxdb grafana-server cloudflared

# View logs
sudo journalctl -u influxdb -f
sudo journalctl -u cloudflared -f

# Restart services
sudo systemctl restart grafana-server
sudo systemctl restart cloudflared

# Enable/disable auto-start
sudo systemctl enable cloudflared
sudo systemctl disable cloudflared
```

---

## Directory Structure

```
rpi-setup/
├── install.sh                          # Main installer
├── install-cloudflare-tunnel.sh        # Cloudflare Tunnel setup
├── configure-grafana-anonymous.sh      # Anonymous viewing config
├── install-logging.sh                  # Enhanced logging installer
├── install-audit-logger.sh             # Audit logger installer
├── README.md                           # This file
├── LOGGING_README.md                   # Logging documentation
├── scripts/
│   ├── sensor-backup.sh                # Daily backup script
│   ├── sensor-health-monitor.sh        # Service monitoring
│   ├── startup-logger.sh               # Boot event logger
│   └── system-metrics-collector.py     # Pi metrics collector
├── systemd/
│   ├── cloudflared.service             # Cloudflare Tunnel service
│   ├── sensor-backup.service           # Backup service
│   ├── sensor-backup.timer             # Backup timer (3 AM daily)
│   ├── sensor-health-monitor.service   # Health monitor
│   ├── startup-logger.service          # Boot logger
│   └── system-metrics-collector.service # Metrics collector
├── grafana-config/
│   └── grafana.ini                     # Grafana config template
├── grafana-provisioning/
│   ├── dashboards.yml                  # Dashboard provisioning
│   └── datasources.yml                 # InfluxDB datasource config
└── logrotate.d/
    └── soil-sensor                     # Log rotation config
```

---

## Troubleshooting

### Cloudflare Tunnel Issues

**Tunnel not connecting:**
```bash
# Check service status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f

# Restart tunnel
sudo systemctl restart cloudflared

# Verify tunnel is registered
cloudflared tunnel list
```

**DNS not resolving:**
- Wait 1-5 minutes for DNS propagation after initial setup
- Verify DNS record: `dig grafana.owenmedeiros.com`
- Check Cloudflare dashboard for DNS settings

### Grafana Anonymous Access Issues

**Still requires login:**
```bash
# Check Grafana config
sudo grep -A5 "auth.anonymous" /etc/grafana/grafana.ini

# Verify anonymous is enabled
# Should show: enabled = true, org_role = Viewer

# Restart Grafana
sudo systemctl restart grafana-server
```

**Can't edit dashboards:**
- This is expected for anonymous users (read-only)
- Log in as admin to edit: Click "Sign in" at bottom of page
- Admin credentials: Set during initial Grafana setup

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u <service-name> --no-pager
```

**Common issues:**
- USB drive not mounted: `mount | grep sensor-data`
- Port already in use: `sudo netstat -tulpn | grep <port>`
- Permission issues: Check file ownership in `/mnt/sensor-data/`

---

## Upgrade Notes

### Updating Cloudflare Tunnel

```bash
# Download latest version
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64

# Replace binary
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

# Restart service
sudo systemctl restart cloudflared
```

### Updating Grafana

```bash
# Update package lists
sudo apt update

# Upgrade Grafana
sudo apt upgrade grafana

# Restart Grafana
sudo systemctl restart grafana-server
```

---

## Security Notes

**Cloudflare Tunnel:**
- No ports exposed on home network
- Automatic SSL/TLS certificate management
- DDoS protection via Cloudflare edge network

**Anonymous Grafana Access:**
- Read-only access (Viewer role)
- No editing, no admin panel access
- User signup disabled

**Admin Access:**
- Always available via local network
- Can also sign in via public URL
- Consider strong password and 2FA

---

## Support

For issues or questions:
1. Check logs: `journalctl -u <service> -f`
2. Review [AGENTS.md](../AGENTS.md) troubleshooting section
3. Check service status: `systemctl status <service>`
4. Verify USB drive: `df -h | grep sensor-data`
