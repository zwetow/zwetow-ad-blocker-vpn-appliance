#!/usr/bin/env bash
set -euo pipefail

WG_CONF="/etc/wireguard/wg0.conf"
WG_PRIV_KEY="/etc/wireguard/server_private.key"

if [[ ! -f "$WG_CONF" ]]; then
  echo "Missing $WG_CONF"
  exit 1
fi
if [[ ! -f "$WG_PRIV_KEY" ]]; then
  echo "Missing $WG_PRIV_KEY"
  exit 1
fi

PRIV="$(sudo cat /etc/wireguard/server_private.key)"
sudo sed -i "s|^PrivateKey = .*|PrivateKey = ${PRIV}|" "$WG_CONF"

TMP_NO_PEERS="$(mktemp)"
TMP_FINAL="$(mktemp)"

# Remove any persisted peer blocks; peers are managed at runtime.
awk '
BEGIN { skip_peer = 0 }
{
  if ($0 ~ /^\[Peer\][[:space:]]*$/) { skip_peer = 1; next }
  if (skip_peer && $0 ~ /^\[/) { skip_peer = 0 }
  if (!skip_peer) print
}
' "$WG_CONF" > "$TMP_NO_PEERS"

# Enforce SaveConfig = false in the Interface section.
awk '
BEGIN {
  in_interface = 0
  saveconfig_set = 0
}
{
  if ($0 ~ /^\[Interface\][[:space:]]*$/) {
    in_interface = 1
    print
    next
  }
  if (in_interface && $0 ~ /^\[/) {
    if (!saveconfig_set) {
      print "SaveConfig = false"
      saveconfig_set = 1
    }
    in_interface = 0
  }
  if (in_interface && $0 ~ /^[[:space:]]*SaveConfig[[:space:]]*=/) {
    if (!saveconfig_set) {
      print "SaveConfig = false"
      saveconfig_set = 1
    }
    next
  }
  print
}
END {
  if (in_interface && !saveconfig_set) {
    print "SaveConfig = false"
    saveconfig_set = 1
  }
}
' "$TMP_NO_PEERS" > "$TMP_FINAL"

sudo install -m 600 "$TMP_FINAL" "$WG_CONF"
rm -f "$TMP_NO_PEERS" "$TMP_FINAL"

sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0
