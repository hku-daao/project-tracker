#!/usr/bin/env bash
# Recreate PostgREST; optionally verify anon JWT when PGRST_JWT_SECRET is set in .env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env" >&2
  exit 1
fi

PGRST_JWT_SECRET="$(python3 scripts/read_env_value.py PGRST_JWT_SECRET 2>/dev/null || true)"
export PGRST_JWT_SECRET

set -a
# shellcheck disable=SC1091
source .env
set +a
: "${POSTGRES_USER:=project_tracker}"
: "${POSTGRES_DB:=project_tracker}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"
: "${POSTGREST_AUTHENTICATOR_PASSWORD:=postgrest-authenticator-dev-change-me}"

echo "==> Ensuring postgres is up..."
docker compose up -d postgres
for i in $(seq 1 60); do
  if docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ "$i" -eq 60 ]]; then
    echo "Postgres not ready" >&2
    exit 1
  fi
done

echo "==> Syncing PostgREST authenticator role password..."
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

echo "==> Recreating PostgREST + gateway (no JWT secret in compose)..."
docker compose up -d --force-recreate postgrest rest-gateway

sleep 2

echo "==> Open REST check (no Authorization header)..."
curl -sf --max-time 5 "http://127.0.0.1:${POSTGREST_PORT:-3001}/rest/v1/staff?select=email&limit=1" | head -c 120
echo ""

if [[ -n "$PGRST_JWT_SECRET" ]]; then
  mkdir -p secrets
  export PGRST_JWT_SECRET
  python3 scripts/generate_local_postgrest_anon_jwt.py > secrets/local_postgrest_anon_jwt.txt
  chmod 600 secrets/local_postgrest_anon_jwt.txt
  if python3 scripts/verify_postgrest_jwt.py; then
    echo "NOTE: JWT verifies but compose no longer passes PGRST_JWT_SECRET — ignored." >&2
  fi
fi
