#!/usr/bin/env bash
# Full attachment audit: Firebase URLs, local URLs, missing files on disk, orphans.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UPLOADS="${ROOT}/data/uploads"
LEGACY="${HOME}/Desktop/project_tracker_files"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PSQL=(docker exec pt-test-postgres psql -U "${POSTGRES_USER:-project_tracker}" -d "${POSTGRES_DB:-project_tracker}" -v ON_ERROR_STOP=1 -t -A)

run_sql() {
  "${PSQL[@]}" -c "$1"
}

echo "==> Active attachment URL breakdown"
docker exec pt-test-postgres psql -U "${POSTGRES_USER:-project_tracker}" -d "${POSTGRES_DB:-project_tracker}" -c "
SELECT 'file_attachment' AS tbl,
  count(*) FILTER (WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%') AS firebase,
  count(*) FILTER (WHERE url ILIKE '%/api/files/%') AS local_api,
  count(*) FILTER (WHERE url NOT ILIKE '%firebasestorage%' AND url NOT ILIKE '%storage.googleapis%' AND url NOT ILIKE '%/api/files/%') AS other,
  count(*) AS total
FROM file_attachment WHERE status = 'Active'
UNION ALL
SELECT 'inline_attachment',
  count(*) FILTER (WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%'),
  count(*) FILTER (WHERE url ILIKE '%/api/files/%'),
  count(*) FILTER (WHERE url NOT ILIKE '%firebasestorage%' AND url NOT ILIKE '%storage.googleapis%' AND url NOT ILIKE '%/api/files/%'),
  count(*)
FROM inline_attachment WHERE status = 'Active';
"

echo ""
echo "==> Firebase URLs in ALL statuses (including Deleted)"
docker exec pt-test-postgres psql -U "${POSTGRES_USER:-project_tracker}" -d "${POSTGRES_DB:-project_tracker}" -c "
SELECT 'file_attachment' AS tbl, status,
  count(*) FILTER (WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%') AS firebase,
  count(*) AS total
FROM file_attachment GROUP BY status
UNION ALL
SELECT 'inline_attachment', status,
  count(*) FILTER (WHERE url ILIKE '%firebasestorage%' OR url ILIKE '%storage.googleapis%'),
  count(*)
FROM inline_attachment GROUP BY status
ORDER BY tbl, status;
"

echo ""
echo "==> url_attachment table (website links)"
docker exec pt-test-postgres psql -U "${POSTGRES_USER:-project_tracker}" -d "${POSTGRES_DB:-project_tracker}" -c "
SELECT count(*) FILTER (WHERE url ILIKE '%firebasestorage%') AS firebase,
       count(*) AS total FROM url_attachment WHERE status='Active';
" 2>/dev/null || echo "(url_attachment table check skipped)"

echo ""
echo "==> Local files on disk"
DISK_COUNT=$(find "$UPLOADS" -type f 2>/dev/null | wc -l | tr -d ' ')
DISK_BYTES=$(find "$UPLOADS" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
echo "data/uploads files: ${DISK_COUNT} (${DISK_BYTES} bytes)"

if [[ -d "$LEGACY" ]]; then
  LEGACY_NZ=$(find "$LEGACY" -type f -size +0 2>/dev/null | wc -l | tr -d ' ')
  LEGACY_ZERO=$(find "$LEGACY" -type f -size 0 2>/dev/null | wc -l | tr -d ' ')
  LEGACY_BYTES=$(find "$LEGACY" -type f -size +0 -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  echo "project_tracker_files: ${LEGACY_NZ} real files (${LEGACY_BYTES} bytes), ${LEGACY_ZERO} empty stubs"
else
  echo "project_tracker_files: (folder not found at $LEGACY)"
fi

echo ""
echo "==> Active rows: local URL but file MISSING on disk"
MISSING_TMP=$(mktemp)
: >"$MISSING_TMP"
while IFS='|' read -r tbl id url; do
  [[ -z "$url" ]] && continue
  rel="${url#*/api/files/}"
  rel="${rel%%\?*}"
  rel=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('${rel//\'/\\\'}'))" 2>/dev/null || echo "$rel")
  if [[ ! -f "${UPLOADS}/${rel}" ]]; then
    echo "${tbl}|${id}|${rel}" >>"$MISSING_TMP"
  fi
done < <(run_sql "
SELECT 'file' || '|' || id || '|' || url FROM file_attachment
WHERE status='Active' AND url LIKE '%/api/files/%'
UNION ALL
SELECT 'inline' || '|' || id || '|' || url FROM inline_attachment
WHERE status='Active' AND url LIKE '%/api/files/%';
")

MISSING_COUNT=$(wc -l <"$MISSING_TMP" | tr -d ' ')
if [[ "$MISSING_COUNT" -eq 0 ]]; then
  echo "None — every active /api/files/ URL has a file on disk."
else
  echo "MISSING: ${MISSING_COUNT} row(s)"
  head -15 "$MISSING_TMP" | while IFS='|' read -r tbl id rel; do
    echo "  [$tbl] $id -> $rel"
  done
  [[ "$MISSING_COUNT" -gt 15 ]] && echo "  ... and $((MISSING_COUNT - 15)) more"
fi
rm -f "$MISSING_TMP"

echo ""
echo "==> Orphan files on disk (not referenced by any Active attachment URL)"
ORPHAN_TMP=$(mktemp)
REFERENCED_TMP=$(mktemp)
run_sql "
SELECT url FROM file_attachment WHERE status='Active' AND url LIKE '%/api/files/%'
UNION ALL
SELECT url FROM inline_attachment WHERE status='Active' AND url LIKE '%/api/files/%';
" | while read -r url; do
  rel="${url#*/api/files/}"
  rel="${rel%%\?*}"
  rel=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$rel'))" 2>/dev/null || echo "$rel")
  echo "$rel"
done | sort -u >"$REFERENCED_TMP"

find "$UPLOADS" -type f 2>/dev/null | while read -r f; do
  rel="${f#${UPLOADS}/}"
  if ! grep -qxF "$rel" "$REFERENCED_TMP" 2>/dev/null; then
    echo "$rel" >>"$ORPHAN_TMP"
  fi
done
ORPHAN_COUNT=$(wc -l <"${ORPHAN_TMP:-/dev/null}" 2>/dev/null | tr -d ' ' || echo 0)
if [[ "${ORPHAN_COUNT:-0}" -eq 0 ]]; then
  echo "None — all disk files are referenced in DB."
else
  echo "Orphans: ${ORPHAN_COUNT} file(s) (extra copies or old uploads)"
  head -10 "$ORPHAN_TMP" 2>/dev/null | sed 's/^/  /'
fi
rm -f "$ORPHAN_TMP" "$REFERENCED_TMP"

echo ""
echo "==> Summary"
ACTIVE_DB=$(run_sql "SELECT count(*) FROM file_attachment WHERE status='Active' AND url LIKE '%/api/files/%';")
ACTIVE_DB=$((ACTIVE_DB + $(run_sql "SELECT count(*) FROM inline_attachment WHERE status='Active' AND url LIKE '%/api/files/%';")))
echo "Active local URLs in DB: ${ACTIVE_DB}"
echo "Files on disk: ${DISK_COUNT}"
echo "Firebase in Active rows: 0 (if audit table shows firebase=0)"
