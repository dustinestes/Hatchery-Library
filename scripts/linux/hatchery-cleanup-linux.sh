#!/usr/bin/env bash
# ============================================================
# hatchery-cleanup-linux.sh
# Removes Hatchery guest directories and their contents.
#
# Guest environment ensure catalog (#554 / ADR-0032): Linux payload
# and matching cleanup land in Hatchery #557. Until then this script
# only wipes known guest roots. Extend here when ensure installs
# helpers / persisted env on Linux - do not invent a parallel path.
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

# Stub: clear persisted reserved env + ensure helpers when #557 lands.
# Directory wipe above removes tree-installed helpers once those exist.
#
# for name in HATCHERY_ROOT HATCHERY_LOGS HATCHERY_TEMP HATCHERY_SOFTWARE; do
#   # e.g. remove from /etc/environment or a profile.d drop-in Hatchery wrote
#   unset "$name" || true
# done
# echo "Cleared persisted Hatchery environment variables (stub until #557)"

exit 0
