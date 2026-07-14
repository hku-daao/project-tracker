#!/usr/bin/env bash
# Step 6: Migrate Firebase export into data/uploads and verify local file API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"

python3 scripts/step6_migrate_firebase_files.py

docker compose up -d --build backend

echo "==> Sample file check"
SAMPLE=$(docker exec "$POSTGRES_CONTAINER" psql -U "${POSTGRES_USER:-project_tracker}" -d "${POSTGRES_DB:-project_tracker}" -t -A -c \
  "SELECT storage_path FROM file_attachment WHERE status='Active' AND storage_path IS NOT NULL LIMIT 1;")
curl -sf -I "${LOCAL_API_BASE_URL%/}/api/files/${SAMPLE}" | head -3

echo "Step 6 complete. Storage: ${ROOT}/data/uploads"
