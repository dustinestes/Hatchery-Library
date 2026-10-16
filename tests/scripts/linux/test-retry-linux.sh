#!/usr/bin/env bash
# ============================================================
# test-retry-linux.sh
# End-to-end test for Hatchery's retry mechanism.
#
# Lives under tests/scripts/ (not scripts/) so default Library
# Script bindings do not pull it. Basename prefix test-.
#
# First run:  writes a flag under /tmp, then exits 1 so
#             Hatchery marks the VM failed.
# Retry run:  finds the flag, deletes it, exits 0 so Hatchery
#             marks the script succeeded and continues automation.
#
# Flag path:  /tmp/test-retry-ran
#
# Usage in a Clutch (after enabling Test Scripts binding + pull):
#   automations:
#     - type: script
#       name: test-retry-linux.sh
#     - <next script>   # only reached on the retry run
# ============================================================
set -euo pipefail

FLAG_FILE="/tmp/test-retry-ran"

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
