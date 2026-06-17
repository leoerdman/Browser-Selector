#!/usr/bin/env bash
set -euo pipefail

REPO="${BROWSER_SELECTOR_REPO:-UltraDeepAutomation/Browser-Selector}"
VERSION="${BROWSER_SELECTOR_VERSION:-latest}"
ASSET_NAME="${BROWSER_SELECTOR_ASSET_NAME:-BrowserSelector.zip}"
APP_NAME="Browser Selector.app"
HELPER_NAME="set-default-browser"
DEFAULT_INSTALL_DIR="${HOME}/Applications"
INSTALL_DIR="${BROWSER_SELECTOR_INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLISTBUDDY="/usr/libexec/PlistBuddy"
CODESIGN="/usr/bin/codesign"
CURL="/usr/bin/curl"
DITTO="/usr/bin/ditto"
OPEN="/usr/bin/open"
PLUTIL="/usr/bin/plutil"
SHASUM="/usr/bin/shasum"
XATTR="/usr/bin/xattr"

need_command() {
    if [[ ! -x "$1" ]]; then
        echo "Missing required command: $1" >&2
        exit 69
    fi
}

need_command "${CODESIGN}"
need_command "${CURL}"
need_command "${DITTO}"
need_command "${OPEN}"
need_command "${PLISTBUDDY}"
need_command "${PLUTIL}"
need_command "${SHASUM}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Browser Selector can only be installed on macOS." >&2
    exit 70
fi

trim_trailing_slashes() {
    local path="$1"
    while [[ "${path}" != "/" && "${path}" == */ ]]; do
        path="${path%/}"
    done
    printf '%s\n' "${path}"
}

DEFAULT_INSTALL_DIR="$(trim_trailing_slashes "${DEFAULT_INSTALL_DIR}")"
INSTALL_DIR="$(trim_trailing_slashes "${INSTALL_DIR}")"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"

if [[ "${INSTALL_DIR}" != "${DEFAULT_INSTALL_DIR}" ]]; then
    echo "Refusing to install outside ~/Applications: ${TARGET_APP}" >&2
    exit 64
fi

if [[ -n "${BROWSER_SELECTOR_RELEASE_BASE_URL:-}" ]]; then
    RELEASE_BASE_URL="${BROWSER_SELECTOR_RELEASE_BASE_URL}"
elif [[ "${VERSION}" == "latest" ]]; then
    RELEASE_BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
    RELEASE_BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
    if [[ -n "${INSTALL_STAGING_APP:-}" && -d "${INSTALL_STAGING_APP}" ]]; then
        rm -rf "${INSTALL_STAGING_APP}"
    fi
}
trap cleanup EXIT

ZIP_PATH="${TMP_DIR}/${ASSET_NAME}"
CHECKSUM_PATH="${TMP_DIR}/${ASSET_NAME}.sha256"
UNPACK_DIR="${TMP_DIR}/unpack"

mkdir -p "${UNPACK_DIR}"

echo "Downloading Browser Selector ${VERSION}..."
"${CURL}" -fL --retry 3 --retry-delay 1 \
    "${RELEASE_BASE_URL}/${ASSET_NAME}" \
    -o "${ZIP_PATH}"

"${CURL}" -fL --retry 3 --retry-delay 1 \
    "${RELEASE_BASE_URL}/${ASSET_NAME}.sha256" \
    -o "${CHECKSUM_PATH}"
(
    cd "${TMP_DIR}"
    "${SHASUM}" -a 256 -c "$(basename "${CHECKSUM_PATH}")"
)

"${DITTO}" -x -k "${ZIP_PATH}" "${UNPACK_DIR}"

SOURCE_APP="${UNPACK_DIR}/${APP_NAME}"
HELPER="${UNPACK_DIR}/${HELPER_NAME}"
SOURCE_INFO_PLIST="${SOURCE_APP}/Contents/Info.plist"

if [[ ! -d "${SOURCE_APP}" ]]; then
    echo "Release archive does not contain ${APP_NAME}." >&2
    exit 65
fi

if [[ ! -x "${HELPER}" ]]; then
    echo "Release archive does not contain executable ${HELPER_NAME}." >&2
    exit 65
fi

"${PLUTIL}" -lint "${SOURCE_INFO_PLIST}" >/dev/null

BUNDLE_IDENTIFIER="$("${PLISTBUDDY}" -c 'Print :CFBundleIdentifier' "${SOURCE_INFO_PLIST}")"
BUNDLE_EXECUTABLE="$("${PLISTBUDDY}" -c 'Print :CFBundleExecutable' "${SOURCE_INFO_PLIST}")"
TARGET_EXECUTABLE="${TARGET_APP}/Contents/MacOS/${BUNDLE_EXECUTABLE}"
INSTALL_STAGING_APP="${INSTALL_DIR}/.${APP_NAME}.installing"

if [[ "${BUNDLE_IDENTIFIER}" != "com.leoerdman.BrowserSelector" ]]; then
    echo "Unexpected bundle identifier: ${BUNDLE_IDENTIFIER}" >&2
    exit 65
fi

if [[ "$("${PLISTBUDDY}" -c 'Print :LSUIElement' "${SOURCE_INFO_PLIST}")" != "true" ]]; then
    echo "Release app is not configured as a menu bar agent." >&2
    exit 65
fi

if [[ ! -x "${SOURCE_APP}/Contents/MacOS/${BUNDLE_EXECUTABLE}" ]]; then
    echo "Release app does not contain executable ${BUNDLE_EXECUTABLE}." >&2
    exit 65
fi

"${CODESIGN}" --verify --deep --strict --verbose=2 "${SOURCE_APP}" >/dev/null
"${CODESIGN}" --verify --strict --verbose=2 "${HELPER}" >/dev/null

mkdir -p "${INSTALL_DIR}"

running_target_pids() {
    local pid
    local command_path

    while IFS= read -r pid; do
        command_path="$(/bin/ps -p "${pid}" -o command= 2>/dev/null || true)"
        if [[ "${command_path}" == "${TARGET_EXECUTABLE}" || "${command_path}" == "${TARGET_EXECUTABLE} "* ]]; then
            printf '%s\n' "${pid}"
        fi
    done < <(/usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" 2>/dev/null || true)
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
    "${LSREGISTER}" -u "${TARGET_APP}" >/dev/null 2>&1 || true
fi

rm -rf "${INSTALL_STAGING_APP}"
"${DITTO}" "${SOURCE_APP}" "${INSTALL_STAGING_APP}"
"${CODESIGN}" --verify --deep --strict --verbose=2 "${INSTALL_STAGING_APP}" >/dev/null

rm -rf "${TARGET_APP}"
mv "${INSTALL_STAGING_APP}" "${TARGET_APP}"

INSTALLED_INFO_PLIST="${TARGET_APP}/Contents/Info.plist"

if [[ -x "${XATTR}" ]]; then
    "${XATTR}" -dr com.apple.quarantine "${TARGET_APP}" >/dev/null 2>&1 || true
fi

"${CODESIGN}" --verify --deep --strict --verbose=2 "${TARGET_APP}" >/dev/null

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}" >/dev/null
fi

"${HELPER}" "${BUNDLE_IDENTIFIER}" "${INSTALLED_INFO_PLIST}"

launch_installed_app() {
    "${OPEN}" -n "${TARGET_APP}"
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
