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
if /usr/bin/pgrep -x "${BUNDLE_IDENTIFIER##*.}" >/dev/null 2>&1; then
    /usr/bin/pkill -TERM -x "${BUNDLE_IDENTIFIER##*.}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        /usr/bin/pgrep -x "${BUNDLE_IDENTIFIER##*.}" >/dev/null 2>&1 || break
        sleep 0.1
    done
fi
ditto "${SOURCE_APP}" "${TARGET_APP}"

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}"
fi

open "${TARGET_APP}"

echo "Installed: ${TARGET_APP}"
echo "Open the menu bar icon and choose 'Назначить браузером по умолчанию' if macOS did not ask automatically."
