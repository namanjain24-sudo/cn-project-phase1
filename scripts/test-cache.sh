#!/bin/bash
# HTTP caching proof — Task F / Demo step 7.
# Run from any client machine.
set -euo pipefail

# Takes a base URL. Default is the real HTTPS service; pass a backend directly
# (e.g. http://localhost:3001) for the 304 demo -- see the note at the bottom.
BASE="${1:-https://app.cn_team.test}"
URL="$BASE/api/data"

echo "== First request: full 200 with Cache-Control + ETag =="
# NOTE: not `curl -I`. -I sends a HEAD request and these backends only route
# GET, so -I falls through to the 404 handler (exactly what happened on camera
# in the Phase 1 video). -D- -o /dev/null is a GET that prints the headers.
curl -s -D- -o /dev/null "$URL"

echo ""
echo "== Extracting ETag for a conditional request =="
ETAG=$(curl -s -D- -o /dev/null "$URL" | grep -i etag | sed 's/[Ee][Tt]ag: //I' | tr -d '\r')
echo "ETag: $ETAG"

echo ""
echo "== Second request, with If-None-Match: expect 304 Not Modified, empty body =="
curl -s -D- -o /dev/null -H "If-None-Match: $ETAG" "$URL"

echo ""
echo "Explain in the demo: first call = full new request (200 + body)."
echo "Second call = conditional request (304, no body, server confirms content unchanged)."
echo ""
echo "Why run this against ONE backend (http://localhost:3001) and not the domain?"
echo "The ETag is a hash of the body, and /api/data's body contains the backend id,"
echo "so Backend A and Backend B produce different ETags. Through nginx round-robin"
echo "the conditional request can land on the other backend, whose ETag does not"
echo "match, so it correctly returns 200 instead of 304. That is caching behaving"
echo "exactly as specified -- be ready to say so if asked."
echo ""
echo "A true 'fresh cache hit' happens client-side within the 60s max-age window and"
echo "never even reaches the server — show this via browser DevTools Network tab"
echo "(the request will show as served 'from disk/memory cache' with no server round-trip)."
