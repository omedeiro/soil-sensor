#!/bin/bash
#
# run-ci-checks.sh
# Run every check that CI runs, locally, before pushing.
#
# Usage:
#   ./scripts/run-ci-checks.sh                 # everything except the firmware build
#   ./scripts/run-ci-checks.sh --with-firmware # also compile the ESP8266 firmware
#
# Exit codes:
#   0 - all checks passed
#   1 - at least one check failed

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

WITH_FIRMWARE=0
[ "${1:-}" = "--with-firmware" ] && WITH_FIRMWARE=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()

run_check() {
    local name=$1
    shift
    echo ""
    echo -e "${BLUE}── $name ${NC}"
    if "$@"; then
        echo -e "${GREEN}✓ $name${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ $name${NC}"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
}

skip_check() {
    echo ""
    echo -e "${YELLOW}⊘ $1 — $2${NC}"
    SKIPPED=$((SKIPPED + 1))
}

# ── Dashboards and configuration ─────────────────────────────────────────────

check_json_parses() {
    local rc=0
    while IFS= read -r file; do
        if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$file"; then
            echo "  invalid JSON: $file"
            rc=1
        fi
    done < <(git ls-files '*.json')
    [ "$rc" -eq 0 ] && echo "  all tracked .json files parse"
    return $rc
}

check_dashboards_are_generated() {
    # soil-moisture-main.json and sensor-explorer.json are generated from
    # sensors-config.json and must never be hand-edited. Regenerate into a
    # scratch copy and compare, leaving the working tree exactly as found.
    local dashboards=(
        grafana-dashboards/soil-moisture-main.json
        grafana-dashboards/sensor-explorer.json
    )
    local scratch dashboard name rc=0
    scratch=$(mktemp -d)

    for dashboard in "${dashboards[@]}"; do
        cp "$dashboard" "$scratch/$(basename "$dashboard")"
    done

    if ! ./scripts/generate-dashboard.py > "$scratch/generate.log" 2>&1; then
        cat "$scratch/generate.log"
        for dashboard in "${dashboards[@]}"; do
            cp "$scratch/$(basename "$dashboard")" "$dashboard"
        done
        rm -rf "$scratch"
        return 1
    fi

    for dashboard in "${dashboards[@]}"; do
        name=$(basename "$dashboard")
        if diff -q "$scratch/$name" "$dashboard" > /dev/null; then
            echo "  $name matches sensors-config.json"
        else
            echo "  $name does not match what sensors-config.json generates."
            echo "  It must never be hand-edited — change sensors-config.json and regenerate:"
            echo "      ./scripts/generate-dashboard.py"
            diff -u "$scratch/$name" "$dashboard" | head -40
            rc=1
        fi
        cp "$scratch/$name" "$dashboard"
    done

    rm -rf "$scratch"
    return $rc
}

# ── Shell and Python ─────────────────────────────────────────────────────────

check_shell_syntax() {
    local rc=0
    while IFS= read -r file; do
        bash -n "$file" || rc=1
    done < <(git ls-files '*.sh')
    [ "$rc" -eq 0 ] && echo "  every tracked shell script parses"
    return $rc
}

check_shellcheck() {
    if ! command -v shellcheck > /dev/null 2>&1; then
        echo "  shellcheck not installed — skipping (CI runs it)"
        return 0
    fi
    # shellcheck disable=SC2046
    shellcheck --severity=error $(git ls-files '*.sh') || return 1
    echo "  no shellcheck errors"
}

check_python_syntax() {
    local rc=0
    while IFS= read -r file; do
        python3 -m py_compile "$file" || rc=1
    done < <(git ls-files '*.py')
    find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
    [ "$rc" -eq 0 ] && echo "  every tracked Python file compiles"
    return $rc
}

# ── Firmware ─────────────────────────────────────────────────────────────────

check_firmware_build() {
    [ -f firmware/src/secrets.h ] || cp firmware/src/secrets.h.example firmware/src/secrets.h
    (cd firmware && pio run -e esp8266)
}

echo "=================================================="
echo "  Soil Sensor — CI checks"
echo "=================================================="

run_check "sensors-config.json is valid"      ./scripts/validate-config.py
run_check "All JSON parses"                   check_json_parses
run_check "Dashboards are generated"          check_dashboards_are_generated
run_check "No \"No Data\" panels"             ./scripts/check-no-data-panels.py --no-color
run_check "Panel checker self-test"           ./tests/test-no-data-checker.sh
run_check "Shell syntax"                      check_shell_syntax
run_check "ShellCheck"                        check_shellcheck
run_check "Python syntax"                     check_python_syntax
run_check "No committed secrets"              ./scripts/check-secrets.sh

if [ "$WITH_FIRMWARE" -eq 1 ]; then
    if command -v pio > /dev/null 2>&1; then
        run_check "Firmware builds" check_firmware_build
    else
        skip_check "Firmware builds" "pio not installed (pip install platformio)"
    fi
else
    skip_check "Firmware builds" "pass --with-firmware to include it"
fi

echo ""
echo "=================================================="
echo -e "  ${GREEN}Passed: $PASSED${NC}   ${RED}Failed: $FAILED${NC}   ${YELLOW}Skipped: $SKIPPED${NC}"
echo "=================================================="

if [ "$FAILED" -gt 0 ]; then
    for name in "${FAILED_NAMES[@]}"; do
        echo -e "  ${RED}✗${NC} $name"
    done
    exit 1
fi
exit 0
