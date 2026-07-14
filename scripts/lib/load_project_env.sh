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
