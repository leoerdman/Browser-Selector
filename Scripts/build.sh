#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}")"
BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${INFO_PLIST}")"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
BROWSER_SELECTOR_ARCHS="${BROWSER_SELECTOR_ARCHS:-}"
SWIFT_PACKAGE_FLAGS=()

if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_PACKAGE_FLAGS+=(--disable-sandbox)
fi

cd "${ROOT_DIR}"

swift Scripts/generate_icon.swift
iconutil -c icns -o Resources/BrowserSelector.icns Resources/BrowserSelector.iconset

build_for_arch() {
    local arch="$1"
    local scratch_path="${ROOT_DIR}/.build/${arch}-release"

    if [[ "${#SWIFT_PACKAGE_FLAGS[@]}" -gt 0 ]]; then
        swift build \
            "${SWIFT_PACKAGE_FLAGS[@]}" \
            -c release \
            --triple "${arch}-apple-macosx${MACOS_DEPLOYMENT_TARGET}" \
            --scratch-path "${scratch_path}" >&2
    else
        swift build \
            -c release \
            --triple "${arch}-apple-macosx${MACOS_DEPLOYMENT_TARGET}" \
            --scratch-path "${scratch_path}" >&2
    fi

    printf '%s/%s-apple-macosx/release/%s\n' "${scratch_path}" "${arch}" "${BINARY_NAME}"
}

BINARY_SOURCE=""
if [[ -n "${BROWSER_SELECTOR_ARCHS}" ]]; then
    UNIVERSAL_DIR="${ROOT_DIR}/.build/universal-release"
    UNIVERSAL_BINARY="${UNIVERSAL_DIR}/${BINARY_NAME}"
    mkdir -p "${UNIVERSAL_DIR}"

    BINARY_SLICES=()
    for arch in ${BROWSER_SELECTOR_ARCHS}; do
        BINARY_SLICES+=("$(build_for_arch "${arch}")")
    done

    if [[ "${#BINARY_SLICES[@]}" -eq 1 ]]; then
        BINARY_SOURCE="${BINARY_SLICES[0]}"
    else
        lipo -create "${BINARY_SLICES[@]}" -output "${UNIVERSAL_BINARY}"
        BINARY_SOURCE="${UNIVERSAL_BINARY}"
    fi
else
    if [[ "${#SWIFT_PACKAGE_FLAGS[@]}" -gt 0 ]]; then
        swift build "${SWIFT_PACKAGE_FLAGS[@]}" -c release
    else
        swift build -c release
    fi
    BINARY_SOURCE=".build/release/${BINARY_NAME}"
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BINARY_SOURCE}" "${MACOS_DIR}/${BINARY_NAME}"
cp "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
cp "Resources/${ICON_NAME}.icns" "${RESOURCES_DIR}/${ICON_NAME}.icns"
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

chmod +x "${MACOS_DIR}/${BINARY_NAME}"
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

SIGN_IDENTITY="$("${ROOT_DIR}/Scripts/resolve_signing_identity.sh")"

if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" ]]; then
    SIGN_IDENTITY="-"
    codesign --force --deep --sign - --timestamp=none "${APP_DIR}"
else
    codesign --force --deep --sign "${SIGN_IDENTITY}" --options runtime --timestamp=none "${APP_DIR}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built: ${APP_DIR}"
echo "Signed with: ${SIGN_IDENTITY}"
