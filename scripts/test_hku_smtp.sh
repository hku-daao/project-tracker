#!/usr/bin/env bash
# Send a test email via HKU mail7 SMTP (backend must have OFFLINE_DEV=true).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TO="${1:-kenkylee@hku.hk}"
API="${API_BASE:-https://projecttrackertest.hku.hk}"

echo "==> POST $API/api/test-smtp  to=$TO"
curl -sk -X POST "$API/api/test-smtp" \
  -H 'Content-Type: application/json' \
  -d "{\"to\":\"$TO\"}" | python3 -m json.tool
