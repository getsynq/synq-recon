#!/usr/bin/env bash
# Test script for synq-recon examples and tests
# Validates all configurations and runs reconciliation with auto-drill
#
# Usage:
#   ./examples/test-all-examples.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

discover_files

# Per-run audit logs land here so the run assertion can inspect per-reconciliation
# status; cleaned up on exit.
AUDIT_DIR="$(mktemp -d)"
trap 'rm -rf "$AUDIT_DIR"' EXIT

# Track results
TOTAL_FILES=0
PASSED_VALIDATION=0
PASSED_RUN=0
FAILED_VALIDATION=0
FAILED_RUN=0

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}synq-recon Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${BLUE}Testing ${#ALL_FILES[@]} files...${NC}"
echo ""

for file in "${ALL_FILES[@]}"; do
    TOTAL_FILES=$((TOTAL_FILES + 1))

    if [ ! -f "$file" ]; then
        echo -e "${RED}File not found: $file${NC}"
        FAILED_VALIDATION=$((FAILED_VALIDATION + 1))
        continue
    fi

    echo -e "${YELLOW}Testing: $file${NC}"

    # Test 1: Check configuration
    echo -n "  Checking config... "
    if synq_recon check-config "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        PASSED_VALIDATION=$((PASSED_VALIDATION + 1))
    else
        echo -e "${RED}FAILED${NC}"
        FAILED_VALIDATION=$((FAILED_VALIDATION + 1))
        synq_recon check-config "$file" 2>&1 | sed 's/^/    /'
        continue
    fi

    # Test 2: Run with auto-drill.
    #
    # A file-level verdict (exit code alone) is too coarse: a reconciliation that
    # errors out is masked by sibling reconciliations that mismatch, since both
    # yield exit code 1. Assert per-reconciliation instead — parse the audit log
    # and fail on any reconciliation left in FAILED status. Mismatches remain the
    # expected, accepted outcome for these fixtures.
    echo -n "  Running reconciliation... "
    AUDIT_FILE="$AUDIT_DIR/$(echo "$file" | tr '/' '_').json"
    # Exit code 1 (mismatches found) is expected here, so shield the capture from
    # `set -e` and read the status back explicitly.
    set +e
    RUN_OUTPUT="$(synq_recon run "$file" --auto-drill --audit-log "$AUDIT_FILE" 2>&1)"
    EXIT_CODE=$?
    set -e

    FAILED_RECONS="$(failed_reconciliations "$AUDIT_FILE")"

    if [ -n "$FAILED_RECONS" ]; then
        echo -e "${RED}FAILED (reconciliations errored: $FAILED_RECONS)${NC}"
        echo "$RUN_OUTPUT" | sed 's/^/    /'
        FAILED_RUN=$((FAILED_RUN + 1))
    elif [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
        PASSED_RUN=$((PASSED_RUN + 1))
    elif [ $EXIT_CODE -eq 1 ]; then
        # Exit code 1 means mismatches were found (and no reconciliation errored),
        # which is the expected outcome for these fixtures.
        echo -e "${GREEN}OK (mismatches detected as expected)${NC}"
        PASSED_RUN=$((PASSED_RUN + 1))
    else
        echo -e "${RED}FAILED (exit code $EXIT_CODE)${NC}"
        echo "$RUN_OUTPUT" | sed 's/^/    /'
        FAILED_RUN=$((FAILED_RUN + 1))
    fi

    echo ""
done

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo "Total files: $TOTAL_FILES"
echo ""
echo -e "Config check:"
echo -e "  ${GREEN}Passed: $PASSED_VALIDATION${NC}"
if [ $FAILED_VALIDATION -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED_VALIDATION${NC}"
fi
echo ""
echo -e "Run execution:"
echo -e "  ${GREEN}Passed: $PASSED_RUN${NC}"
if [ $FAILED_RUN -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED_RUN${NC}"
fi
echo ""

# Exit with appropriate code
if [ $FAILED_VALIDATION -gt 0 ] || [ $FAILED_RUN -gt 0 ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
