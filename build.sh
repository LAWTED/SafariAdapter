#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/SafariAdapter.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
DEPLOYMENT_TARGET="15.0"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

mkdir -p "$BUILD_DIR" "$MACOS_DIR"

for architecture in arm64 x86_64; do
  xcrun swiftc \
    -parse-as-library \
    -O \
    -target "$architecture-apple-macos$DEPLOYMENT_TARGET" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -framework ApplicationServices \
    "$PROJECT_DIR"/Sources/*.swift \
    -o "$BUILD_DIR/SafariAdapter-$architecture"
done

lipo -create \
  "$BUILD_DIR/SafariAdapter-arm64" \
  "$BUILD_DIR/SafariAdapter-x86_64" \
  -output "$MACOS_DIR/SafariAdapter"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
  echo "Signing: ad-hoc (set SIGNING_IDENTITY for a distributable build)"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$PROJECT_DIR/SafariAdapter.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"
  echo "Signing: $SIGNING_IDENTITY"
fi

echo "Architectures: $(lipo -archs "$MACOS_DIR/SafariAdapter")"
echo "Built: $APP_DIR"
