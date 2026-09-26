#!/usr/bin/env bash
# ============================================================
# Hatchery Automation Script Template (macOS)
# ============================================================
# Copy this file into Hatchery automation/scripts/ and declare
# it in a Clutch under a VM's automations list.
#
# Conventions:
#   - Use echo for progress lines (captured in the live feed)
#   - Use set -euo pipefail so unhandled errors become fatal
#   - Exit 0 on success; non-zero on failure
#   - Keep each script focused on one concern
#
# Optional inputs: pass via environment variables from the
# Clutch parameters map (values are always strings).
# ============================================================
set -euo pipefail

# EXAMPLE_PARAM="${EXAMPLE_PARAM:-}"

echo "Script started"

# --- Your work goes here ---
#
# Example: set a preference (requires appropriate privileges)
#   echo "Writing defaults"
#   defaults write /Library/Preferences/com.example Setting -bool true
#
# Example: advisory
#   echo "WARN: key not found, using default"

echo "Script finished successfully"
exit 0
