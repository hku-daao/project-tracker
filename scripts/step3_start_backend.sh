#!/usr/bin/env bash
# Step 3: start Postgres + backend containers and verify /health
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Starting postgres + backend..."
docker compose up -d postgres backend --build

echo "==> Waiting for backend health..."
for i in $(seq 1 30); do
  if curl -sf --max-time 5 http://127.0.0.1:3000/health >/tmp/pt-health.json 2>/dev/null; then
    echo "==> Health response (host):"
    cat /tmp/pt-health.json
    echo
    exit 0
  fi
  if docker compose exec -T backend node -e "require('http').get('http://127.0.0.1:3000/health',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>process.stdout.write(d))})" 2>/dev/null | grep -q '"ok":true'; then
    echo "==> Health response (via docker exec):"
    docker compose exec -T backend node -e "require('http').get('http://127.0.0.1:3000/health',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>console.log(d))})"
    echo
    exit 0
  fi
  sleep 2
done

echo "Backend did not become healthy in time. Logs:"
docker compose logs --tail=40 backend
exit 1
