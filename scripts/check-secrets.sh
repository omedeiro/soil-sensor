#!/bin/bash
#
# check-secrets.sh
# Scan tracked files for credentials that must never be committed.
#
# The rule for this repo (AGENTS.md #12): InfluxDB tokens and the Slack webhook
# URL live only on the Pi under /mnt/sensor-data/config/ (chmod 600). Scripts
# read them from the environment; systemd units load them with EnvironmentFile=.
#
# Usage:
#   ./scripts/check-secrets.sh            # scan tracked files
#   ./scripts/check-secrets.sh --staged   # scan staged changes only
#
# Exit codes:
#   0 - clean
#   1 - a secret (or a pattern that leaks one) was found

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FINDINGS=0

if [ "${1:-}" = "--staged" ]; then
    mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACM)
else
    mapfile -t FILES < <(git ls-files)
fi

# Drop files that no longer exist (deleted but still tracked in the index).
EXISTING=()
for FILE in "${FILES[@]}"; do
    [ -f "$FILE" ] && EXISTING+=("$FILE")
done

if [ ${#EXISTING[@]} -eq 0 ]; then
    echo "No files to scan"
    exit 0
fi

report() {
    local label=$1
    local guidance=$2
    shift 2
    local hits
    hits=$(grep -nEI "$@" -- "${EXISTING[@]}" 2>/dev/null)
    if [ -n "$hits" ]; then
        echo -e "${RED}✗ $label${NC}"
        echo "$hits" | sed 's/^/    /'
        echo -e "    ${YELLOW}→ $guidance${NC}"
        echo ""
        FINDINGS=$((FINDINGS + 1))
    fi
}

echo "Scanning ${#EXISTING[@]} tracked files for committed secrets..."
echo ""

# InfluxDB v2 tokens: 88-char base64 ending in '=='.
report "InfluxDB token" \
    "Read it from \$INFLUX_TOKEN; store the value in /mnt/sensor-data/config/ (chmod 600)" \
    '[A-Za-z0-9_-]{60,}=='

# Slack webhook URLs — the placeholder form in the docs is fine.
report "Slack webhook URL" \
    "Store it in /mnt/sensor-data/config/slack_webhook_url (chmod 600)" \
    'hooks\.slack\.com/services/[A-Za-z0-9]+/[A-Za-z0-9]+/[A-Za-z0-9]{10,}'

# systemd units must load secrets from a file, never inline them.
report "Secret inlined in a systemd unit" \
    "Use EnvironmentFile=-/mnt/sensor-data/config/<name>.env instead" \
    '^[[:space:]]*Environment=.*(INFLUX_TOKEN|SLACK_WEBHOOK|_TOKEN|PASSWORD)='

# A real token assigned in a script (placeholders such as YOUR_TOKEN_HERE pass).
report "Hardcoded token assignment" \
    "Read it from the environment instead" \
    '(INFLUX_TOKEN|INFLUX_ADMIN_TOKEN|SLACK_WEBHOOK_URL|GRAFANA_TOKEN)=["'"'"']?[A-Za-z0-9_-]{32,}'

# Private keys.
report "Private key material" \
    "Keys belong on the Pi, not in git" \
    'BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY'

if [ "$FINDINGS" -eq 0 ]; then
    echo -e "${GREEN}✓ No committed secrets found${NC}"
    exit 0
fi

echo -e "${RED}✗ $FINDINGS secret pattern(s) found${NC}"
echo "  Remove the value, rotate the credential, and read it from the"
echo "  environment (see AGENTS.md 'Committing secrets')."
exit 1
