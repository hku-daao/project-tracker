#!/usr/bin/env python3
"""Step 6: Copy test-environment files from Firebase export into local data/uploads."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT.parent / "project_tracker_files"
UPLOAD_ROOT = ROOT / "data" / "uploads"
API_BASE = os.environ.get("LOCAL_FILES_API_BASE", "http://127.0.0.1:3000/api/files")


def psql_csv(sql: str) -> list[list[str]]:
    cmd = [
        "docker",
        "exec",
        "pt-test-postgres",
        "psql",
        "-U",
        "project_tracker",
        "-d",
        "project_tracker",
        "-t",
        "-A",
        "-F",
        "\t",
        "-c",
        sql,
    ]
    out = subprocess.check_output(cmd, text=True)
    rows: list[list[str]] = []
    for line in out.splitlines():
        if not line.strip():
            continue
        rows.append(line.split("\t"))
    return rows


def firebase_object_path(raw_url: str, storage_path: str | None) -> str | None:
    if storage_path and storage_path.strip():
        try:
            return urllib.parse.unquote(storage_path.strip())
        except Exception:
            pass
    url = (raw_url or "").strip()
    if not url:
        return None
    marker = "/o/"
    idx = url.find(marker)
    if idx < 0:
        return None
    encoded = url[idx + len(marker) :].split("?", 1)[0]
    try:
        return urllib.parse.unquote(encoded)
    except Exception:
        return None


def source_file_for_object_path(object_path: str) -> Path | None:
    rel = object_path.replace("\\", "/").lstrip("/")
    if rel.startswith("project_tracker/"):
        rel = rel[len("project_tracker/") :]
    candidate = SOURCE_ROOT / rel
    if candidate.is_file():
        return candidate
    # Fallback: match by filename within users tree
    name = Path(rel).name
    if not name:
        return None
    matches = list(SOURCE_ROOT.rglob(name))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        for m in matches:
            if rel.endswith(str(m.relative_to(SOURCE_ROOT)).replace("\\", "/")):
                return m
    return None


def safe_ext(filename: str | None, object_path: str) -> str:
    for candidate in (filename, Path(object_path).name):
        if not candidate:
            continue
        suffix = Path(candidate).suffix.lower()
        if suffix and len(suffix) <= 12 and re.match(r"^\.[a-z0-9]+$", suffix):
            return suffix
    return ""


def local_relative_path(entity_type: str, entity_id: str, attachment_id: str, ext: str) -> str:
    return f"{entity_type}/{entity_id}/{attachment_id}{ext}"


def local_public_url(relative_path: str) -> str:
    return f"{API_BASE.rstrip('/')}/{relative_path.replace(os.sep, '/')}"


def copy_attachment_rows(
    table: str,
    *,
    has_storage_path: bool = True,
    has_filename: bool = True,
) -> tuple[int, int, int]:
    copied = missing = skipped = 0
    cols = ["id", "entity_type", "entity_id"]
    if has_filename:
        cols.append("filename")
    if has_storage_path:
        cols.append("storage_path")
    cols.append("url")
    rows = psql_csv(
        f"SELECT {', '.join(cols)} FROM {table} WHERE status = 'Active';"
    )
    for row in rows:
        if len(row) < len(cols):
            continue
        idx = 0
        att_id = row[idx]
        idx += 1
        entity_type = row[idx]
        idx += 1
        entity_id = row[idx]
        idx += 1
        filename = ""
        if has_filename:
            filename = row[idx]
            idx += 1
        storage_path = None
        if has_storage_path:
            storage_path = row[idx]
            idx += 1
        url = row[idx]
        if url.startswith("http://127.0.0.1") or "/api/files/" in url:
            skipped += 1
            continue
        object_path = firebase_object_path(url, storage_path)
        if not object_path:
            missing += 1
            print(f"MISSING {table} {att_id}: no object path")
            continue
        src = source_file_for_object_path(object_path)
        if src is None:
            missing += 1
            print(f"MISSING {table} {att_id}: {object_path}")
            continue
        ext = safe_ext(filename, object_path)
        rel = local_relative_path(entity_type, entity_id, att_id, ext)
        dest = UPLOAD_ROOT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists() or dest.stat().st_size != src.stat().st_size:
            shutil.copy2(src, dest)
        new_url = local_public_url(rel)
        escaped_url = new_url.replace("'", "''")
        escaped_path = rel.replace("'", "''")
        if has_storage_path:
            update_sql = (
                f"UPDATE {table} SET url = '{escaped_url}', "
                f"storage_path = '{escaped_path}' WHERE id = '{att_id}';"
            )
        else:
            update_sql = f"UPDATE {table} SET url = '{escaped_url}' WHERE id = '{att_id}';"
        subprocess.check_call(
            [
                "docker",
                "exec",
                "pt-test-postgres",
                "psql",
                "-U",
                "project_tracker",
                "-d",
                "project_tracker",
                "-c",
                update_sql,
            ]
        )
        copied += 1
    return copied, missing, skipped


def main() -> int:
    if not SOURCE_ROOT.is_dir():
        print(f"Source folder not found: {SOURCE_ROOT}", file=sys.stderr)
        return 1
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)

    file_copied, file_missing, file_skipped = copy_attachment_rows("file_attachment")
    inline_copied, inline_missing, inline_skipped = copy_attachment_rows(
        "inline_attachment",
        has_storage_path=False,
        has_filename=False,
    )

    print("==> file_attachment")
    print(f"    copied={file_copied} missing={file_missing} already_local={file_skipped}")
    print("==> inline_attachment")
    print(f"    copied={inline_copied} missing={inline_missing} already_local={inline_skipped}")
    print(f"==> storage root: {UPLOAD_ROOT}")
    total_files = sum(1 for _ in UPLOAD_ROOT.rglob("*") if _.is_file())
    print(f"==> files on disk: {total_files}")
    return 0 if (file_missing + inline_missing) == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
