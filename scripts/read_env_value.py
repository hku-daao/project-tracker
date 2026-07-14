#!/usr/bin/env python3
"""Read a single KEY from repo .env without bash `#`-comment truncation."""
from __future__ import annotations

import sys
from pathlib import Path


def read_env_value(key: str, env_path: Path | None = None) -> str:
    path = env_path or Path(__file__).resolve().parent.parent / ".env"
    if not path.is_file():
        return ""
    want = key.strip()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if not line.startswith(f"{want}="):
            continue
        val = line.split("=", 1)[1].strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            return val[1:-1]
        # Match docker compose .env: unquoted # starts an inline comment.
        hash_at = val.find("#")
        if hash_at >= 0:
            return val[:hash_at].rstrip()
        return val
    return ""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: read_env_value.py KEY", file=sys.stderr)
        return 2
    val = read_env_value(sys.argv[1])
    if not val:
        return 1
    sys.stdout.write(val)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
