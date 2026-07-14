#!/usr/bin/env bash
# Step 4: PostgREST + /rest/v1 gateway (local Supabase-compatible API)
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
: "${POSTGREST_AUTHENTICATOR_PASSWORD:=postgrest-authenticator-dev-change-me}"
: "${POSTGREST_PORT:=3001}"

echo "==> Starting postgres..."
docker compose up -d postgres

echo "==> Waiting for postgres..."
for i in $(seq 1 60); do
  if docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ "$i" -eq 60 ]]; then
    echo "Postgres not ready"
    exit 1
  fi
done

echo "==> Ensuring PostgREST authenticator role..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD '${POSTGREST_AUTHENTICATOR_PASSWORD}';
  ELSE
    ALTER ROLE authenticator WITH LOGIN PASSWORD '${POSTGREST_AUTHENTICATOR_PASSWORD}';
  END IF;
END \$\$;
GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO authenticator;
GRANT USAGE ON SCHEMA public TO authenticator;
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
SQL

echo "==> Starting PostgREST + rest-gateway (+ backend if configured)..."
docker compose up -d postgrest rest-gateway backend

echo "==> Waiting for REST gateway..."
for i in $(seq 1 30); do
  if curl -sf --max-time 3 "http://127.0.0.1:${POSTGREST_PORT}/rest/v1/staff?select=email,name,app_id&limit=1" >/tmp/pt-rest.json 2>/dev/null; then
    echo "==> Sample staff row (local PostgREST):"
    cat /tmp/pt-rest.json
    echo
    echo "==> Ken user:"
    curl -sf --max-time 5 \
      "http://127.0.0.1:${POSTGREST_PORT}/rest/v1/staff?select=email,name,app_id&email=ilike.kenkylee@hku.hk" \
      || true
    echo
    echo "Step 4 complete. Local API base URL for Flutter (Step 5): http://127.0.0.1:${POSTGREST_PORT}"
    exit 0
  fi
  sleep 2
done

echo "REST gateway did not respond. Logs:"
docker compose logs --tail=30 postgrest rest-gateway
exit 1
