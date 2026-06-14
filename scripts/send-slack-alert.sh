#!/bin/bash
#
# send-slack-alert.sh
# Generic Slack webhook notification sender with rate limiting and retry logic
#
# Usage:
#   ./send-slack-alert.sh "Simple message"
#   ./send-slack-alert.sh --severity critical --title "Alert Title" --message "Detailed message"
#   ./send-slack-alert.sh --from-json /path/to/report.json
#
# Configuration:
#   SLACK_WEBHOOK_URL can be set via:
#   1. File: /mnt/sensor-data/config/slack_webhook_url (recommended)
#   2. Environment variable: SLACK_WEBHOOK_URL
#   3. Command line: --webhook URL
#

set -euo pipefail

# Configuration
WEBHOOK_FILE="${SLACK_WEBHOOK_FILE:-/mnt/sensor-data/config/slack_webhook_url}"
RATE_LIMIT_DIR="${RATE_LIMIT_DIR:-/tmp/slack-rate-limit}"
RATE_LIMIT_SECONDS=300  # 5 minutes
MAX_RETRIES=3
RETRY_DELAY=5  # seconds

# Default values
SEVERITY="info"
TITLE=""
MESSAGE=""
WEBHOOK_URL=""
FROM_JSON=""
TOPIC="general"

# Colors for Slack attachments
declare -A SEVERITY_COLORS=(
    ["info"]="#36a64f"      # Green
    ["warning"]="#ff9900"   # Orange
    ["critical"]="#ff0000"  # Red
    ["success"]="#00ff00"   # Bright green
)

# Emojis for severity levels
declare -A SEVERITY_EMOJIS=(
    ["info"]=":information_source:"
    ["warning"]=":warning:"
    ["critical"]=":rotating_light:"
    ["success"]=":white_check_mark:"
)

# Usage help
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MESSAGE]

Send notifications to Slack with rate limiting and retry logic.

OPTIONS:
    --severity LEVEL    Set severity: info, warning, critical, success (default: info)
    --title TITLE       Alert title (appears as attachment title)
    --message TEXT      Alert message (detailed description)
    --topic TOPIC       Rate limit topic (default: general)
    --webhook URL       Override webhook URL
    --from-json FILE    Load message from JSON report
    --no-rate-limit     Bypass rate limiting (use with caution)
    --help              Show this help message

POSITIONAL:
    MESSAGE             Simple text message (shorthand for --message)

EXAMPLES:
    # Simple message
    $0 "Sensor offline: sensor-3"

    # Formatted alert
    $0 --severity critical --title "System Alert" --message "5 panels offline"

    # From JSON report
    $0 --from-json /tmp/panel-report.json

    # Custom webhook
    $0 --webhook https://hooks.slack.com/... --message "Test"

CONFIGURATION:
    Webhook URL is loaded from (in order):
    1. Command line --webhook flag
    2. Environment variable SLACK_WEBHOOK_URL
    3. File: $WEBHOOK_FILE

RATE LIMITING:
    By default, maximum 1 alert per topic per 5 minutes.
    Use --topic to separate different alert types.

EXIT CODES:
    0   Success
    1   Configuration error
    2   Rate limited
    3   Delivery failed after retries
EOF
    exit 0
}

# Logging functions
log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

# Load webhook URL
load_webhook_url() {
    if [[ -n "$WEBHOOK_URL" ]]; then
        return 0  # Already set via command line
    elif [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        WEBHOOK_URL="$SLACK_WEBHOOK_URL"
        return 0
    elif [[ -f "$WEBHOOK_FILE" ]]; then
        WEBHOOK_URL=$(cat "$WEBHOOK_FILE")
        if [[ -z "$WEBHOOK_URL" ]]; then
            log_error "Webhook URL file is empty: $WEBHOOK_FILE"
            return 1
        fi
        return 0
    else
        log_error "Slack webhook URL not configured"
        log_error "Set SLACK_WEBHOOK_URL or create file: $WEBHOOK_FILE"
        return 1
    fi
}

# Check rate limit
check_rate_limit() {
    local topic=$1
    local bypass=${2:-false}
    
    if [[ "$bypass" == "true" ]]; then
        return 0
    fi
    
    mkdir -p "$RATE_LIMIT_DIR"
    local marker_file="$RATE_LIMIT_DIR/${topic}.last"
    
    if [[ -f "$marker_file" ]]; then
        local last_send=$(cat "$marker_file")
        local now=$(date +%s)
        local elapsed=$((now - last_send))
        
        if [[ $elapsed -lt $RATE_LIMIT_SECONDS ]]; then
            local remaining=$((RATE_LIMIT_SECONDS - elapsed))
            log_error "Rate limited: topic '$topic' (${remaining}s remaining)"
            return 1
        fi
    fi
    
    # Update marker
    date +%s > "$marker_file"
    return 0
}

# Build JSON payload
build_payload() {
    local severity=$1
    local title=$2
    local message=$3
    
    local color="${SEVERITY_COLORS[$severity]}"
    local emoji="${SEVERITY_EMOJIS[$severity]}"
    local timestamp=$(date +%s)
    
    cat <<EOF
{
  "username": "Soil Monitor Bot",
  "icon_emoji": ":seedling:",
  "attachments": [
    {
      "color": "$color",
      "title": "$emoji $title",
      "text": "$message",
      "footer": "Soil Moisture Monitoring System",
      "footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png",
      "ts": $timestamp
    }
  ]
}
EOF
}

# Send to Slack with retry
send_to_slack() {
    local payload=$1
    local attempt=1
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        local http_code=$(curl -s -o /tmp/slack_response.txt -w "%{http_code}" \
            -X POST \
            -H 'Content-Type: application/json' \
            --data "$payload" \
            "$WEBHOOK_URL")
        
        if [[ "$http_code" == "200" ]]; then
            log_info "Slack notification sent successfully (attempt $attempt)"
            return 0
        else
            log_error "Slack delivery failed (attempt $attempt/$MAX_RETRIES, HTTP $http_code)"
            
            if [[ -f /tmp/slack_response.txt ]]; then
                cat /tmp/slack_response.txt >&2
            fi
            
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                local delay=$((RETRY_DELAY * attempt))
                log_info "Retrying in ${delay}s..."
                sleep "$delay"
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to deliver Slack notification after $MAX_RETRIES attempts"
    return 1
}

# Parse command line arguments
BYPASS_RATE_LIMIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --message)
            MESSAGE="$2"
            shift 2
            ;;
        --topic)
            TOPIC="$2"
            shift 2
            ;;
        --webhook)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        --from-json)
            FROM_JSON="$2"
            shift 2
            ;;
        --no-rate-limit)
            BYPASS_RATE_LIMIT=true
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            # Positional argument - treat as simple message
            MESSAGE="$1"
            shift
            ;;
    esac
done

# Validate severity
if [[ ! "${SEVERITY_COLORS[$SEVERITY]+isset}" ]]; then
    log_error "Invalid severity: $SEVERITY (use: info, warning, critical, success)"
    exit 1
fi

# Load webhook URL
if ! load_webhook_url; then
    exit 1
fi

# Check rate limit
if ! check_rate_limit "$TOPIC" "$BYPASS_RATE_LIMIT"; then
    exit 2
fi

# Handle --from-json
if [[ -n "$FROM_JSON" ]]; then
    if [[ ! -f "$FROM_JSON" ]]; then
        log_error "JSON file not found: $FROM_JSON"
        exit 1
    fi
    
    # Extract summary from JSON report
    TITLE=$(jq -r '.summary.title // "Grafana Panel Health Report"' "$FROM_JSON")
    
    local total=$(jq -r '.summary.total_panels // 0' "$FROM_JSON")
    local healthy=$(jq -r '.summary.healthy // 0' "$FROM_JSON")
    local no_data=$(jq -r '.summary.no_data // 0' "$FROM_JSON")
    local errors=$(jq -r '.summary.query_error // 0' "$FROM_JSON")
    
    MESSAGE="Total Panels: $total\n"
    MESSAGE+="✓ Healthy: $healthy\n"
    MESSAGE+="✗ No Data: $no_data\n"
    MESSAGE+="⚠ Errors: $errors\n"
    
    if [[ $no_data -gt 0 ]] || [[ $errors -gt 0 ]]; then
        SEVERITY="warning"
        if [[ $no_data -gt 5 ]]; then
            SEVERITY="critical"
        fi
    else
        SEVERITY="success"
    fi
fi

# Ensure we have a message
if [[ -z "$MESSAGE" ]]; then
    log_error "No message provided"
    usage
fi

# Set default title if not provided
if [[ -z "$TITLE" ]]; then
    case $SEVERITY in
        info)
            TITLE="Information"
            ;;
        warning)
            TITLE="Warning"
            ;;
        critical)
            TITLE="Critical Alert"
            ;;
        success)
            TITLE="Success"
            ;;
    esac
fi

# Build payload
PAYLOAD=$(build_payload "$SEVERITY" "$TITLE" "$MESSAGE")

# Send notification
if send_to_slack "$PAYLOAD"; then
    exit 0
else
    exit 3
fi
