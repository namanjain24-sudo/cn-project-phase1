#!/bin/bash
# Run from any client machine once Mac 1 (DNS) is set up.
set -euo pipefail

DOMAIN_APP="${1:-app.team1.test}"
DOMAIN_API="${2:-api.team1.test}"

echo "== dig $DOMAIN_APP =="
dig "$DOMAIN_APP" +short

echo ""
echo "== dig $DOMAIN_API =="
dig "$DOMAIN_API" +short

echo ""
echo "== full dig output (save this for evidence/dns/) =="
dig "$DOMAIN_APP"

echo ""
echo "== nslookup (alternate tool) =="
nslookup "$DOMAIN_APP"
