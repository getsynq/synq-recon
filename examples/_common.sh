#!/usr/bin/env bash
# Shared configuration for synq-recon shell scripts.
# Source this file from other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../examples/_common.sh"   # or adjust path as needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Root of the repository
COMMON_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run synq-recon via go run (no manual build step needed)
synq_recon() {
    go run "$COMMON_ROOT_DIR/cmd/synq-recon" "$@"
}

# failed_reconciliations prints the space-separated names of any reconciliations
# left in FAILED status in the given audit-log JSON (empty when all reconciliations
# passed or mismatched cleanly). Used to catch reconciliations that error out —
# which a file-level exit code hides behind sibling mismatches.
failed_reconciliations() {
    local audit_file="$1"
    [ -f "$audit_file" ] || return 0
    python3 - "$audit_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except (OSError, ValueError):
    sys.exit(0)
failed = []
for rec in data.get("reconciliations", []):
    if rec.get("status") == "RECONCILIATION_OUTCOME_FAILED":
        name = (rec.get("reconciliation") or {}).get("name") or "<unnamed>"
        failed.append(name)
print(" ".join(failed))
PY
}

# Auto-discover YAML files via glob.
# TEST_FILES: all tests/*.yaml (relative paths from repo root)
# EXAMPLE_FILES: all examples/*.yaml except time-travel.yaml (requires real DWH)
discover_files() {
    TEST_FILES=()
    for f in "$COMMON_ROOT_DIR"/tests/*.yaml; do
        [ -f "$f" ] && TEST_FILES+=("tests/$(basename "$f")")
    done

    EXAMPLE_FILES=()
    for f in "$COMMON_ROOT_DIR"/examples/*.yaml; do
        [ -f "$f" ] || continue
        local base
        base="$(basename "$f")"
        # Skip files that require real DWH connections
        [ "$base" = "time-travel.yaml" ] && continue
        EXAMPLE_FILES+=("examples/$base")
    done

    ALL_FILES=("${TEST_FILES[@]}" "${EXAMPLE_FILES[@]}")
}
