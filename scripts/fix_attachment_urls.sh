#!/usr/bin/env bash
# Rewrite stored /api/files/ URLs to the public origin (Postgres).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"
require_public_web_app_url

ORIGIN="${PUBLIC_ORIGIN%/}"
: "${POSTGRES_USER:=project_tracker}"
: "${POSTGRES_DB:=project_tracker}"

SQL=$(cat <<EOF
UPDATE inline_attachment
SET url = regexp_replace(url, '^https?://[^/]+', '${ORIGIN}')
WHERE url LIKE '%/api/files/%'
  AND url NOT LIKE '${ORIGIN}/%';

UPDATE file_attachment
SET url = regexp_replace(url, '^https?://[^/]+', '${ORIGIN}')
WHERE url LIKE '%/api/files/%'
  AND url NOT LIKE '${ORIGIN}/%';
EOF
)

echo "==> Rewriting attachment URLs to ${ORIGIN}"
docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<< "$SQL"

echo "==> Sample inline_attachment URLs:"
docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT left(url, 100) AS url FROM inline_attachment WHERE status = 'Active' LIMIT 5;"
