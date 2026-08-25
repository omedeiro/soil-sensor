#!/bin/bash
# validate-config.sh
# Validates firmware configuration before flashing
# Prevents common configuration mistakes that brick sensors

set -e

CONFIG_FILE="src/config.h"
SECRETS_FILE="src/secrets.h"
# WIFI_SSID and INFLUX_TOKEN live in secrets.h (gitignored), not config.h.
# Searching only config.h reported them as missing on a correctly configured tree.
SEARCH_FILES=("$CONFIG_FILE")
[[ -f "$SECRETS_FILE" ]] && SEARCH_FILES+=("$SECRETS_FILE")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo -e "${BLUE}=== Firmware Configuration Validator ===${NC}"
echo -e "Checking: ${BLUE}$CONFIG_FILE${NC}"
echo ""

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}✗ Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Function to extract #define value
get_define() {
    local key=$1
    grep -hE "^#define[[:space:]]+${key}[[:space:]]" "${SEARCH_FILES[@]}" 2>/dev/null \
        | head -1 | awk '{print $3}' | tr -d '"'
}

# Function to check if #define exists
has_define() {
    local key=$1
    grep -qhE "^#define[[:space:]]+${key}[[:space:]]" "${SEARCH_FILES[@]}" 2>/dev/null
}

# =============================================================================
# CRITICAL CHECKS (must pass)
# =============================================================================

echo -e "${BLUE}Critical Checks:${NC}"

# Check 1: WiFi SSID
if ! has_define "WIFI_SSID"; then
    echo -e "${RED}  ✗ WIFI_SSID not defined${NC}"
    ERRORS=$((ERRORS+1))
else
    WIFI_SSID=$(get_define "WIFI_SSID")
    if [[ -z "$WIFI_SSID" || "$WIFI_SSID" == "\"\"" ]]; then
        echo -e "${RED}  ✗ WIFI_SSID is empty${NC}"
        ERRORS=$((ERRORS+1))
    else
        echo -e "${GREEN}  ✓ WIFI_SSID is set${NC}"
    fi
fi

# Check 2: InfluxDB Token
if ! has_define "INFLUX_TOKEN"; then
    echo -e "${RED}  ✗ INFLUX_TOKEN not defined${NC}"
    ERRORS=$((ERRORS+1))
else
    INFLUX_TOKEN=$(get_define "INFLUX_TOKEN")
    if [[ -z "$INFLUX_TOKEN" || "$INFLUX_TOKEN" == "\"\"" ]]; then
        echo -e "${RED}  ✗ INFLUX_TOKEN is empty${NC}"
        ERRORS=$((ERRORS+1))
    elif [[ ${#INFLUX_TOKEN} -lt 50 ]]; then
        echo -e "${YELLOW}  ⚠ INFLUX_TOKEN seems too short (${#INFLUX_TOKEN} chars)${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "${GREEN}  ✓ INFLUX_TOKEN is set (${#INFLUX_TOKEN} chars)${NC}"
    fi
fi

# Check 3: InfluxDB URL
if ! has_define "DB_SERVER_URL"; then
    echo -e "${RED}  ✗ DB_SERVER_URL not defined${NC}"
    ERRORS=$((ERRORS+1))
else
    DB_SERVER_URL=$(get_define "DB_SERVER_URL")
    if [[ -z "$DB_SERVER_URL" ]]; then
        echo -e "${RED}  ✗ DB_SERVER_URL is empty${NC}"
        ERRORS=$((ERRORS+1))
    elif [[ ! "$DB_SERVER_URL" =~ ^http ]]; then
        echo -e "${RED}  ✗ DB_SERVER_URL must start with http:// or https://${NC}"
        ERRORS=$((ERRORS+1))
    elif [[ "$DB_SERVER_URL" =~ localhost|127\.0\.0\.1 ]]; then
        echo -e "${RED}  ✗ DB_SERVER_URL uses localhost (should be Raspberry Pi IP)${NC}"
        ERRORS=$((ERRORS+1))
    else
        echo -e "${GREEN}  ✓ DB_SERVER_URL is valid: $DB_SERVER_URL${NC}"
    fi
fi

# Check 4: Device ID Configuration
DEVICE_ID_AUTO=$(get_define "DEVICE_ID_AUTO")
DEVICE_ID=$(get_define "DEVICE_ID")

if [[ "$DEVICE_ID_AUTO" == "true" ]]; then
    echo -e "${GREEN}  ✓ DEVICE_ID_AUTO is true (MAC-based ID)${NC}"
    
    # Warn if DEVICE_ID is also set
    if [[ -n "$DEVICE_ID" && "$DEVICE_ID" != '""' ]]; then
        echo -e "${YELLOW}  ⚠ DEVICE_ID is set but DEVICE_ID_AUTO=true (DEVICE_ID will be ignored)${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
elif [[ "$DEVICE_ID_AUTO" == "false" ]]; then
    echo -e "${GREEN}  ✓ DEVICE_ID_AUTO is false (manual ID)${NC}"
    
    # Require DEVICE_ID when auto is false
    if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == '""' ]]; then
        echo -e "${RED}  ✗ DEVICE_ID must be set when DEVICE_ID_AUTO=false${NC}"
        ERRORS=$((ERRORS+1))
    else
        echo -e "${GREEN}  ✓ DEVICE_ID is set: $DEVICE_ID${NC}"
    fi
else
    echo -e "${RED}  ✗ DEVICE_ID_AUTO must be 'true' or 'false' (found: $DEVICE_ID_AUTO)${NC}"
    ERRORS=$((ERRORS+1))
fi

# Check 5: Device Location
if ! has_define "DEVICE_LOCATION"; then
    echo -e "${YELLOW}  ⚠ DEVICE_LOCATION not defined${NC}"
    WARNINGS=$((WARNINGS+1))
else
    DEVICE_LOCATION=$(get_define "DEVICE_LOCATION")
    if [[ -z "$DEVICE_LOCATION" || "$DEVICE_LOCATION" == '""' ]]; then
        echo -e "${YELLOW}  ⚠ DEVICE_LOCATION is empty (won't be tagged in InfluxDB)${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "${GREEN}  ✓ DEVICE_LOCATION is set: $DEVICE_LOCATION${NC}"
    fi
fi

# =============================================================================
# RECOMMENDED SETTINGS (warnings only)
# =============================================================================

echo ""
echo -e "${BLUE}Recommended Settings:${NC}"

# Check reading interval
READ_INTERVAL=$(get_define "READ_INTERVAL_MS")
if [[ -n "$READ_INTERVAL" ]]; then
    if [[ $READ_INTERVAL -lt 60000 ]]; then
        echo -e "${YELLOW}  ⚠ READ_INTERVAL_MS is very short (${READ_INTERVAL}ms < 1 min)${NC}"
        WARNINGS=$((WARNINGS+1))
    elif [[ $READ_INTERVAL -gt 3600000 ]]; then
        echo -e "${YELLOW}  ⚠ READ_INTERVAL_MS is very long (${READ_INTERVAL}ms > 1 hour)${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "${GREEN}  ✓ READ_INTERVAL_MS is reasonable: ${READ_INTERVAL}ms${NC}"
    fi
fi

# Check WiFi diagnostics
WIFI_DIAGNOSTICS=$(get_define "ENABLE_WIFI_DIAGNOSTICS")
if [[ "$WIFI_DIAGNOSTICS" == "true" ]]; then
    echo -e "${GREEN}  ✓ WiFi diagnostics enabled${NC}"
elif [[ "$WIFI_DIAGNOSTICS" == "false" ]]; then
    echo -e "${YELLOW}  ⚠ WiFi diagnostics disabled (recommended for debugging)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

# Check reading queue
QUEUE_ENABLED=$(get_define "QUEUE_FAILED_READINGS")
if [[ "$QUEUE_ENABLED" == "true" ]]; then
    echo -e "${GREEN}  ✓ Reading queue enabled (survives network outages)${NC}"
elif [[ "$QUEUE_ENABLED" == "false" ]]; then
    echo -e "${YELLOW}  ⚠ Reading queue disabled (data loss during outages)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

# Check OTA password
OTA_PASSWORD=$(get_define "OTA_PASSWORD")
if [[ -n "$OTA_PASSWORD" && "$OTA_PASSWORD" != '""' ]]; then
    if [[ ${#OTA_PASSWORD} -lt 8 ]]; then
        echo -e "${YELLOW}  ⚠ OTA_PASSWORD is short (${#OTA_PASSWORD} chars < 8)${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo -e "${GREEN}  ✓ OTA_PASSWORD is set${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ OTA_PASSWORD not set (OTA updates won't work)${NC}"
    WARNINGS=$((WARNINGS+1))
fi

# =============================================================================
# NETWORK CONNECTIVITY TEST (optional, slow)
# =============================================================================

if [[ "${SKIP_NETWORK_TEST:-false}" != "true" ]]; then
    echo ""
    echo -e "${BLUE}Network Connectivity Test:${NC}"
    
    # Extract IP from DB_SERVER_URL
    if [[ -n "$DB_SERVER_URL" ]]; then
        DB_HOST=$(echo "$DB_SERVER_URL" | sed -E 's|https?://([^:/]+).*|\1|')
        DB_PORT=$(echo "$DB_SERVER_URL" | sed -E 's|.*:([0-9]+).*|\1|' || echo "8086")
        # Fallback if no port in URL
        [[ "$DB_PORT" == "$DB_SERVER_URL" ]] && DB_PORT="8086"
        
        echo -n "  Testing connection to $DB_HOST:$DB_PORT... "
        
        # python3 rather than `timeout` + /dev/tcp: coreutils `timeout` is absent
        # on macOS, so the old check reported FAILED on every Mac.
        if python3 -c 'import socket,sys
try:
    socket.create_connection((sys.argv[1], int(sys.argv[2])), 5).close()
except Exception:
    sys.exit(1)' "$DB_HOST" "$DB_PORT" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}FAILED${NC}"
            echo -e "${YELLOW}  ⚠ Cannot reach InfluxDB server (may be normal if Pi is off)${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    fi
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo -e "${BLUE}=== Validation Summary ===${NC}"

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ Configuration is valid and optimal!${NC}"
    echo ""
    echo "Safe to flash firmware:"
    echo "  - OTA: ./flash-ota-canary.sh"
    echo "  - USB: pio run --target upload"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Configuration is valid but has $WARNINGS warning(s)${NC}"
    echo ""
    echo "Safe to flash firmware, but consider fixing warnings:"
    echo "  - OTA: ./flash-ota-canary.sh"
    echo "  - USB: pio run --target upload"
    exit 0
else
    echo -e "${RED}✗ Configuration has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Fix errors before flashing firmware!"
    echo "Edit: $CONFIG_FILE"
    exit 1
fi
