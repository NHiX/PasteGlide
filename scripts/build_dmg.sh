#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
DMG_STAGING_DIR="${DIST_DIR}/dmg-staging"
DMG_PATH="${DIST_DIR}/PasteGlide.dmg"
INSTALL_NOTE="${DMG_STAGING_DIR}/Installation - Gatekeeper.txt"

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

cp -R "${APP_DIR}" "${DMG_STAGING_DIR}/PasteGlide.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

cat > "${INSTALL_NOTE}" <<'NOTE'
FR
Glissez PasteGlide.app vers Applications.

Si macOS bloque l'ouverture avec le message "Apple n'a pas pu confirmer que PasteGlide ne contenait pas de logiciel malveillant", l'app n'est pas notarizée avec un certificat Apple Developer ID.

Solution utilisateur:
1. Ouvrez Réglages Système > Confidentialité et sécurité.
2. Dans Sécurité, choisissez "Ouvrir quand même" pour PasteGlide.

Ou:
1. Faites clic droit sur PasteGlide.app.
2. Choisissez Ouvrir.
3. Confirmez l'ouverture.

EN
Drag PasteGlide.app to Applications.

If macOS blocks launch with "Apple could not verify PasteGlide is free of malware", the app is not notarized with an Apple Developer ID certificate.

User workaround:
1. Open System Settings > Privacy & Security.
2. Under Security, choose "Open Anyway" for PasteGlide.

Or:
1. Right-click PasteGlide.app.
2. Choose Open.
3. Confirm opening.
NOTE

hdiutil create \
  -volname "PasteGlide" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${DMG_STAGING_DIR}"

echo "${DMG_PATH}"
