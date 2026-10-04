#!/usr/bin/env bash
# ============================================================
# hatchery-cleanup-macos.sh
# Removes Hatchery guest directories and their contents.
#
# Guest environment ensure catalog (#554 / ADR-0032): macOS payload
# and matching cleanup land in Hatchery #558. Until then this script
# only wipes known guest roots. Extend here when ensure installs
# helpers / persisted env on macOS - do not invent a parallel path.
#
# Add as the LAST script in a Clutch automations list if you
# want no Hatchery artifacts left after provisioning.
#
# Paths checked:
#   /usr/local/var/hatchery
#   /Library/Application Support/Hatchery
# ============================================================
set -euo pipefail

removed=0
for dir in "/usr/local/var/hatchery" "/Library/Application Support/Hatchery"; do
  if [[ -d "$dir" ]]; then
    echo "Removing Hatchery guest directory: $dir"
    rm -rf "$dir"
    removed=1
  fi
done

if [[ "$removed" -eq 0 ]]; then
  echo "WARN: Hatchery guest directory not found - nothing to remove"
else
  echo "Hatchery guest directory removed"
fi

# Stub: clear persisted reserved env + ensure helpers when #558 lands.
# Directory wipe above removes tree-installed helpers once those exist.
#
# for name in HATCHERY_ROOT HATCHERY_LOGS HATCHERY_TEMP HATCHERY_SOFTWARE; do
#   # e.g. remove from /etc/paths.d or a launchd plist Hatchery wrote
#   unset "$name" || true
# done
# echo "Cleared persisted Hatchery environment variables (stub until #558)"

exit 0
