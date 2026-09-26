#!/usr/bin/env bash
# ============================================================
# install-qemu-guest-agent-linux.sh
# Install and enable the QEMU guest agent package.
#
# Uses apt, dnf, or yum when available. Idempotent when the
# package and service are already present.
# ============================================================
set -euo pipefail

echo "Installing QEMU guest agent"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y qemu-guest-agent
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y qemu-guest-agent
elif command -v yum >/dev/null 2>&1; then
  yum install -y qemu-guest-agent
else
  echo "ERROR: no supported package manager (apt/dnf/yum)" >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now qemu-guest-agent || systemctl enable --now qemu-ga || true
fi

echo "QEMU guest agent installation complete"
exit 0
