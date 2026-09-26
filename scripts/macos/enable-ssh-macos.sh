#!/usr/bin/env bash
# ============================================================
# enable-ssh-macos.sh
# Enable the built-in Remote Login (SSH) service on macOS.
#
# Environment:
#   SSH_USERS - optional comma-separated local users granted
#               Remote Login access (systemsetup -setremotelogin)
# ============================================================
set -euo pipefail

SSH_USERS="${SSH_USERS:-}"

echo "Enabling Remote Login (SSH)"

# -f forces without interactive confirm on some versions
systemsetup -setremotelogin on >/dev/null 2>&1 || \
  systemsetup -f -setremotelogin on >/dev/null

IFS=',' read -r -a users <<< "$SSH_USERS"
for raw in "${users[@]}"; do
  name="$(echo "$raw" | xargs)"
  [[ -z "$name" ]] && continue
  echo "Ensuring Remote Login access for '$name' (best effort)"
  # Prefer dseditgroup when available
  if command -v dseditgroup >/dev/null 2>&1; then
    dseditgroup -o edit -a "$name" -t user com.apple.access_ssh 2>/dev/null || true
  fi
done

echo "Remote Login enable complete"
exit 0
