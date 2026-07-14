#!/usr/bin/env bash
# Start Project Tracker with HTTPS (ports 80/443) from this repo folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"
require_public_web_app_url

if [[ -z "${SSO_CLIENT_SECRET:-}" ]]; then
  echo "Missing SSO_CLIENT_SECRET in .env" >&2
  exit 1
fi

if [[ "${SSO_ISSUER_URL:-}" == "" ]]; then
  echo "WARNING: SSO_ISSUER_URL is empty — set it in .env (from HKU IT)." >&2
fi

if [[ ! -f docker/nginx/ssl/nginx.crt || ! -f docker/nginx/ssl/nginx.key ]]; then
  echo "Missing TLS files in docker/nginx/ssl/ — run ./scripts/setup_hku_test_ssl.sh" >&2
  exit 1
fi

if [[ ! -d build/web ]] || [[ ! -f build/web/index.html ]]; then
  echo "Missing Flutter build — run ./scripts/build_web_for_hku_test.sh first." >&2
  exit 1
fi

if [[ -n "${POC_COMPOSE_DIR:-}" && -f "${POC_COMPOSE_DIR}/docker-compose.yml" ]]; then
  echo "==> Stopping other stack at ${POC_COMPOSE_DIR} (free ports 80/443)..."
  (cd "${POC_COMPOSE_DIR}" && docker compose down) || true
fi

echo "==> Starting Project Tracker (production profile)..."
docker compose --profile production up -d --build

sleep 2

if ! docker ps --format '{{.Names}}' | grep -qx pt-frontend; then
  echo "" >&2
  echo "ERROR: pt-frontend did not stay running (ports 80/443 will refuse connections)." >&2
  echo "Run: ./scripts/diagnose_hku_test_stack.sh" >&2
  echo "Logs:" >&2
  docker logs pt-frontend 2>&1 | tail -40 >&2 || true
  exit 1
fi

if command -v ss >/dev/null; then
  if ! ss -tln | grep -q ':443 '; then
    echo "WARNING: port 443 not listening on host — check docker logs pt-frontend" >&2
  fi
fi

echo ""
echo "Stack up. Open: ${PUBLIC_WEB_APP_URL}"
echo "Containers:"
docker compose --profile production ps
