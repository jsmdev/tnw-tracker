#!/usr/bin/env bash
# Validates that every key with an English value also has a Spanish (es-ES) value.
# Exits 1 on any mismatch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

CATALOGS=(
  "$IOS_DIR/TNWTracker/Resources/Localizable.xcstrings"
  "$IOS_DIR/TNWTrackerWidget/Resources/Localizable.xcstrings"
)

missing=0
for catalog in "${CATALOGS[@]}"; do
  [ -f "$catalog" ] || continue
  result=$(jq -r '.strings | to_entries[] | select(.value.localizations.en) | select(.value.localizations["es-ES"] | not) | .key' "$catalog")
  if [ -n "$result" ]; then
    echo "Missing es-ES translation in $catalog:"
    echo "$result"
    missing=1
  fi
done

exit $missing
