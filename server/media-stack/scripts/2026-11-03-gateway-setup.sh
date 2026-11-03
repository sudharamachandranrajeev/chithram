#!/usr/bin/env bash
# Gateway prep (idempotent): state dir (700) and, on first run, a self-signed ECDSA P-256 TLS cert
# + key in $SECRETS_ROOT (600). The key is never printed. Prints the certificate SHA-256
# fingerprint (public information) which the app pins at pairing time.
set -euo pipefail

ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a

umask 077
S="$SECRETS_ROOT"
mkdir -p "$S" "$CONFIG_ROOT/gateway"
chmod 700 "$S" "$CONFIG_ROOT/gateway"

KEY="$S/gateway_tls_key"
CRT="$S/gateway_tls_cert"
if [ ! -s "$KEY" ] || [ ! -s "$CRT" ]; then
  TMP="$(mktemp -d "$S/.gateway.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMP/key" 2>/dev/null
  openssl req -new -x509 -key "$TMP/key" -sha256 -days 3650 -subj "/CN=chithram-gateway" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -out "$TMP/crt"
  chmod 600 "$TMP/key" "$TMP/crt"
  mv "$TMP/key" "$KEY"
  mv "$TMP/crt" "$CRT"
  echo "gateway TLS certificate generated (ECDSA P-256, 10 years)"
fi
chmod 600 "$KEY" "$CRT"
echo "gateway cert SHA-256: $(openssl x509 -in "$CRT" -noout -fingerprint -sha256 | cut -d= -f2)"
