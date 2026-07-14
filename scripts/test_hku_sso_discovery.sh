#!/usr/bin/env bash
# Verify HKU OIDC discovery using SSO_ISSUER_URL from .env
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"

ISSUER="${SSO_ISSUER_URL:-}"
if [[ -z "$ISSUER" ]]; then
  echo "Set SSO_ISSUER_URL in .env (see .env.example)" >&2
  exit 1
fi
ISSUER="${ISSUER%/}"
DISCOVERY="${ISSUER}/.well-known/openid-configuration"

echo "==> HKU OIDC discovery: $DISCOVERY"
curl -sf --max-time 15 "$DISCOVERY" | python3 -m json.tool | head -40

echo ""
echo "==> Backend SSO status (if stack running)"
HEALTH_URLS=()
if [[ -n "${PUBLIC_WEB_APP_URL:-}" ]]; then
  HEALTH_URLS+=("${PUBLIC_WEB_APP_URL}/health")
fi
HEALTH_URLS+=(
  "http://127.0.0.1:${POSTGREST_PORT:-3001}/health"
  "http://127.0.0.1:3000/health"
)

found=0
for url in "${HEALTH_URLS[@]}"; do
  body="$(curl -sk --max-time 8 "$url" 2>/dev/null || true)"
  if [[ -z "$body" ]]; then
    echo "  $url → (no response)"
    continue
  fi
  if ! echo "$body" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "  $url → not JSON: ${body:0:80}"
    continue
  fi
  found=1
  echo "  $url →"
  echo "$body" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('    ssoConfigured:', d.get('ssoConfigured'))
print('    ssoIssuer:', d.get('ssoIssuer'))
print('    offlineDev:', d.get('offlineDev'))
"
  break
done

if [[ "$found" -eq 0 ]]; then
  echo ""
  echo "Backend not reachable. Start stack:"
  echo "  docker compose --profile production up -d"
fi
