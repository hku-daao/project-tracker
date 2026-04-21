"""
Firebase Admin SDK — BACKEND / SERVER ONLY (Python).

The snippet you have in "Firebase Admin SDK.txt" belongs here or in another
trusted server process — NOT in the Flutter app. Never ship the service
account JSON in client code; anyone can extract it from a built app.

Typical uses on the server:
  - Generate signed download URLs for private Storage objects
  - Cleanup / migration jobs touching Storage or Auth
  - Verify ID tokens if you add your own API layer

Flutter uploads should use the Firebase *client* SDK (`firebase_storage`) with
Storage Security Rules and Firebase Auth — not Admin credentials.

Setup:
  1. Save your real JSON outside the git repo (e.g. ~/.secrets/project-firebase.json).
  2. export GOOGLE_APPLICATION_CREDENTIALS=/path/to/file.json
  3. pip install firebase-admin
  4. Run your script that calls init_firebase_admin() once at startup.
"""

from __future__ import annotations

import os

import firebase_admin
from firebase_admin import credentials


def init_firebase_admin() -> None:
    if firebase_admin._apps:
        return
    path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not path or not os.path.isfile(path):
        raise RuntimeError(
            "Set GOOGLE_APPLICATION_CREDENTIALS to the absolute path of your "
            "service account JSON (file must exist; do not commit that file)."
        )
    cred = credentials.Certificate(path)
    firebase_admin.initialize_app(cred)


if __name__ == "__main__":
    init_firebase_admin()
    print("Firebase Admin initialized (no Storage call in this example).")
