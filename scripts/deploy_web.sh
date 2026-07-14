#!/usr/bin/env bash
# Build web + restart stack for https://projecttrackertest.hku.hk (or PUBLIC_WEB_APP_URL in .env)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env first." >&2
  exit 1
fi

load_project_env "$ROOT"
require_public_web_app_url
require_sso_client_secret
set_env_kv .env SSO_REDIRECT_URI "$PUBLIC_WEB_APP_URL"
set_env_kv .env SSO_POST_LOGOUT_REDIRECT_URI "$PUBLIC_WEB_APP_URL"

echo "==> Deploy settings:"
grep -E '^PUBLIC_WEB_APP_URL=|^SSO_ISSUER_URL=|^SSO_CLIENT_ID=' .env

echo ""
./scripts/test_hku_sso_discovery.sh | tail -12

echo ""
./scripts/sync_postgrest_jwt.sh

echo ""
./scripts/build_web_for_hku_test.sh

docker compose --profile production up -d --build --force-recreate postgrest rest-gateway backend frontend

echo ""
echo "Done. Open: ${PUBLIC_WEB_APP_URL}"
