#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
DMG_STAGING_DIR="${DIST_DIR}/dmg-staging"
DMG_PATH="${DIST_DIR}/PasteGlide.dmg"

cd "${ROOT_DIR}"

APP_DIR="${1:-}"
if [[ -z "${APP_DIR}" ]]; then
  APP_DIR="$(find "${DIST_DIR}" -maxdepth 1 -name 'PasteGlide_*.app' -type d -print | sort | tail -n 1)"
fi

if [[ -z "${APP_DIR}" || ! -d "${APP_DIR}" ]]; then
  echo "No PasteGlide app bundle found in ${DIST_DIR}. Run scripts/build_app.sh first." >&2
  exit 1
fi

rm -rf "${DMG_STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING_DIR}"

cp -R "${APP_DIR}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

hdiutil create \
  -volname "PasteGlide" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${DMG_STAGING_DIR}"

echo "${DMG_PATH}"
