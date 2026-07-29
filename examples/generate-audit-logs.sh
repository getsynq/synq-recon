#!/usr/bin/env bash
# Regenerate all audit log JSON files from example configurations.
#
# Each output file is named: <name>_<datetime>.audit.json
# This allows accumulating audit history over time.
#
# Uses `run --auto-drill` for each file to produce a single audit per config.
#
# Usage:
#   ./examples/generate-audit-logs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

discover_files

ROOT_DIR="$COMMON_ROOT_DIR"
AUDIT_DIR="$ROOT_DIR/audit-logs"
TIMESTAMP="$(date '+%Y-%m-%dT%H-%M-%S')"

mkdir -p "$AUDIT_DIR"

PASSED=0
FAILED=0

run_cmd() {
    local label="$1"
    shift
    echo -n "  $label ... "
    if "$@" > /dev/null 2>&1; then
        echo -e "${GREEN}ok${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        local rc=$?
        # exit code 1 means mismatches detected, which is expected
        if [ $rc -eq 1 ]; then
            echo -e "${GREEN}ok (mismatches detected)${NC}"
            PASSED=$((PASSED + 1))
            return 0
        fi
        echo -e "${RED}FAILED (exit $rc)${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Regenerating audit logs ($TIMESTAMP)${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# --- Example audits ---
echo -e "${YELLOW}Examples${NC}"
for file in "${EXAMPLE_FILES[@]}"; do
    name="$(basename "${file%.yaml}")"
    run_cmd "run examples/$name" \
        synq_recon run "$ROOT_DIR/$file" --auto-drill \
        --audit-log "$AUDIT_DIR/run-${name}_${TIMESTAMP}.audit.json"
done
echo ""

# --- Test audits ---
echo -e "${YELLOW}Tests${NC}"
for file in "${TEST_FILES[@]}"; do
    name="$(basename "${file%.yaml}")"
    run_cmd "run tests/$name" \
        synq_recon run "$ROOT_DIR/$file" --auto-drill \
        --audit-log "$AUDIT_DIR/run-test-${name}_${TIMESTAMP}.audit.json"
done
echo ""

# --- Summary ---
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo ""

TOTAL_FILES=$(find "$AUDIT_DIR" -name '*.audit.json' | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$AUDIT_DIR" | cut -f1)
echo "Generated $TOTAL_FILES audit files ($TOTAL_SIZE) in audit-logs/"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Some commands failed${NC}"
    exit 1
fi
echo -e "${GREEN}All audit logs regenerated successfully${NC}"
