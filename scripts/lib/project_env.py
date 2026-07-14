"""Load repo .env keys for Python ops scripts (no secrets printed)."""
from __future__ import annotations

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent.parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from read_env_value import read_env_value  # noqa: E402

ROOT = _SCRIPTS.parent


def env(key: str, default: str = "") -> str:
    val = read_env_value(key, ROOT / ".env")
    return val if val else default


def stack_settings() -> dict[str, str]:
    stack = env("STACK_NAME", "pt-test")
    host_backend = env("HOST_BACKEND_PORT", "3000")
    host_postgrest = env("HOST_POSTGREST_PORT") or env("POSTGREST_PORT", "3001")
    local_api = env("LOCAL_API_BASE_URL", f"http://127.0.0.1:{host_backend}")
    return {
        "STACK_NAME": stack,
        "POSTGRES_CONTAINER": env("POSTGRES_CONTAINER", f"{stack}-postgres"),
        "POSTGREST_CONTAINER": env("POSTGREST_CONTAINER", f"{stack}-postgrest"),
        "BACKEND_CONTAINER": env("BACKEND_CONTAINER", f"{stack}-backend"),
        "HOST_POSTGRES_PORT": env("HOST_POSTGRES_PORT", "5432"),
        "HOST_BACKEND_PORT": host_backend,
        "HOST_POSTGREST_PORT": host_postgrest,
        "POSTGREST_PORT": host_postgrest,
        "POSTGRES_USER": env("POSTGRES_USER", "project_tracker"),
        "POSTGRES_DB": env("POSTGRES_DB", "project_tracker"),
        "LOCAL_API_BASE_URL": local_api,
        "LOCAL_POSTGREST_URL": env(
            "LOCAL_POSTGREST_URL", f"http://127.0.0.1:{host_postgrest}"
        ),
        "LOCAL_FILES_API_BASE": env(
            "LOCAL_FILES_API_BASE", f"{local_api.rstrip('/')}/api/files"
        ),
    }
