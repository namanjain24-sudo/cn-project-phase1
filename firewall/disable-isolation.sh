#!/bin/bash
# PHASE 2 Extension C — roll back to the original firewall configuration.
# "Restore the original configuration after the demonstration" (spec).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HERE/rollback"

echo "==> 1/3 Flushing our anchor's rules"
sudo pfctl -a cn-backend -F rules 2>/dev/null || true

echo "==> 2/3 Reloading the stock macOS ruleset (/etc/pf.conf)"
sudo pfctl -f /etc/pf.conf 2>&1 | sed 's/^/    /'

echo "==> 3/3 Restoring pf enabled/disabled state"
BEFORE="$(cat "$BACKUP_DIR/pf-status-before.txt" 2>/dev/null || echo '')"
if echo "$BEFORE" | grep -qi 'Enabled'; then
  echo "    pf was already Enabled before the demo -- leaving it enabled."
else
  echo "    pf was Disabled before the demo -- disabling it again."
  sudo pfctl -d 2>&1 | sed 's/^/    /' || true
fi

echo
echo "Rollback complete. Confirm the backend is directly reachable again:"
echo "    curl -s --max-time 5 http://<this-machine-ip>:3001/api/status   (from a client)"
