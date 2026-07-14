"""
Firebase Admin SDK — BACKEND / SERVER ONLY (Python).

The snippet you have in "Firebase Admin SDK.txt" belongs here or in another
trusted server process — NOT in the Flutter app. Never ship the service
account JSON in client code; anyone can extract it from a built app.

Typical uses on the server:
  - Verify ID tokens if you add your own API layer
  - Auth-related cleanup or migration jobs

File uploads are handled by the local backend (`/api/files/*`), not Firebase.

Setup:
  1. Save your real JSON outside the git repo (e.g. ~/.secrets/project-firebase.json).
  2. export GOOGLE_APPLICATION_CREDENTIALS=/path/to/file.json
  3. pip install firebase-admin
  4. Run your script that calls init_firebase_admin() once at startup.

See also: backend/server.js (Node) uses FIREBASE_SERVICE_ACCOUNT_JSON for Auth.
"""

from __future__ import annotations

import os

import firebase_admin
from firebase_admin import credentials


def init_firebase_admin() -> firebase_admin.App:
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not cred_path:
        raise RuntimeError("Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON path.")
    cred = credentials.Certificate(cred_path)
    return firebase_admin.initialize_app(cred)


if __name__ == "__main__":
    app = init_firebase_admin()
    print(f"Firebase Admin initialized: {app.project_id}")
