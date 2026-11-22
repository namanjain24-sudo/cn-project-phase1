#!/bin/bash
# PHASE 2 Extension E -- watch a DNS-based edge migration, from a CLIENT.
#
#   ./scripts/test-edge-cutover.sh
#
# Each line shows, at that moment:
#   resolved  the IP this client currently believes app.<domain> is
#   served-by the IP that ACTUALLY answered the request (curl's %{remote_ip})
#
# Run this, then have Mac 1 run ./scripts/dns-cutover.sh to-standby, and watch
# both columns move from the primary edge to the standby. 'resolved' lags by up
# to the TTL, which is the effect the spec asks you to observe.
. "$(dirname "$0")/_common.sh"

bold "Extension E -- edge cutover watch (Ctrl+C to stop)"
info "primary edge = $MAC2_IP (Mac 2)   standby edge = $MAC4_IP (Mac 4)   TTL = ${DNS_TTL:-30}s"
hr
while true; do
  resolved=$(dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}')
  served=$(ccurl -s -m 6 -o /dev/null -w '%{remote_ip}' "$BASE/api/status" 2>/dev/null)
  tag() { case "$1" in "$MAC2_IP") echo "(primary)";; "$MAC4_IP") echo "(standby)";; *) echo "";; esac; }
  printf '  %s  resolved=%-15s %-10s served-by=%-15s %s\n' \
    "$(date '+%H:%M:%S')" "${resolved:-<none>}" "$(tag "$resolved")" \
    "${served:-<no answer>}" "$(tag "$served")"
  sleep 3
done
