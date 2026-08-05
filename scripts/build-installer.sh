#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-1.5.2}"
SIGN_NAME="${SIGN_NAME:-Reuben Miller}"
SIGN_DESCRIPTION="${SIGN_DESCRIPTION:-Virtual Scanner}"
SIGN_TIMESTAMP_URL="${SIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}"
SIGN_URL="${SIGN_URL:-}"
SIGN_CERT_TEMP=""

decode_signing_certificate() {
    if [[ -z "${SIGN_CERT_BASE64:-}" || -n "${SIGN_CERT_PATH:-}" ]]; then
        return 0
    fi

    SIGN_CERT_TEMP="$(mktemp)"
    if printf '%s' "${SIGN_CERT_BASE64}" | base64 -d >"${SIGN_CERT_TEMP}" 2>/dev/null; then
        SIGN_CERT_PATH="${SIGN_CERT_TEMP}"
        trap 'rm -f "${SIGN_CERT_TEMP}"' EXIT
        return 0
    fi

    if printf '%s' "${SIGN_CERT_BASE64}" | base64 -D >"${SIGN_CERT_TEMP}" 2>/dev/null; then
        SIGN_CERT_PATH="${SIGN_CERT_TEMP}"
        trap 'rm -f "${SIGN_CERT_TEMP}"' EXIT
        return 0
    fi

    printf 'SIGN_CERT_BASE64 is not valid base64 certificate data.\n' >&2
    return 1
}

sign_file() {
    local file="$1"

    if [[ -z "${SIGN_CERT_PATH:-}" ]]; then
        return 0
    fi

    if [[ ! -f "${SIGN_CERT_PATH}" ]]; then
        printf 'Signing certificate not found: %s\n' "${SIGN_CERT_PATH}" >&2
        return 1
    fi

    if ! command -v osslsigncode >/dev/null 2>&1; then
        printf 'osslsigncode is required when SIGN_CERT_PATH is set.\n' >&2
        return 1
    fi

    local signed_file="${file}.signed"
    local sign_args=(
        sign
        -pkcs12 "${SIGN_CERT_PATH}"
        -n "${SIGN_DESCRIPTION}"
        -h sha256
        -ts "${SIGN_TIMESTAMP_URL}"
    )

    if [[ -n "${SIGN_CERT_PASSWORD:-}" ]]; then
        sign_args+=(-pass "${SIGN_CERT_PASSWORD}")
    fi

    if [[ -n "${SIGN_URL}" ]]; then
        sign_args+=(-i "${SIGN_URL}")
    fi

    sign_args+=(-in "${file}" -out "${signed_file}")

    printf 'Signing %s as %s...\n' "${file}" "${SIGN_NAME}"
    osslsigncode "${sign_args[@]}"
    mv "${signed_file}" "${file}"
}

bundle_ghostscript() {
    local arch="$1"
    local flavor="win64"

    if [[ "${arch}" == "x86" ]]; then
        flavor="win32"
    fi

    bash scripts/bundle-ghostscript.sh "${flavor}" "dist/ghostscript-${arch}"
}

rm -rf dist
mkdir -p dist
decode_signing_certificate

make clean
make ARCH=x64 CC=x86_64-w64-mingw32-clang++
mkdir -p dist/x64
cp build/x64/VirtualScanner.ds dist/x64/VirtualScanner.ds
sign_file "dist/x64/VirtualScanner.ds"
bundle_ghostscript x64
makensis -V2 -DVERSION="${VERSION}" -DARCH=x64 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
sign_file "dist/VirtualScanner-${VERSION}-x64-setup.exe"
zip -j "dist/VirtualScanner-${VERSION}-x64.zip" "dist/VirtualScanner-${VERSION}-x64-setup.exe"
mkdir -p "dist/portable-x64"
cp build/x64/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-x64/"
sign_file "dist/portable-x64/VirtualScanner.ds"
zip -j "dist/VirtualScanner-${VERSION}-x64-portable.zip" dist/portable-x64/*

make ARCH=x86 CC=i686-w64-mingw32-clang++
mkdir -p dist/x86
cp build/x86/VirtualScanner.ds dist/x86/VirtualScanner.ds
sign_file "dist/x86/VirtualScanner.ds"
bundle_ghostscript x86
makensis -V2 -DVERSION="${VERSION}" -DARCH=x86 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
sign_file "dist/VirtualScanner-${VERSION}-x86-setup.exe"
zip -j "dist/VirtualScanner-${VERSION}-x86.zip" "dist/VirtualScanner-${VERSION}-x86-setup.exe"
mkdir -p "dist/portable-x86"
cp build/x86/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-x86/"
sign_file "dist/portable-x86/VirtualScanner.ds"
zip -j "dist/VirtualScanner-${VERSION}-x86-portable.zip" dist/portable-x86/*

make ARCH=arm64 CC=aarch64-w64-mingw32-clang++
mkdir -p dist/arm64
cp build/arm64/VirtualScanner.ds dist/arm64/VirtualScanner.ds
sign_file "dist/arm64/VirtualScanner.ds"
bundle_ghostscript arm64
makensis -V2 -DVERSION="${VERSION}" -DARCH=arm64 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
sign_file "dist/VirtualScanner-${VERSION}-arm64-setup.exe"
zip -j "dist/VirtualScanner-${VERSION}-arm64.zip" "dist/VirtualScanner-${VERSION}-arm64-setup.exe"
mkdir -p "dist/portable-arm64"
cp build/arm64/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-arm64/"
sign_file "dist/portable-arm64/VirtualScanner.ds"
zip -j "dist/VirtualScanner-${VERSION}-arm64-portable.zip" dist/portable-arm64/*

printf '\nBuilt artifacts:\n'
find dist -type f -print
