#!/usr/bin/env bash
# Rebuild Flutter web + restart HTTPS stack on projecttrackertest.hku.hk.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building Flutter web..."
./scripts/build_web_for_hku.sh

echo "==> Restarting containers..."
docker compose --profile production up -d --build --force-recreate frontend backend

sleep 2
docker compose --profile production ps

echo ""
echo "Done. Hard-refresh browser: Ctrl+Shift+R"
echo "URL: https://projecttrackertest.hku.hk"
echo "Expected: HKU login screen (not endless Loading spinner)"
