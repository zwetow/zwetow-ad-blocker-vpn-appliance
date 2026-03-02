#!/usr/bin/env bash
set -euo pipefail

PRIV="$(sudo cat /etc/wireguard/server_private.key)"
sudo sed -i "s|^PrivateKey = .*|PrivateKey = ${PRIV}|" /etc/wireguard/wg0.conf

sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0
