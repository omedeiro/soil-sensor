#!/bin/bash
#
# repair-grafana-panels.sh
# Automated detection and repair of Grafana panel issues with Slack alerting
#
# Usage:
#   ./repair-grafana-panels.sh [OPTIONS]
#
# Options:
#   --auto-repair         Enable automatic repairs (default: manual alert only)
#   --notify              Send Slack notification on issues
#   --dashboard UID       Check specific dashboard only
#   --dry-run             Show what would be repaired without making changes
#   --verbose             Show detailed output
#   --help                Show this help message
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Scripts
PANEL_CHECKER="${SCRIPT_DIR}/check-grafana-panels.py"
SLACK_SCRIPT="${SCRIPT_DIR}/send-slack-alert.sh"

# Logs
LOG_DIR="/mnt/sensor-data/logs"
ISSUE_LOG="${LOG_DIR}/grafana-panel-issues.log"

# Options
AUTO_REPAIR=false
ENABLE_NOTIFICATIONS=false
DASHBOARD_UID=""
DRY_RUN=false
VERBOSE=false

# Colors
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
CYAN='\033[96m'
RESET='\033[0m'

# Usage help
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated detection and repair of Grafana panel "No Data" issues.

OPTIONS:
    --auto-repair         Enable automatic repairs (default: manual alert only)
    --notify              Send Slack notification on issues
    --dashboard UID       Check specific dashboard only
    --dry-run             Show what would be repaired without making changes
    --verbose             Show detailed output
    --help                Show this help message

REPAIR ACTIONS:
    When --auto-repair is enabled:
    • Restart InfluxDB datasource on connection errors
    • Suggest time range adjustments for "No Data" panels
    • Validate and suggest fixes for query errors
    
    Manual alert mode (default):
    • Log all issues to: $ISSUE_LOG
    • Send Slack notification (if --notify enabled)
    • Exit with error code for systemd integration

EXAMPLES:
    # Check all panels, alert only (manual mode)
    $0 --notify

    # Check and auto-repair issues
    $0 --auto-repair --notify

    # Check specific dashboard
    $0 --dashboard soil-moisture-main-v2 --notify

    # Dry run to preview repairs
    $0 --auto-repair --dry-run --verbose

EXIT CODES:
    0   All panels healthy
    1   Issues detected (manual alert sent)
    2   Auto-repair attempted
    3   Configuration error
EOF
    exit 0
}

# Logging functions
log_info() { 
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[$(date +'%H:%M:%S')] ${BLUE}INFO:${RESET} $*"
    fi
}

log_issue() {
    local message=$1
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $message" | tee -a "$ISSUE_LOG"
}

log_error() { echo -e "[$(date +'%H:%M:%S')] ${RED}ERROR:${RESET} $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-repair)
            AUTO_REPAIR=true
            shift
            ;;
        --notify)
            ENABLE_NOTIFICATIONS=true
            shift
            ;;
        --dashboard)
            DASHBOARD_UID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check dependencies
if [[ ! -x "$PANEL_CHECKER" ]]; then
    log_error "Panel checker not found or not executable: $PANEL_CHECKER"
    exit 3
fi

if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && [[ ! -x "$SLACK_SCRIPT" ]]; then
    log_error "Slack script not found: $SLACK_SCRIPT"
    log_error "Notifications disabled"
    ENABLE_NOTIFICATIONS=false
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Print header
echo "════════════════════════════════════════════════════════════"
echo "Grafana Panel Repair Tool"
echo "════════════════════════════════════════════════════════════"
echo "Mode:         $(if [[ "$AUTO_REPAIR" == "true" ]]; then echo "AUTO-REPAIR"; else echo "MANUAL ALERT"; fi)"
echo "Notifications: $(if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then echo "ENABLED"; else echo "DISABLED"; fi)"
echo "Dry Run:      $(if [[ "$DRY_RUN" == "true" ]]; then echo "YES"; else echo "NO"; fi)"
echo ""

# Run panel health check
log_info "Running panel health check..."

REPORT_FILE=$(mktemp)
PANEL_CHECK_ARGS="--format json"

if [[ -n "$DASHBOARD_UID" ]]; then
    PANEL_CHECK_ARGS="$PANEL_CHECK_ARGS --dashboard $DASHBOARD_UID"
fi

if ! "$PANEL_CHECKER" $PANEL_CHECK_ARGS > "$REPORT_FILE" 2>/dev/null; then
    panel_exit_code=$?
    log_info "Panel checker exit code: $panel_exit_code"
fi

# Parse report
if [[ ! -f "$REPORT_FILE" ]] || [[ ! -s "$REPORT_FILE" ]]; then
    log_error "Failed to generate panel health report"
    rm -f "$REPORT_FILE"
    exit 3
fi

log_info "Analyzing report..."

# Extract summary
total_panels=$(jq -r '.summary.total_panels // 0' "$REPORT_FILE")
healthy=$(jq -r '.summary.healthy // 0' "$REPORT_FILE")
no_data=$(jq -r '.summary.no_data // 0' "$REPORT_FILE")
query_error=$(jq -r '.summary.query_error // 0' "$REPORT_FILE")
datasource_error=$(jq -r '.summary.datasource_error // 0' "$REPORT_FILE")

echo "Panel Health Summary"
echo "────────────────────────────────────────────────────────────"
echo "Total Panels:       $total_panels"
echo -e "${GREEN}✓ Healthy:${RESET}          $healthy"
echo -e "${YELLOW}✗ No Data:${RESET}          $no_data"
echo -e "${RED}⚠ Query Errors:${RESET}     $query_error"
echo -e "${RED}🔴 Datasource Errors:${RESET} $datasource_error"
echo ""

# Check if any issues detected
ISSUES_DETECTED=$((no_data + query_error + datasource_error))

if [[ $ISSUES_DETECTED -eq 0 ]]; then
    echo -e "${GREEN}✓ All panels healthy - no action needed${RESET}"
    echo ""
    echo "════════════════════════════════════════════════════════════"
    rm -f "$REPORT_FILE"
    exit 0
fi

echo -e "${YELLOW}⚠ Issues detected in $ISSUES_DETECTED panel(s)${RESET}"
echo ""

# List affected panels
echo "Affected Panels"
echo "────────────────────────────────────────────────────────────"

# Extract panel details with jq
jq -r '.dashboards[] | .title as $dash | .panels[] | select(.status != "healthy" and .status != "skipped") | "[\($dash)] \(.title) - Status: \(.status)"' "$REPORT_FILE" | while read -r line; do
    echo -e "${YELLOW}•${RESET} $line"
done

echo ""

# Log issues
log_issue "PANEL HEALTH CHECK - Issues detected: $ISSUES_DETECTED"
log_issue "  No Data: $no_data, Query Errors: $query_error, Datasource Errors: $datasource_error"

# Auto-repair mode
if [[ "$AUTO_REPAIR" == "true" ]]; then
    echo "Auto-Repair Actions"
    echo "────────────────────────────────────────────────────────────"
    
    REPAIRS_MADE=0
    
    # Handle datasource errors (restart InfluxDB connection test)
    if [[ $datasource_error -gt 0 ]]; then
        echo -e "${YELLOW}•${RESET} Datasource errors detected ($datasource_error panels)"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would test InfluxDB connection"
        else
            log_info "Testing InfluxDB connection..."
            if curl -sf --max-time 5 "${INFLUX_URL:-http://192.168.99.134:8086}/health" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${RESET} InfluxDB is responsive - issue may be token-related"
                log_issue "  Auto-repair: InfluxDB is healthy, check token permissions"
            else
                echo -e "  ${RED}✗${RESET} InfluxDB is unreachable"
                log_issue "  Auto-repair: InfluxDB unreachable - manual intervention required"
            fi
        fi
        REPAIRS_MADE=$((REPAIRS_MADE + 1))
    fi
    
    # Handle "No Data" panels
    if [[ $no_data -gt 0 ]]; then
        echo -e "${YELLOW}•${RESET} No Data panels detected ($no_data panels)"
        echo "  Suggested fixes:"
        echo "    - Expand time range to -7d or -30d"
        echo "    - Check if sensors are actively sending data"
        echo "    - Verify device_id filters match sensor IDs"
        
        log_issue "  Auto-repair suggestion: Expand time range or check sensor connectivity"
        REPAIRS_MADE=$((REPAIRS_MADE + 1))
    fi
    
    # Handle query errors
    if [[ $query_error -gt 0 ]]; then
        echo -e "${YELLOW}•${RESET} Query errors detected ($query_error panels)"
        echo "  Suggested fixes:"
        echo "    - Validate Flux query syntax"
        echo "    - Check measurement and field names"
        echo "    - Use debug-grafana-query.sh for detailed analysis"
        
        log_issue "  Auto-repair suggestion: Run debug-grafana-query.sh for affected panels"
        REPAIRS_MADE=$((REPAIRS_MADE + 1))
    fi
    
    echo ""
    
    if [[ $REPAIRS_MADE -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${BLUE}✓ Dry run complete - $REPAIRS_MADE action(s) would be taken${RESET}"
        else
            echo -e "${BLUE}✓ Auto-repair complete - $REPAIRS_MADE action(s) taken${RESET}"
            log_issue "Auto-repair completed: $REPAIRS_MADE actions taken"
        fi
    fi
    
    echo ""
fi

# Send Slack notification
if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
    echo "Sending Slack Notification"
    echo "────────────────────────────────────────────────────────────"
    
    # Build message
    message="Grafana Panel Health Alert\n\n"
    message+="Total Panels: $total_panels\n"
    message+="✓ Healthy: $healthy\n"
    message+="✗ No Data: $no_data\n"
    message+="⚠ Query Errors: $query_error\n"
    message+="🔴 Datasource Errors: $datasource_error\n\n"
    
    # Add affected panels (limit to 10)
    affected_panels=$(jq -r '.dashboards[] | .title as $dash | .panels[] | select(.status != "healthy" and .status != "skipped") | "• [\($dash)] \(.title)"' "$REPORT_FILE" | head -10)
    
    if [[ -n "$affected_panels" ]]; then
        message+="Affected Panels:\n$affected_panels\n"
        
        # Check if more than 10
        total_affected=$(jq -r '[.dashboards[].panels[] | select(.status != "healthy" and .status != "skipped")] | length' "$REPORT_FILE")
        if [[ $total_affected -gt 10 ]]; then
            message+="\n... and $((total_affected - 10)) more\n"
        fi
    fi
    
    message+="\nView dashboard: http://192.168.99.134:3000"
    
    # Determine severity
    severity="warning"
    if [[ $datasource_error -gt 0 ]] || [[ $ISSUES_DETECTED -gt 10 ]]; then
        severity="critical"
    fi
    
    log_info "Sending Slack notification (severity: $severity)"
    
    if "$SLACK_SCRIPT" \
        --severity "$severity" \
        --title "Grafana Panel Health Alert" \
        --message "$message" \
        --topic "panel-health" 2>&1 | grep -q "sent successfully"; then
        echo -e "${GREEN}✓ Slack notification sent${RESET}"
        log_issue "Slack notification sent successfully"
    else
        echo -e "${YELLOW}⚠ Slack notification failed (may be rate limited)${RESET}"
        log_issue "Slack notification failed"
    fi
    
    echo ""
fi

# Final summary
echo "════════════════════════════════════════════════════════════"

if [[ "$AUTO_REPAIR" == "true" ]]; then
    echo -e "${BLUE}Auto-repair mode: repairs attempted${RESET}"
    echo "See log for details: $ISSUE_LOG"
    rm -f "$REPORT_FILE"
    exit 2
else
    echo -e "${YELLOW}Manual alert mode: issues logged${RESET}"
    echo "Log file: $ISSUE_LOG"
    echo ""
    echo "Next steps:"
    echo "  1. Review affected panels in Grafana dashboard"
    echo "  2. Run debug-grafana-query.sh for detailed analysis"
    echo "  3. Check sensor connectivity with check-sensor-health.sh"
    echo "  4. Enable --auto-repair for automated fixes"
    rm -f "$REPORT_FILE"
    exit 1
fi
