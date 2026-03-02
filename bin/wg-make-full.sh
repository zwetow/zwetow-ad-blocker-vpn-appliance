#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: wg-make-full.sh <client-name>"
  exit 1
fi

BASE="/etc/zwetow/clients/${NAME}.conf"
OUT="/etc/zwetow/clients/${NAME}-full.conf"

if [[ ! -f "$BASE" ]]; then
  echo "Missing client config: $BASE"
  exit 1
fi

sudo cp "$BASE" "$OUT"
sudo sed -i "s|^AllowedIPs = .*|AllowedIPs = 0.0.0.0/0, ::/0|" "$OUT"

echo "Created: $OUT"
echo
echo "QR code:"
qrencode -t ansiutf8 < "$OUT"
