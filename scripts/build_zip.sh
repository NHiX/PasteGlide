#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ZIP_STAGING_DIR="${DIST_DIR}/zip-staging"
ZIP_PATH="${DIST_DIR}/PasteGlide.app.zip"

cd "${ROOT_DIR}"

APP_DIR="${1:-}"
if [[ -z "${APP_DIR}" ]]; then
  APP_DIR="$(find "${DIST_DIR}" -maxdepth 1 -name 'PasteGlide_*.app' -type d -print | sort | tail -n 1)"
fi

if [[ -z "${APP_DIR}" || ! -d "${APP_DIR}" ]]; then
  echo "No PasteGlide app bundle found in ${DIST_DIR}. Run scripts/build_app.sh first." >&2
  exit 1
fi

rm -rf "${ZIP_STAGING_DIR}" "${ZIP_PATH}"
mkdir -p "${ZIP_STAGING_DIR}"

cp -R "${APP_DIR}" "${ZIP_STAGING_DIR}/PasteGlide.app"

(
  cd "${ZIP_STAGING_DIR}"
  zip -r -y "${ZIP_PATH}" PasteGlide.app >/dev/null
)

rm -rf "${ZIP_STAGING_DIR}"

echo "${ZIP_PATH}"
