#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: wg-add-client.sh <client-name>"
  exit 1
fi

WG_IF="wg0"
WG_DIR="/etc/wireguard"
CLIENT_DIR="/etc/zwetow/clients"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
mkdir -p "$CLIENT_DIR"
chmod 700 "$CLIENT_DIR"

# Find next available IP
USED="$(sudo wg show "$WG_IF" allowed-ips 2>/dev/null | awk '{print $2}' | cut -d/ -f1 | sort -V || true)"
IP="10.6.0.2"
for i in $(seq 2 254); do
  CAND="10.6.0.$i"
  if ! grep -qx "$CAND" <<< "$USED"; then
    IP="$CAND"
    break
  fi
done

umask 077
CLIENT_PRIV="$(wg genkey)"
CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"

if [[ ! -f "$WG_DIR/server_public.key" ]]; then
  echo "Missing $WG_DIR/server_public.key"
  exit 1
fi

SERVER_PUB="$(sudo cat "$WG_DIR/server_public.key")"

# You should set ENDPOINT to your public DNS later (for now it can be blank or LAN IP for testing)
ENDPOINT="${LOCAL_IP}:51820"
DNS="$LOCAL_IP"

CONF_PATH="$CLIENT_DIR/${NAME}.conf"

cat > "$CONF_PATH" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $IP/32
DNS = $DNS

[Peer]
PublicKey = $SERVER_PUB
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $ENDPOINT
PersistentKeepalive = 25
EOF

# Add peer to server
sudo wg set "$WG_IF" peer "$CLIENT_PUB" allowed-ips "$IP/32"

echo "Saved: $CONF_PATH"
echo
echo "QR code:"
qrencode -t ansiutf8 < "$CONF_PATH"
