#!/usr/bin/env bash
# ============================================================
# enable-ssh-linux.sh
# Enable OpenSSH server and allow SSH through the firewall.
#
# Environment:
#   SSH_USERS - optional comma-separated local users to ensure
#               exist in the ssh group (or create sshd allow)
# ============================================================
set -euo pipefail

SSH_USERS="${SSH_USERS:-}"

echo "Enabling OpenSSH server"

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl enable --now ssh
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl enable --now sshd
  else
    echo "WARN: ssh/sshd unit not found - install openssh-server first" >&2
  fi
fi

if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || ufw allow 22/tcp || true
  echo "UFW SSH rule applied (best effort)"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=ssh || true
  firewall-cmd --reload || true
  echo "firewalld SSH rule applied (best effort)"
fi

IFS=',' read -r -a users <<< "$SSH_USERS"
for raw in "${users[@]}"; do
  name="$(echo "$raw" | xargs)"
  [[ -z "$name" ]] && continue
  if getent group ssh >/dev/null 2>&1; then
    usermod -aG ssh "$name" || true
    echo "Added '$name' to group ssh (best effort)"
  fi
done

echo "OpenSSH enable complete"
exit 0
