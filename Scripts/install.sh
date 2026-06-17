#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}").app"
SOURCE_APP="${ROOT_DIR}/dist/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
INSTALL_STAGING_APP="${INSTALL_DIR}/.${APP_NAME}.installing"
STAGING_DIR="${ROOT_DIR}/.build/install-stage"
STAGING_APP="${STAGING_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
TARGET_EXECUTABLE="${TARGET_APP}/Contents/MacOS/${BUNDLE_EXECUTABLE}"
HELPER_DIR="${ROOT_DIR}/.build/install-tools"
DEFAULT_BROWSER_HELPER="${HELPER_DIR}/set-default-browser"

case "${TARGET_APP}" in
    "${HOME}/Applications/"*.app) ;;
    *)
        echo "Refusing to replace unsafe install target: ${TARGET_APP}" >&2
        exit 1
        ;;
esac

cleanup() {
    if [[ -n "${INSTALL_STAGING_APP:-}" && -d "${INSTALL_STAGING_APP}" ]]; then
        rm -rf "${INSTALL_STAGING_APP}"
    fi
}
trap cleanup EXIT

"${ROOT_DIR}/Scripts/build.sh"

mkdir -p "${HELPER_DIR}"
xcrun swiftc "${ROOT_DIR}/Scripts/set_default_browser.swift" -o "${DEFAULT_BROWSER_HELPER}"

mkdir -p "${INSTALL_DIR}" "${STAGING_DIR}"
rm -rf "${STAGING_APP}"
ditto "${SOURCE_APP}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}" >/dev/null

running_target_pids() {
    local pid
    local command_path

    /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" 2>/dev/null | while IFS= read -r pid; do
        command_path="$(/bin/ps -p "${pid}" -o comm= 2>/dev/null || true)"
        if [[ "${command_path}" == "${TARGET_EXECUTABLE}" ]]; then
            printf '%s\n' "${pid}"
        fi
    done
}

is_target_app_running() {
    [[ -n "$(running_target_pids)" ]]
}

terminate_target_app() {
    local pid
    local pids

    pids="$(running_target_pids)"
    [[ -z "${pids}" ]] && return 0

    while IFS= read -r pid; do
        kill -TERM "${pid}" >/dev/null 2>&1 || true
    done <<< "${pids}"

    for _ in {1..50}; do
        is_target_app_running || return 0
        sleep 0.1
    done

    pids="$(running_target_pids)"
    while IFS= read -r pid; do
        kill -KILL "${pid}" >/dev/null 2>&1 || true
    done <<< "${pids}"

    for _ in {1..20}; do
        is_target_app_running || return 0
        sleep 0.1
    done

    echo "Unable to stop running app at ${TARGET_EXECUTABLE}." >&2
    return 1
}

terminate_target_app

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${SOURCE_APP}" >/dev/null 2>&1 || true
    "${LSREGISTER}" -u "${TARGET_APP}" >/dev/null 2>&1 || true
fi

rm -rf "${INSTALL_STAGING_APP}"
ditto "${STAGING_APP}" "${INSTALL_STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${INSTALL_STAGING_APP}" >/dev/null

rm -rf "${TARGET_APP}"
mv "${INSTALL_STAGING_APP}" "${TARGET_APP}"
codesign --verify --deep --strict --verbose=2 "${TARGET_APP}" >/dev/null

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
        is_target_app_running && return 0
        sleep 0.1
    done

    "${TARGET_APP}/Contents/MacOS/${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 &
    for _ in {1..30}; do
        is_target_app_running && return 0
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
