#!/usr/bin/env bash
set -euo pipefail

OUT="/var/www/html/device-info.html"

HOST="$(hostname)"
IP="$(hostname -I | awk '{print $1}')"
SERIAL="$(awk '/Serial/ {print $3}' /proc/cpuinfo | tail -n1)"
OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
KERNEL="$(uname -r)"

PIHOLE_CORE="$(pihole -v -c 2>/dev/null | tr -d '\n' || true)"
PIHOLE_WEB="$(pihole -v -w 2>/dev/null | tr -d '\n' || true)"
PIHOLE_FTL="$(pihole -v -f 2>/dev/null | tr -d '\n' || true)"

WG_VER="$(wg --version 2>/dev/null | head -n1 || true)"

cat > "$OUT" <<EOF
<div>
  <div><b>Hostname:</b> ${HOST}</div>
  <div><b>IP Address:</b> ${IP}</div>
  <div><b>Serial:</b> ${SERIAL}</div>
  <div><b>OS:</b> ${OS}</div>
  <div><b>Kernel:</b> ${KERNEL}</div>
  <div><b>Pi-hole:</b> ${PIHOLE_CORE} / ${PIHOLE_WEB} / ${PIHOLE_FTL}</div>
  <div><b>WireGuard:</b> ${WG_VER}</div>
</div>
EOF

chmod 644 "$OUT"
