#!/usr/bin/env python3
"""Verify anon JWT against local PostgREST gateway (no secret output)."""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    jwt_path = ROOT / "secrets" / "local_postgrest_anon_jwt.txt"
    if not jwt_path.is_file():
        print("Missing secrets/local_postgrest_anon_jwt.txt", file=sys.stderr)
        return 1

    token = jwt_path.read_text(encoding="utf-8").strip()
    parts = token.split(".")
    if len(parts) != 3:
        print("JWT file is not a valid JWT shape", file=sys.stderr)
        return 1

    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    import base64

    try:
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except Exception as e:
        print(f"JWT payload decode failed: {e}", file=sys.stderr)
        return 1

    print(f"JWT role claim: {claims.get('role')}")

    env = subprocess.check_output(
        ["docker", "inspect", "pt-test-postgrest", "--format", "{{json .Config.Env}}"],
        text=True,
    )
    env_list = json.loads(env)
    secret_entry = next((e for e in env_list if e.startswith("PGRST_JWT_SECRET=")), "")
    secret_len = len(secret_entry.split("=", 1)[1]) if secret_entry else 0
    print(f"PostgREST PGRST_JWT_SECRET length: {secret_len}")

    port = "3001"
    env_file = ROOT / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            if line.startswith("POSTGREST_PORT="):
                port = line.split("=", 1)[1].strip().strip('"').strip("'")
                break

    url = f"http://127.0.0.1:{port}/rest/v1/staff?select=email&limit=1"
    req = urllib.request.Request(
        url,
        headers={"apikey": token, "Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = resp.read(200).decode("utf-8", errors="replace")
            print(f"REST OK ({resp.status}): {body}")
            return 0
    except urllib.error.HTTPError as e:
        body = e.read(200).decode("utf-8", errors="replace")
        print(f"REST FAIL ({e.code}): {body}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
