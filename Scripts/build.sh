#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Browser Selector"
BINARY_NAME="BrowserSelector"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "${ROOT_DIR}"

swift Scripts/generate_icon.swift
iconutil -c icns -o Resources/BrowserSelector.icns Resources/BrowserSelector.iconset

swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/${BINARY_NAME}" "${MACOS_DIR}/${BINARY_NAME}"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "Resources/BrowserSelector.icns" "${RESOURCES_DIR}/BrowserSelector.icns"
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

chmod +x "${MACOS_DIR}/${BINARY_NAME}"
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    codesign --force --deep --sign - --timestamp=none "${APP_DIR}"
else
    codesign --force --deep --sign "${SIGN_IDENTITY}" --options runtime --timestamp "${APP_DIR}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built: ${APP_DIR}"
