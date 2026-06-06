#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Browser Selector.app"
SOURCE_APP="${ROOT_DIR}/dist/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${ROOT_DIR}/Resources/Info.plist")"

"${ROOT_DIR}/Scripts/build.sh"

mkdir -p "${INSTALL_DIR}"
osascript -e "tell application id \"${BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
sleep 0.5
ditto "${SOURCE_APP}" "${TARGET_APP}"

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}"
fi

open "${TARGET_APP}"

echo "Installed: ${TARGET_APP}"
echo "Open the menu bar icon and choose 'Назначить браузером по умолчанию' if macOS did not ask automatically."
