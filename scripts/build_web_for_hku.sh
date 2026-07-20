#!/usr/bin/env bash
# Build Flutter web (HKU SSO) using PUBLIC_WEB_APP_URL from .env
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/flutter/bin:${PATH}"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/load_project_env.sh"
load_project_env "$ROOT"
require_public_web_app_url

JWT_FILE="secrets/local_postgrest_anon_jwt.txt"
mkdir -p secrets

ARGS=(
  --dart-define=POSTGREST_URL="$PUBLIC_ORIGIN"
  --dart-define=API_BASE_URL="$PUBLIC_ORIGIN"
  --dart-define=DEPLOY_ENV="${DEPLOY_ENV:-testing}"
)

PGRST_JWT_SECRET="$(python3 scripts/read_env_value.py PGRST_JWT_SECRET 2>/dev/null || true)"
if [[ -n "$PGRST_JWT_SECRET" ]]; then
  export PGRST_JWT_SECRET
  python3 scripts/generate_local_postgrest_anon_jwt.py > "$JWT_FILE"
  chmod 600 "$JWT_FILE"
  ANON_KEY="$(tr -d '\r\n' < "$JWT_FILE")"
  if python3 scripts/verify_postgrest_jwt.py >/dev/null 2>&1; then
    echo "==> PostgREST JWT auth enabled"
    ARGS+=(--dart-define=POSTGREST_ANON_KEY="$ANON_KEY")
  else
    echo "WARNING: PGRST_JWT_SECRET is set but JWT verify failed." >&2
    echo "         Rebuild without anon JWT (comment out PGRST_JWT_SECRET in .env)." >&2
  fi
else
  echo "==> PostgREST JWT auth disabled — REST without Authorization header"
  flutter clean
fi

if [[ -f scripts/local_llm.env ]]; then
  # shellcheck disable=SC1091
  source scripts/local_llm.env
fi
if [[ -z "${LOCAL_LLM_API_KEY:-}" && -f secrets/internal_llm_api_key.txt ]]; then
  LOCAL_LLM_API_KEY="$(tr -d '\r\n' < secrets/internal_llm_api_key.txt)"
fi

ARGS=(
  --dart-define=POSTGREST_URL="$PUBLIC_ORIGIN"
  --dart-define=API_BASE_URL="$PUBLIC_ORIGIN"
  --dart-define=DEPLOY_ENV="${DEPLOY_ENV:-testing}"
)

if [[ -n "${ADMIN_EMAIL:-}" ]]; then
  ARGS+=(--dart-define=ADMIN_EMAIL="$ADMIN_EMAIL")
fi

if [[ -n "${LOCAL_LLM_BASE_URL:-}" ]]; then
  ARGS+=(--dart-define=LOCAL_LLM_BASE_URL="$LOCAL_LLM_BASE_URL")
fi
if [[ -n "${LOCAL_LLM_API_KEY:-}" ]]; then
  ARGS+=(--dart-define=LOCAL_LLM_API_KEY="$LOCAL_LLM_API_KEY")
fi
if [[ -n "${LOCAL_LLM_MODEL:-}" ]]; then
  ARGS+=(--dart-define=LOCAL_LLM_MODEL="$LOCAL_LLM_MODEL")
fi
if [[ -n "${LOCAL_LLM_AUTH:-}" ]]; then
  ARGS+=(--dart-define=LOCAL_LLM_AUTH="$LOCAL_LLM_AUTH")
fi

echo "==> flutter build web for $PUBLIC_ORIGIN (DEPLOY_ENV=${DEPLOY_ENV:-testing})"
python3 scripts/embed_logo_base64.py
flutter build web --release "${ARGS[@]}"

if [[ -f assets/images/logo.png ]]; then
  mkdir -p build/web/images
  cp assets/images/logo.png build/web/images/logo.png
  cp assets/images/logo.png build/web/favicon.png
fi

echo "==> Output: build/web/"
