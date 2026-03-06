#!/usr/bin/env bash
set -euo pipefail

HIST="/opt/zwetow/state/DEPLOY_HISTORY"
if [[ ! -s "$HIST" ]]; then
  echo "No rollback history available."
  exit 1
fi

# Last line is the most recent prior version
TAG="$(tail -n 1 "$HIST" | tr -d '\r\n')"
if [[ -z "$TAG" ]]; then
  echo "Rollback history empty."
  exit 1
fi

# Remove last entry (pop)
tmp="$(mktemp)"
head -n -1 "$HIST" > "$tmp" || true
mv "$tmp" "$HIST"

exec /opt/zwetow/bin/zwetow-deploy-tag.sh "$TAG"
