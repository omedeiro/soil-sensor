#!/bin/bash
#
# test-no-data-checker.sh
# Self-test for scripts/check-no-data-panels.py.
#
# A checker that silently passes everything is worse than no checker, so CI
# runs it against two fixture dashboards: one that must come back clean, and
# one that trips every rule exactly once.
#
# Usage:
#   ./tests/test-no-data-checker.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-no-data-panels.py"
FIXTURES="$REPO_ROOT/tests/fixtures/no-data"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Testing $CHECKER"
echo ""

# ── 1. The healthy fixture must pass ─────────────────────────────────────────
echo "Healthy fixture:"
if OUTPUT=$("$CHECKER" --no-color --dashboard "$FIXTURES/healthy.json" 2>&1); then
    pass "exits 0 on a dashboard with no problems"
else
    fail "exits non-zero on a healthy dashboard"
    echo "$OUTPUT" | sed 's/^/      /'
fi
echo ""

# ── 2. The broken fixture must trip every rule ───────────────────────────────
echo "Broken fixture:"
REPORT="$WORKDIR/report.json"
"$CHECKER" --format json --dashboard "$FIXTURES/broken.json" > "$REPORT"
STATUS=$?

if [ "$STATUS" -eq 1 ]; then
    pass "exits 1 when panels would render \"No Data\""
else
    fail "expected exit 1, got $STATUS"
fi

for RULE in datasource no_query bucket measurement field tag device_id \
            missing_range unbalanced variable; do
    if python3 -c "
import json, sys
report = json.load(open('$REPORT'))
sys.exit(0 if any(f['rule'] == '$RULE' for f in report['findings']) else 1)
"; then
        pass "detects: $RULE"
    else
        fail "missed rule: $RULE"
    fi
done

# The tag-not-a-field case is the most common real-world cause, so assert on
# the wording rather than just the rule name.
if grep -q 'is a TAG of sensor_diagnostics' "$REPORT"; then
    pass "explains that a field filter matched a tag"
else
    fail "did not explain the tag-used-as-field case"
fi
echo ""

# ── 3. The allowlist must suppress a finding ─────────────────────────────────
echo "Allowlist:"
cat > "$WORKDIR/allowlist.json" <<'ALLOW'
{
  "suppressions": [
    {
      "dashboard": "broken.json",
      "rule": "measurement",
      "match": "soil_reading",
      "reason": "fixture: written by a collector outside this repo"
    }
  ]
}
ALLOW

"$CHECKER" --format json --allowlist "$WORKDIR/allowlist.json" \
    --dashboard "$FIXTURES/broken.json" > "$WORKDIR/allowed.json"

if python3 -c "
import json, sys
report = json.load(open('$WORKDIR/allowed.json'))
errors = [f for f in report['findings'] if f['rule'] == 'measurement']
allowed = [f for f in report['allowlisted'] if f['rule'] == 'measurement']
sys.exit(0 if not errors and len(allowed) == 1 else 1)
"; then
    pass "moves an allowlisted finding out of the failures"
else
    fail "allowlist did not suppress the finding"
fi

if python3 -c "
import json, sys
report = json.load(open('$WORKDIR/allowed.json'))
sys.exit(0 if report['summary']['errors'] > 0 else 1)
"; then
    pass "still reports the findings that are not allowlisted"
else
    fail "allowlist suppressed more than its entry"
fi
echo ""

# ── 4. The committed dashboards must be clean ────────────────────────────────
echo "Committed dashboards:"
if OUTPUT=$("$CHECKER" --no-color 2>&1); then
    pass "no \"No Data\" panels in grafana-dashboards/"
else
    fail "grafana-dashboards/ has panels that would render \"No Data\""
    echo "$OUTPUT" | sed 's/^/      /'
fi
echo ""

echo "=================================================="
echo "  Passed: $PASSED   Failed: $FAILED"
echo "=================================================="
[ "$FAILED" -eq 0 ]
