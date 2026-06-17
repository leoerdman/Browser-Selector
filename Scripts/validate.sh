#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}")"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${INFO_PLIST}")"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
BUILT_INFO_PLIST="${APP_DIR}/Contents/Info.plist"
HELPER_DIR="${ROOT_DIR}/.build/install-tools"
DEFAULT_BROWSER_HELPER="${HELPER_DIR}/set-default-browser"
SWIFT_PACKAGE_FLAGS=()

if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_PACKAGE_FLAGS+=(--disable-sandbox)
fi

cd "${ROOT_DIR}"

mkdir -p "${HELPER_DIR}"
xcrun swiftc "${ROOT_DIR}/Scripts/set_default_browser.swift" -o "${DEFAULT_BROWSER_HELPER}"

validate_browser_plist() {
    local plist_path="$1"
    local declared_web_schemes
    local declared_web_content_types
    local declared_document_types
    local document_index

    plutil -lint "${plist_path}" >/dev/null
    declared_web_schemes="$("${DEFAULT_BROWSER_HELPER}" --print-web-schemes "${plist_path}")"
    declared_web_content_types="$("${DEFAULT_BROWSER_HELPER}" --print-web-content-types "${plist_path}")"
    declared_document_types="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "${plist_path}")"

    for scheme in http https; do
        if ! printf '%s\n' "${declared_web_schemes}" | grep -qx "${scheme}"; then
            echo "Missing URL scheme in ${plist_path}: ${scheme}" >&2
            exit 1
        fi
    done

    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:1:CFBundleURLSchemes" "${plist_path}" | grep -qx "    file"; then
        echo "Missing browser claim URL scheme in ${plist_path}: file" >&2
        exit 1
    fi

    if [[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${plist_path}")" != "true" ]]; then
        echo "LSUIElement must be true in ${plist_path}; Browser Selector must never appear in Dock." >&2
        exit 1
    fi

    for content_type in public.html; do
        if ! printf '%s\n' "${declared_web_content_types}" | grep -qx "${content_type}"; then
            echo "Missing web content type in ${plist_path}: ${content_type}" >&2
            exit 1
        fi
    done

    if ! printf '%s\n' "${declared_document_types}" | sed 's/^[[:space:]]*//' | grep -qx "public.xhtml"; then
        echo "Missing browser claim content type in ${plist_path}: public.xhtml" >&2
        exit 1
    fi

    for document_index in 0 1; do
        if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:${document_index}:LSHandlerRank" "${plist_path}")" != "Owner" ]]; then
            echo "CFBundleDocumentTypes:${document_index}:LSHandlerRank must be Owner in ${plist_path}" >&2
            exit 1
        fi

        if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:${document_index}:LSItemContentTypes" "${plist_path}" | grep -c '^[[:space:]]*public\.')" != "1" ]]; then
            echo "CFBundleDocumentTypes:${document_index} must declare exactly one public content type in ${plist_path}" >&2
            exit 1
        fi
    done

    if ! /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "${plist_path}" >/dev/null; then
        echo "Missing NSAppleEventsUsageDescription in ${plist_path}" >&2
        exit 1
    fi

    if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:LSHandlerRank" "${plist_path}")" != "Owner" ]]; then
        echo "CFBundleURLTypes:0:LSHandlerRank must be Owner in ${plist_path}" >&2
        exit 1
    fi

    for capability in \
        IsSupported \
        EphemeralBrowserSessionIsSupported \
        CallbackURLMatchingIsSupported \
        AdditionalHeaderFieldsAreSupported; do
        if [[ "$(/usr/libexec/PlistBuddy -c "Print :ASWebAuthenticationSessionWebBrowserSupportCapabilities:${capability}" "${plist_path}")" != "true" ]]; then
            echo "ASWebAuthenticationSessionWebBrowserSupportCapabilities:${capability} must be true in ${plist_path}" >&2
            exit 1
        fi
    done
}

validate_browser_plist "${INFO_PLIST}"

if [[ "${#SWIFT_PACKAGE_FLAGS[@]}" -gt 0 ]]; then
    swift test "${SWIFT_PACKAGE_FLAGS[@]}"
else
    swift test
fi

"${ROOT_DIR}/Scripts/build.sh"

validate_browser_plist "${BUILT_INFO_PLIST}"
if [[ ! -f "${APP_DIR}/Contents/Resources/${ICON_NAME}.icns" ]]; then
    echo "Missing built app icon: ${APP_DIR}/Contents/Resources/${ICON_NAME}.icns" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Validation passed: plist, URL schemes, web content types, auth session capabilities, Apple Events usage, install-helper, tests, build, codesign."
