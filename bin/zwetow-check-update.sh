#!/usr/bin/env bash
set -euo pipefail

REPO="zwetow/zwetow-ad-blocker-vpn-appliance"
STATE_DIR="/opt/zwetow/state"
CURRENT_FILE="/opt/zwetow/VERSION"
LATEST_FILE="${STATE_DIR}/LATEST_VERSION"
FLAG_FILE="${STATE_DIR}/UPDATE_AVAILABLE"

mkdir -p "$STATE_DIR"

CURRENT="$(cat "$CURRENT_FILE" 2>/dev/null || echo 'v0.0.0')"

LATEST="$(curl -fsSL --max-time 6 "https://api.github.com/repos/${REPO}/releases/latest" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" \
  || true)"

[[ -z "${LATEST:-}" ]] && exit 0

echo "$LATEST" > "$LATEST_FILE"

if [[ "$LATEST" != "$CURRENT" ]]; then
  echo "$LATEST" > "$FLAG_FILE"
else
  rm -f "$FLAG_FILE"
fi
