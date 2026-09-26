#!/usr/bin/env bash
# ============================================================
# configure-vm-basics-macos.sh
# Basic VM configuration - ComputerName / LocalHostName / timezone.
#
# Environment:
#   HOSTNAME  - new computer name (required)
#   TIMEZONE  - IANA timezone, e.g. America/Chicago (default: UTC)
#
# Requires root (or sudo) for scutil / systemsetup.
# ============================================================
set -euo pipefail

HOSTNAME_NEW="${HOSTNAME:-}"
TIMEZONE="${TIMEZONE:-UTC}"

if [[ -z "$HOSTNAME_NEW" ]]; then
  echo "ERROR: HOSTNAME is required" >&2
  exit 1
fi

echo "Setting timezone to '$TIMEZONE'"
systemsetup -settimezone "$TIMEZONE" >/dev/null
echo "Timezone set"

current="$(scutil --get ComputerName 2>/dev/null || hostname)"
if [[ "$current" == "$HOSTNAME_NEW" ]]; then
  echo "WARN: host is already named '$HOSTNAME_NEW' - skipping rename"
else
  echo "Renaming host from '$current' to '$HOSTNAME_NEW'"
  scutil --set ComputerName "$HOSTNAME_NEW"
  scutil --set LocalHostName "$HOSTNAME_NEW"
  scutil --set HostName "$HOSTNAME_NEW"
  echo "Hostname set - reboot recommended for full effect"
fi

echo "Basic configuration complete"
exit 0
