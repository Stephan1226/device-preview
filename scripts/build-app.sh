#!/usr/bin/env bash
# Device Preview.app 을 만들고 릴리스용 zip 을 만든다.
#   scripts/build-app.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?버전을 넣어주세요 (예: 0.1.0)}"
APP_NAME="Device Preview"
APP="build/$APP_NAME.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

[ -f Support/AppIcon.icns ] || swift scripts/make-icon.swift Support/AppIcon.icns

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DevicePreview" "$APP/Contents/MacOS/DevicePreview"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" Support/Info.plist > "$APP/Contents/Info.plist"

# 애플 공증 없이 ad-hoc 서명 (Apple Silicon 에서 실행하려면 서명이 필요)
codesign --force --deep --sign - "$APP"

ZIP="build/Device-Preview-$VERSION.zip"
(cd build && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP")")
echo "app: $APP"
echo "zip: $ZIP"
shasum -a 256 "$ZIP"
