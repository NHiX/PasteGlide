#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BASE_NAME="PasteGlide"
STAMP="$(date '+%Y-%m-%d_%H-%M')"
APP_NAME="${APP_BASE_NAME}_${STAMP}"
DISPLAY_NAME="${APP_BASE_NAME}"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_FILE="${ROOT_DIR}/Assets/AppIcon.icns"

cd "${ROOT_DIR}"

swift build -c release --product "${APP_BASE_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/${APP_BASE_NAME}" "${MACOS_DIR}/${APP_BASE_NAME}"
cp "${ICON_FILE}" "${RESOURCES_DIR}/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_BASE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>local.pasteglide</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${STAMP}</string>
    <key>CFBundleVersion</key>
    <string>${STAMP}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "${MACOS_DIR}/${APP_BASE_NAME}"

codesign --force --deep --sign - "${APP_DIR}"

echo "${APP_DIR}"
