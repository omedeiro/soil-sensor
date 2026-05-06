#!/bin/bash
# Raspberry Pi 5 - Soil Sensor System Installation Script
# OS: Raspberry Pi OS Bookworm 64-bit
# Run with: sudo ./install.sh

set -e  # Exit on any error

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_section "🌱 Soil Sensor System Installer"

echo "This script will install and configure:"
echo "  - InfluxDB 2.x (time-series database)"
echo "  - Grafana (visualization platform)"
echo "  - Systemd services (auto-start on boot)"
echo "  - Health monitoring"
echo "  - Automated backups"
echo ""
echo "Prerequisites:"
echo "  ✓ Raspberry Pi 5 with Bookworm 64-bit"
echo "  ✓ 256GB USB drive inserted"
echo "  ✓ Internet connection"
echo ""
read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ─── Step 1: System Update ───────────────────────────────────────────────────

log_section "Step 1/8: System Update"

log_info "Updating package lists..."
apt update

log_info "Upgrading existing packages..."
apt upgrade -y

log_info "Installing prerequisites..."
apt install -y curl gnupg lsb-release ufw vim htop git python3 python3-pip

# ─── Step 2: USB Drive Setup ─────────────────────────────────────────────────

log_section "Step 2/8: USB Drive Setup"

# Detect USB drive - target whole disk (not partition) to allow full reformatting
# Use grep -oP to extract clean /dev/sdX path, stripping any unicode box-drawing chars from lsblk TTY output
USB_DEVICE=$(lsblk -lnp -o NAME,TYPE | awk '$2=="disk"' | grep -oP '/dev/sd\w+' | head -1)

if [[ -z "$USB_DEVICE" ]]; then
    log_warn "Could not auto-detect USB drive"
    echo "Available devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    echo ""
    read -p "Enter USB device path (e.g., /dev/sda1): " USB_DEVICE
fi

log_info "Using USB device: $USB_DEVICE"

log_info "Formatting as ext4 (THIS WILL ERASE ALL DATA)..."
read -p "Are you sure? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Unmount all partitions on this disk first
    for part in ${USB_DEVICE}*; do
        if mount | grep -q "$part"; then
            log_warn "Unmounting $part..."
            umount "$part" || true
        fi
    done

    # Wipe partition table and create a single ext4 partition
    log_info "Creating new partition table on $USB_DEVICE..."
    parted -s "$USB_DEVICE" mklabel gpt
    parted -s "$USB_DEVICE" mkpart primary ext4 0% 100%
    sleep 2  # Wait for kernel to re-read partition table

    USB_PARTITION="${USB_DEVICE}1"
    log_info "Formatting partition $USB_PARTITION as ext4..."
    mkfs.ext4 -F -L sensor-data "$USB_PARTITION"
else
    log_warn "Skipping format — using existing partition ${USB_DEVICE}1"
    USB_PARTITION="${USB_DEVICE}1"
fi

# Get UUID
USB_UUID=$(blkid -s UUID -o value "$USB_PARTITION")
log_info "USB Drive UUID: $USB_UUID"

# Create mount point
mkdir -p /mnt/sensor-data

# Add to fstab if not already there
if ! grep -q "$USB_UUID" /etc/fstab; then
    log_info "Adding to /etc/fstab..."
    echo "UUID=$USB_UUID /mnt/sensor-data ext4 defaults,nofail,noatime 0 2" >> /etc/fstab
fi

# Mount
log_info "Mounting USB drive..."
mount -a
mount | grep sensor-data

# Create directory structure
log_info "Creating directory structure..."
mkdir -p /mnt/sensor-data/{influxdb,grafana,backups,logs,docs}
# influxdb dir will be chowned to influxdb user after install; set rest to sudoer
chown -R "${SUDO_USER:-omedeiro}:${SUDO_USER:-omedeiro}" /mnt/sensor-data

# ─── Step 3: Configure Network ───────────────────────────────────────────────

log_section "Step 3/8: Network Configuration"

# Get current IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
log_info "Current IP address: $CURRENT_IP"

read -p "Configure static IP? (recommended) (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    while true; do
        read -p "Enter desired static IP [$CURRENT_IP]: " STATIC_IP
        STATIC_IP=${STATIC_IP:-$CURRENT_IP}
        if [[ "$STATIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
        log_warn "Invalid IP address '$STATIC_IP'. Please enter a valid IPv4 address (e.g. 192.168.99.200)."
    done
    
    read -p "Enter router IP [192.168.99.1]: " ROUTER_IP
    ROUTER_IP=${ROUTER_IP:-192.168.99.1}
    
    log_info "Configuring static IP: $STATIC_IP"
    
    # Backup dhcpcd.conf (only if not already backed up)
    [[ ! -f /etc/dhcpcd.conf.backup ]] && cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup

    # Remove any previous static IP block added by this script, then re-add
    sed -i '/# Static IP for Soil Sensor System/,+4d' /etc/dhcpcd.conf
    
    # Add static IP configuration
    cat >> /etc/dhcpcd.conf <<EOF

# Static IP for Soil Sensor System
interface wlan0
static ip_address=${STATIC_IP}/24
static routers=${ROUTER_IP}
static domain_name_servers=${ROUTER_IP} 8.8.8.8
EOF
    
    log_info "Static IP configured (will apply after reboot)"
else
    STATIC_IP=$CURRENT_IP
fi

# Configure firewall
log_info "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 8086/tcp # InfluxDB
ufw allow 3000/tcp # Grafana
echo "y" | ufw enable

log_info "Firewall configured and enabled"

# ─── Step 4: Install InfluxDB ────────────────────────────────────────────────

log_section "Step 4/8: Installing InfluxDB 2.x"

log_info "Adding InfluxData repository..."
# Use the current InfluxDB GPG key (required for Debian Trixie with sqv)
curl -fsSL https://repos.influxdata.com/influxdata-archive.key | \
    gpg --dearmor | tee /etc/apt/trusted.gpg.d/influxdata-archive.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' \
    | tee /etc/apt/sources.list.d/influxdata.list

log_info "Installing InfluxDB..."
apt update
apt install -y influxdb2

# Configure InfluxDB to use USB storage
log_info "Configuring InfluxDB for USB storage..."
mkdir -p /etc/systemd/system/influxdb.service.d
cat > /etc/systemd/system/influxdb.service.d/override.conf <<EOF
[Unit]
RequiresMountsFor=/mnt/sensor-data
After=mnt-sensor\\x2ddata.mount

[Service]
Environment="INFLUXD_ENGINE_PATH=/mnt/sensor-data/influxdb"
Environment="INFLUXD_BOLT_PATH=/mnt/sensor-data/influxdb/influxd.bolt"
Restart=always
RestartSec=10
EOF

systemctl daemon-reload
systemctl enable influxdb
# Fix ownership before starting - influxd runs as influxdb user, not root
chown -R influxdb:influxdb /mnt/sensor-data/influxdb
systemctl start influxdb

log_info "Waiting for InfluxDB to start..."
sleep 5

if systemctl is-active --quiet influxdb; then
    log_info "InfluxDB is running"
else
    log_error "InfluxDB failed to start"
    journalctl -u influxdb -n 20
    exit 1
fi

# ─── Step 5: Install Grafana ─────────────────────────────────────────────────

log_section "Step 5/8: Installing Grafana"

log_info "Adding Grafana repository..."
apt install -y software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list

log_info "Installing Grafana..."
apt update
apt install -y grafana

# Configure Grafana for USB storage
log_info "Configuring Grafana for USB storage..."
mkdir -p /mnt/sensor-data/grafana/{data,plugins}
chown -R grafana:grafana /mnt/sensor-data/grafana

# Backup original config
cp /etc/grafana/grafana.ini /etc/grafana/grafana.ini.backup

# Update paths in grafana.ini
sed -i "s|^;data = .*|data = /mnt/sensor-data/grafana/data|" /etc/grafana/grafana.ini
sed -i "s|^;logs = .*|logs = /mnt/sensor-data/logs/grafana|" /etc/grafana/grafana.ini
sed -i "s|^;plugins = .*|plugins = /mnt/sensor-data/grafana/plugins|" /etc/grafana/grafana.ini
sed -i "s|^;http_addr = .*|http_addr = 0.0.0.0|" /etc/grafana/grafana.ini

systemctl enable grafana-server
systemctl start grafana-server

log_info "Waiting for Grafana to start..."
sleep 5

if systemctl is-active --quiet grafana-server; then
    log_info "Grafana is running"
else
    log_error "Grafana failed to start"
    journalctl -u grafana-server -n 20
    exit 1
fi

# ─── Step 6: Install Monitoring Services ─────────────────────────────────────

log_section "Step 6/8: Installing Monitoring Services"

# Copy health monitor script
log_info "Installing health monitor..."
cp scripts/sensor-health-monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/sensor-health-monitor.sh
cp systemd/sensor-health-monitor.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable sensor-health-monitor
systemctl start sensor-health-monitor

# ─── Step 7: Install Backup System ──────────────────────────────────────────

log_section "Step 7/8: Installing Backup System"

log_info "Installing backup scripts..."
cp scripts/sensor-backup.sh /usr/local/bin/
chmod +x /usr/local/bin/sensor-backup.sh
cp systemd/sensor-backup.service /etc/systemd/system/
cp systemd/sensor-backup.timer /etc/systemd/system/

systemctl daemon-reload
systemctl enable sensor-backup.timer
systemctl start sensor-backup.timer

log_info "Backup scheduled for daily at 3:00 AM"

# ─── Step 8: Final Setup ─────────────────────────────────────────────────────

log_section "Step 8/8: Final Setup"

# Set timezone
log_info "Setting timezone..."
timedatectl set-timezone America/New_York

# Install Python dependencies for scripts
log_info "Installing Python dependencies..."
pip3 install requests influxdb-client --break-system-packages

# Copy documentation
log_info "Copying documentation..."
cp -r ../docs/* /mnt/sensor-data/docs/ 2>/dev/null || true

# Create quick reference
cat > /mnt/sensor-data/QUICK_REFERENCE.txt <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║           🌱 SOIL SENSOR SYSTEM QUICK REFERENCE                ║
╚════════════════════════════════════════════════════════════════╝

┌─ SYSTEM INFO ──────────────────────────────────────────────────┐
│ InfluxDB URL:     http://STATIC_IP_PLACEHOLDER:8086            │
│ Grafana URL:      http://STATIC_IP_PLACEHOLDER:3000            │
│ Data Storage:     /mnt/sensor-data (256GB USB)                 │
└────────────────────────────────────────────────────────────────┘

┌─ DEFAULT CREDENTIALS ──────────────────────────────────────────┐
│ Grafana:          admin / admin (CHANGE ON FIRST LOGIN!)       │
│ InfluxDB:         Setup via web UI at :8086                    │
└────────────────────────────────────────────────────────────────┘

┌─ SERVICES ─────────────────────────────────────────────────────┐
│ Check status:     sudo systemctl status influxdb              │
│                   sudo systemctl status grafana-server        │
│                   sudo systemctl status sensor-health-monitor │
│ View logs:        journalctl -u influxdb -f                   │
│ Restart:          sudo systemctl restart influxdb             │
└────────────────────────────────────────────────────────────────┘

┌─ NEXT STEPS ───────────────────────────────────────────────────┐
│ 1. Open InfluxDB:  http://STATIC_IP_PLACEHOLDER:8086          │
│    - Complete setup wizard                                     │
│    - Create org: soil-monitoring                              │
│    - Create bucket: sensor-readings (365d retention)          │
│    - Generate ESP8266 write token                             │
│                                                                │
│ 2. Open Grafana:   http://STATIC_IP_PLACEHOLDER:3000          │
│    - Login with admin/admin                                   │
│    - Add InfluxDB data source                                 │
│    - Import dashboards from /mnt/sensor-data/docs/            │
│                                                                │
│ 3. Configure ESP8266:                                         │
│    - Update firmware/src/config.h with InfluxDB details       │
│    - Upload firmware                                           │
│    - Monitor serial output                                     │
└────────────────────────────────────────────────────────────────┘
EOF

sed -i "s/STATIC_IP_PLACEHOLDER/$STATIC_IP/g" /mnt/sensor-data/QUICK_REFERENCE.txt

# ─── Installation Complete ───────────────────────────────────────────────────

log_section "Installation Complete! 🎉"

echo ""
echo "System Status:"
echo "  InfluxDB:       $(systemctl is-active influxdb)"
echo "  Grafana:        $(systemctl is-active grafana-server)"
echo "  Health Monitor: $(systemctl is-active sensor-health-monitor)"
echo "  Backup Timer:   $(systemctl is-active sensor-backup.timer)"
echo ""
echo "Access URLs:"
echo "  InfluxDB:  http://$STATIC_IP:8086"
echo "  Grafana:   http://$STATIC_IP:3000"
echo ""
echo "Next Steps:"
echo "  1. Complete InfluxDB setup at http://$STATIC_IP:8086"
echo "     - Create organization: soil-monitoring"
echo "     - Create bucket: sensor-readings (365 day retention)"
echo "     - Generate API tokens for ESP8266 and Grafana"
echo ""
echo "  2. Configure Grafana at http://$STATIC_IP:3000"
echo "     - Login: admin / admin (change password!)"
echo "     - Add InfluxDB data source"
echo "     - Import dashboards"
echo ""
echo "  3. Update ESP8266 firmware with InfluxDB settings"
echo ""
echo "Documentation: /mnt/sensor-data/docs/"
echo "Quick Reference: /mnt/sensor-data/QUICK_REFERENCE.txt"
echo ""
log_warn "REBOOT RECOMMENDED to apply all changes"
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Rebooting..."
    reboot
fi
