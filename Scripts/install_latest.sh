#!/usr/bin/env bash
set -euo pipefail

REPO="${BROWSER_SELECTOR_REPO:-UltraDeepAutomation/browser-selector}"
VERSION="${BROWSER_SELECTOR_VERSION:-latest}"
ASSET_NAME="${BROWSER_SELECTOR_ASSET_NAME:-BrowserSelector.zip}"
APP_NAME="Browser Selector.app"
HELPER_NAME="set-default-browser"
INSTALL_DIR="${BROWSER_SELECTOR_INSTALL_DIR:-${HOME}/Applications}"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

need_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 69
    fi
}

need_command curl
need_command ditto
need_command shasum
need_command /usr/libexec/PlistBuddy

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Browser Selector can only be installed on macOS." >&2
    exit 70
fi

case "${TARGET_APP}" in
    "${HOME}/Applications/"*.app) ;;
    *)
        echo "Refusing to install outside ~/Applications: ${TARGET_APP}" >&2
        exit 64
        ;;
esac

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
}
trap cleanup EXIT

ZIP_PATH="${TMP_DIR}/${ASSET_NAME}"
CHECKSUM_PATH="${TMP_DIR}/${ASSET_NAME}.sha256"
UNPACK_DIR="${TMP_DIR}/unpack"

mkdir -p "${UNPACK_DIR}"

echo "Downloading Browser Selector ${VERSION}..."
curl -fL --retry 3 --retry-delay 1 \
    "${RELEASE_BASE_URL}/${ASSET_NAME}" \
    -o "${ZIP_PATH}"

if [[ "${BROWSER_SELECTOR_SKIP_CHECKSUM:-0}" == "1" ]]; then
    echo "Skipping checksum verification because BROWSER_SELECTOR_SKIP_CHECKSUM=1."
else
    curl -fL --retry 3 --retry-delay 1 \
        "${RELEASE_BASE_URL}/${ASSET_NAME}.sha256" \
        -o "${CHECKSUM_PATH}"
    (
        cd "${TMP_DIR}"
        shasum -a 256 -c "$(basename "${CHECKSUM_PATH}")"
    )
fi

ditto -x -k "${ZIP_PATH}" "${UNPACK_DIR}"

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

plutil -lint "${SOURCE_INFO_PLIST}" >/dev/null

BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${SOURCE_INFO_PLIST}")"
BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${SOURCE_INFO_PLIST}")"

if [[ "${BUNDLE_IDENTIFIER}" != "com.leoerdman.BrowserSelector" ]]; then
    echo "Unexpected bundle identifier: ${BUNDLE_IDENTIFIER}" >&2
    exit 65
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${SOURCE_INFO_PLIST}")" != "true" ]]; then
    echo "Release app is not configured as a menu bar agent." >&2
    exit 65
fi

mkdir -p "${INSTALL_DIR}"

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
    "${LSREGISTER}" -u "${TARGET_APP}" >/dev/null 2>&1 || true
fi

rm -rf "${TARGET_APP}"
ditto "${SOURCE_APP}" "${TARGET_APP}"

INSTALLED_INFO_PLIST="${TARGET_APP}/Contents/Info.plist"

if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}" >/dev/null
fi

"${HELPER}" "${BUNDLE_IDENTIFIER}" "${INSTALLED_INFO_PLIST}"

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
