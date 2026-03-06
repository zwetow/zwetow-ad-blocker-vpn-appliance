#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 2
fi

REPO_DIR="/opt/zwetow/ui-repo"
RELEASES_DIR="/opt/zwetow/releases"
STATE_DIR="/opt/zwetow/state"

mkdir -p "$RELEASES_DIR" "$STATE_DIR"

cd "$REPO_DIR"

# Make encourage "latest tag" is available locally
git fetch --tags origin >/dev/null 2>&1 || true

# Verify tag exists
if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "ERROR: Tag not found: ${TAG}" >&2
  exit 3
fi

WT="${RELEASES_DIR}/${TAG}"

# Recreate worktree cleanly (safe even if it already exists)
if git worktree list | awk '{print $1}' | grep -qx "$WT"; then
  git worktree remove --force "$WT" >/dev/null 2>&1 || true
fi
rm -rf "$WT"
git worktree add --force "$WT" "refs/tags/${TAG}" >/dev/null

# --- Deploy files ---
# We intentionally only deploy known folders (bin/ systemd/ www/) from the repo
if [[ -d "$WT/bin" ]]; then
  rsync -a --delete "$WT/bin/" /opt/zwetow/bin/
fi

if [[ -d "$WT/systemd" ]]; then
  rsync -a "$WT/systemd/" /etc/systemd/system/
fi

# Optional: deploy web content if you decide to include any static files
if [[ -d "$WT/www" ]]; then
  rsync -a --delete "$WT/www/" /var/www/html/
fi

# Ensure scripts are executable
chmod +x /opt/zwetow/bin/*.sh 2>/dev/null || true

# Record version
echo "$TAG" > /opt/zwetow/VERSION

# Reload units if we shipped any
systemctl daemon-reload >/dev/null 2>&1 || true

# Enable known timers/services if they exist
systemctl enable --now zwetow-check-update.timer >/dev/null 2>&1 || true
systemctl enable --now zwetow-support-download.service >/dev/null 2>&1 || true

# Restart “zwetow” services gracefully if present
systemctl try-restart zwetow-support-download.service >/dev/null 2>&1 || true
systemctl try-restart zwetow-check-update.service >/dev/null 2>&1 || true

# Re-render landing page if present
if [[ -x /opt/zwetow/bin/render-index.sh ]]; then
  /opt/zwetow/bin/render-index.sh || true
fi

# Refresh update state
if [[ -x /opt/zwetow/bin/zwetow-check-update.sh ]]; then
  /opt/zwetow/bin/zwetow-check-update.sh || true
fi

echo "Deployed ${TAG}"
