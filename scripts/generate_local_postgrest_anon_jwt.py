#!/usr/bin/env python3
"""Mint a long-lived PostgREST anon JWT for local Flutter (matches PGRST_JWT_SECRET)."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sys
import time
from pathlib import Path


def _load_secret() -> str:
    direct = os.environ.get("PGRST_JWT_SECRET", "").strip()
    if direct:
        return direct
    helper = Path(__file__).resolve().parent / "read_env_value.py"
    if helper.is_file():
        import subprocess

        try:
            out = subprocess.check_output(
                [sys.executable, str(helper), "PGRST_JWT_SECRET"],
                text=True,
            ).strip()
            if out:
                return out
        except subprocess.CalledProcessError:
            pass
    return ""


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def main() -> int:
    secret = _load_secret()
    if not secret:
        print("PGRST_JWT_SECRET is not set in environment or .env", file=sys.stderr)
        return 1

    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    payload = b64url(
        json.dumps(
            {
                "role": "anon",
                "iss": "project-tracker-local",
                "iat": now,
                "exp": now + 10 * 365 * 24 * 3600,
            },
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    sys.stdout.write(f"{header}.{payload}.{signature}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
