#!/bin/bash
# Load-balancing check -- Task D / demo step 5. Run from any client.
#
# Phase 1's version wrapped `curl | grep` in `set -euo pipefail`: one failed
# request made grep exit 1 and killed the script after printing only the banner,
# which is why this proof showed ZERO output in the Phase 1 video. This version
# prints one line per request, failures included.
. "$(dirname "$0")/_common.sh"

COUNT="${1:-10}"
URL="$BASE/api/status"

bold "$COUNT requests to $URL"
hr
a=0; b=0; fail=0
for i in $(seq 1 "$COUNT"); do
  body=$(ccurl -s -m 10 "$URL" 2>/dev/null); rc=$?
  backend=$(printf '%s' "$body" | sed -n 's/.*"backend":"\([A-Z]\)".*/\1/p')
  if [ -n "$backend" ]; then
    printf '  request %-2s -> Backend %s\n' "$i" "$backend"
    [ "$backend" = A ] && a=$((a+1)); [ "$backend" = B ] && b=$((b+1))
  else
    printf '  request %-2s -> FAILED (curl exit %s)\n' "$i" "$rc"
    fail=$((fail+1))
  fi
done
hr
printf '  Backend A: %s   Backend B: %s   failed: %s\n' "$a" "$b" "$fail"
if [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then
  ok "both backends served traffic -- round-robin load balancing confirmed"
elif [ "$((a+b))" -gt 0 ]; then
  warn "only one backend answered -- the other is down (expected during the Ext D demo)"
else
  bad "nothing succeeded -- run ./scripts/diagnose.sh"
fi
