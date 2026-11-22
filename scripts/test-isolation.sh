#!/bin/bash
# =============================================================================
# PHASE 2 Extension C -- SERVICE ISOLATION
# Run this FROM A CLIENT MACHINE (Mac 1 is ideal -- it is neither a backend
# nor the edge, so it is the honest test).
#
# Expected result once isolation is ON:
#   direct to backend ports  -> BLOCKED (timeout)
#   same service via the edge -> STILL WORKS
# =============================================================================
. "$(dirname "$0")/_common.sh"

A_HOST="${MAC3_IP:?}"; A_PORT="${BACKEND_A_PORT:-3001}"
B_HOST="${MAC4_IP:?}"; B_PORT="${BACKEND_B_PORT:-3002}"
CT=4

bold "Extension C -- backend isolation, tested from $(hostname -s) ($(ipconfig getifaddr en0 2>/dev/null || echo 'no en0 IP'))"
hr

direct() { # direct <label> <host> <port>
  local label="$1" host="$2" port="$3" out rc
  out=$(ccurl -s -o /dev/null -w '%{http_code}' --connect-timeout $CT \
        "http://$host:$port/api/status" 2>/dev/null); rc=$?
  case $rc in
    0)  bad "$label  http://$host:$port -> HTTP $out  (REACHABLE -- isolation is NOT active)"; return 1 ;;
    28) ok  "$label  http://$host:$port -> connection TIMED OUT after ${CT}s  (packets silently dropped by pf)"; return 0 ;;
    7)  warn "$label  http://$host:$port -> connection REFUSED"
        info "      refused != filtered. Refused means nothing is listening on that"
        info "      port (is the backend even running?). A firewall DROP gives a"
        info "      timeout instead. Say this distinction out loud in the viva."
        return 2 ;;
    *)  warn "$label  http://$host:$port -> curl exit $rc"; return 2 ;;
  esac
}

bold "1. Try to reach the backends DIRECTLY (this must FAIL)"
direct "Backend A" "$A_HOST" "$A_PORT"; ra=$?
direct "Backend B" "$B_HOST" "$B_PORT"; rb=$?
hr

bold "2. Reach the SAME service through the edge (this must still WORK)"
body=$(ccurl -s -m 10 "$BASE/api/status" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$body" | grep -q '"backend"'; then
  ok "$BASE/api/status -> $body"
  info "The edge can reach the backends; this client cannot. That is the whole point."
else
  bad "the service is NOT reachable through the edge either (curl exit $rc)"
  info "Run ./scripts/diagnose.sh -- isolation may have locked out nginx too,"
  info "which means the pass rule for the edge IP has the wrong address in it."
fi
hr

bold "Verdict"
if [ $ra -eq 0 ] && [ $rb -eq 0 ] && [ $rc -eq 0 ]; then
  ok "ISOLATION PROVEN: backends unreachable directly, service reachable via edge."
elif [ $ra -eq 1 ] || [ $rb -eq 1 ]; then
  warn "Isolation is not in force yet. On Mac 3 and Mac 4 run:  ./firewall/enable-isolation.sh"
else
  warn "Mixed result -- check whether the backends are actually running first."
fi

cat <<'TXT'

  What this models in the real world: backends in a private subnet / security
  group that only accepts traffic from the load balancer. The app servers have
  no public exposure at all; the edge is the only door.
TXT
