#!/bin/bash
# =============================================================================
# PHASE 2 Extension B -- DNS TTL AND CONTROLLED RECORD CHANGE
#
#   ./scripts/test-ttl.sh            # one-shot snapshot
#   ./scripts/test-ttl.sh watch      # poll every 5s -- use this during the demo
#   ./scripts/test-ttl.sh flush      # flush the client DNS cache
#
# Demo sequence:
#   1. ./scripts/test-ttl.sh watch              (on a CLIENT, leave running)
#   2. on Mac 1: ./scripts/dns-cutover.sh to-standby
#   3. watch the CACHED column stay on the old IP while the AUTHORITATIVE
#      column already shows the new one -- that gap IS the TTL.
#   4. after <= TTL seconds the cached column flips by itself.
#   5. ./scripts/test-ttl.sh flush   -> shows the change can be forced instantly
# =============================================================================
. "$(dirname "$0")/_common.sh"

PRIMARY="${MAC1_IP:?}"
TTL="${DNS_TTL:-30}"

snapshot() {
  # Authoritative answer, straight from dnsmasq, bypassing every cache.
  local cached
  # One query, then validate both fields. dig writes diagnostics into the same
  # stream, so blindly taking $5/$2 would print nonsense like "ttl=connection"
  # when the resolver is simply down.
  local answer
  answer=$(dig +time=2 +tries=1 +noall +answer "@$PRIMARY" "$APP" A 2>/dev/null \
           | awk '$4=="A" && $5 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $2, $5; exit}')
  ttlval=$(printf '%s' "$answer" | awk '{print $1}')
  auth=$(printf '%s' "$answer" | awk '{print $2}')
  # What this CLIENT actually believes right now (goes through mDNSResponder's cache).
  cached=$(dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}')
  printf '  %s   authoritative=%-15s ttl=%-4s   client-cached=%-15s %s\n' \
    "$(date '+%H:%M:%S')" "${auth:-<none>}" "${ttlval:-?}" "${cached:-<none>}" \
    "$([ -n "$auth" ] && [ -n "$cached" ] && [ "$auth" != "$cached" ] && printf '\033[33m<-- STALE (inside TTL)\033[0m')"
}

case "${1:-once}" in
  flush)
    bold "Flushing this client's DNS cache"
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
    ok "cache flushed -- the next lookup goes to the resolver, not the cache"
    hr; snapshot
    ;;
  watch)
    bold "Extension B -- TTL watch (Ctrl+C to stop). Configured TTL: ${TTL}s"
    info "authoritative = asked dnsmasq directly, so it ALWAYS shows the current record"
    info "client-cached = what this machine believes, which is allowed to lag by up to ${TTL}s"
    hr
    while true; do snapshot; sleep 5; done
    ;;
  *)
    bold "Extension B -- TTL snapshot"
    hr; snapshot; hr
    cat <<TXT
  Why doesn't 'dig' show the TTL counting down?
    Because dig talks to the authoritative resolver DIRECTLY and dnsmasq
    re-stamps a full ${TTL}s TTL on every answer. A TTL only counts down inside
    a CACHE. On macOS that cache is mDNSResponder, which is what dscacheutil
    (and ping, and curl, and the browser) go through. That is why the
    'client-cached' column is the one that demonstrates TTL behaviour, and it
    is a question worth being ready for in the viva.
TXT
    ;;
esac
