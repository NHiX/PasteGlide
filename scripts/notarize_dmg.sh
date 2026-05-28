#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
DMG_PATH="${DIST_DIR}/PasteGlide.dmg"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Apple Developer ID Application identity}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a stored xcrun notarytool keychain profile}"

cd "${ROOT_DIR}"

CODESIGN_HARDENED_RUNTIME=1 SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" ./scripts/build_app.sh
APP_DIR="$(find "${DIST_DIR}" -maxdepth 1 -name 'PasteGlide_*.app' -type d -print | sort | tail -n 1)"

./scripts/build_dmg.sh "${APP_DIR}"
codesign --force --sign "${DEVELOPER_ID_APPLICATION}" "${DMG_PATH}"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"

echo "${DMG_PATH}"
