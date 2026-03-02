#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="/etc/zwetow/support_authorized_keys"
TARGET="/home/zwetow/.ssh/authorized_keys"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE. Put your support public key there first."
  exit 1
fi

sudo install -d -m 700 -o zwetow -g zwetow /home/zwetow/.ssh
sudo install -m 600 -o zwetow -g zwetow "$KEY_FILE" "$TARGET"
echo "Support SSH key enabled."
