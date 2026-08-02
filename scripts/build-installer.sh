#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-1.5.1}"

rm -rf dist
mkdir -p dist

make clean
make ARCH=x64 CC=x86_64-w64-mingw32-clang++
mkdir -p dist/x64
cp build/x64/VirtualScanner.ds dist/x64/VirtualScanner.ds
makensis -V2 -DVERSION="${VERSION}" -DARCH=x64 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
zip -j "dist/VirtualScanner-${VERSION}-x64.zip" "dist/VirtualScanner-${VERSION}-x64-setup.exe"
mkdir -p "dist/portable-x64"
cp build/x64/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-x64/"
zip -j "dist/VirtualScanner-${VERSION}-x64-portable.zip" dist/portable-x64/*

make ARCH=x86 CC=i686-w64-mingw32-clang++
mkdir -p dist/x86
cp build/x86/VirtualScanner.ds dist/x86/VirtualScanner.ds
makensis -V2 -DVERSION="${VERSION}" -DARCH=x86 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
zip -j "dist/VirtualScanner-${VERSION}-x86.zip" "dist/VirtualScanner-${VERSION}-x86-setup.exe"
mkdir -p "dist/portable-x86"
cp build/x86/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-x86/"
zip -j "dist/VirtualScanner-${VERSION}-x86-portable.zip" dist/portable-x86/*

make ARCH=arm64 CC=aarch64-w64-mingw32-clang++
mkdir -p dist/arm64
cp build/arm64/VirtualScanner.ds dist/arm64/VirtualScanner.ds
makensis -V2 -DVERSION="${VERSION}" -DARCH=arm64 -DSOURCE_DIR="$(pwd)" installer/VirtualScanner.nsi
zip -j "dist/VirtualScanner-${VERSION}-arm64.zip" "dist/VirtualScanner-${VERSION}-arm64-setup.exe"
mkdir -p "dist/portable-arm64"
cp build/arm64/VirtualScanner.ds app/VirtualScannerInbox.ps1 app/VirtualScannerInbox.vbs app/VirtualScanner.ico scripts/install-portable.ps1 "dist/portable-arm64/"
zip -j "dist/VirtualScanner-${VERSION}-arm64-portable.zip" dist/portable-arm64/*

printf '\nBuilt artifacts:\n'
find dist -type f -print
