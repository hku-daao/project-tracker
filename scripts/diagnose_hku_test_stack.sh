#!/usr/bin/env bash
# Diagnose HTTPS stack using PUBLIC_WEB_APP_URL from .env
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"

HOST="${DIAG_HOST:-}"
if [[ -z "$HOST" && -n "${PUBLIC_WEB_APP_URL:-}" ]]; then
  HOST="$(python3 -c "from urllib.parse import urlparse; print(urlparse('${PUBLIC_WEB_APP_URL}').hostname or '')")"
fi
if [[ -z "$HOST" ]]; then
  echo "Set PUBLIC_WEB_APP_URL in .env or DIAG_HOST=hostname" >&2
  exit 1
fi

echo "=== Project Tracker HKU test diagnostics ==="
echo "Project dir: $ROOT"
echo ""

echo "--- DNS ---"
getent hosts "$HOST" 2>/dev/null || true
echo ""

echo "--- Host listening ports 80 / 443 ---"
if command -v ss >/dev/null; then
  ss -tlnp | grep -E ':80 |:443 ' || echo "(nothing listening on 80/443 on this machine)"
elif command -v netstat >/dev/null; then
  netstat -tlnp 2>/dev/null | grep -E ':80 |:443 ' || echo "(nothing listening on 80/443)"
else
  echo "ss/netstat not available"
fi
echo ""

echo "--- Docker containers (project + POC) ---"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | grep -E 'NAMES|pt-|app-' || docker ps -a 2>/dev/null || echo "docker not running"
echo ""

echo "--- Preflight files ---"
for f in .env docker/nginx/ssl/nginx.crt docker/nginx/ssl/nginx.key build/web/index.html; do
  if [[ -e "$f" ]]; then echo "OK  $f"; else echo "MISS $f"; fi
done
echo ""

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx pt-frontend; then
  echo "--- pt-frontend logs (last 15 lines) ---"
  docker logs pt-frontend 2>&1 | tail -15
else
  echo "pt-frontend is NOT running."
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx pt-frontend; then
    echo "--- pt-frontend exit logs ---"
    docker logs pt-frontend 2>&1 | tail -30
  fi
fi
echo ""

echo "--- Local curl (this server) ---"
curl -sS -o /dev/null -w "http://127.0.0.1:80 → %{http_code}\n" --connect-timeout 3 http://127.0.0.1/ 2>/dev/null || echo "http://127.0.0.1:80 → failed"
curl -sk -o /dev/null -w "https://127.0.0.1:443 → %{http_code}\n" --connect-timeout 3 https://127.0.0.1/ 2>/dev/null || echo "https://127.0.0.1:443 → failed"
echo ""

echo "=== Likely fixes ==="
echo "1. On HKU VPN / campus WiFi (site is campus-restricted)."
echo "2. If MISS files above: run setup_hku_test_ssl.sh and build_web_for_hku_test.sh"
echo "3. Start stack: ./scripts/start_hku_test_stack.sh"
echo "4. If IT POC was stopped and this stack never started, temporarily restore POC:"
echo "   cd /var/www/my-fullstack-app && docker compose up -d"
