#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${INFO_PLIST}")"
APP_BUNDLE_NAME="${APP_NAME}.app"
BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
RELEASE_ARCHS="${BROWSER_SELECTOR_RELEASE_ARCHS:-arm64 x86_64}"
REQUIRE_DEVELOPER_ID="${BROWSER_SELECTOR_REQUIRE_DEVELOPER_ID:-0}"
ALLOW_UNSIGNED_INSTALLER="${BROWSER_SELECTOR_ALLOW_UNSIGNED_INSTALLER:-0}"
NOTARY_PROFILE="${BROWSER_SELECTOR_NOTARY_PROFILE:-}"
NOTARY_TIMEOUT="${BROWSER_SELECTOR_NOTARY_TIMEOUT:-30m}"

APP_DIR="${ROOT_DIR}/dist/${APP_BUNDLE_NAME}"
INSTALLER_DIR="${ROOT_DIR}/dist/installer"
WORK_DIR="${INSTALLER_DIR}/build"
SCRIPTS_DIR="${WORK_DIR}/scripts"
STAGED_COMPONENT_DIR="${WORK_DIR}/component"
STAGED_APP_DIR="${STAGED_COMPONENT_DIR}/${APP_BUNDLE_NAME}"
COMPONENT_PKG="${WORK_DIR}/BrowserSelector-component.pkg"
PRODUCT_REQUIREMENTS="${WORK_DIR}/product-requirements.plist"
DMG_ROOT="${WORK_DIR}/dmg-root"
PKG_BASENAME="BrowserSelector-${VERSION}"
PKG_PATH="${INSTALLER_DIR}/${PKG_BASENAME}.pkg"
DMG_PATH="${INSTALLER_DIR}/${PKG_BASENAME}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
PKG_IDENTIFIER="${BUNDLE_IDENTIFIER}.installer"

cd "${ROOT_DIR}"

find_codesigning_identity() {
    local expression="$1"
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' "${expression} { print \$2; exit }"
}

find_installer_identity() {
    security find-identity -v -p basic 2>/dev/null \
        | awk -F '"' '/Developer ID Installer:/ { print $2; exit }'
}

APP_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "${APP_SIGN_IDENTITY}" ]]; then
    APP_SIGN_IDENTITY="$(find_codesigning_identity '/Developer ID Application:/')"
fi
if [[ -z "${APP_SIGN_IDENTITY}" && "${REQUIRE_DEVELOPER_ID}" != "1" ]]; then
    APP_SIGN_IDENTITY="$("${ROOT_DIR}/Scripts/resolve_signing_identity.sh")"
fi

if [[ -z "${APP_SIGN_IDENTITY}" || "${APP_SIGN_IDENTITY}" == "-" ]]; then
    if [[ "${REQUIRE_DEVELOPER_ID}" == "1" ]]; then
        echo "Missing Developer ID Application identity. Install it or set CODE_SIGN_IDENTITY." >&2
        exit 65
    fi
    APP_SIGN_IDENTITY="-"
fi

if [[ "${REQUIRE_DEVELOPER_ID}" == "1" && "${APP_SIGN_IDENTITY}" != Developer\ ID\ Application:* ]]; then
    echo "Production installer requires Developer ID Application, got: ${APP_SIGN_IDENTITY}" >&2
    exit 65
fi

INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
if [[ -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
    INSTALLER_SIGN_IDENTITY="$(find_installer_identity)"
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY}" && "${ALLOW_UNSIGNED_INSTALLER}" != "1" ]]; then
    echo "Missing Developer ID Installer identity. Install it, set INSTALLER_SIGN_IDENTITY, or set BROWSER_SELECTOR_ALLOW_UNSIGNED_INSTALLER=1 for a local preview build." >&2
    exit 65
fi

if [[ "${REQUIRE_DEVELOPER_ID}" == "1" && -z "${NOTARY_PROFILE}" ]]; then
    echo "Production installer requires notarization. Set BROWSER_SELECTOR_NOTARY_PROFILE." >&2
    exit 65
fi

rm -rf "${WORK_DIR}"
mkdir -p "${INSTALLER_DIR}" "${WORK_DIR}" "${SCRIPTS_DIR}" "${DMG_ROOT}"
rm -f "${PKG_PATH}" "${DMG_PATH}" "${CHECKSUM_PATH}" "${PKG_PATH}.sha256"

BROWSER_SELECTOR_ARCHS="${RELEASE_ARCHS}" \
CODE_SIGN_IDENTITY="${APP_SIGN_IDENTITY}" \
CODE_SIGN_TIMESTAMP="${CODE_SIGN_TIMESTAMP:-enabled}" \
    "${ROOT_DIR}/Scripts/build.sh"

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
SPCTL_OUTPUT="$(spctl --assess --type execute --verbose=4 "${APP_DIR}" 2>&1)" || {
    echo "Gatekeeper assessment did not accept the pre-notarization app bundle:" >&2
    echo "${SPCTL_OUTPUT}" >&2
}

cat > "${SCRIPTS_DIR}/postinstall" <<POSTINSTALL
#!/bin/zsh
set -eu

APP_PATH="/Applications/${APP_BUNDLE_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -x "\${LSREGISTER}" && -d "\${APP_PATH}" ]]; then
    "\${LSREGISTER}" -f "\${APP_PATH}" >/dev/null 2>&1 || true
fi

CONSOLE_USER="\$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
if [[ -n "\${CONSOLE_USER}" && "\${CONSOLE_USER}" != "root" && "\${CONSOLE_USER}" != "loginwindow" ]]; then
    USER_ID="\$(/usr/bin/id -u "\${CONSOLE_USER}" 2>/dev/null || true)"
    if [[ -n "\${USER_ID}" && -d "\${APP_PATH}" ]]; then
        /bin/launchctl asuser "\${USER_ID}" /usr/bin/sudo -u "\${CONSOLE_USER}" /usr/bin/open -n "\${APP_PATH}" >/dev/null 2>&1 || true
    fi
fi

exit 0
POSTINSTALL
chmod +x "${SCRIPTS_DIR}/postinstall"

mkdir -p "${STAGED_COMPONENT_DIR}"
ditto --norsrc --noextattr --noacl "${APP_DIR}" "${STAGED_APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${STAGED_APP_DIR}"

cat > "${PRODUCT_REQUIREMENTS}" <<PRODUCT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>arch</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
    <key>os</key>
    <array>
        <string>${MACOS_DEPLOYMENT_TARGET}</string>
    </array>
</dict>
</plist>
PRODUCT

pkgbuild \
    --component "${STAGED_APP_DIR}" \
    --install-location "/Applications" \
    --identifier "${PKG_IDENTIFIER}" \
    --version "${VERSION}.${BUILD_NUMBER}" \
    --scripts "${SCRIPTS_DIR}" \
    --min-os-version "${MACOS_DEPLOYMENT_TARGET}" \
    "${COMPONENT_PKG}"

PRODUCTBUILD_ARGS=(
    --product "${PRODUCT_REQUIREMENTS}"
    --identifier "${PKG_IDENTIFIER}"
    --version "${VERSION}.${BUILD_NUMBER}"
    --package "${COMPONENT_PKG}"
)

if [[ -n "${INSTALLER_SIGN_IDENTITY}" ]]; then
    PRODUCTBUILD_ARGS+=(--sign "${INSTALLER_SIGN_IDENTITY}" --timestamp)
fi

PRODUCTBUILD_ARGS+=("${PKG_PATH}")
productbuild "${PRODUCTBUILD_ARGS[@]}"

pkgutil --check-signature "${PKG_PATH}" || {
    if [[ "${ALLOW_UNSIGNED_INSTALLER}" != "1" ]]; then
        exit 65
    fi
}

if [[ -n "${NOTARY_PROFILE}" ]]; then
    xcrun notarytool submit "${PKG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait --timeout "${NOTARY_TIMEOUT}"
    xcrun stapler staple "${PKG_PATH}"
    xcrun stapler validate "${PKG_PATH}"
    spctl --assess --type install --verbose=4 "${PKG_PATH}"
elif [[ "${REQUIRE_DEVELOPER_ID}" == "1" ]]; then
    echo "Production installer requires notarization. Set BROWSER_SELECTOR_NOTARY_PROFILE." >&2
    exit 65
fi

cat > "${DMG_ROOT}/README.txt" <<README
Browser Selector ${VERSION}

Double-click ${PKG_BASENAME}.pkg to install.
The installer copies Browser Selector to /Applications and launches it.
On first launch, macOS may ask you to confirm Browser Selector as the default browser.
README

ditto "${PKG_PATH}" "${DMG_ROOT}/${PKG_BASENAME}.pkg"
hdiutil create \
    -volname "Browser Selector ${VERSION}" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

if [[ "${APP_SIGN_IDENTITY}" != "-" ]]; then
    DMG_CODESIGN_TIMESTAMP_FLAGS=(--timestamp=none)
    if [[ "${CODE_SIGN_TIMESTAMP:-enabled}" == "1" || "${CODE_SIGN_TIMESTAMP:-enabled}" == "true" || "${CODE_SIGN_TIMESTAMP:-enabled}" == "enabled" ]]; then
        DMG_CODESIGN_TIMESTAMP_FLAGS=(--timestamp)
    fi

    codesign --force --sign "${APP_SIGN_IDENTITY}" "${DMG_CODESIGN_TIMESTAMP_FLAGS[@]}" "${DMG_PATH}" || true
fi

if [[ -n "${NOTARY_PROFILE}" ]]; then
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait --timeout "${NOTARY_TIMEOUT}"
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
    spctl --assess --type open --verbose=4 "${DMG_PATH}"
fi

(
    cd "${INSTALLER_DIR}"
    shasum -a 256 "$(basename "${PKG_PATH}")" > "$(basename "${PKG_PATH}").sha256"
    shasum -a 256 "$(basename "${DMG_PATH}")" > "$(basename "${CHECKSUM_PATH}")"
)

lipo -info "${APP_DIR}/Contents/MacOS/${BINARY_NAME}"
echo "Installer package: ${PKG_PATH}"
echo "Installer disk image: ${DMG_PATH}"
echo "Checksum: ${CHECKSUM_PATH}"
echo "App signed with: ${APP_SIGN_IDENTITY}"
if [[ -n "${INSTALLER_SIGN_IDENTITY}" ]]; then
    echo "Installer signed with: ${INSTALLER_SIGN_IDENTITY}"
else
    echo "Installer signed with: unsigned local preview"
fi
