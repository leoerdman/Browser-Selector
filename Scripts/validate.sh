#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/dist/Browser Selector.app"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
BUILT_INFO_PLIST="${APP_DIR}/Contents/Info.plist"

cd "${ROOT_DIR}"

plutil -lint "${INFO_PLIST}" >/dev/null

for scheme in http https; do
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "${INFO_PLIST}" | grep -q "${scheme}"; then
        echo "Missing URL scheme: ${scheme}" >&2
        exit 1
    fi
done

if ! /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "${INFO_PLIST}" >/dev/null; then
    echo "Missing NSAppleEventsUsageDescription" >&2
    exit 1
fi

"${ROOT_DIR}/Scripts/build.sh"

plutil -lint "${BUILT_INFO_PLIST}" >/dev/null
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Validation passed: plist, URL schemes, Apple Events usage, build, codesign."
