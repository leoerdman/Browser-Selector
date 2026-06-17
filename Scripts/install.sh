#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}").app"
SOURCE_APP="${ROOT_DIR}/dist/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
STAGING_DIR="${ROOT_DIR}/.build/install-stage"
STAGING_APP="${STAGING_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
HELPER_DIR="${ROOT_DIR}/.build/install-tools"
DEFAULT_BROWSER_HELPER="${HELPER_DIR}/set-default-browser"

case "${TARGET_APP}" in
    "${HOME}/Applications/"*.app) ;;
    *)
        echo "Refusing to replace unsafe install target: ${TARGET_APP}" >&2
        exit 1
        ;;
esac

"${ROOT_DIR}/Scripts/build.sh"

mkdir -p "${HELPER_DIR}"
xcrun swiftc "${ROOT_DIR}/Scripts/set_default_browser.swift" -o "${DEFAULT_BROWSER_HELPER}"

mkdir -p "${INSTALL_DIR}" "${STAGING_DIR}"
rm -rf "${STAGING_APP}"
ditto "${SOURCE_APP}" "${STAGING_APP}"

if /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1; then
    /usr/bin/pkill -TERM -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || true
    for _ in {1..50}; do
        /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || break
        sleep 0.1
    done

    if /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1; then
        /usr/bin/pkill -KILL -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || true
    fi
fi

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${SOURCE_APP}" >/dev/null 2>&1 || true
    "${LSREGISTER}" -u "${TARGET_APP}" >/dev/null 2>&1 || true
fi

rm -rf "${TARGET_APP}"
ditto "${STAGING_APP}" "${TARGET_APP}"

INSTALLED_INFO_PLIST="${TARGET_APP}/Contents/Info.plist"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INSTALLED_INFO_PLIST}")"

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}"
    "${LSREGISTER}" -u "${SOURCE_APP}" >/dev/null 2>&1 || true
fi

"${DEFAULT_BROWSER_HELPER}" "${BUNDLE_IDENTIFIER}" "${INSTALLED_INFO_PLIST}"

launch_installed_app() {
    open -n "${TARGET_APP}"
    for _ in {1..30}; do
        /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 && return 0
        sleep 0.1
    done

    "${TARGET_APP}/Contents/MacOS/${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 &
    for _ in {1..30}; do
        /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 && return 0
        sleep 0.1
    done

    return 1
}

if ! launch_installed_app; then
    echo "Installed app did not start: ${TARGET_APP}" >&2
    exit 1
fi

echo "Installed: ${TARGET_APP}"
echo "Registered as default handler for web URL schemes."
