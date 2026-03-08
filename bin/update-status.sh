#!/usr/bin/env bash
set -euo pipefail

OUT="/var/www/html/zwetow/status.json"
HOST="$(hostname)"
IP="$(hostname -I | awk '{print $1}')"
SERIAL="$(awk '/Serial/ {print $3}' /proc/cpuinfo | tail -n1)"
OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
KERNEL="$(uname -r)"

PIHOLE_CORE="$(pihole -v 2>/dev/null | awk -F'[: ]+' '/Core version is/ {print "Core " $4}' | head -n1)"
PIHOLE_WEB="$(pihole -v 2>/dev/null | awk -F'[: ]+' '/Web version is/ {print "Web " $4}' | head -n1)"
PIHOLE_FTL="$(pihole -v 2>/dev/null | awk -F'[: ]+' '/FTL version is/ {print "FTL " $4}' | head -n1)"

WG_VER="$(wg --version 2>/dev/null | awk '{print $2}' || echo 'not installed')"
KUMA_URL="http://${IP}:3001/"
ADMIN_URL="http://${IP}/admin/"

sudo tee "$OUT" >/dev/null <<EOF
{
  "hostname": "$HOST",
  "ip": "$IP",
  "serial": "$SERIAL",
  "os": "$OS",
  "kernel": "$KERNEL",
  "pihole_core": "$PIHOLE_CORE",
  "pihole_web": "$PIHOLE_WEB",
  "pihole_ftl": "$PIHOLE_FTL",
  "wireguard": "$WG_VER",
  "links": {
    "pihole_admin": "$ADMIN_URL",
    "uptime_kuma": "$KUMA_URL"
  }
}
EOF

sudo chmod 644 "$OUT"
