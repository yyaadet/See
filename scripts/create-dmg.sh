#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-See}"
SCHEME="${SCHEME:-See}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_PATH="${PROJECT_PATH:-See.xcodeproj}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/XcodeDerivedData}"
DIST_DIR="${DIST_DIR:-dist}"
STAGING_DIR="${STAGING_DIR:-build/dmg-root}"
DMG_PATH="${DMG_PATH:-${DIST_DIR}/${APP_NAME}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME}}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

cd "$(dirname "$0")/.."

echo "Building ${APP_NAME}.app..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app was not found at ${APP_PATH}" >&2
  exit 1
fi

echo "Staging DMG contents..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${DIST_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
