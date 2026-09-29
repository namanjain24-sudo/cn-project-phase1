#!/bin/bash
# TLS handshake proof — Task E / Demo step 6, without needing Wireshark.
# Run from any client machine.
set -euo pipefail

DOMAIN="${1:-app.team1.test}"

echo "== curl -v: shows the TLS handshake steps in the client's own log =="
echo "   (look for 'TLSv1.3', 'Server certificate', 'SSL connection using...')"
curl -v "https://$DOMAIN/" 2>&1 | head -40

echo ""
echo "== openssl s_client: raw handshake + certificate details =="
echo "   (Ctrl+C or Ctrl+D to exit after it connects)"
echo "Q" | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>&1 | head -30
