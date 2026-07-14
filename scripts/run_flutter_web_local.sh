#!/usr/bin/env bash
# Run Flutter web against local stack URLs from .env (no ports in Dart source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/flutter/bin:${PATH}"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"

ARGS=(
  --dart-define=API_BASE_URL="$LOCAL_API_BASE_URL"
  --dart-define=POSTGREST_URL="$LOCAL_POSTGREST_URL"
  --dart-define=DEPLOY_ENV="${DEPLOY_ENV:-testing}"
)

if [[ -n "${ADMIN_EMAIL:-}" ]]; then
  ARGS+=(--dart-define=ADMIN_EMAIL="$ADMIN_EMAIL")
fi

JWT_FILE="secrets/local_postgrest_anon_jwt.txt"
if [[ -f "$JWT_FILE" ]]; then
  ANON_KEY="$(tr -d '\r\n' < "$JWT_FILE")"
  if [[ -n "$ANON_KEY" ]]; then
    ARGS+=(--dart-define=POSTGREST_ANON_KEY="$ANON_KEY")
  fi
fi

echo "==> flutter run -d chrome (API=$LOCAL_API_BASE_URL REST=$LOCAL_POSTGREST_URL)"
exec flutter run -d chrome "${ARGS[@]}" "$@"
