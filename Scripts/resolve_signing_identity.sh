#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "${CODE_SIGN_IDENTITY}"
    exit 0
fi

IDENTITY_LIST="$(security find-identity -v -p codesigning 2>/dev/null || true)"
SIGN_IDENTITY="$(printf '%s\n' "${IDENTITY_LIST}" | awk -F '"' '/Developer ID Application:/ { print $2; exit }')"

if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="$(printf '%s\n' "${IDENTITY_LIST}" | awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi

if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="$(printf '%s\n' "${IDENTITY_LIST}" | awk -F '"' '/"/ { print $2; exit }')"
fi

printf '%s\n' "${SIGN_IDENTITY:--}"
