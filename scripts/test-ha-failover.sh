#!/bin/bash
# =============================================================================
# PHASE 2 Extension D -- HIGH-AVAILABILITY FAILOVER
# Run from a client. Measures BOTH correctness (which backend answered) and
# LATENCY -- latency is the point, because the Phase 1 bug was not "it broke",
# it was "it took 60 seconds".
#
#   ./scripts/test-ha-failover.sh [requests]
#
# Demo sequence:
#   1. run it with both backends up        -> A and B alternate, all fast
#   2. stop Backend A on Mac 3             -> all B, STILL fast (this is the fix)
#   3. restart Backend A                   -> alternation resumes within ~10s
# =============================================================================
. "$(dirname "$0")/_common.sh"

COUNT="${1:-8}"
URL="$BASE/api/status"

bold "Extension D -- HA failover behaviour ($COUNT requests to $URL)"
hr

a=0; b=0; fail=0; worst=0
for i in $(seq 1 "$COUNT"); do
  out=$(ccurl -s -m 15 -w '\n%{http_code}|%{time_total}' "$URL" 2>/dev/null); rc=$?
  meta=$(printf '%s' "$out" | tail -1); json=$(printf '%s' "$out" | sed '$d')
  code="${meta%%|*}"; secs="${meta##*|}"
  backend=$(printf '%s' "$json" | sed -n 's/.*"backend":"\([A-Z]\)".*/\1/p')
  # track the worst latency, in integer milliseconds (portable, no bc needed)
  ms=$(printf '%.0f' "$(echo "$secs" | awk '{print $1*1000}')" 2>/dev/null || echo 0)
  [ "$ms" -gt "$worst" ] 2>/dev/null && worst=$ms

  if [ -n "$backend" ]; then
    printf '  %-2s  Backend %s   HTTP %s   %sms\n' "$i" "$backend" "$code" "$ms"
    [ "$backend" = A ] && a=$((a+1)); [ "$backend" = B ] && b=$((b+1))
  else
    printf '  %-2s  \033[31mFAILED\033[0m   HTTP %s   %sms   (curl exit %s)\n' "$i" "$code" "$ms" "$rc"
    fail=$((fail+1))
  fi
done
hr
printf '  A=%s  B=%s  failed=%s  worst latency=%sms\n' "$a" "$b" "$fail" "$worst"
hr

bold "Verdict"
if [ "$fail" -eq 0 ] && [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then
  ok "Both backends healthy and load balanced."
elif [ "$fail" -eq 0 ] && [ "$((a+b))" -eq "$COUNT" ]; then
  ok "ONE backend is down, yet every single request succeeded."
  info "nginx ejected the dead backend (max_fails=2 fail_timeout=10s) and served"
  info "everything from the healthy one. The client never saw an error."
else
  bad "$fail request(s) failed outright."
fi

if [ "$worst" -gt 10000 ]; then
  bad "Worst latency ${worst}ms -- this is the PHASE 1 BUG pattern: nginx waiting out"
  info "its DEFAULT 60s timeout on a backend that is hung rather than refusing."
  info "Mac 2 is still running the old Phase 1 config. Fix:"
  info "  sudo cp mac2-edge/nginx-phase2.conf /opt/homebrew/etc/nginx/servers/cn-project.conf"
  info "  sudo nginx -t && sudo nginx -s reload"
elif [ "$worst" -gt 2800 ]; then
  warn "Worst latency ${worst}ms ~= proxy_read_timeout (3s)."
  info "That means the dead backend ACCEPTED the TCP connection and then never"
  info "answered -- a hung process or a sleeping laptop. nginx waited out the read"
  info "timeout, then retried the healthy backend, so the client still got a 200."
  info "Expect exactly max_fails(=2) slow requests, then the backend is ejected"
  info "for fail_timeout(=10s) and everything is fast again -- which is the shape"
  info "of the timings printed above."
elif [ "$worst" -gt 1800 ]; then
  warn "Worst latency ${worst}ms ~= proxy_connect_timeout (2s)."
  info "The dead backend did not even complete the TCP handshake -- machine off,"
  info "asleep, or packets being dropped by a firewall. Retried and served."
else
  ok "Worst latency ${worst}ms -- failover is effectively invisible to the client."
  info "A cleanly stopped backend refuses the connection instantly, so nginx moves"
  info "to the next upstream with no measurable delay at all."
fi

cat <<'TXT'

  The single point of failure that remains (the spec asks you to name it):
    the EDGE itself -- nginx on Mac 2. Every request goes through that one
    machine, so if it dies, DNS still resolves and the backends are still
    healthy, but nobody can reach the service.
  To eliminate it you would need either several edges behind one DNS name
    (multiple A records / round-robin DNS, or an anycast VIP + health checks),
    or a floating IP that a standby edge takes over. Extension E is the
    manual, DNS-driven version of exactly that.
TXT
