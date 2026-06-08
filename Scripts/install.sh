#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}").app"
SOURCE_APP="${ROOT_DIR}/dist/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"

"${ROOT_DIR}/Scripts/build.sh"

mkdir -p "${INSTALL_DIR}"
if /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1; then
    /usr/bin/pkill -TERM -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || break
        sleep 0.1
    done
fi
ditto "${SOURCE_APP}" "${TARGET_APP}"

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}"
fi

"${ROOT_DIR}/Scripts/set_default_browser.swift" "${BUNDLE_IDENTIFIER}"

open "${TARGET_APP}"

echo "Installed: ${TARGET_APP}"
echo "Registered as default handler for http and https."
