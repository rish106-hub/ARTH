#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-rish106-hub/ARTH}"
WORK_DIR="${TMPDIR:-/tmp}/arth-latest-apk"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required but was not found in PATH." >&2
  exit 1
fi

RUN_ID="$(gh run list \
  --repo "${REPO}" \
  --branch main \
  --workflow 'CI — Build & Analyse' \
  --status success \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"

if [ -z "${RUN_ID}" ] || [ "${RUN_ID}" = "null" ]; then
  echo "No successful main CI run found for ${REPO}." >&2
  exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "Downloading latest ARTH debug APK artifact from run ${RUN_ID}..."
gh run download "${RUN_ID}" --repo "${REPO}" --dir "${WORK_DIR}"

APK_PATH="$(find "${WORK_DIR}" -type f -name '*.apk' | head -n 1)"
if [ -z "${APK_PATH}" ]; then
  echo "No APK found in downloaded artifacts." >&2
  exit 1
fi

echo "Connected Android devices:"
adb devices

if ! adb devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "No ready Android device found." >&2
  exit 1
fi

echo "Installing over existing ARTH app, without uninstalling..."
adb install -r "${APK_PATH}"
echo "Installed: ${APK_PATH}"
