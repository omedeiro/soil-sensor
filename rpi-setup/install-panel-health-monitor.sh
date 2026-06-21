#!/bin/bash
#
# install-panel-health-monitor.sh
# Install Grafana Panel Health Monitoring system on Raspberry Pi
#
# This script installs:
#   - Systemd service and timer for automated monitoring
#   - Python dependencies for panel checker
#   - Slack webhook configuration
#   - Log directory structure
#

set -euo pipefail

# Colors
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
RESET='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
CONFIG_DIR="/mnt/sensor-data/config"
LOG_DIR="/mnt/sensor-data/logs"

# Slack webhook URL (will prompt user)
SLACK_WEBHOOK_URL=""

# Print header
echo "════════════════════════════════════════════════════════════"
echo "Grafana Panel Health Monitor - Installation"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if running on Raspberry Pi
if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: This doesn't appear to be a Raspberry Pi${RESET}"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
fi

# Check if running as regular user (not root)
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}ERROR: Do not run this script as root${RESET}"
    echo "Run as regular user with sudo privileges"
    exit 1
fi

# Step 1: Install Python dependencies
echo "Step 1: Installing Python dependencies"
echo "────────────────────────────────────────────────────────────"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: Python 3 not found${RESET}"
    exit 1
fi

if ! command -v pip3 &> /dev/null; then
    echo "Installing pip3..."
    sudo apt-get update
    sudo apt-get install -y python3-pip
fi

echo "Installing Python packages..."
pip3 install --user requests 2>&1 | grep -E "(Requirement|Installing|Successfully)" || true

echo -e "${GREEN}✓ Python dependencies installed${RESET}"
echo ""

# Step 2: Create directory structure
echo "Step 2: Creating directory structure"
echo "────────────────────────────────────────────────────────────"

sudo mkdir -p "$CONFIG_DIR"
sudo mkdir -p "$LOG_DIR"
sudo chown -R "$USER:$USER" "$CONFIG_DIR" "$LOG_DIR"
chmod 755 "$CONFIG_DIR" "$LOG_DIR"

echo -e "${GREEN}✓ Directories created${RESET}"
echo "  - Config: $CONFIG_DIR"
echo "  - Logs:   $LOG_DIR"
echo ""

# Step 3: Configure Slack webhook
echo "Step 3: Configuring Slack webhook"
echo "────────────────────────────────────────────────────────────"

WEBHOOK_FILE="$CONFIG_DIR/slack_webhook_url"

if [[ -f "$WEBHOOK_FILE" ]]; then
    echo -e "${YELLOW}Slack webhook already configured${RESET}"
    EXISTING_URL=$(cat "$WEBHOOK_FILE")
    echo "Current URL: ${EXISTING_URL:0:40}..."
    read -p "Update webhook URL? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter new Slack webhook URL: " SLACK_WEBHOOK_URL
    else
        SLACK_WEBHOOK_URL="$EXISTING_URL"
    fi
else
    echo "No webhook configured yet"
    read -p "Enter Slack webhook URL (or press Enter to skip): " SLACK_WEBHOOK_URL
fi

if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    # Write with restrictive umask so the secret is never world-readable, even briefly
    ( umask 077; printf '%s' "$SLACK_WEBHOOK_URL" > "$WEBHOOK_FILE" )
    chmod 600 "$WEBHOOK_FILE"
    echo -e "${GREEN}✓ Slack webhook configured${RESET}"
    echo "  File: $WEBHOOK_FILE (chmod 600)"

    # Self-verify: send a test message through the new webhook
    if [[ -x "$PROJECT_ROOT/scripts/send-slack-alert.sh" ]]; then
        echo "  Sending Slack test message..."
        if SLACK_WEBHOOK_FILE="$WEBHOOK_FILE" \
           "$PROJECT_ROOT/scripts/send-slack-alert.sh" \
             --severity success --no-rate-limit \
             --title "Panel Health Monitor installed" \
             --message "Slack alerts configured on $(hostname) at $(date)"; then
            echo -e "  ${GREEN}✓ Slack test message delivered${RESET}"
        else
            echo -e "  ${YELLOW}⚠ Slack test message failed — verify the webhook URL is valid and not revoked${RESET}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Slack webhook not configured (you can add it later)${RESET}"
    echo "  To configure later (secure):"
    echo "    ( umask 077; printf '%s' 'YOUR_WEBHOOK_URL' > $WEBHOOK_FILE ); chmod 600 $WEBHOOK_FILE"
fi

echo ""

# Step 3b: Configure secrets/env file for the systemd service
echo "Step 3b: Configuring service environment (secrets)"
echo "────────────────────────────────────────────────────────────"

ENV_FILE="$CONFIG_DIR/panel-health.env"

if [[ -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}Environment file already exists${RESET}"
    echo "  File: $ENV_FILE"
    read -p "Overwrite secrets (InfluxDB token / Grafana creds)? [y/N] " -n 1 -r
    echo
    WRITE_ENV=false
    [[ $REPLY =~ ^[Yy]$ ]] && WRITE_ENV=true
else
    WRITE_ENV=true
fi

if [[ "$WRITE_ENV" == "true" ]]; then
    read -p "InfluxDB token (write/read): " INFLUX_TOKEN_INPUT
    read -p "InfluxDB URL [http://localhost:8086]: " INFLUX_URL_INPUT
    INFLUX_URL_INPUT="${INFLUX_URL_INPUT:-http://localhost:8086}"
    read -p "InfluxDB org [soil-monitoring]: " INFLUX_ORG_INPUT
    INFLUX_ORG_INPUT="${INFLUX_ORG_INPUT:-soil-monitoring}"
    read -p "InfluxDB bucket [sensor-readings]: " INFLUX_BUCKET_INPUT
    INFLUX_BUCKET_INPUT="${INFLUX_BUCKET_INPUT:-sensor-readings}"
    read -p "Grafana URL [http://localhost:3000]: " GRAFANA_URL_INPUT
    GRAFANA_URL_INPUT="${GRAFANA_URL_INPUT:-http://localhost:3000}"
    read -p "Grafana user [admin]: " GRAFANA_USER_INPUT
    GRAFANA_USER_INPUT="${GRAFANA_USER_INPUT:-admin}"
    read -p "Grafana password [admin]: " GRAFANA_PASSWORD_INPUT
    GRAFANA_PASSWORD_INPUT="${GRAFANA_PASSWORD_INPUT:-admin}"

    ( umask 077; cat > "$ENV_FILE" <<EOF
# Secrets for grafana-panel-health.service — NOT tracked in git (chmod 600)
INFLUX_TOKEN=$INFLUX_TOKEN_INPUT
INFLUX_URL=$INFLUX_URL_INPUT
INFLUX_ORG=$INFLUX_ORG_INPUT
INFLUX_BUCKET=$INFLUX_BUCKET_INPUT
GRAFANA_URL=$GRAFANA_URL_INPUT
GRAFANA_USER=$GRAFANA_USER_INPUT
GRAFANA_PASSWORD=$GRAFANA_PASSWORD_INPUT
EOF
    )
    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}✓ Environment file written${RESET}"
    echo "  File: $ENV_FILE (chmod 600)"
else
    echo -e "${YELLOW}⚠ Keeping existing environment file${RESET}"
fi

echo ""

# Step 4: Install systemd service
echo "Step 4: Installing systemd service"
echo "────────────────────────────────────────────────────────────"

SERVICE_FILE="$SYSTEMD_DIR/grafana-panel-health.service"
TIMER_FILE="$SYSTEMD_DIR/grafana-panel-health.timer"

echo "Copying service files..."
sudo cp "$SCRIPT_DIR/systemd/grafana-panel-health.service" "$SERVICE_FILE"
sudo cp "$SCRIPT_DIR/systemd/grafana-panel-health.timer" "$TIMER_FILE"

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo -e "${GREEN}✓ Systemd service installed${RESET}"
echo "  Service: $SERVICE_FILE"
echo "  Timer:   $TIMER_FILE"
echo ""

# Step 5: Enable and start timer
echo "Step 5: Enabling systemd timer"
echo "────────────────────────────────────────────────────────────"

read -p "Enable automatic monitoring (runs every 5 minutes)? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl enable grafana-panel-health.timer
    sudo systemctl start grafana-panel-health.timer
    
    echo -e "${GREEN}✓ Timer enabled and started${RESET}"
    echo ""
    
    # Show timer status
    echo "Timer status:"
    systemctl status grafana-panel-health.timer --no-pager | head -10
else
    echo -e "${YELLOW}⚠ Timer not enabled (start manually with: sudo systemctl start grafana-panel-health.timer)${RESET}"
fi

echo ""

# Step 6: Verify installation
echo "Step 6: Verifying installation"
echo "────────────────────────────────────────────────────────────"

echo "Checking scripts..."
for script in check-grafana-panels.py send-slack-alert.sh repair-grafana-panels.sh; do
    if [[ -x "$PROJECT_ROOT/scripts/$script" ]]; then
        echo -e "  ${GREEN}✓${RESET} $script"
    else
        echo -e "  ${RED}✗${RESET} $script (not found or not executable)"
    fi
done

echo ""
echo "Checking environment..."

# Check INFLUX_TOKEN
if [[ -n "${INFLUX_TOKEN:-}" ]]; then
    echo -e "  ${GREEN}✓${RESET} INFLUX_TOKEN is set"
else
    echo -e "  ${YELLOW}⚠${RESET} INFLUX_TOKEN not set in environment"
    echo "    (systemd service has it configured)"
fi

# Test InfluxDB connection
if curl -sf --max-time 5 http://localhost:8086/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} InfluxDB is reachable"
else
    echo -e "  ${YELLOW}⚠${RESET} InfluxDB is not reachable (may need to start services)"
fi

# Test Grafana connection
if curl -sf --max-time 5 http://localhost:3000/api/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} Grafana is reachable"
else
    echo -e "  ${YELLOW}⚠${RESET} Grafana is not reachable (may need to start services)"
fi

echo ""

# Final summary
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Installation complete!${RESET}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "What's installed:"
echo "  • Grafana panel health checker (Python script)"
echo "  • Automated monitoring (systemd timer, runs every 5 minutes)"
echo "  • Slack notification system"
echo "  • Log directory: $LOG_DIR"
echo ""
echo "Useful commands:"
echo "  # Check timer status"
echo "  systemctl status grafana-panel-health.timer"
echo ""
echo "  # View timer schedule"
echo "  systemctl list-timers grafana-panel-health.timer"
echo ""
echo "  # Run health check manually"
echo "  $PROJECT_ROOT/scripts/repair-grafana-panels.sh --notify"
echo ""
echo "  # View logs"
echo "  journalctl -u grafana-panel-health -f"
echo "  tail -f $LOG_DIR/grafana-panel-issues.log"
echo ""
echo "  # Test Slack notification"
echo "  $PROJECT_ROOT/scripts/send-slack-alert.sh \"Test message\""
echo ""
echo "════════════════════════════════════════════════════════════"
