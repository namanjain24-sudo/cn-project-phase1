#!/bin/bash
# Task E — generate a TLS certificate for the edge (Mac 2).
#
# Prefers mkcert (simplest — it creates a local CA and automatically trusts it on THIS
# machine). Falls back to a plain OpenSSL self-signed cert if mkcert isn't available.
#
# Usage: ./generate-cert.sh app.team1.test api.team1.test

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <domain1> [domain2] ..."
  echo "Example: $0 app.team1.test api.team1.test"
  exit 1
fi

DOMAINS=("$@")
OUT_DIR="$(dirname "$0")/certs"
mkdir -p "$OUT_DIR"

if command -v mkcert >/dev/null 2>&1; then
  echo "==> Using mkcert (recommended)"
  mkcert -install   # installs the local CA into THIS machine's system trust store
  (
    cd "$OUT_DIR"
    mkcert "${DOMAINS[@]}"
    # mkcert names files after the first domain; normalize to fixed names nginx expects
    first="${DOMAINS[0]}"
    mv "${first}"*-key.pem privkey.pem 2>/dev/null || mv "${first}+"*"-key.pem" privkey.pem
    mv "${first}"*.pem fullchain.pem 2>/dev/null || true
    # (if the above globs don't line up exactly, just check `ls certs/` and rename manually
    # to privkey.pem / fullchain.pem — nginx.conf expects those two filenames)
  )
  echo ""
  echo "==> Local CA root, for copying to OTHER client machines' trust stores:"
  mkcert -CAROOT
  echo "Copy the rootCA.pem from that folder to every other Mac and trust it there too"
  echo "(see mac2-edge/README.md step 4)."
else
  echo "==> mkcert not found, falling back to plain OpenSSL self-signed certificate"
  echo "    (brew install mkcert is recommended instead — it avoids manual trust-store steps)"

  SAN_ENTRIES=""
  for d in "${DOMAINS[@]}"; do
    SAN_ENTRIES="${SAN_ENTRIES}DNS:${d},"
  done
  SAN_ENTRIES="${SAN_ENTRIES%,}"

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$OUT_DIR/privkey.pem" \
    -out "$OUT_DIR/fullchain.pem" \
    -days 365 \
    -subj "/CN=${DOMAINS[0]}" \
    -addext "subjectAltName=${SAN_ENTRIES}"

  echo ""
  echo "==> Self-signed cert created at $OUT_DIR/fullchain.pem"
  echo "You must manually trust $OUT_DIR/fullchain.pem on EVERY client machine, e.g.:"
  echo "  sudo security add-trusted-cert -d -r trustRoot \\"
  echo "    -k /Library/Keychains/System.keychain $OUT_DIR/fullchain.pem"
fi

echo ""
echo "==> Done. Point nginx.conf's ssl_certificate / ssl_certificate_key at:"
echo "    $OUT_DIR/fullchain.pem"
echo "    $OUT_DIR/privkey.pem"
