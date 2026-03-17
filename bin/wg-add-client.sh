#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: wg-add-client.sh <client-name>"
  exit 1
fi
if [[ ! "$NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Invalid client name. Use letters, numbers, dash, underscore only."
  exit 1
fi

WG_IF="wg0"
WG_DIR="/etc/wireguard"
ZWETOW_DIR="/etc/zwetow"
CLIENT_DIR="/etc/zwetow/clients"
REGISTRY_FILE="/etc/zwetow/wireguard-peers.json"
LOCK_FILE="/etc/zwetow/wireguard-peers.lock"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
SUBNET_PREFIX="10.6.0"
START_HOST=2
END_HOST=254

mkdir -p "$ZWETOW_DIR"
chmod 700 "$ZWETOW_DIR"
mkdir -p "$CLIENT_DIR"
chmod 700 "$CLIENT_DIR"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  cat > "$REGISTRY_FILE" <<EOF
{"version":1,"clients":{}}
EOF
  chmod 600 "$REGISTRY_FILE"
fi

exec 9>"$LOCK_FILE"
flock 9

if [[ -f "$CLIENT_DIR/${NAME}.conf" ]]; then
  echo "Client already exists: $NAME"
  exit 0
fi

if python3 - "$REGISTRY_FILE" "$NAME" <<'PY'
import json, sys
registry_path, client_name = sys.argv[1], sys.argv[2]
try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}
clients = data.get("clients", {}) if isinstance(data, dict) else {}
sys.exit(0 if client_name in clients else 1)
PY
then
  echo "Client already exists in registry: $NAME"
  exit 0
fi

declare -A USED_IPS=()
while IFS= read -r ip; do
  [[ -n "$ip" ]] && USED_IPS["$ip"]=1
done < <(
  {
    sudo wg show "$WG_IF" allowed-ips 2>/dev/null | awk '{print $2}' | cut -d/ -f1
    python3 - "$REGISTRY_FILE" <<'PY'
import json, sys
registry_path = sys.argv[1]
try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}
clients = data.get("clients", {}) if isinstance(data, dict) else {}
for _, entry in clients.items():
    if isinstance(entry, dict):
        ip = str(entry.get("ip", "")).strip()
        if ip:
            print(ip.split("/")[0])
PY
    for conf in "$CLIENT_DIR"/*.conf; do
      [[ -f "$conf" ]] || continue
      awk '/^Address[[:space:]]*=/{print $3}' "$conf" | cut -d/ -f1
    done
  } | sed '/^$/d' | sort -V
)

IP=""
for i in $(seq "$START_HOST" "$END_HOST"); do
  CAND="${SUBNET_PREFIX}.${i}"
  if [[ -z "${USED_IPS[$CAND]:-}" ]]; then
    IP="$CAND"
    break
  fi
done
if [[ -z "$IP" ]]; then
  echo "No available WireGuard client IPs in ${SUBNET_PREFIX}.0/24"
  exit 1
fi

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
TMP_CONF="$(mktemp)"

cat > "$TMP_CONF" <<EOF
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

install -m 600 "$TMP_CONF" "$CONF_PATH"
rm -f "$TMP_CONF"

# Add peer to server
if ! sudo wg set "$WG_IF" peer "$CLIENT_PUB" allowed-ips "$IP/32"; then
  rm -f "$CONF_PATH"
  echo "Failed to add runtime peer for $NAME"
  exit 1
fi

python3 - "$REGISTRY_FILE" "$NAME" "$CLIENT_PUB" "$IP/32" "$CONF_PATH" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

registry_path, name, public_key, ip_cidr, conf_path = sys.argv[1:6]
try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}
data.setdefault("version", 1)
clients = data.get("clients")
if not isinstance(clients, dict):
    clients = {}
data["clients"] = clients

clients[name] = {
    "public_key": public_key,
    "ip": ip_cidr,
    "config_path": conf_path,
    "created_at": datetime.now(timezone.utc).isoformat(),
}

tmp_path = f"{registry_path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
os.replace(tmp_path, registry_path)
PY
chmod 600 "$REGISTRY_FILE"

echo "Saved: $CONF_PATH"
echo
echo "QR code:"
qrencode -t ansiutf8 < "$CONF_PATH"
