#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: wg-make-split.sh <client-name>"
  exit 1
fi

BASE="/etc/zwetow/clients/${NAME}.conf"
OUT="/etc/zwetow/clients/${NAME}-split.conf"

if [[ ! -f "$BASE" ]]; then
  echo "Missing client config: $BASE"
  exit 1
fi

LAN="$("/opt/zwetow/bin/get-lan-subnet.sh")"
if [[ "$LAN" == "UNKNOWN" ]]; then
  echo "Could not detect LAN subnet on eth0."
  exit 1
fi

sudo cp "$BASE" "$OUT"
sudo sed -i "s|^AllowedIPs = .*|AllowedIPs = ${LAN}|" "$OUT"

echo "Created: $OUT"
echo "LAN Split Tunnel subnet: $LAN"
echo
echo "QR code:"
qrencode -t ansiutf8 < "$OUT"
