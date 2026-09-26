#!/usr/bin/env bash
# ============================================================
# configure-vm-basics-linux.sh
# Basic VM configuration - hostname and timezone (systemd).
#
# Environment:
#   HOSTNAME  - new hostname (required)
#   TIMEZONE  - IANA timezone, e.g. America/Chicago (default: UTC)
#
# Declare in a Clutch with reboot_after: true so the hostname
# takes effect before subsequent scripts run.
# ============================================================
set -euo pipefail

HOSTNAME_NEW="${HOSTNAME:-}"
TIMEZONE="${TIMEZONE:-UTC}"

if [[ -z "$HOSTNAME_NEW" ]]; then
  echo "ERROR: HOSTNAME is required" >&2
  exit 1
fi

echo "Setting timezone to '$TIMEZONE'"
timedatectl set-timezone "$TIMEZONE"
echo "Timezone set"

current="$(hostname)"
if [[ "$current" == "$HOSTNAME_NEW" ]]; then
  echo "WARN: host is already named '$HOSTNAME_NEW' - skipping rename"
else
  echo "Renaming host from '$current' to '$HOSTNAME_NEW'"
  hostnamectl set-hostname "$HOSTNAME_NEW"
  echo "Hostname set - reboot recommended for full effect"
fi

echo "Basic configuration complete"
exit 0
