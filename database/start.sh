#!/bin/bash
# Start the soil sensor database server

cd "$(dirname "$0")"

echo "═══════════════════════════════════════"
echo "  🌱 Soil Sensor Database Server"
echo "═══════════════════════════════════════"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed"
    echo "Please install Python 3 first"
    exit 1
fi

# Check if requirements are installed
if ! python3 -c "import flask" &> /dev/null; then
    echo "📦 Installing dependencies..."
    pip3 install -r requirements.txt
    echo ""
fi

# Get local IP address
echo "📡 Your computer's IP addresses:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print "   - " $2}'
else
    # Linux
    hostname -I | tr ' ' '\n' | grep -v '^$' | awk '{print "   - " $1}'
fi
echo ""

echo "📝 Update your ESP8266 config.h with:"
echo "   #define DB_SERVER_URL \"http://YOUR_IP:5000/api/reading\""
echo ""

echo "🚀 Starting server..."
echo ""

# Start the server
python3 server.py
