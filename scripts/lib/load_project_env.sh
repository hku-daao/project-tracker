#!/usr/bin/env bash
# Load .env and derive deploy URL fields. Source from repo root:
#   source scripts/lib/load_project_env.sh
#   load_project_env

load_project_env() {
  local root="${1:-.}"
  if [[ -f "$root/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$root/.env"
    set +a
  fi

  if [[ -n "${PUBLIC_WEB_APP_URL:-}" ]]; then
    PUBLIC_WEB_APP_URL="${PUBLIC_WEB_APP_URL%/}"
    export PUBLIC_WEB_APP_URL
    export PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-$PUBLIC_WEB_APP_URL}"
    export PROJECT_TRACKER_LANDING_URL="${PROJECT_TRACKER_LANDING_URL:-$PUBLIC_WEB_APP_URL}"
    export PUBLIC_API_BASE_URL="${PUBLIC_API_BASE_URL:-$PUBLIC_WEB_APP_URL}"
    if [[ -z "${CORS_ORIGINS:-}" ]]; then
      export CORS_ORIGINS="$PUBLIC_WEB_APP_URL"
    fi
    export SSO_REDIRECT_URI="${SSO_REDIRECT_URI:-$PUBLIC_WEB_APP_URL}"
    export SSO_POST_LOGOUT_REDIRECT_URI="${SSO_POST_LOGOUT_REDIRECT_URI:-$PUBLIC_WEB_APP_URL}"
  fi

  export DEPLOY_ENV="${DEPLOY_ENV:-testing}"
  export ADMIN_EMAIL="${ADMIN_EMAIL:-}"

  # Host bind ports / container names (set in .env — no hardcoding in app code)
  export HOST_POSTGRES_PORT="${HOST_POSTGRES_PORT:-5432}"
  export HOST_BACKEND_PORT="${HOST_BACKEND_PORT:-3000}"
  export HOST_POSTGREST_PORT="${HOST_POSTGREST_PORT:-${POSTGREST_PORT:-3001}}"
  export POSTGREST_PORT="${POSTGREST_PORT:-$HOST_POSTGREST_PORT}"

  export STACK_NAME="${STACK_NAME:-pt-test}"
  export POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-${STACK_NAME}-postgres}"
  export BACKEND_CONTAINER="${BACKEND_CONTAINER:-${STACK_NAME}-backend}"
  export POSTGREST_CONTAINER="${POSTGREST_CONTAINER:-${STACK_NAME}-postgrest}"
  export REST_GATEWAY_CONTAINER="${REST_GATEWAY_CONTAINER:-${STACK_NAME}-rest-gateway}"
  export NGINX_CONTAINER="${NGINX_CONTAINER:-${STACK_NAME}-nginx}"
  export FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-pt-frontend}"

  export LOCAL_API_BASE_URL="${LOCAL_API_BASE_URL:-http://127.0.0.1:${HOST_BACKEND_PORT}}"
  export LOCAL_POSTGREST_URL="${LOCAL_POSTGREST_URL:-http://127.0.0.1:${HOST_POSTGREST_PORT}}"
  export LOCAL_FILES_API_BASE="${LOCAL_FILES_API_BASE:-${LOCAL_API_BASE_URL}/api/files}"
}

require_public_web_app_url() {
  if [[ -z "${PUBLIC_WEB_APP_URL:-}" ]]; then
    echo "Missing PUBLIC_WEB_APP_URL in .env" >&2
    echo "Set PUBLIC_WEB_APP_URL in .env (see .env.example)" >&2
    exit 1
  fi
}

require_sso_client_secret() {
  if [[ -z "${SSO_CLIENT_SECRET:-}" ]]; then
    echo "Missing SSO_CLIENT_SECRET in .env" >&2
    echo "Set SSO_CLIENT_SECRET in .env (from HKU ITS)." >&2
    exit 1
  fi
}

set_env_kv() {
  local env_file="$1"
  local key="$2"
  local val="$3"
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$env_file"
  else
    echo "${key}=${val}" >> "$env_file"
  fi
}
