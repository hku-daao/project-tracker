#!/usr/bin/env bash
# Step 6: Migrate Firebase export into data/uploads and verify local file API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 scripts/step6_migrate_firebase_files.py

docker compose up -d --build backend

echo "==> Sample file check"
SAMPLE=$(docker exec pt-test-postgres psql -U project_tracker -d project_tracker -t -A -c \
  "SELECT storage_path FROM file_attachment WHERE status='Active' AND storage_path IS NOT NULL LIMIT 1;")
curl -sf -I "http://127.0.0.1:3000/api/files/${SAMPLE}" | head -3

echo "Step 6 complete. Storage: ${ROOT}/data/uploads"
