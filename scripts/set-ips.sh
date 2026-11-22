#!/bin/bash
# =============================================================================
# Regenerate EVERY config in this repo from config/ips.env.
#
# This exists because the team is on a shared mobile hotspot where IPs get
# reassigned on every reconnect -- which already broke the project twice during
# Phase 1. Instead of hand-editing five files and missing one, edit the single
# table in config/ips.env and run this.
#
#   ./scripts/set-ips.sh                 # use config/ips.env as-is
#   ./scripts/set-ips.sh --detect        # auto-fill THIS machine's IP first
#
# After running, restart whichever service you changed (it tells you which).
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO/config/ips.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found"; exit 1; }

# --- optionally detect this machine's own IP and tell the user which slot it is
if [ "${1:-}" = "--detect" ]; then
  MYIP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  if [ -n "$MYIP" ]; then
    echo "This machine's current IPv4 on Wi-Fi: $MYIP"
    echo "Make sure the right MACn_IP line in config/ips.env says that, then re-run without --detect."
    echo
  else
    echo "Could not detect an IPv4 address on en0/en1 -- are you on Wi-Fi?"; echo
  fi
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

for v in DOMAIN MAC1_IP MAC2_IP MAC3_IP MAC4_IP DNS_TTL; do
  [ -n "${!v:-}" ] || { echo "ERROR: $v is empty in config/ips.env"; exit 1; }
done

# basic sanity: all four must be distinct, dotted-quad
for v in MAC1_IP MAC2_IP MAC3_IP MAC4_IP; do
  echo "${!v}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' \
    || { echo "ERROR: $v='${!v}' is not a valid IPv4 address"; exit 1; }
done
if [ "$(printf '%s\n' "$MAC1_IP" "$MAC2_IP" "$MAC3_IP" "$MAC4_IP" | sort -u | wc -l)" -ne 4 ]; then
  echo "WARNING: two machines have the same IP in config/ips.env -- is that really right?"
fi

render() {   # render <template> <output>
  local tpl="$1" out="$2"
  [ -f "$tpl" ] || { echo "  skip (no template): $tpl"; return; }
  sed -e "s|<MAC1_IP>|$MAC1_IP|g" \
      -e "s|<MAC2_IP>|$MAC2_IP|g" \
      -e "s|<MAC3_IP>|$MAC3_IP|g" \
      -e "s|<MAC4_IP>|$MAC4_IP|g" \
      -e "s|<DNS_TTL>|$DNS_TTL|g" \
      -e "s|cn_team\.test|$DOMAIN|g" \
      "$tpl" > "$out"
  echo "  wrote $(basename "$out")"
}

echo "Rendering configs for domain '$DOMAIN':"
printf "  Mac 1 (DNS primary)   %s\n  Mac 2 (edge primary)  %s\n  Mac 3 (backend A + backup DNS) %s\n  Mac 4 (backend B + standby edge) %s\n  DNS TTL %ss\n\n" \
  "$MAC1_IP" "$MAC2_IP" "$MAC3_IP" "$MAC4_IP" "$DNS_TTL"

# The Phase 1 live configs are a graded deliverable ("Configuration Bundle --
# your actual working configs"). They carry hand-written provenance comments
# like "Points at Harsha's laptop, confirmed 2026-09-30". Re-rendering them from
# the template would replace those with placeholder boilerplate, so instead we
# only rewrite the IP VALUES in place and leave every comment untouched.
retarget() {  # retarget <file> <sed-expr>...
  local file="$1"; shift
  [ -f "$file" ] || { echo "  skip (missing): $(basename "$file")"; return; }
  sed -i '' "$@" "$file" && echo "  updated IPs in $(basename "$file") (comments preserved)"
}

echo "Phase 1 live configs (IPs updated in place):"
retarget "$REPO/mac1-dns/dnsmasq.conf" \
  -E -e "s#^(address=/(app|api)\.$DOMAIN/).*#\1$MAC2_IP#" \
     -e "s#^listen-address=127\.0\.0\.1,.*#listen-address=127.0.0.1,$MAC1_IP#"
retarget "$REPO/mac2-edge/nginx.conf" \
  -E -e "s#^([[:space:]]*server )[0-9.]+(:3001;)#\1$MAC3_IP\2#" \
     -e "s#^([[:space:]]*server )[0-9.]+(:3002;)#\1$MAC4_IP\2#"

echo "Phase 2 configs:"
render "$REPO/mac1-dns/dnsmasq-phase2.conf.template"     "$REPO/mac1-dns/dnsmasq-phase2.conf"
render "$REPO/mac2-edge/nginx-phase2.conf.template"      "$REPO/mac2-edge/nginx-phase2.conf"
render "$REPO/backup-dns/dnsmasq-backup.conf.template"   "$REPO/backup-dns/dnsmasq-backup.conf"
render "$REPO/standby-edge/nginx-standby.conf.template"  "$REPO/standby-edge/nginx-standby.conf"
render "$REPO/firewall/pf.anchors.cn-backend.template"   "$REPO/firewall/pf.anchors.cn-backend"

cat <<EOF

Done. Now copy the file(s) YOUR machine owns into place and restart:

  Mac 1 (Naman)    sudo cp mac1-dns/dnsmasq-phase2.conf /opt/homebrew/etc/dnsmasq.conf
                   sudo brew services restart dnsmasq

  Mac 2 (Harsha)   sudo cp mac2-edge/nginx-phase2.conf /opt/homebrew/etc/nginx/servers/cn-project.conf
                   sudo nginx -t && sudo nginx -s reload

  Mac 3 (Hemanth)  sudo cp backup-dns/dnsmasq-backup.conf /opt/homebrew/etc/dnsmasq.conf
                   sudo brew services restart dnsmasq
                   sudo cp firewall/pf.anchors.cn-backend /etc/pf.anchors/cn-backend

  Mac 4 (Akshay)   sudo cp standby-edge/nginx-standby.conf /opt/homebrew/etc/nginx/servers/cn-project.conf
                   sudo nginx -t          # do NOT start it yet -- Ext E starts it on demand
                   sudo cp firewall/pf.anchors.cn-backend /etc/pf.anchors/cn-backend

  Every client     sudo networksetup -setdnsservers Wi-Fi $MAC1_IP $MAC3_IP
EOF
