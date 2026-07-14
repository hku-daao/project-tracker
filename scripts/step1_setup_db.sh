#!/usr/bin/env bash
# Step 1: start Postgres in Docker, apply migrations, seed dev user kenkylee@hku.hk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy from .env.example and set POSTGRES_PASSWORD."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${POSTGRES_USER:=project_tracker}"
: "${POSTGRES_DB:=project_tracker}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"

run_sql_file() {
  local file="$1"
  echo "==> Applying $(basename "$file")"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <"$file"
}

echo "==> Starting Postgres container..."
docker compose up -d postgres

echo "==> Waiting for Postgres to be healthy..."
for i in $(seq 1 60); do
  if docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ "$i" -eq 60 ]]; then
    echo "Postgres did not become ready in time."
    exit 1
  fi
done

echo "==> Applying Postgres init (extensions + Supabase-compatible roles)..."
for f in docker/postgres/init/01-extensions.sql docker/postgres/init/02-supabase-roles.sql; do
  run_sql_file "$f"
done

echo "==> Applying numbered migrations..."
shopt -s nullglob
files=(supabase/migrations/*.sql)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No migration files in supabase/migrations/"
  exit 1
fi
for f in "${files[@]}"; do
  run_sql_file "$f"
done

echo "==> Applying post-migration grants..."
run_sql_file docker/postgres/init/03-post-migrate-grants.sql

echo "==> Seeding dev user kenkylee@hku.hk..."
run_sql_file supabase/seed_dev_kenkylee.sql

echo "==> Verification"
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT email, name, app_id FROM staff WHERE email ILIKE 'kenkylee@hku.hk';"

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT COUNT(*) AS migration_tables FROM information_schema.tables WHERE table_schema = 'public';"

echo "Step 1 complete."
