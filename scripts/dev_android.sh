#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${ARTH_API_BASE_URL:-https://arth-backend-production.up.railway.app/v1}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required but was not found in PATH." >&2
  exit 1
fi

echo "Connected Android devices:"
adb devices

if ! adb devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
  cat >&2 <<'MSG'

No ready Android device found.

Fix:
  1. Connect phone with USB, or start an Android emulator.
  2. Enable Developer Options and USB debugging on the phone.
  3. Accept the "Allow USB debugging" prompt on the phone.
  4. Run this script again.
MSG
  exit 1
fi

echo
echo "Starting ARTH in Flutter development mode."
echo "Backend: ${API_BASE_URL}"
echo
echo "While this is running:"
echo "  - Save Dart files and press r for hot reload."
echo "  - Press R for hot restart."
echo "  - Press q to quit."
echo

flutter run \
  --dart-define=ARTH_API_BASE_URL="${API_BASE_URL}"
