#!/bin/bash
# Cloudflare Tunnel Setup Script for Soil Sensor Grafana Dashboard
# Makes soil.owenmedeiros.com publicly accessible

set -e

echo "========================================"
echo "Cloudflare Tunnel Setup for Grafana"
echo "========================================"
echo ""

# Check if running on Raspberry Pi
if [ "$(uname -m)" != "aarch64" ]; then
    echo "⚠️  Warning: This script is designed for Raspberry Pi 5 (ARM64)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 1: Install cloudflared
echo "Step 1: Installing cloudflared..."
if command -v cloudflared &> /dev/null; then
    echo "✓ cloudflared already installed ($(cloudflared --version))"
else
    echo "Downloading cloudflared for ARM64..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
    sudo dpkg -i cloudflared-linux-arm64.deb
    rm cloudflared-linux-arm64.deb
    echo "✓ cloudflared installed successfully"
fi

echo ""

# Step 2: Authenticate with Cloudflare
echo "Step 2: Authenticating with Cloudflare..."
echo ""
echo "🌐 A browser window will open. Please log into your Cloudflare account."
echo "   If you're running this over SSH, copy the URL and open it on your computer."
echo ""
read -p "Press ENTER to continue..."

cloudflared tunnel login

if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    echo "❌ Authentication failed. No cert.pem found."
    exit 1
fi

echo "✓ Authentication successful"
echo ""

# Step 3: Create tunnel
echo "Step 3: Creating Cloudflare Tunnel..."
TUNNEL_NAME="soil-sensor-grafana"

# Check if tunnel already exists
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "⚠️  Tunnel '$TUNNEL_NAME' already exists. Using existing tunnel."
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
else
    echo "Creating new tunnel: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    echo "✓ Tunnel created with ID: $TUNNEL_ID"
fi

echo ""

# Step 4: Configure tunnel
echo "Step 4: Configuring tunnel..."
sudo mkdir -p /etc/cloudflared

CREDENTIALS_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "❌ Credentials file not found: $CREDENTIALS_FILE"
    exit 1
fi

# Create config file
sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

ingress:
  - hostname: soil.owenmedeiros.com
    service: http://localhost:3000
  - service: http_status:404
EOF

echo "✓ Configuration file created: /etc/cloudflared/config.yml"
echo ""

# Step 5: Create DNS record
echo "Step 5: Creating DNS record..."
if cloudflared tunnel route dns "$TUNNEL_NAME" soil.owenmedeiros.com 2>&1 | grep -q "already exists"; then
    echo "⚠️  DNS record already exists for soil.owenmedeiros.com"
else
    cloudflared tunnel route dns "$TUNNEL_NAME" soil.owenmedeiros.com
    echo "✓ DNS record created: soil.owenmedeiros.com"
fi
echo ""

# Step 6: Install and start service
echo "Step 6: Installing systemd service..."
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared

echo "✓ Cloudflare Tunnel service installed and started"
echo ""

# Check service status
echo "Checking service status..."
sleep 2
if systemctl is-active --quiet cloudflared; then
    echo "✓ Cloudflare Tunnel is running"
else
    echo "⚠️  Service may not be running. Check logs with: sudo journalctl -u cloudflared -n 50"
fi

echo ""
echo "========================================"
echo "✅ Cloudflare Tunnel Setup Complete!"
echo "========================================"
echo ""
echo "Your Grafana dashboard should be accessible at:"
echo "🌐 https://soil.owenmedeiros.com"
echo ""
echo "Note: DNS propagation may take 1-5 minutes."
echo ""
echo "Useful commands:"
echo "  sudo systemctl status cloudflared     # Check tunnel status"
echo "  sudo journalctl -u cloudflared -f     # View tunnel logs"
echo "  cloudflared tunnel list                # List all tunnels"
echo ""
echo "Next step: Configure Grafana for anonymous viewing"
echo "Run: ./configure-grafana-anonymous.sh"
echo ""
