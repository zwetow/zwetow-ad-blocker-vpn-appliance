#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: wg-delete-client.sh <client-name>" >&2
  exit 1
fi
if [[ ! "$NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Invalid client name. Use letters, numbers, dash, underscore only." >&2
  exit 1
fi

WG_IF="wg0"
WG_CONF="/etc/wireguard/wg0.conf"
ZWETOW_DIR="/etc/zwetow"
CLIENT_DIR="/etc/zwetow/clients"
REGISTRY_FILE="/etc/zwetow/wireguard-peers.json"
LOCK_FILE="/etc/zwetow/wireguard-peers.lock"

mkdir -p "$ZWETOW_DIR"
mkdir -p "$CLIENT_DIR"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo "WireGuard registry not found: $REGISTRY_FILE" >&2
  exit 3
fi

exec 9>"$LOCK_FILE"
flock 9

PUBKEY="$(
python3 - "$REGISTRY_FILE" "$NAME" <<'PY'
import json
import sys

registry_path, client_name = sys.argv[1], sys.argv[2]

try:
    with open(registry_path, "r", encoding="utf-8") as registry_file:
        data = json.load(registry_file)
except FileNotFoundError:
    sys.exit(3)
except Exception as exc:
    print(f"Failed to read registry: {exc}", file=sys.stderr)
    sys.exit(1)

clients = data.get("clients", {}) if isinstance(data, dict) else {}
entry = clients.get(client_name) if isinstance(clients, dict) else None
if not isinstance(entry, dict):
    sys.exit(3)

public_key = str(entry.get("public_key", "")).strip()
if not public_key:
    print(f"Client '{client_name}' is missing a public key in the registry", file=sys.stderr)
    sys.exit(1)

print(public_key)
PY
)" || {
  rc=$?
  if [[ $rc -eq 3 ]]; then
    echo "Client not found in registry: $NAME" >&2
    exit 3
  fi
  exit "$rc"
}

if sudo wg show "$WG_IF" peers 2>/dev/null | grep -Fxq "$PUBKEY"; then
  sudo wg set "$WG_IF" peer "$PUBKEY" remove
fi

if [[ -f "$WG_CONF" ]]; then
  TMP_WG="$(mktemp)"
  python3 - "$WG_CONF" "$PUBKEY" "$TMP_WG" <<'PY'
import sys

src_path, public_key, dst_path = sys.argv[1:4]

with open(src_path, "r", encoding="utf-8") as source_file:
    lines = source_file.readlines()

blocks = []
current = []
for line in lines:
    if line.strip() == "[Peer]":
        if current:
            blocks.append(current)
        current = [line]
    else:
        current.append(line)
if current:
    blocks.append(current)

with open(dst_path, "w", encoding="utf-8") as output_file:
    for block in blocks:
        block_text = "".join(block)
        if "[Peer]" in block_text and f"PublicKey = {public_key}" in block_text:
            continue
        output_file.writelines(block)
PY
  sudo install -m 600 "$TMP_WG" "$WG_CONF"
  rm -f "$TMP_WG"
fi

TMP_REGISTRY="$(mktemp)"
python3 - "$REGISTRY_FILE" "$NAME" "$TMP_REGISTRY" <<'PY'
import json
import os
import sys

registry_path, client_name, tmp_path = sys.argv[1:4]

with open(registry_path, "r", encoding="utf-8") as registry_file:
    data = json.load(registry_file)

if not isinstance(data, dict):
    data = {}
data.setdefault("version", 1)
clients = data.get("clients")
if not isinstance(clients, dict):
    clients = {}

if client_name not in clients:
    sys.exit(3)

del clients[client_name]
data["clients"] = clients

with open(tmp_path, "w", encoding="utf-8") as tmp_file:
    json.dump(data, tmp_file, indent=2, sort_keys=True)
    tmp_file.write("\n")
PY

sudo install -m 600 "$TMP_REGISTRY" "$REGISTRY_FILE"
rm -f "$TMP_REGISTRY"

sudo rm -f \
  "$CLIENT_DIR/${NAME}.conf" \
  "$CLIENT_DIR/${NAME}.png" \
  "$CLIENT_DIR/${NAME}.json" \
  "$CLIENT_DIR/${NAME}-full.conf" \
  "$CLIENT_DIR/${NAME}-split.conf"

echo "Client deleted: $NAME"
