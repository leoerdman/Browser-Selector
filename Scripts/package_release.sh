#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}")"
BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
RELEASE_DIR="${ROOT_DIR}/dist/release"
PACKAGE_STAGING="${RELEASE_DIR}/package"
ZIP_NAME="BrowserSelector.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
HELPER_NAME="set-default-browser"
HELPER_SOURCE="${ROOT_DIR}/Scripts/set_default_browser.swift"
HELPER_UNIVERSAL="${RELEASE_DIR}/${HELPER_NAME}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
RELEASE_ARCHS="${BROWSER_SELECTOR_RELEASE_ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="$("${ROOT_DIR}/Scripts/resolve_signing_identity.sh")"

cd "${ROOT_DIR}"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

BROWSER_SELECTOR_ARCHS="${RELEASE_ARCHS}" "${ROOT_DIR}/Scripts/build.sh"

HELPER_SLICES=()
for arch in ${RELEASE_ARCHS}; do
    helper_slice="${RELEASE_DIR}/${HELPER_NAME}-${arch}"
    xcrun swiftc \
        -target "${arch}-apple-macosx${MACOS_DEPLOYMENT_TARGET}" \
        "${HELPER_SOURCE}" \
        -o "${helper_slice}"
    HELPER_SLICES+=("${helper_slice}")
done

if [[ "${#HELPER_SLICES[@]}" -eq 1 ]]; then
    cp "${HELPER_SLICES[0]}" "${HELPER_UNIVERSAL}"
else
    lipo -create "${HELPER_SLICES[@]}" -output "${HELPER_UNIVERSAL}"
fi

chmod +x "${HELPER_UNIVERSAL}"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    codesign --force --sign - --timestamp=none "${HELPER_UNIVERSAL}"
else
    codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp=none "${HELPER_UNIVERSAL}"
fi

codesign --verify --strict --verbose=2 "${HELPER_UNIVERSAL}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${APP_DIR}/Contents/Info.plist")" != "true" ]]; then
    echo "Release app must be a menu bar agent: LSUIElement is not true." >&2
    exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_DIR}/Contents/Info.plist")" != "${BUNDLE_IDENTIFIER}" ]]; then
    echo "Release app bundle identifier mismatch." >&2
    exit 1
fi

assert_architectures() {
    local binary_path="$1"
    local label="$2"
    local actual_archs

    actual_archs="$(lipo -archs "${binary_path}")"
    for arch in ${RELEASE_ARCHS}; do
        if [[ " ${actual_archs} " != *" ${arch} "* ]]; then
            echo "${label} is missing required architecture ${arch}; actual: ${actual_archs}" >&2
            exit 1
        fi
    done
}

assert_architectures "${APP_DIR}/Contents/MacOS/${BINARY_NAME}" "Release app"
assert_architectures "${HELPER_UNIVERSAL}" "Release helper"

mkdir -p "${PACKAGE_STAGING}"
ditto "${APP_DIR}" "${PACKAGE_STAGING}/${APP_NAME}.app"
cp "${HELPER_UNIVERSAL}" "${PACKAGE_STAGING}/${HELPER_NAME}"

(
    cd "${PACKAGE_STAGING}"
    /usr/bin/zip -qry "${ZIP_PATH}" "${APP_NAME}.app" "${HELPER_NAME}"
)

(
    cd "${RELEASE_DIR}"
    shasum -a 256 "${ZIP_NAME}" > "${ZIP_NAME}.sha256"
)

lipo -info "${APP_DIR}/Contents/MacOS/${BINARY_NAME}"
lipo -info "${HELPER_UNIVERSAL}"

echo "Packaged: ${ZIP_PATH}"
echo "Checksum: ${ZIP_PATH}.sha256"
