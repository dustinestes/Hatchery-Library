#!/usr/bin/env bash
# ============================================================
# hatchery-cleanup-linux.sh
# Removes Hatchery guest directories and their contents.
#
# Add as the LAST script in a Clutch automations list if you
# want no Hatchery artifacts left after provisioning.
#
# Paths checked:
#   /var/lib/hatchery
#   /opt/hatchery
# ============================================================
set -euo pipefail

removed=0
for dir in /var/lib/hatchery /opt/hatchery; do
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

# Optional: remove persisted reserved env vars when Linux persist lands (#501 / #482).
# Directory wipe above is the default cleanup path. Uncomment / adapt when used:
#
# for name in HATCHERY_ROOT HATCHERY_LOGS HATCHERY_TEMP HATCHERY_SOFTWARE; do
#   # e.g. remove from /etc/environment or a profile.d drop-in Hatchery wrote
#   unset "$name" || true
# done
# echo "Cleared persisted Hatchery environment variables (stub)"

exit 0
