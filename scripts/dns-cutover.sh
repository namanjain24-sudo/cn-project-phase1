#!/bin/bash
# =============================================================================
# PHASE 2 Extension E -- CONTROLLED EDGE MIGRATION (DNS-based cutover)
# RUN THIS ON MAC 1 (the DNS machine) ONLY.
#
#   ./scripts/dns-cutover.sh status       # which edge is the record pointing at?
#   ./scripts/dns-cutover.sh to-standby   # repoint app/api -> Mac 4 standby edge
#   ./scripts/dns-cutover.sh to-primary   # repoint back  -> Mac 2 primary edge
#
# This is the production pattern for migrating a service to new infrastructure
# without touching the client: you do not move the machine, you move the NAME.
# =============================================================================
set -uo pipefail
. "$(dirname "$0")/_common.sh"

CONF="${DNSMASQ_CONF:-/opt/homebrew/etc/dnsmasq.conf}"
PRIMARY_EDGE="${MAC2_IP:?}"
STANDBY_EDGE="${MAC4_IP:?}"

[ -f "$CONF" ] || { bad "dnsmasq config not found at $CONF"; info "Set DNSMASQ_CONF=/path if your Homebrew prefix differs (Intel: /usr/local/etc)."; exit 1; }

current() { grep -E "^address=/app\.$DOMAIN/" "$CONF" | head -1 | awk -F/ '{print $3}'; }

label() {
  case "$1" in
    "$PRIMARY_EDGE") echo "Mac 2 PRIMARY edge" ;;
    "$STANDBY_EDGE") echo "Mac 4 STANDBY edge" ;;
    *)               echo "unknown host" ;;
  esac
}

point_at() { # point_at <ip>
  local target="$1" now; now="$(current)"
  if [ "$now" = "$target" ]; then
    info "Already pointing at $target ($(label "$target")) -- nothing to do."
    return 0
  fi
  cp "$CONF" "$CONF.before-cutover.$(date +%H%M%S)" 2>/dev/null \
    || { bad "cannot back up $CONF -- re-run with sudo"; exit 1; }
  # NOTE: the s### delimiter is deliberate. Using s||| here breaks, because the
  # alternation (app|api) contains the delimiter character itself.
  sed -i '' -E "s#^(address=/(app|api)\.$DOMAIN/).*#\1$target#" "$CONF" \
    || { bad "sed failed -- re-run with sudo"; exit 1; }
  ok "records rewritten: app.$DOMAIN and api.$DOMAIN -> $target ($(label "$target"))"
  info "restarting dnsmasq so the new record is served..."
  sudo brew services restart dnsmasq >/dev/null 2>&1 && ok "dnsmasq restarted" \
    || warn "could not restart dnsmasq automatically -- run: sudo brew services restart dnsmasq"
}

case "${1:-status}" in
  status)
    now="$(current)"
    bold "Extension E -- current DNS target"
    hr
    info "config file : $CONF"
    info "app.$DOMAIN -> ${now:-<no record found>}  ($(label "${now:-x}"))"
    info "primary edge: $PRIMARY_EDGE (Mac 2)"
    info "standby edge: $STANDBY_EDGE (Mac 4)"
    hr
    dig +time=2 +tries=1 +noall +answer @127.0.0.1 "$APP" A 2>/dev/null | sed 's/^/  /'
    ;;
  to-standby)
    bold "Cutting over to the STANDBY edge (Mac 4)"
    hr
    warn "Before running this, make sure the standby nginx is actually UP on Mac 4:"
    info "  sudo nginx -t && sudo brew services start nginx"
    info "  curl -s https://$APP/ --resolve $APP:443:$STANDBY_EDGE -o /dev/null -w '%{http_code}\n'"
    hr
    point_at "$STANDBY_EDGE"
    hr
    info "Now watch the cutover from a client:  ./scripts/test-edge-cutover.sh"
    info "Clients that already cached the old answer keep hitting Mac 2 until"
    info "their TTL (${DNS_TTL:-30}s) expires. That lag is the demo."
    ;;
  to-primary)
    bold "Cutting back to the PRIMARY edge (Mac 2)"
    hr
    point_at "$PRIMARY_EDGE"
    ;;
  *)
    bad "unknown mode '${1}'"; info "use: status | to-standby | to-primary"; exit 1 ;;
esac
