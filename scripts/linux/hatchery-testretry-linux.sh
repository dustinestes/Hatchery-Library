#!/usr/bin/env bash
# ============================================================
# hatchery-testretry-linux.sh
# End-to-end test for Hatchery's retry mechanism.
#
# First run:  writes a flag under /tmp, then exits 1 so
#             Hatchery marks the VM failed.
# Retry run:  finds the flag, deletes it, exits 0 so Hatchery
#             marks the script succeeded and continues automation.
#
# Flag path:  /tmp/hatchery-testretry-ran
#
# Usage in a Clutch:
#   automations:
#     - hatchery-testretry-linux.sh
#     - <next script>   # only reached on the retry run
# ============================================================
set -euo pipefail

FLAG_FILE="/tmp/hatchery-testretry-ran"

if [[ -f "$FLAG_FILE" ]]; then
  echo "Retry flag found -- this is the retry run"
  rm -f "$FLAG_FILE"
  echo "Flag removed -- retry succeeded"
  exit 0
fi

echo "First run -- writing retry flag and failing intentionally"
touch "$FLAG_FILE"
echo "Flag written to: $FLAG_FILE"
echo "WARN: Exiting with code 1 -- use Hatchery retry to continue"
exit 1
