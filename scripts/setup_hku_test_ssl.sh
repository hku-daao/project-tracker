#!/usr/bin/env bash
# Copy TLS certs into docker/nginx/ssl/ for HTTPS (nginx frontend container).
# Does not configure DNS or hostnames — that is separate (see docs in deploy runbook).
#
# Option 1: place nginx.crt + nginx.key directly in docker/nginx/ssl/
# Option 2: set POC_SSL_DIR to a folder that already has those files, then run this script
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="$ROOT/docker/nginx/ssl"
POC_SSL="${POC_SSL_DIR:-$DEST}"

if [[ -f "$DEST/nginx.crt" && -f "$DEST/nginx.key" ]]; then
  echo "TLS already present in $DEST"
  exit 0
fi

if [[ ! -f "$POC_SSL/nginx.crt" || ! -f "$POC_SSL/nginx.key" ]]; then
  echo "TLS certs not found." >&2
  echo "Place nginx.crt and nginx.key in: $DEST" >&2
  echo "Or set POC_SSL_DIR=/path/to/folder/with/certs and re-run." >&2
  exit 1
fi

if [[ "$POC_SSL" == "$DEST" ]]; then
  echo "Nothing to copy — certs should already be in $DEST" >&2
  exit 1
fi

mkdir -p "$DEST"

if [[ -r "$POC_SSL/nginx.key" ]]; then
  cp "$POC_SSL/nginx.crt" "$DEST/"
  cp "$POC_SSL/nginx.key" "$DEST/"
else
  echo "Need sudo to read POC TLS key ($POC_SSL/nginx.key)..."
  sudo cp "$POC_SSL/nginx.crt" "$POC_SSL/nginx.key" "$DEST/"
  sudo chown "$(id -u):$(id -g)" "$DEST/nginx.crt" "$DEST/nginx.key"
fi
chmod 644 "$DEST/nginx.crt"
chmod 600 "$DEST/nginx.key"
echo "SSL copied to $DEST"
