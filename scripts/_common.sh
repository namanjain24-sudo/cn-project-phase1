# Shared helpers. Sourced by the other scripts -- not meant to be run directly.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load config/ips.env. An already-set environment variable wins over the file,
# so a one-off override is possible without editing the shared config.
if [ -f "$REPO/config/ips.env" ]; then
  while IFS='=' read -r _k _v; do
    case "$_k" in ''|\#*) continue ;; esac
    _k="$(printf '%s' "$_k" | tr -d '[:space:]')"
    _v="${_v%%#*}"
    _v="$(printf '%s' "$_v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$_k" ] || continue
    if [ -z "${!_k:-}" ]; then export "$_k=$_v"; fi
  done < "$REPO/config/ips.env"
  unset _k _v
fi

DOMAIN="${DOMAIN:-cn_team.test}"
APP="app.$DOMAIN"
API="api.$DOMAIN"

# Normally just https://app.<domain>. BASE_URL exists so the scripts can be
# pointed at a test stack (e.g. the 8443 fallback port the spec allows).
BASE="${BASE_URL:-https://$APP}"
# CURL_EXTRA is empty in normal use.
# shellcheck disable=SC2086
ccurl() { curl ${CURL_EXTRA:-} "$@"; }

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }
hr()   { printf '%s\n' "------------------------------------------------------------"; }
