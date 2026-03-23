#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: $0 /path/to/Navigator.app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"
ZIP_PATH="${APP_PATH%/}/../Navigator-App.zip"

if [[ -z "${TEAM_ID}" || -z "${APPLE_ID}" || -z "${NOTARY_PASSWORD}" ]]; then
  echo "Missing TEAM_ID, APPLE_ID, or NOTARY_PASSWORD environment variables." >&2
  exit 1
fi

echo "Signing nested binaries..."
/usr/bin/codesign --force --timestamp --options runtime --sign "${TEAM_ID}" \
  --entitlements "${SCRIPT_DIR}/entitlements.plist" \
  "${APP_PATH}/Contents/Frameworks/Chromium Embedded Framework.framework"

echo "Signing app executable..."
/usr/bin/codesign --force --timestamp --options runtime --sign "${TEAM_ID}" \
  "${APP_PATH}/Contents/MacOS/$(basename "${APP_PATH}" .app)"

echo "Signing app bundle..."
/usr/bin/codesign --force --timestamp --options runtime --sign "${TEAM_ID}" \
  --deep "${APP_PATH}"

echo "Verifying signature..."
/usr/bin/codesign --verify --deep --strict --verbose=4 "${APP_PATH}"
/usr/sbin/spctl -a -vvv "${APP_PATH}"

echo "Creating notary zip..."
/usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "Submitting for notarization..."
/usr/bin/xcrun notarytool submit "${ZIP_PATH}" \
  --apple-id "${APPLE_ID}" \
  --password "${NOTARY_PASSWORD}" \
  --team-id "${TEAM_ID}" \
  --wait

echo "Stapling ticket..."
/usr/bin/xcrun stapler staple "${APP_PATH}"
echo "Done."
