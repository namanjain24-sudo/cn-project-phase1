#!/bin/bash
# Load-balancing proof — Task D / Demo step 5.
# Run from any client machine, after DNS + TLS + both backends are up.
set -euo pipefail

DOMAIN="${1:-app.team1.test}"
COUNT="${2:-10}"

echo "Sending $COUNT requests to https://$DOMAIN/api/status ..."
echo ""

for i in $(seq 1 "$COUNT"); do
  BACKEND=$(curl -s "https://$DOMAIN/api/status" | grep -o '"backend":"[A-Z]"')
  echo "Request $i -> $BACKEND"
done

echo ""
echo "You should see A and B alternating above. If it's all one letter, one backend"
echo "may be down (see docs/failure-demos.md #3) or you're hitting a keep-alive"
echo "connection that's pinned to one upstream — try again with fresh connections:"
echo "  curl -s --no-keepalive https://$DOMAIN/api/status"
