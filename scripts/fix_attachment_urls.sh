#!/usr/bin/env bash
# Rewrite stored /api/files/ URLs to the HKU test public origin (Postgres).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-https://projecttrackertest.hku.hk}"
ORIGIN="${PUBLIC_ORIGIN%/}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

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
docker exec -i pt-test-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<< "$SQL"

echo "==> Sample inline_attachment URLs:"
docker exec pt-test-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT left(url, 100) AS url FROM inline_attachment WHERE status = 'Active' LIMIT 5;"
