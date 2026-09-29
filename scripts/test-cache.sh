#!/bin/bash
# HTTP caching proof — Task F / Demo step 7.
# Run from any client machine.
set -euo pipefail

DOMAIN="${1:-app.cn_team.test}"
URL="https://$DOMAIN/api/data"

echo "== First request: full 200 with Cache-Control + ETag =="
curl -sI "$URL"

echo ""
echo "== Extracting ETag for a conditional request =="
ETAG=$(curl -sI "$URL" | grep -i etag | sed 's/[Ee][Tt]ag: //I' | tr -d '\r')
echo "ETag: $ETAG"

echo ""
echo "== Second request, with If-None-Match: expect 304 Not Modified, empty body =="
curl -sI -H "If-None-Match: $ETAG" "$URL"

echo ""
echo "Explain in the demo: first call = full new request (200 + body)."
echo "Second call = conditional request (304, no body, server confirms content unchanged)."
echo "A true 'fresh cache hit' happens client-side within the 60s max-age window and"
echo "never even reaches the server — show this via browser DevTools Network tab"
echo "(the request will show as served 'from disk/memory cache' with no server round-trip)."
