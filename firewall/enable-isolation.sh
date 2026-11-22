#!/bin/bash
# PHASE 2 Extension C — turn ON backend isolation.
# Run on Mac 3 (Backend A) and/or Mac 4 (Backend B). Needs sudo.
#
# Takes a rollback snapshot FIRST, so the "maintain a rollback copy" part of
# the spec is satisfied by construction, not by remembering to do it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
BACKUP_DIR="$HERE/rollback"
mkdir -p "$BACKUP_DIR"

if [ ! -f "$HERE/pf.anchors.cn-backend" ]; then
  echo "ERROR: $HERE/pf.anchors.cn-backend not found."
  echo "Run ./scripts/set-ips.sh first -- it generates it from the .template."
  exit 1
fi

echo "==> 1/5 Snapshotting current firewall state for rollback"
sudo pfctl -sr   > "$BACKUP_DIR/rules-before.txt"   2>/dev/null || true
sudo pfctl -s info 2>/dev/null | head -1 > "$BACKUP_DIR/pf-status-before.txt" || true
echo "    saved: $BACKUP_DIR/rules-before.txt"
echo "    pf was: $(cat "$BACKUP_DIR/pf-status-before.txt")"

echo "==> 2/5 Installing anchor file to /etc/pf.anchors/cn-backend"
sudo cp "$HERE/pf.anchors.cn-backend" /etc/pf.anchors/cn-backend

echo "==> 3/5 Syntax-checking the ruleset BEFORE loading it (pfctl -n = dry run)"
sudo pfctl -n -f "$HERE/pf-cn.conf"
echo "    syntax OK"

echo "==> 4/5 Loading ruleset and enabling pf"
sudo pfctl -E -f "$HERE/pf-cn.conf" 2>&1 | sed 's/^/    /'

echo "==> 5/5 Active rules in our anchor:"
sudo pfctl -a cn-backend -s rules 2>/dev/null | sed 's/^/    /'

echo
echo "Isolation is ON. Backend ports are now reachable ONLY from the edge (Mac 2)"
echo "and from localhost. Verify from a CLIENT machine with:"
echo "    ./scripts/test-isolation.sh"
echo "Roll back with:  ./firewall/disable-isolation.sh"
