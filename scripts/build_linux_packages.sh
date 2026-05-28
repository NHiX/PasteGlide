#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
LINUX_DIST_DIR="${DIST_DIR}/linux-packages"
VERSION="${VERSION:-0.0.0}"
ARCH="${ARCH:-$(uname -m)}"
BINARY_PATH="${1:-${DIST_DIR}/linux/PasteGlide}"

case "${ARCH}" in
  x86_64|amd64) PACKAGE_ARCH="amd64" ;;
  aarch64|arm64) PACKAGE_ARCH="arm64" ;;
  *) PACKAGE_ARCH="${ARCH}" ;;
esac

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Linux packages must be built on Linux with a native PasteGlide binary." >&2
  exit 1
fi

if ! command -v nfpm >/dev/null 2>&1; then
  echo "nfpm is required to build .deb and .rpm packages: https://nfpm.goreleaser.com/install/" >&2
  exit 1
fi

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "Missing executable Linux binary: ${BINARY_PATH}" >&2
  echo "Build the Linux port first, then rerun this script with the binary path." >&2
  exit 1
fi

rm -rf "${LINUX_DIST_DIR}"
mkdir -p "${LINUX_DIST_DIR}/root/usr/bin"
mkdir -p "${LINUX_DIST_DIR}/root/usr/share/applications"
mkdir -p "${LINUX_DIST_DIR}/root/usr/share/icons/hicolor/512x512/apps"

cp "${BINARY_PATH}" "${LINUX_DIST_DIR}/root/usr/bin/pasteglide"
cp "${ROOT_DIR}/packaging/linux/pasteglide.desktop" "${LINUX_DIST_DIR}/root/usr/share/applications/pasteglide.desktop"
cp "${ROOT_DIR}/Assets/AppIcon.iconset/icon_512x512.png" "${LINUX_DIST_DIR}/root/usr/share/icons/hicolor/512x512/apps/pasteglide.png"

cat > "${LINUX_DIST_DIR}/nfpm.yaml" <<EOF
name: pasteglide
arch: ${PACKAGE_ARCH}
platform: linux
version: ${VERSION}
section: utils
priority: optional
maintainer: PasteGlide
description: Local clipboard history manager.
license: MIT
contents:
  - src: ${LINUX_DIST_DIR}/root/usr/bin/pasteglide
    dst: /usr/bin/pasteglide
  - src: ${LINUX_DIST_DIR}/root/usr/share/applications/pasteglide.desktop
    dst: /usr/share/applications/pasteglide.desktop
  - src: ${LINUX_DIST_DIR}/root/usr/share/icons/hicolor/512x512/apps/pasteglide.png
    dst: /usr/share/icons/hicolor/512x512/apps/pasteglide.png
EOF

nfpm package --config "${LINUX_DIST_DIR}/nfpm.yaml" --packager deb --target "${DIST_DIR}/pasteglide_${VERSION}_${PACKAGE_ARCH}.deb"
nfpm package --config "${LINUX_DIST_DIR}/nfpm.yaml" --packager rpm --target "${DIST_DIR}/pasteglide-${VERSION}.${PACKAGE_ARCH}.rpm"

echo "${DIST_DIR}/pasteglide_${VERSION}_${PACKAGE_ARCH}.deb"
echo "${DIST_DIR}/pasteglide-${VERSION}.${PACKAGE_ARCH}.rpm"
