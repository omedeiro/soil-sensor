#!/bin/bash
# WiFi Reconnection Test
# Simulates WiFi disconnects to test ESP8266 reconnection logic

echo "═══════════════════════════════════════"
echo "  WiFi Reconnection Test"
echo "═══════════════════════════════════════"
echo ""

ESP_IP="${ESP_IP:-192.168.99.70}"

if ! ping -c 1 -W 2 "$ESP_IP" > /dev/null 2>&1; then
    echo "✗ ESP8266 is not online at $ESP_IP"
    echo "  Connect to serial monitor instead: pio device monitor"
    exit 1
fi

echo "This test requires:"
echo "  1. ESP8266 connected to USB (for serial monitoring)"
echo "  2. Serial monitor running: pio device monitor"
echo "  3. Router access to toggle WiFi or kick device"
echo ""
echo "Test procedure:"
echo "  1. Note current WiFi status in serial monitor"
echo "  2. Disconnect ESP8266 from WiFi (router admin page or turn off router)"
echo "  3. Watch serial monitor for reconnection attempts"
echo "  4. Restore WiFi connectivity"
echo "  5. Verify ESP8266 reconnects and resumes posting"
echo ""
echo "Expected behavior:"
echo "  ⚠️ WiFi disconnected (reason: X)"
echo "  ⏳ Reconnection attempt 1/10 (backoff: 5s)"
echo "  ⏳ Reconnection attempt 2/10 (backoff: 10s)"
echo "  ⏳ Reconnection attempt 3/10 (backoff: 30s)"
echo "  ✅ WiFi reconnected! (stable for: Xs)"
echo "  [Queue] 🔄 Draining 3 queued readings..."
echo "  [DB] ✓ Posted queued reading (HTTP 204)"
echo "  [Queue] ✓ All queued readings sent"
echo ""
echo "Reconnection backoff progression:"
echo "  Attempt 1-2:  5 seconds"
echo "  Attempt 3-4:  10 seconds"
echo "  Attempt 5-6:  30 seconds"
echo "  Attempt 7+:   60 seconds (max)"
echo "  After 10 failed attempts: ESP8266 will reboot"
echo ""
echo "After reconnection:"
echo "  - Queued readings should be sent (if any were taken while offline)"
echo "  - Normal posting should resume"
echo "  - Backoff should reset after 5 minutes of stability"
echo ""
echo "Press Enter when ready to begin manual test..."
read

echo "Monitoring ESP8266..."
echo "(Switch to serial monitor terminal to observe behavior)"
echo ""
echo "Press Ctrl+C when test is complete"

# Poll ESP8266 and show connectivity status
while true; do
    if ping -c 1 -W 2 "$ESP_IP" > /dev/null 2>&1; then
        echo "[$(date '+%H:%M:%S')] ✓ ESP8266 online"
    else
        echo "[$(date '+%H:%M:%S')] ✗ ESP8266 OFFLINE (reconnecting...)"
    fi
    sleep 5
done
