#!/usr/bin/env bash
# Step 5: Point Flutter at local PostgREST + Node backend.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy from .env.example"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${POSTGRES_USER:=project_tracker}"
: "${POSTGRES_DB:=project_tracker}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"
: "${POSTGREST_PORT:=3001}"
: "${PGRST_JWT_SECRET:=local-postgrest-jwt-secret-dev-change-me}"

mkdir -p secrets
python3 scripts/generate_local_postgrest_anon_jwt.py > secrets/local_postgrest_anon_jwt.txt
chmod 600 secrets/local_postgrest_anon_jwt.txt

echo "==> Starting stack with PostgREST JWT..."
docker compose up -d postgres postgrest rest-gateway backend

echo "==> Ensuring gateway picks up PostgREST after recreate..."
docker compose restart rest-gateway

echo "==> Waiting for REST gateway..."
sleep 3
ANON_JWT="$(tr -d '\r\n' < secrets/local_postgrest_anon_jwt.txt)"
for i in $(seq 1 30); do
  if curl -sf --max-time 3 \
    "http://127.0.0.1:${POSTGREST_PORT}/rest/v1/staff?select=email&limit=1" \
    -H "apikey: ${ANON_JWT}" \
    -H "Authorization: Bearer ${ANON_JWT}" \
    >/tmp/pt-step5-rest.json 2>/dev/null; then
    break
  fi
  sleep 2
  if [[ "$i" -eq 30 ]]; then
    echo "REST gateway did not accept JWT. Logs:"
    docker compose logs --tail=30 postgrest rest-gateway
    exit 1
  fi
done

TASK_COUNT="$(
  curl -sf --max-time 5 \
    "http://127.0.0.1:${POSTGREST_PORT}/rest/v1/task?select=count" \
    -H "Prefer: count=exact" \
    -H "apikey: ${ANON_JWT}" \
    -H "Authorization: Bearer ${ANON_JWT}" \
    -I 2>/dev/null | tr -d '\r' | grep -i '^content-range:' | sed 's/.*\///'
)"

echo "==> Local REST OK (tasks: ${TASK_COUNT:-?})"
echo "Step 5 complete. Build and deploy:"
echo "  ./scripts/deploy_web.sh"
