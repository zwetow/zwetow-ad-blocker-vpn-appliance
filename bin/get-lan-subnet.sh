#!/usr/bin/env bash
set -euo pipefail

# Detect IPv4 CIDR on eth0 (example: 192.168.1.99/24)
CIDR="$(ip -o -f inet addr show eth0 | awk '{print $4}' | head -n1)"

if [[ -z "${CIDR:-}" ]]; then
  echo "UNKNOWN"
  exit 0
fi

# Convert to network CIDR using iproute2
ipcalc_out="$(ipcalc -n "$CIDR" 2>/dev/null || true)"
if [[ -n "$ipcalc_out" ]]; then
  # Some ipcalc versions output "Network: 192.168.1.0/24"
  echo "$ipcalc_out" | awk -F': ' '/Network/ {print $2; exit}'
  exit 0
fi

# Fallback: just print the CIDR if ipcalc isn't available
echo "$CIDR"
