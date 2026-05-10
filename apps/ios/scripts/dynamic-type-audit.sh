#!/usr/bin/env bash
# dynamic-type-audit.sh — ADR-4 Dynamic Type compliance audit
# Exits 1 if absolute .frame(height:) or .frame(width:) found in view code.
# Only .frame(minHeight:) and .frame(maxWidth:) are allowed (HIG tap targets and expansions).
#
# Usage: ./scripts/dynamic-type-audit.sh
# CI: add as a build phase or pre-commit step.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGETS=(
    "$IOS_ROOT/TNWTracker/DesignSystem"
    "$IOS_ROOT/TNWTracker/Features"
    "$IOS_ROOT/TNWTrackerWidget/Sources"
)

# Pattern: .frame(height: N) or .frame(width: N) with a numeric literal (absolute).
# Excludes: .frame(minHeight:), .frame(maxHeight:), .frame(maxWidth:), .frame(minWidth:),
#           .frame(maxWidth: .infinity) — these are OK.
VIOLATIONS=0

for target in "${TARGETS[@]}"; do
    if [ ! -d "$target" ]; then
        continue
    fi

    # Search for absolute frame height/width constraints with literal numbers.
    # Exclude minHeight/maxHeight/minWidth/maxWidth patterns.
    results=$(grep -rn "\.frame(height:\|\.frame(width:" "$target" \
        --include="*.swift" \
        | grep -v "min\|max" \
        | grep -v "// audit:" \
        || true)

    if [ -n "$results" ]; then
        echo "VIOLATION — absolute .frame(height:) or .frame(width:) found in $target:"
        echo "$results"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

if [ "$VIOLATIONS" -eq 0 ]; then
    echo "Dynamic Type audit PASSED — no absolute frame heights/widths found."
    exit 0
else
    echo ""
    echo "Dynamic Type audit FAILED — $VIOLATIONS violation(s)."
    echo "Fix: use .frame(minHeight: 44) for tap targets, or @ScaledMetric for text-related sizes."
    exit 1
fi
