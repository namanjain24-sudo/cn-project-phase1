#!/bin/bash
# =============================================================================
# PHASE 2 Extension F -- SYSTEMATIC LAYER-BY-LAYER DIAGNOSIS
#
#   ./scripts/diagnose.sh
#
# The faculty will inject ONE fault into the running system and ask which layer
# it is in. The marks are for METHODOLOGY, not for guessing fast. This script
# walks the layers in order -- link, network, DNS, transport, TLS, edge, app --
# and stops you at the FIRST one that breaks, because everything above a broken
# layer is meaningless.
#
# Say the order out loud while it runs: "name resolution first, then TCP
# connectivity, then TLS, then the application."
# =============================================================================
. "$(dirname "$0")/_common.sh"

PORT="$(printf '%s' "$BASE" | sed -n 's|^https://[^:/]*:\([0-9]*\).*|\1|p')"; PORT="${PORT:-443}"

FAILED_LAYER=""
note() { [ -z "$FAILED_LAYER" ] && FAILED_LAYER="$1"; }

bold "LAYER-BY-LAYER DIAGNOSIS for https://$APP"
info "expected edge: ${MAC2_IP:-?} (Mac 2)   |   standby edge: ${MAC4_IP:-?} (Mac 4)"
hr

# ---------------------------------------------------------------- L2/L3 local
bold "1. Link / Network -- is this machine even on the LAN?"
MYIP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
GW="$(netstat -rn -f inet 2>/dev/null | awk '/^default/{print $2; exit}')"
if [ -n "$MYIP" ]; then ok "this machine: $MYIP   gateway: ${GW:-<none>}"
else bad "no IPv4 address on en0/en1 -- not connected to Wi-Fi"; note "L1/L2 (link)"; fi
if [ -n "$GW" ]; then
  if ping -c 2 -t 4 "$GW" >/dev/null 2>&1; then ok "gateway $GW reachable"
  else bad "gateway $GW NOT reachable"; note "L3 (network)"; fi
fi
hr

# ----------------------------------------------------------------------- DNS
bold "2. DNS -- can the NAME be turned into an IP?"
RESOLVERS="$(networksetup -getdnsservers Wi-Fi 2>/dev/null | tr '\n' ' ')"
info "configured resolvers: $RESOLVERS"

SYSIP="$(dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}')"
if [ -n "$SYSIP" ]; then ok "system resolver: $APP -> $SYSIP"
else bad "system resolver cannot resolve $APP"; note "DNS"; fi

for pair in "primary:${MAC1_IP:-}" "backup:${MAC3_IP:-}"; do
  tag="${pair%%:*}"; ip="${pair##*:}"
  [ -n "$ip" ] || continue
  ans="$(dig +time=2 +tries=1 +short "@$ip" "$APP" A 2>/dev/null \
         | grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1)"
  if [ -n "$ans" ]; then ok "$tag resolver $ip -> $ans"
  else bad "$tag resolver $ip did not answer (stopped? wrong IP? UDP 53 blocked?)"; fi
done

if [ -n "$SYSIP" ] && [ -n "${MAC2_IP:-}" ] && [ "$SYSIP" != "$MAC2_IP" ] && [ "$SYSIP" != "${MAC4_IP:-}" ]; then
  bad "resolved IP $SYSIP is neither the primary nor the standby edge"
  info "      -> this is the 'DNS record points at the wrong host' fault class."
  note "DNS (wrong record)"
fi
TARGET="${SYSIP:-${MAC2_IP:-}}"
hr

# ----------------------------------------------------------------- TRANSPORT
bold "3. Transport -- is the IP reachable, and is port $PORT open on it?"
if [ -n "$TARGET" ]; then
  if ping -c 2 -t 4 "$TARGET" >/dev/null 2>&1; then ok "$TARGET answers ICMP (host is up)"
  else warn "$TARGET does not answer ping (could just be a firewall rule -- not conclusive)"; fi

  ccurl -s -o /dev/null --connect-timeout 5 -m 6 -k \
       "https://$TARGET:$PORT/" >/dev/null 2>&1; rc=$?
  case $rc in
    0|22|60|35) ok "TCP connect to $TARGET:$PORT succeeded" ;;
    7)  bad "connection REFUSED on $TARGET:$PORT -- nothing is LISTENING there"
        info "      -> edge process is stopped, or the record points at the wrong machine."
        note "TCP (port closed)" ;;
    28) bad "connection TIMED OUT to $TARGET:$PORT -- packets are being DROPPED"
        info "      -> firewall/pf rule, or the host is off/asleep."
        info "      refused = nobody home;  timeout = someone is filtering you."
        note "TCP (filtered)" ;;
    *)  warn "curl exit $rc connecting to $TARGET:$PORT" ;;
  esac
else
  bad "no target IP to test -- fix DNS first"; note "DNS"
fi
hr

# ----------------------------------------------------------------------- TLS
bold "4. TLS -- does the certificate validate WITHOUT -k?"
out=$(ccurl -sS -o /dev/null -m 10 "$BASE/" 2>&1); rc=$?
case $rc in
  0)  ok "certificate chain validated and handshake completed" ;;
  60) bad "certificate NOT trusted on this machine"
      info "      -> install the team CA:  sudo security add-trusted-cert -d -r trustRoot \\"
      info "             -k /Library/Keychains/System.keychain mac2-edge/rootCA.pem"
      note "TLS (trust)" ;;
  51) bad "certificate does not match the hostname $APP"; note "TLS (SAN mismatch)" ;;
  35) bad "TLS handshake failed (protocol/cipher). Check ssl_protocols on the edge."; note "TLS (handshake)" ;;
  *)  [ -n "$FAILED_LAYER" ] && info "skipped -- a lower layer is already broken" \
        || warn "curl exit $rc: $(printf '%s' "$out" | tail -1)" ;;
esac
hr

# ------------------------------------------------------------------ EDGE/APP
bold "5. Edge -- is nginx itself alive?"
srv=$(ccurl -s -m 8 -o /dev/null -D- "$BASE/" 2>/dev/null \
      | awk 'BEGIN{IGNORECASE=1}/^server:/{print $2}' | tr -d '\r')
if [ -n "$srv" ]; then
  ok "the edge answered, Server: $srv"
  info "      Any HTTP response at all -- even a 502 -- is GENERATED BY nginx, so"
  info "      it proves the edge is alive. Pair that with the next check to tell"
  info "      an edge fault apart from a backend fault."
else
  [ -n "$FAILED_LAYER" ] && info "skipped -- a lower layer is already broken" \
    || { bad "no response from the edge at all"; note "HTTP (edge)"; }
fi
hr

bold "6. Application -- do the backends answer through the edge?"
DIAGFILE="$(mktemp)"
code=$(ccurl -s -o "$DIAGFILE" -w '%{http_code}' -m 12 "$BASE/api/status" 2>/dev/null)
body=$(cat "$DIAGFILE" 2>/dev/null); rm -f "$DIAGFILE"
case "$code" in
  200) ok "HTTP 200 -> $body" ;;
  502) bad "HTTP 502 Bad Gateway -- the edge is healthy but NO backend answered"
       info "      -> DNS fine, TCP fine, TLS fine. The fault is the application layer."
       note "APPLICATION (all backends down)" ;;
  504) bad "HTTP 504 Gateway Timeout -- a backend accepted but never replied"; note "APPLICATION (backend hung)" ;;
  "")  [ -n "$FAILED_LAYER" ] && info "skipped -- a lower layer is already broken" \
         || { bad "no HTTP response at all"; note "HTTP"; } ;;
  *)   warn "unexpected HTTP $code -> $body" ;;
esac
hr

bold "7. Backends, probed directly (expect FAILURE if Extension C isolation is ON)"
for pair in "A:${MAC3_IP:-}:${BACKEND_A_PORT:-3001}" "B:${MAC4_IP:-}:${BACKEND_B_PORT:-3002}"; do
  id="$(echo "$pair" | cut -d: -f1)"; h="$(echo "$pair" | cut -d: -f2)"; p="$(echo "$pair" | cut -d: -f3)"
  [ -n "$h" ] || continue
  ccurl -s -o /dev/null --connect-timeout 4 "http://$h:$p/api/status" >/dev/null 2>&1; rc=$?
  case $rc in
    0)  info "Backend $id ($h:$p) reachable directly -- isolation is OFF" ;;
    28) info "Backend $id ($h:$p) TIMEOUT -- filtered (isolation ON, or machine asleep)" ;;
    7)  info "Backend $id ($h:$p) REFUSED -- process not running" ;;
    *)  info "Backend $id ($h:$p) curl exit $rc" ;;
  esac
done
hr

bold "VERDICT"
if [ -z "$FAILED_LAYER" ]; then
  ok "No fault detected -- every layer from link to application is healthy."
else
  bad "Lowest broken layer: $FAILED_LAYER"
  case "$FAILED_LAYER" in
    DNS*)         info "Next: is dnsmasq running on Mac 1/Mac 3? Does the address= line hold the right IP?" ;;
    TCP*)         info "Next: is nginx running on the edge? Is a pf rule dropping you?" ;;
    TLS*)         info "Next: is the team CA in this machine's trust store? Does the SAN cover $APP?" ;;
    APPLICATION*) info "Next: are node server.js processes alive on Mac 3 and Mac 4?" ;;
    HTTP*)        info "Next: check nginx error log on Mac 2: tail -f /opt/homebrew/var/log/nginx/error.log" ;;
    *)            info "Next: re-check the layer below the one named above." ;;
  esac
fi
