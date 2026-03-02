#!/usr/bin/env bash
set -euo pipefail

echo "Updating OS packages..."
sudo apt update
sudo apt -y upgrade

echo "Updating Pi-hole..."
if command -v pihole >/dev/null 2>&1; then
  sudo pihole -up
fi

echo "Done."
