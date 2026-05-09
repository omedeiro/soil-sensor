# Test Suite - Soil Sensor System

Comprehensive test scripts for validating ESP8266 firmware, InfluxDB integration, WiFi stability, and multi-sensor deployments.

## 📋 Test Overview

| Test Script | Purpose | Duration | Prerequisites |
|-------------|---------|----------|---------------|
| `test_e2e.sh` | End-to-end system validation | 2 minutes | InfluxDB + Grafana running |
| `test_influx_write.sh` | InfluxDB write test | 30 seconds | `INFLUX_TOKEN` set |
| `test_multi_sensor.sh` | Multi-sensor simulation | 1 minute | `INFLUX_TOKEN` set |
| `test_wifi_reconnection.sh` | WiFi reconnection logic | Manual | ESP8266 + serial monitor |
| `test_queue_drain.sh` | Reading queue functionality | Manual (15 min) | ESP8266 + InfluxDB |
| `test_72h_stability.sh` | Long-term stability | 72 hours | `INFLUX_TOKEN` set |

## 🚀 Quick Start

### 1. End-to-End Test (Recommended First Test)

Validates InfluxDB, Grafana, ESP8266 connectivity, and data flow.

```bash
cd tests

# Set your InfluxDB write token
export INFLUX_TOKEN="your_influxdb_write_token"
export INFLUX_ORG="soil-monitoring"
export INFLUX_BUCKET="sensor-readings"

# Optional: override default URLs
export INFLUX_URL="http://192.168.99.200:8086"
export GRAFANA_URL="http://192.168.99.200:3000"
export ESP_IP="192.168.99.70"

# Run test
./test_e2e.sh
```

**Expected output:**
```
═══════════════════════════════════════
  🌱 Soil Sensor System - End-to-End Test
═══════════════════════════════════════

Test 1/8: InfluxDB Health Check
✓ InfluxDB is healthy

Test 2/8: Grafana Health Check
✓ Grafana is healthy

Test 3/8: InfluxDB Write Test
✓ InfluxDB write successful (HTTP 204)

...

═══════════════════════════════════════
  Test Summary
═══════════════════════════════════════

Tests Passed: 6
Tests Failed: 0

✓ All critical tests PASSED! 🎉

Next steps:
  1. Open Grafana: http://192.168.99.200:3000
  2. Check dashboards for live data
  3. Monitor ESP8266 serial output
```

### 2. InfluxDB Write Test

Quick test to verify InfluxDB connectivity and token permissions.

```bash
export INFLUX_TOKEN="your_write_token"
./test_influx_write.sh
```

**Expected output:**
```
Sending test reading:
  Device: test-script
  Location: test
  Moisture: 52.3%
  Raw ADC: 642
  Timestamp: 1714784123

Response:
  HTTP Status: 204
  ✓ SUCCESS - Data written to InfluxDB

Check Grafana dashboard to see the test data point!
```

### 3. Multi-Sensor Test

Simulates 5 sensors posting data to test Grafana filtering.

```bash
export INFLUX_TOKEN="your_write_token"
./test_multi_sensor.sh
```

**Expected output:**
```
Simulating 5 sensors in different locations...

[sensor-1] @ backyard
  Moisture: 45.2%
  Raw ADC: 612
  RSSI: -52 dBm
  ✓ Sent successfully

[sensor-2] @ greenhouse
  Moisture: 68.1%
  Raw ADC: 394
  RSSI: -61 dBm
  ✓ Sent successfully

...

Summary:
  Successful: 5 / 5
  Failed: 0

✓ All sensors sent data successfully!
```

## 🧪 Manual Tests

### WiFi Reconnection Test

Tests ESP8266's automatic reconnection after WiFi disconnect.

**Requirements:**
- ESP8266 connected via USB
- Serial monitor running: `pio device monitor`
- Router admin access (to disconnect device)

**Procedure:**

1. Start test script:
   ```bash
   ./test_wifi_reconnection.sh
   ```

2. Watch serial monitor for WiFi status

3. Disconnect ESP8266 from WiFi (router admin page or turn off router)

4. Observe serial output:
   ```
   ⚠️ WiFi disconnected (reason: 200 - beacon timeout)
   ⏳ Reconnection attempt 1/10 (backoff: 5s)
   ⏳ Reconnection attempt 2/10 (backoff: 5s)
   ⏳ Reconnection attempt 3/10 (backoff: 10s)
   ```

5. Restore WiFi connectivity

6. Verify reconnection:
   ```
   ✅ WiFi reconnected! (stable for: 7s)
   [Queue] 🔄 Draining 2 queued readings...
   [DB] ✓ Posted queued reading (HTTP 204)
   [Queue] ✓ All queued readings sent
   ```

**Pass criteria:**
- ✅ ESP8266 automatically reconnects (no manual intervention)
- ✅ Queued readings drain after reconnection
- ✅ Normal operation resumes

### Queue Drain Test

Tests reading queue during database outages.

**Requirements:**
- ESP8266 connected via USB
- Serial monitor running
- SSH access to Raspberry Pi

**Procedure:**

1. Start test script:
   ```bash
   ./test_queue_drain.sh
   ```

2. Stop InfluxDB on Raspberry Pi:
   ```bash
   ssh pi@raspberrypi.local 'sudo systemctl stop influxdb'
   ```

3. Wait 10-15 minutes for 2-3 readings (at 5-minute interval)

4. Watch serial monitor for queuing:
   ```
   [DB] ✗ POST failed (connection refused)
   [Queue] ⬆️ Queued reading (1/20)
   [DB] ✗ POST failed (connection refused)
   [Queue] ⬆️ Queued reading (2/20)
   ```

5. Restart InfluxDB:
   ```bash
   ssh pi@raspberrypi.local 'sudo systemctl start influxdb'
   ```

6. Verify queue drains:
   ```
   [WiFi] ✓ Connected
   [Queue] 🔄 Draining 2 queued readings...
   [DB] ✓ Posted queued reading (HTTP 204)
   [DB] ✓ Posted queued reading (HTTP 204)
   [Queue] ✓ All queued readings sent
   ```

**Pass criteria:**
- ✅ Readings queued during outage (max 20)
- ✅ Queue drains automatically when database restored
- ✅ All queued readings successfully posted
- ✅ Normal operation resumes

## 🕐 Long-Term Tests

### 72-Hour Stability Test

Monitors ESP8266 uptime, WiFi stability, and data collection over 3 days.

**Requirements:**
- ESP8266 must remain powered on for 72 hours
- InfluxDB running on Raspberry Pi
- `INFLUX_TOKEN` set for reading count queries
- Stable network connection

**Procedure:**

1. Start test:
   ```bash
   export INFLUX_TOKEN="your_read_token"
   ./test_72h_stability.sh
   ```

2. Test runs unattended for 72 hours

3. Monitor progress (test writes to log file):
   ```bash
   tail -f /tmp/stability_test_*.log
   ```

4. Sample output:
   ```
   [2026-05-03 10:00:00] ✓ ESP8266 online (144/144)
   [2026-05-03 10:00:00] 📊 Total readings: 144 (+12 in last hour)
   [2026-05-03 10:00:00] ⏱️  Progress: 12h elapsed, 60h remaining
   ```

5. Final report after 72 hours:
   ```
   ═══════════════════════════════════════
     72-Hour Stability Test - COMPLETE
   ═══════════════════════════════════════

   Test duration: 72 hours
   Connectivity checks: 864
     Successful: 860
     Failed: 4
     Uptime: 99.54%

   Total readings collected: 850
   Expected readings: ~864
   Data collection rate: 98.38%

   ✅ TEST PASSED - System is stable!
   ```

**Pass criteria:**
- ✅ Uptime > 95%
- ✅ Data collection rate > 90%
- ✅ No memory leaks (free heap stable)
- ✅ Automatic recovery from transient failures

## 🔧 Configuration

### Environment Variables

All tests support these environment variables:

```bash
# InfluxDB settings
export INFLUX_URL="http://192.168.99.200:8086"
export INFLUX_ORG="soil-monitoring"
export INFLUX_BUCKET="sensor-readings"
export INFLUX_TOKEN="your_token"  # Required for write tests

# Grafana settings (for E2E test)
export GRAFANA_URL="http://192.168.99.200:3000"
export GRAFANA_USER="admin"  # Optional, for data source test
export GRAFANA_PASSWORD="admin"  # Optional, for data source test

# ESP8266 settings
export ESP_IP="192.168.99.70"
export DEVICE_ID="sensor-1"  # For 72h stability test
```

### Default Values

If not specified, tests use these defaults:

- `INFLUX_URL`: `http://192.168.99.200:8086`
- `GRAFANA_URL`: `http://192.168.99.200:3000`
- `ESP_IP`: `192.168.99.70`
- `INFLUX_ORG`: `soil-monitoring`
- `INFLUX_BUCKET`: `sensor-readings`

## 🐛 Troubleshooting

### Test Fails: "InfluxDB is not responding"

**Cause:** InfluxDB service not running or wrong URL

**Solution:**
```bash
# Check InfluxDB status
curl http://192.168.99.200:8086/health

# Or on Raspberry Pi
sudo systemctl status influxdb

# Restart if needed
sudo systemctl restart influxdb
```

### Test Fails: "INFLUX_TOKEN not set"

**Cause:** Required environment variable missing

**Solution:**
```bash
# Generate token in InfluxDB UI: http://192.168.99.200:8086
# Settings → Tokens → Generate Token → Custom Token
# Grant write access to sensor-readings bucket

export INFLUX_TOKEN="your_write_token_here"
```

### Test Fails: "HTTP 401 - Unauthorized"

**Cause:** Invalid or expired InfluxDB token

**Solution:**
1. Verify token has correct permissions (read or write)
2. Regenerate token in InfluxDB UI
3. Update `INFLUX_TOKEN` environment variable
4. Update ESP8266 `config.h` if using write token

### Test Fails: "ESP8266 is OFFLINE"

**Cause:** ESP8266 not on network or wrong IP

**Solution:**
```bash
# Find ESP8266 IP via serial monitor
pio device monitor

# Or ping entire subnet
nmap -sn 192.168.99.0/24 | grep SoilSensor

# Update ESP_IP environment variable
export ESP_IP="192.168.99.XXX"
```

### WiFi Reconnection Test: No reconnection attempts

**Cause:** WiFi stability features disabled in firmware

**Solution:**
1. Edit `firmware/src/config.h`:
   ```cpp
   #define WIFI_STABILITY_ENABLED   true
   #define WIFI_RECONNECT_ENABLED   true
   ```
2. Reflash firmware: `pio run --target upload`

### Queue Drain Test: Queue not draining

**Cause:** Invalid InfluxDB token or URL

**Solution:**
1. Check serial output for error details
2. Verify `DB_SERVER_URL` in `config.h` matches Raspberry Pi IP
3. Verify `INFLUX_TOKEN` is correct
4. Test manually: `./test_influx_write.sh`

## 📊 Test Results Interpretation

### E2E Test Results

| Passed | Failed | Status | Action |
|--------|--------|--------|--------|
| 6-8 | 0 | ✅ Perfect | No action needed |
| 4-5 | 1-2 | ⚠️ Warning | Check logs for skipped tests |
| 0-3 | 3+ | ❌ Critical | System not functional, debug immediately |

### 72h Stability Results

| Uptime | Data Rate | Status | Action |
|--------|-----------|--------|--------|
| >99% | >95% | ✅ Excellent | Production ready |
| 95-99% | 90-95% | ⚠️ Good | Investigate occasional drops |
| 90-95% | 85-90% | ⚠️ Fair | Check WiFi signal, power supply |
| <90% | <85% | ❌ Poor | Major issues, not production ready |

## 🔗 Related Documentation

- `docs/RPI_SETUP.md` - Raspberry Pi installation and configuration
- `docs/WIFI_IMPROVEMENTS.md` - WiFi stability features
- `docs/MULTI_SENSOR_GUIDE.md` - Multi-sensor deployment
- `AGENTS.md` - System architecture and troubleshooting

## 📝 Adding New Tests

To add a new test script:

1. Create executable script: `touch test_myfeature.sh && chmod +x test_myfeature.sh`
2. Use this template:

```bash
#!/bin/bash
# Brief description of test

set -e

# Configuration
TEST_VAR="${TEST_VAR:-default_value}"

echo "═══════════════════════════════════════"
echo "  Test Name"
echo "═══════════════════════════════════════"

# Test logic here

# Exit with status
if [ $success ]; then
    echo "✅ TEST PASSED"
    exit 0
else
    echo "❌ TEST FAILED"
    exit 1
fi
```

3. Document in this README
4. Add to `AGENTS.md` test list
