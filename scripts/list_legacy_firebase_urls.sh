#!/usr/bin/env bash
# List any attachment rows (any status) that still mention Firebase Storage.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

docker exec pt-test-postgres psql -U project_tracker -d project_tracker -c "
SELECT 'file_attachment' AS tbl, id, status, left(url, 140) AS url
FROM file_attachment
WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%'
UNION ALL
SELECT 'inline_attachment', id, status, left(url, 140)
FROM inline_attachment
WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%'
ORDER BY tbl, status
LIMIT 50;
"
