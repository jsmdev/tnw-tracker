#!/usr/bin/env bash
# Lint check: verifies that ActiveWorkoutCoordinator has the minimum expected
# logger.info calls for phase transitions (REQ-LOG-03).
# Exits 1 if the threshold is not met.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

COORDINATOR="$IOS_DIR/TNWTracker/Features/Workout/ActiveWorkoutCoordinator.swift"
TIMER_SERVICE="$IOS_DIR/TNWTracker/Features/Workout/RestTimerService.swift"

fail=0

check_file() {
  local file="$1"
  local label="$2"
  local threshold="$3"
  local count
  count=$(grep -c "logger\." "$file" 2>/dev/null) || count=0
  if [ "$count" -lt "$threshold" ]; then
    echo "FAIL: $label has $count logger call(s) — expected >= $threshold"
    fail=1
  else
    echo "OK:   $label has $count logger call(s) (threshold: $threshold)"
  fi
}

check_file "$COORDINATOR" "ActiveWorkoutCoordinator" 8
check_file "$TIMER_SERVICE" "RestTimerService" 3

exit $fail
