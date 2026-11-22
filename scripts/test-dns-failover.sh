#!/bin/bash
# =============================================================================
# PHASE 2 Extension A -- BACKUP DNS RESOLVER
# Run this ON A CLIENT, once BEFORE stopping the primary and once AFTER.
#
#   ./scripts/test-dns-failover.sh        # check current state
#
# The demo sequence is:
#   1. run this (both resolvers should answer)
#   2. on Mac 1:  sudo brew services stop dnsmasq
#   3. run this again (primary dead, backup answers, name resolution survives)
#   4. on Mac 1:  sudo brew services start dnsmasq
# =============================================================================
. "$(dirname "$0")/_common.sh"

PRIMARY="${MAC1_IP:?set MAC1_IP in config/ips.env}"
BACKUP="${MAC3_IP:?set MAC3_IP in config/ips.env}"
EXPECT="${MAC2_IP:?set MAC2_IP in config/ips.env}"

bold "Extension A -- backup DNS resolver"
hr

bold "1. Which resolvers is this client configured to use?"
cfg=$(networksetup -getdnsservers Wi-Fi 2>/dev/null)
printf '%s\n' "$cfg" | sed 's/^/  /'
if printf '%s' "$cfg" | grep -q "$PRIMARY" && printf '%s' "$cfg" | grep -q "$BACKUP"; then
  ok "both primary ($PRIMARY) and backup ($BACKUP) are listed"
else
  warn "this client is not listing both resolvers. Fix with:"
  warn "  sudo networksetup -setdnsservers Wi-Fi $PRIMARY $BACKUP"
fi
hr

probe() { # probe <label> <server-ip>
  local label="$1" ip="$2" out rc
  # Only a real dotted-quad counts as an answer. dig prints its diagnostics on
  # stdout/stderr too, and treating that text as "an answer" would make a dead
  # resolver look alive -- which would quietly invalidate the whole demo.
  out=$(dig +time=2 +tries=1 +short "@$ip" "$APP" A 2>/dev/null \
        | grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1); rc=$?
  if [ -n "$out" ]; then
    if [ "$out" = "$EXPECT" ]; then
      ok "$label ($ip) answered $out  -- matches the expected edge IP"
    else
      warn "$label ($ip) answered $out  -- expected $EXPECT (record drift? cutover in progress?)"
    fi
    return 0
  else
    bad "$label ($ip) did NOT answer (this is expected if you stopped it on purpose)"
    return 1
  fi
}

bold "2. Query each resolver DIRECTLY (bypasses the client's own cache)"
probe "primary dnsmasq (Mac 1)" "$PRIMARY"; p=$?
probe "backup  dnsmasq (Mac 3)" "$BACKUP";  b=$?
hr

bold "3. Does the CLIENT still resolve the name using its normal resolver?"
sys=$(dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}')
if [ -n "$sys" ]; then
  ok "system resolver returned $sys for $APP"
else
  bad "system resolver could NOT resolve $APP"
fi
hr

bold "Verdict"
if [ $p -ne 0 ] && [ $b -eq 0 ] && [ -n "$sys" ]; then
  ok "PRIMARY IS DOWN BUT NAMES STILL RESOLVE -- backup DNS failover proven."
  info "This is the Extension A result the evaluator wants to see."
elif [ $p -eq 0 ] && [ $b -eq 0 ]; then
  info "Both resolvers healthy -- this is the 'before' state."
  info "Now stop the primary on Mac 1:  sudo brew services stop dnsmasq"
  info "...then run this script again."
elif [ $p -eq 0 ] && [ $b -ne 0 ]; then
  bad "The BACKUP is the one that is down. Start it on Mac 3:"
  info "  sudo brew services start dnsmasq"
else
  bad "Neither resolver answered -- name resolution is fully down."
fi

cat <<'TXT'

  The distinction the spec asks you to explain:
    DNS SERVICE failure       the resolver is gone, so names cannot be turned
                              into IPs at all. Nothing resolves. (This demo.)
    APPLICATION SERVER failure resolution still works perfectly -- the name
                              still maps to an IP -- but the service at that IP
                              does not answer. You get 502, not NXDOMAIN.
TXT
