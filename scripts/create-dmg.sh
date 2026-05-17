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

echo "Bundling dependencies..."
FRAMEWORKS_DIR="${STAGING_DIR}/${APP_NAME}.app/Contents/Frameworks"
mkdir -p "${FRAMEWORKS_DIR}"

# Copy SQLite.framework from build products
SQLITE_FRAMEWORK="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/SQLite.framework"
if [ -d "$SQLITE_FRAMEWORK" ]; then
  ditto "$SQLITE_FRAMEWORK" "${FRAMEWORKS_DIR}/SQLite.framework"
  echo "  Bundled: SQLite.framework"
fi

# Find cmark-gfm dylibs (try Homebrew paths)
CMARK_DYLIB=""
CMARK_EXT_DYLIB=""
for dir in /opt/homebrew/lib /usr/local/lib; do
  # Find the versioned dylib (contains a dot before .dylib, e.g. libcmark-gfm.0.29.0.gfm.13.dylib)
  [ -z "$CMARK_DYLIB" ] && CMARK_DYLIB=$(ls "$dir"/libcmark-gfm.*.dylib 2>/dev/null | grep -v -- '-extensions' | head -1)
  [ -z "$CMARK_EXT_DYLIB" ] && CMARK_EXT_DYLIB=$(ls "$dir"/libcmark-gfm-extensions.*.dylib 2>/dev/null | head -1)
done

if [ -n "$CMARK_DYLIB" ]; then
  ditto "$CMARK_DYLIB" "${FRAMEWORKS_DIR}/$(basename "$CMARK_DYLIB")"
  install_name_tool -id "@rpath/$(basename "$CMARK_DYLIB")" "${FRAMEWORKS_DIR}/$(basename "$CMARK_DYLIB")"
  echo "  Bundled: $(basename "$CMARK_DYLIB")"
else
  echo "WARNING: libcmark-gfm.dylib not found — app may not run on other machines" >&2
fi

if [ -n "$CMARK_EXT_DYLIB" ]; then
  ditto "$CMARK_EXT_DYLIB" "${FRAMEWORKS_DIR}/$(basename "$CMARK_EXT_DYLIB")"
  install_name_tool -id "@rpath/$(basename "$CMARK_EXT_DYLIB")" "${FRAMEWORKS_DIR}/$(basename "$CMARK_EXT_DYLIB")"
  # Update extensions' dependency on libcmark-gfm to use @rpath
  if [ -n "$CMARK_DYLIB" ]; then
    install_name_tool -change \
      "$(otool -L "$CMARK_EXT_DYLIB" | grep 'libcmark-gfm-extensions' | awk '{print $1}')" \
      "@rpath/$(basename "$CMARK_EXT_DYLIB")" \
      "${FRAMEWORKS_DIR}/$(basename "$CMARK_EXT_DYLIB")"
    # Update dependency on main cmark-gfm
    install_name_tool -change \
      "$(otool -L "$CMARK_EXT_DYLIB" | grep '@rpath/libcmark-gfm' | awk '{print $1}')" \
      "@rpath/$(basename "$CMARK_DYLIB")" \
      "${FRAMEWORKS_DIR}/$(basename "$CMARK_EXT_DYLIB")"
  fi
  echo "  Bundled: $(basename "$CMARK_EXT_DYLIB")"
else
  echo "WARNING: libcmark-gfm-extensions.dylib not found" >&2
fi

# Add RPATH for bundled frameworks and remove system Homebrew RPATH
BINARY="${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
if ! otool -l "$BINARY" 2>/dev/null | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY"
fi
# Remove old Homebrew RPATH so bundled dylibs take precedence
install_name_tool -delete_rpath "/opt/homebrew/lib" "$BINARY" 2>/dev/null || true
install_name_tool -delete_rpath "/usr/local/lib" "$BINARY" 2>/dev/null || true

# Replace absolute homebrew paths in binary with @rpath references
if [ -n "$CMARK_DYLIB" ]; then
  HOMEBREW_CMARK_PATH=$(otool -L "$BINARY" 2>/dev/null | grep 'libcmark-gfm\.0\.' | grep -v 'extensions' | head -1 | awk '{print $1}')
  if [ -n "$HOMEBREW_CMARK_PATH" ]; then
    install_name_tool -change "$HOMEBREW_CMARK_PATH" "@rpath/$(basename "$CMARK_DYLIB")" "$BINARY"
  fi
fi
if [ -n "$CMARK_EXT_DYLIB" ]; then
  HOMEBREW_EXT_PATH=$(otool -L "$BINARY" 2>/dev/null | grep 'libcmark-gfm-extensions\.0\.' | head -1 | awk '{print $1}')
  if [ -n "$HOMEBREW_EXT_PATH" ]; then
    install_name_tool -change "$HOMEBREW_EXT_PATH" "@rpath/$(basename "$CMARK_EXT_DYLIB")" "$BINARY"
  fi
fi

# Re-sign the app after framework modifications
codesign --force --sign - --deep "${STAGING_DIR}/${APP_NAME}.app" --timestamp=none

echo "Creating ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
